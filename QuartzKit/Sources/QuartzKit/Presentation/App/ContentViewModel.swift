import SwiftUI

/// Coordinates vault loading, note opening, and command routing.
///
/// Extracts the business logic from `ContentView` so that the view
/// is only responsible for layout and presentation.
@Observable
@MainActor
public final class ContentViewModel {
    public var sidebarViewModel: SidebarViewModel?
    public var editorViewModel: NoteEditorViewModel?
    public var searchIndex: VaultSearchIndex?
    public var embeddingService: VectorEmbeddingService?
    public var cloudSyncStatus: CloudSyncStatus = .notApplicable
    public var indexingProgress: (current: Int, total: Int)?

    private let appState: AppState
    private var cloudSyncService: CloudSyncService?
    private var syncMonitoringTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var currentVaultRootURL: URL?

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Vault Loading

    /// Loads a vault: creates sidebar VM, search index, builds the file tree, and indexes notes for Vault Chat.
    public func loadVault(_ vault: VaultConfig) {
        editorViewModel?.cancelAllTasks()
        editorViewModel = nil
        stopCloudSync()
        indexingTask?.cancel()
        indexingTask = nil

        currentVaultRootURL = vault.rootURL

        let provider = ServiceContainer.shared.resolveVaultProvider()
        let viewModel = SidebarViewModel(vaultProvider: provider)
        sidebarViewModel = viewModel

        let index = VaultSearchIndex(vaultProvider: provider)
        searchIndex = index

        let embedding = VectorEmbeddingService(vaultURL: vault.rootURL)
        embeddingService = embedding

        Task {
            await viewModel.loadTree(at: vault.rootURL)
            await index.indexFromPreloadedTree(viewModel.fileTree)
            try? await embedding.loadIndex()
            indexAllNotes(in: viewModel.fileTree, vaultRoot: vault.rootURL, embedding: embedding)
        }

        if Self.isICloudDriveURL(vault.rootURL) {
            startCloudSync(for: vault.rootURL)
        }
    }

    // MARK: - Note Opening

    /// Opens a note at the given URL, cancelling any previous editor tasks.
    public func openNote(at url: URL?) {
        editorViewModel?.cancelAllTasks()
        guard let url else {
            editorViewModel = nil
            return
        }
        let container = ServiceContainer.shared
        let vm = NoteEditorViewModel(
            vaultProvider: container.resolveVaultProvider(),
            frontmatterParser: container.resolveFrontmatterParser()
        )
        vm.vaultRootURL = sidebarViewModel?.vaultRootURL
        vm.fileTree = sidebarViewModel?.fileTree ?? []
        editorViewModel = vm
        Task { await vm.loadNote(at: url) }
    }

    // MARK: - Daily Note

    /// Creates a daily note with today's date as the filename (ISO 8601).
    public func createDailyNote() {
        guard let root = sidebarViewModel?.vaultRootURL else { return }
        // en_US_POSIX ensures stable ISO date format for filenames
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: Date())
        Task {
            await sidebarViewModel?.createNote(named: name, in: root)
        }
    }

    // MARK: - Vault Chat

    /// Creates a new vault chat session wired to the current embedding service.
    public func createVaultChatSession() -> VaultChatSession? {
        guard let embeddingService,
              let vaultRoot = currentVaultRootURL else { return nil }

        let fileTree = sidebarViewModel?.fileTree ?? []
        let titleMap = Self.buildNoteTitleMap(from: fileTree, vaultRoot: vaultRoot)

        let chatService = VaultChatService(
            embeddingService: embeddingService,
            providerRegistry: .shared
        )

        return VaultChatSession(
            chatService: chatService,
            noteResolver: { noteID in titleMap[noteID] }
        )
    }

    /// Re-indexes every note in the vault. Can be triggered from the UI.
    public func reindexVault() {
        guard let tree = sidebarViewModel?.fileTree,
              let vaultRoot = currentVaultRootURL,
              let embedding = embeddingService else { return }
        indexAllNotes(in: tree, vaultRoot: vaultRoot, embedding: embedding)
    }

    // MARK: - Note Indexing

    /// Recursively flattens the file tree into a UUID → title lookup using stable IDs.
    private static func buildNoteTitleMap(from nodes: [FileNode], vaultRoot: URL) -> [UUID: String] {
        var map: [UUID: String] = [:]
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isNote {
                    let title = node.name.replacingOccurrences(of: ".md", with: "")
                    let stableID = VectorEmbeddingService.stableNoteID(for: node.url, vaultRoot: vaultRoot)
                    map[stableID] = title
                }
                if let children = node.children {
                    walk(children)
                }
            }
        }
        walk(nodes)
        return map
    }

    /// Collects all note file URLs from the tree recursively.
    private static func collectNoteURLs(from nodes: [FileNode]) -> [URL] {
        var urls: [URL] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isNote {
                    urls.append(node.url)
                }
                if let children = node.children {
                    walk(children)
                }
            }
        }
        walk(nodes)
        return urls
    }

    /// Indexes all notes in the file tree via the embedding service.
    /// Runs file I/O and embedding generation on a background thread,
    /// hopping back to MainActor only for progress updates.
    private func indexAllNotes(
        in tree: [FileNode],
        vaultRoot: URL,
        embedding: VectorEmbeddingService
    ) {
        indexingTask?.cancel()

        let noteURLs = Self.collectNoteURLs(from: tree)
        guard !noteURLs.isEmpty else { return }

        indexingProgress = (current: 0, total: noteURLs.count)

        indexingTask = Task.detached(priority: .utility) {
            let total = noteURLs.count
            for (i, url) in noteURLs.enumerated() {
                guard !Task.isCancelled else { break }

                let content = try? String(contentsOf: url, encoding: .utf8)
                if let content, !content.isEmpty {
                    let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
                    try? await embedding.indexNote(noteID: stableID, content: content)
                }

                let current = i + 1
                await MainActor.run { [weak self] in
                    self?.indexingProgress = (current: current, total: total)
                }
            }

            try? await embedding.saveIndex()
            await MainActor.run { [weak self] in
                self?.indexingProgress = nil
            }
        }
    }

    // MARK: - iCloud Sync

    private func startCloudSync(for vaultURL: URL) {
        let service = CloudSyncService()
        cloudSyncService = service
        cloudSyncStatus = .current

        syncMonitoringTask = Task {
            let stream = await service.startMonitoring(vaultRoot: vaultURL)
            var fileStatuses: [URL: CloudSyncStatus] = [:]
            for await (url, status) in stream {
                fileStatuses[url] = status
                cloudSyncStatus = Self.aggregateStatus(from: fileStatuses)
            }
        }
    }

    public func stopCloudSync() {
        syncMonitoringTask?.cancel()
        syncMonitoringTask = nil
        if let service = cloudSyncService {
            Task { await service.stopMonitoring() }
        }
        cloudSyncService = nil
        cloudSyncStatus = .notApplicable
    }

    private static func isICloudDriveURL(_ url: URL) -> Bool {
        if FileManager.default.isUbiquitousItem(at: url) { return true }
        let path = url.path(percentEncoded: false)
        return path.contains("com~apple~CloudDocs") || path.contains("/Mobile Documents/")
    }

    private static func aggregateStatus(from statuses: [URL: CloudSyncStatus]) -> CloudSyncStatus {
        let values = statuses.values
        if values.contains(.error) { return .error }
        if values.contains(.conflict) { return .conflict }
        if values.contains(.uploading) { return .uploading }
        if values.contains(.downloading) { return .downloading }
        if values.contains(.notDownloaded) { return .downloading }
        return .current
    }

    // MARK: - Command Handling

    /// Processes a keyboard shortcut command and returns any UI action needed.
    public func handleCommand(
        _ command: CommandAction,
        showNewNote: inout Bool,
        showNewFolder: inout Bool,
        showSearch: inout Bool,
        columnVisibility: inout NavigationSplitViewVisibility,
        newNoteParent: inout URL?
    ) {
        switch command {
        case .newNote:
            if let root = sidebarViewModel?.vaultRootURL {
                newNoteParent = root
                showNewNote = true
            }
        case .newFolder:
            if let root = sidebarViewModel?.vaultRootURL {
                newNoteParent = root
                showNewFolder = true
            }
        case .search, .globalSearch:
            showSearch = true
        case .toggleSidebar:
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        case .dailyNote:
            createDailyNote()
        case .none:
            break
        }
    }
}
