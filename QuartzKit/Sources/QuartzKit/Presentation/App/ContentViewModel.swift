import SwiftUI

/// Coordinates vault loading, note opening, and command routing.
///
/// Extracts the business logic from `ContentView` so that the view
/// is only responsible for layout and presentation.
@Observable
@MainActor
public final class ContentViewModel {
    public var sidebarViewModel: SidebarViewModel?
    /// Jitter-free editor session. Used by WorkspaceView's detail column.
    /// This is the SOLE editor state machine — no legacy fallback.
    public var editorSession: EditorSession?
    /// Document-context chat session — reads live text from EditorSession at send-time.
    public var documentChatSession: DocumentChatSession?
    /// Inspector store — shared across note switches, persists visibility state.
    public let inspectorStore = InspectorStore()
    public var searchIndex: VaultSearchIndex?
    /// Core Spotlight indexer (system search); separate from in-app ``searchIndex``.
    private var spotlightIndexer: QuartzSpotlightIndexer?
    public var embeddingService: VectorEmbeddingService?
    /// Preview cache for the middle column note list.
    public var previewRepository: NotePreviewRepository?
    /// Preview indexer — reads 8KB prefix of each note for title/snippet/tags.
    public var previewIndexer: NotePreviewIndexer?
    public var cloudSyncStatus: CloudSyncStatus = .notApplicable
    /// URLs of files with unresolved iCloud sync conflicts. Used to present ConflictResolverView.
    public var conflictingFileURLs: [URL] = []
    public var indexingProgress: (current: Int, total: Int)?
    /// VaultProvider for injection into child views (avoids ServiceContainer in render path).
    public var vaultProvider: (any VaultProviding)?

    // MARK: - Backup State

    /// Vault backup service — manages export, auto-backup, and restore.
    public let backupService = VaultBackupService()
    /// Available backups for the current vault.
    public var availableBackups: [BackupEntry] = []
    /// Whether a backup operation is currently running.
    public var isBackupInProgress: Bool = false
    /// Backup progress (0.0–1.0).
    public var backupProgress: Double = 0
    /// Last sync timestamp (updated when cloudSyncStatus becomes .current).
    public var lastSyncTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: "quartzLastSyncTimestamp") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "quartzLastSyncTimestamp") }
    }

    private let appState: AppState
    private var cloudSyncService: CloudSyncService?
    private var syncMonitoringTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var currentVaultRootURL: URL?
    /// Debounced task for re-indexing embeddings after note saves.
    private var embeddingReindexTask: Task<Void, Never>?
    /// Observer token for `.quartzNoteSaved` notifications (embedding reindex).
    private var noteSavedObserver: Any?
    /// Observer tokens for note lifecycle notifications (spotlight, preview, search).
    private var noteLifecycleObservers: [Any] = []
    /// Background semantic link discovery engine.
    public var semanticLinkService: SemanticLinkService?
    /// Background AI concept extraction engine.
    public var knowledgeExtractionService: KnowledgeExtractionService?
    /// Unified Intelligence Engine coordinator — bridges file events to all AI services.
    public var intelligenceCoordinator: IntelligenceEngineCoordinator?
    /// Shared graph edge store for wiki-link and semantic edges.
    public let graphEdgeStore = GraphEdgeStore()

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Vault Loading

    /// Loads a vault: creates sidebar VM, search index, builds the file tree, and indexes notes.
    /// Wires the `NoteListStore` with preview data after indexing completes.
    public func loadVault(_ vault: VaultConfig, noteListStore: NoteListStore? = nil) {
        editorSession?.closeNote()
        stopCloudSync()
        indexingTask?.cancel()
        indexingTask = nil

        currentVaultRootURL = vault.rootURL

        let provider = ServiceContainer.shared.resolveVaultProvider()
        vaultProvider = provider
        let viewModel = SidebarViewModel(vaultProvider: provider)
        sidebarViewModel = viewModel

        let index = VaultSearchIndex(vaultProvider: provider)
        searchIndex = index

        spotlightIndexer = QuartzSpotlightIndexer(vaultProvider: provider)

        let embedding = VectorEmbeddingService(vaultURL: vault.rootURL)
        embeddingService = embedding

        // Initialize background semantic link service
        semanticLinkService = SemanticLinkService(
            embeddingService: embedding,
            edgeStore: graphEdgeStore,
            vaultRootURL: vault.rootURL
        )

        // Initialize background AI concept extraction engine
        knowledgeExtractionService = KnowledgeExtractionService(
            edgeStore: graphEdgeStore,
            vaultRootURL: vault.rootURL
        )

        // Initialize Intelligence Engine coordinator — unified event routing
        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embedding,
            semanticService: semanticLinkService,
            extractionService: knowledgeExtractionService,
            vaultRootURL: vault.rootURL
        )
        intelligenceCoordinator = coordinator
        Task { await coordinator.startObserving() }

        let frontmatterParser = ServiceContainer.shared.resolveFrontmatterParser()
        let previewRepo = NotePreviewRepository(vaultRoot: vault.rootURL)
        previewRepository = previewRepo
        let previewIdx = NotePreviewIndexer(
            vaultRoot: vault.rootURL,
            repository: previewRepo,
            frontmatterParser: frontmatterParser
        )
        previewIndexer = previewIdx

        // Create EditorSession ONCE per vault — reused across all note switches.
        // This prevents view destruction/flashing when switching notes.
        let container2 = ServiceContainer.shared
        let session = EditorSession(
            vaultProvider: container2.resolveVaultProvider(),
            frontmatterParser: container2.resolveFrontmatterParser(),
            inspectorStore: inspectorStore
        )
        session.vaultRootURL = vault.rootURL
        session.graphEdgeStore = graphEdgeStore
        editorSession = session

        // Create DocumentChatSession ONCE per vault — reuses the same EditorSession.
        documentChatSession = DocumentChatSession(editorSession: session)

        Task {
            // Load preview cache from disk first (instant middle column population)
            await previewRepo.loadCache()

            // Wire NoteListStore with cached data immediately (before full reindex)
            if let noteListStore {
                noteListStore.configure(repository: previewRepo, vaultRoot: vault.rootURL)
                await noteListStore.loadItems(for: .allNotes)
            }

            await viewModel.loadTree(at: vault.rootURL)
            // Run preview indexer alongside other indexers — it's the fastest (8KB reads)
            await previewIdx.indexAll(from: viewModel.fileTree)

            // Refresh note list after full reindex completes (picks up new/changed notes)
            if let noteListStore {
                await noteListStore.refresh()
            }

            await index.indexFromPreloadedTree(viewModel.fileTree)
            if let root = currentVaultRootURL {
                await spotlightIndexer?.removeAllInDomain()
                await spotlightIndexer?.indexAllNotes(
                    urls: Self.collectNoteURLs(from: viewModel.fileTree),
                    vaultRoot: root
                )
            }
            try? await embedding.loadIndex()
            indexAllNotes(in: viewModel.fileTree, vaultRoot: vault.rootURL, embedding: embedding)

            // Start proactive AI concept extraction for the entire vault (rate-limited, low priority)
            await knowledgeExtractionService?.startVaultScan()
        }

        let iCloudSyncEnabled = (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool) ?? true
        if Self.isICloudDriveURL(vault.rootURL) {
            // Vault is in iCloud — always monitor sync status
            startCloudSync(for: vault.rootURL)
        } else if iCloudSyncEnabled && CloudSyncService.isAvailable {
            // Local vault with sync enabled — user may want to migrate
            cloudSyncStatus = .notApplicable
        }

        // Observe note saves for debounced embedding re-indexing (5s after last save)
        startEmbeddingReindexObserver()
        startNoteLifecycleObservers()

        // Auto-backup check (runs in background if enabled)
        scheduleAutoBackupIfNeeded(vaultRoot: vault.rootURL)

        // Load list of available backups
        refreshAvailableBackups(vaultRoot: vault.rootURL)

        // Check iCloud availability (resolves container URL on background thread)
        checkICloudAvailability()
    }

    /// Listens for `.quartzNoteSaved` and re-indexes the saved note's embeddings
    /// after a 5-second debounce. This keeps the vector index fresh without
    /// blocking the editor on every keystroke.
    private func startEmbeddingReindexObserver() {
        noteSavedObserver.map { NotificationCenter.default.removeObserver($0) }
        noteSavedObserver = NotificationCenter.default.addObserver(
            forName: .quartzNoteSaved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.scheduleEmbeddingReindex(for: url)
            }
        }
    }

    /// Debounced embedding reindex — waits 5 seconds after the last save.
    private func scheduleEmbeddingReindex(for url: URL) {
        embeddingReindexTask?.cancel()
        embeddingReindexTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            updateEmbeddingForNote(at: url)
        }
    }

    /// Subscribes to note lifecycle notifications for spotlight, preview, and search index updates.
    /// **Per CODEX.md F1:** Extracted from ContentView's onReceive handlers.
    private func startNoteLifecycleObservers() {
        // Clear any existing observers
        for observer in noteLifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        noteLifecycleObservers.removeAll()

        // .quartzNoteSaved — update spotlight, preview, and search index
        let savedObserver = NotificationCenter.default.addObserver(
            forName: .quartzNoteSaved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.spotlightIndexNote(at: url)
                self.updatePreviewForNote(at: url)
                self.updateSearchIndex(for: url)
            }
        }
        noteLifecycleObservers.append(savedObserver)

        // .quartzSpotlightNotesRemoved — remove spotlight and preview entries
        let removedObserver = NotificationCenter.default.addObserver(
            forName: .quartzSpotlightNotesRemoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let urls = notification.userInfo?["urls"] as? [URL] else { return }
            Task { @MainActor in
                self.spotlightRemoveNotes(at: urls)
                self.removePreviewsForNotes(at: urls)
            }
        }
        noteLifecycleObservers.append(removedObserver)

        // .quartzSpotlightNoteRelocated — update spotlight and preview paths
        let relocatedObserver = NotificationCenter.default.addObserver(
            forName: .quartzSpotlightNoteRelocated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let oldURL = notification.userInfo?["old"] as? URL,
                  let newURL = notification.userInfo?["new"] as? URL else { return }
            Task { @MainActor in
                self.spotlightRelocateNote(from: oldURL, to: newURL)
                self.relocatePreview(from: oldURL, to: newURL)
            }
        }
        noteLifecycleObservers.append(relocatedObserver)

        // .quartzReindexRequested — full vault reindex
        let reindexObserver = NotificationCenter.default.addObserver(
            forName: .quartzReindexRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reindexVault()
            }
        }
        noteLifecycleObservers.append(reindexObserver)
    }

    /// Stops all note lifecycle observers.
    private func stopNoteLifecycleObservers() {
        for observer in noteLifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        noteLifecycleObservers.removeAll()
    }

    // MARK: - Note Opening

    /// Opens a note by loading it into the existing EditorSession.
    /// The session object is REUSED — no view destruction, no flash.
    public func openNote(at url: URL?) {
        guard let url else {
            editorSession?.closeNote()
            documentChatSession?.clear()
            return
        }

        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }

        // Reuse existing session — just load the new note into it
        if let session = editorSession {
            session.fileTree = sidebarViewModel?.fileTree ?? []
            Task { await session.loadNote(at: url) }
        }

        // Clear chat history — system prompt is document-specific
        documentChatSession?.clear()
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

    /// Creates a new streaming vault chat session wired to the current embedding service.
    ///
    /// **Just-in-time indexing:** Before creating the session, ensures the background
    /// indexer has completed (waits up to 30s), then force-saves the active note
    /// and indexes its live text into the vector store.
    public func createVaultChatSession2() async -> VaultChatSession2? {
        guard let embeddingService,
              let vaultRoot = currentVaultRootURL else { return nil }

        // Just-in-time: save + index the active note before chat opens
        if let session = editorSession, let noteURL = session.note?.fileURL {
            await session.save(force: true)
            let liveText = session.currentText
            if !liveText.isEmpty {
                let stableID = VectorEmbeddingService.stableNoteID(for: noteURL, vaultRoot: vaultRoot)
                try? await embeddingService.indexNote(noteID: stableID, content: liveText)
                try? await embeddingService.saveIndex()
            }
        }

        let fileTree = sidebarViewModel?.fileTree ?? []
        let titleMap = Self.buildNoteTitleMap(from: fileTree, vaultRoot: vaultRoot)

        // Log index state for diagnostics
        let entryCount = await embeddingService.entryCount
        let noteCount = await embeddingService.indexedNoteCount
        print("[VaultChat] Opening with \(entryCount) chunks from \(noteCount) notes, \(titleMap.count) notes in tree")

        let chatService = VaultChatService(
            embeddingService: embeddingService,
            providerRegistry: .shared
        )

        return VaultChatSession2(
            chatService: chatService,
            noteResolver: { noteID in titleMap[noteID] },
            indexedChunkCount: entryCount,
            indexedNoteCount: noteCount
        )
    }

    /// Legacy non-streaming vault chat session (kept for backward compatibility during migration).
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

    /// Resolves a stable vault note ID (embeddings / vault chat sources) to the note’s file URL.
    public func urlForVaultNote(stableID: UUID) -> URL? {
        guard let vaultRoot = currentVaultRootURL,
              let tree = sidebarViewModel?.fileTree else { return nil }
        return Self.urlForNoteFile(stableID: stableID, nodes: tree, vaultRoot: vaultRoot)
    }

    private static func urlForNoteFile(stableID: UUID, nodes: [FileNode], vaultRoot: URL) -> URL? {
        for node in nodes {
            if node.isNote {
                let id = VectorEmbeddingService.stableNoteID(for: node.url, vaultRoot: vaultRoot)
                if id == stableID { return node.url }
            }
            if let children = node.children,
               let url = urlForNoteFile(stableID: stableID, nodes: children, vaultRoot: vaultRoot) {
                return url
            }
        }
        return nil
    }

    /// Re-indexes every note in the vault. Can be triggered from the UI.
    public func reindexVault() {
        guard let tree = sidebarViewModel?.fileTree,
              let vaultRoot = currentVaultRootURL else { return }
        if let embedding = embeddingService {
            indexAllNotes(in: tree, vaultRoot: vaultRoot, embedding: embedding)
        }
        Task {
            await spotlightIndexer?.removeAllInDomain()
            await spotlightIndexer?.indexAllNotes(urls: Self.collectNoteURLs(from: tree), vaultRoot: vaultRoot)
        }
    }

    // MARK: - Incremental Search Index Updates

    /// Incrementally updates the in-app search index for a single saved note.
    /// Called on every note save via `.quartzNoteSaved` notification.
    public func updateSearchIndex(for url: URL) {
        Task {
            await searchIndex?.updateEntry(for: url)
        }
    }

    /// Removes search index entries for deleted notes.
    public func removeSearchEntries(for urls: [URL]) {
        Task {
            for url in urls {
                await searchIndex?.removeEntry(for: url)
            }
        }
    }

    // MARK: - Core Spotlight

    /// Called when a note file is saved (autosave or explicit).
    public func spotlightIndexNote(at url: URL) {
        guard let vaultRoot = currentVaultRootURL else { return }
        Task {
            await spotlightIndexer?.indexNote(at: url, vaultRoot: vaultRoot)
        }
    }

    /// Removes Spotlight entries for deleted markdown files.
    public func spotlightRemoveNotes(at urls: [URL]) {
        Task {
            for url in urls {
                await spotlightIndexer?.removeNote(fileURL: url)
            }
        }
    }

    /// Updates Spotlight when a note file moves on disk.
    public func spotlightRelocateNote(from oldURL: URL, to newURL: URL) {
        guard let vaultRoot = currentVaultRootURL else { return }
        Task { @MainActor in
            // Single markdown file: update one Spotlight entry. Folder moves change many paths — reindex the vault.
            if newURL.pathExtension.lowercased() == "md" {
                await spotlightIndexer?.relocate(from: oldURL, to: newURL, vaultRoot: vaultRoot)
            } else if let tree = sidebarViewModel?.fileTree {
                await spotlightIndexer?.removeAllInDomain()
                await spotlightIndexer?.indexAllNotes(urls: Self.collectNoteURLs(from: tree), vaultRoot: vaultRoot)
            }
        }
    }

    // MARK: - Preview Cache (Incremental Updates)

    /// Incrementally updates the preview cache for a single saved note.
    /// Posts `.quartzPreviewCacheDidChange` with the URL so `NoteListStore` can do a targeted update.
    public func updatePreviewForNote(at url: URL) {
        Task {
            await previewIndexer?.indexFile(at: url)
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: url)
        }
    }

    /// Removes preview entries for deleted notes.
    public func removePreviewsForNotes(at urls: [URL]) {
        Task {
            for url in urls {
                await previewIndexer?.removeFile(at: url)
            }
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: nil)
        }
    }

    /// Updates preview entry when a note is renamed or moved.
    public func relocatePreview(from oldURL: URL, to newURL: URL) {
        Task {
            await previewIndexer?.removeFile(at: oldURL)
            await previewIndexer?.indexFile(at: newURL)
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: nil)
        }
    }

    // MARK: - Incremental Embedding Updates

    /// Re-indexes a single note's embeddings after save.
    /// Runs on a background thread to avoid blocking the editor.
    public func updateEmbeddingForNote(at url: URL) {
        guard let embedding = embeddingService,
              let vaultRoot = currentVaultRootURL else { return }

        // If this is the active note, use live text (avoids stale disk read)
        let liveText: String? = (editorSession?.note?.fileURL == url) ? editorSession?.currentText : nil

        let semanticService = self.semanticLinkService
        let extractionService = self.knowledgeExtractionService
        Task.detached(priority: .utility) {
            let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
            // CRITICAL: Use coordinated read to prevent race with iCloud sync
            let content = liveText ?? (try? CoordinatedFileWriter.shared.readString(from: url))
            if let content, !content.isEmpty {
                try? await embedding.indexNote(noteID: stableID, content: content)
                try? await embedding.saveIndex()
                // Trigger background semantic link discovery after successful embedding update
                await semanticService?.scheduleAnalysis(for: url)
                // Trigger AI concept extraction
                await extractionService?.scheduleExtraction(for: url)
            }
        }
    }

    /// Removes embeddings for deleted notes.
    public func removeEmbeddingsForNotes(at urls: [URL]) {
        guard let embedding = embeddingService,
              let vaultRoot = currentVaultRootURL else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
                await embedding.removeNote(stableID)
            }
            try? await embedding.saveIndex()
        }
    }

    /// Updates embeddings when a note is renamed or moved.
    public func relocateEmbedding(from oldURL: URL, to newURL: URL) {
        guard let embedding = embeddingService,
              let vaultRoot = currentVaultRootURL else { return }
        Task.detached(priority: .utility) {
            // Remove old stableID entries
            let oldID = VectorEmbeddingService.stableNoteID(for: oldURL, vaultRoot: vaultRoot)
            await embedding.removeNote(oldID)
            // Index at new stableID with coordinated read
            let newID = VectorEmbeddingService.stableNoteID(for: newURL, vaultRoot: vaultRoot)
            // CRITICAL: Use coordinated read to prevent race with iCloud sync
            let content = try? CoordinatedFileWriter.shared.readString(from: newURL)
            if let content, !content.isEmpty {
                try? await embedding.indexNote(noteID: newID, content: content)
            }
            try? await embedding.saveIndex()
        }
    }

    // MARK: - Backup

    /// Triggers a manual backup of the current vault.
    public func triggerManualBackup() {
        guard let vaultRoot = currentVaultRootURL else { return }
        guard !isBackupInProgress else { return }

        isBackupInProgress = true
        backupProgress = 0

        Task.detached(priority: .utility) { [backupService] in
            do {
                _ = try await backupService.createBackup(vaultRoot: vaultRoot) { progress in
                    Task { @MainActor [weak self] in
                        self?.backupProgress = progress.fraction
                    }
                }
                await MainActor.run { [weak self] in
                    self?.isBackupInProgress = false
                    self?.backupProgress = 1
                    self?.refreshAvailableBackups(vaultRoot: vaultRoot)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isBackupInProgress = false
                    self?.backupProgress = 0
                }
            }
        }
    }

    /// Restores a backup to a user-chosen destination.
    /// Returns the URL of the restored vault folder.
    public func restoreFromBackup(backupURL: URL, destination: URL) async throws {
        try await backupService.restoreBackup(from: backupURL, to: destination)
    }

    /// Refreshes the list of available backups for the current vault.
    public func refreshAvailableBackups(vaultRoot: URL? = nil) {
        guard let root = vaultRoot ?? currentVaultRootURL else { return }
        Task {
            let backups = await backupService.listBackups(vaultRoot: root)
            availableBackups = backups
        }
    }

    /// Checks if auto-backup is enabled and schedules one if >24h since last backup.
    private func scheduleAutoBackupIfNeeded(vaultRoot: URL) {
        let autoEnabled = UserDefaults.standard.bool(forKey: "quartzAutoBackupEnabled")
        guard autoEnabled else { return }

        Task.detached(priority: .utility) { [backupService] in
            let retainCount = UserDefaults.standard.integer(forKey: "quartzAutoBackupRetainCount")
            try? await backupService.runAutoBackup(
                vaultRoot: vaultRoot,
                retainCount: max(1, retainCount > 0 ? retainCount : 7)
            )
            await MainActor.run { [weak self] in
                self?.refreshAvailableBackups(vaultRoot: vaultRoot)
            }
        }
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
        sidebarViewModel?.indexingProgress = indexingProgress

        indexingTask = Task.detached(priority: .utility) {
            let total = noteURLs.count
            for (i, url) in noteURLs.enumerated() {
                guard !Task.isCancelled else { break }

                let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let mtime, let lastIndexed = await embedding.lastIndexedDate(for: stableID), mtime <= lastIndexed {
                    // File unchanged since last index, skip
                    let current = i + 1
                    await MainActor.run { [weak self] in
                        let progress = (current: current, total: total)
                        self?.indexingProgress = progress
                        self?.sidebarViewModel?.indexingProgress = progress
                    }
                    continue
                }

                let content = try? CoordinatedFileWriter.shared.readString(from: url)
                if let content, !content.isEmpty {
                    try? await embedding.indexNote(noteID: stableID, content: content)
                }

                let current = i + 1
                await MainActor.run { [weak self] in
                    let progress = (current: current, total: total)
                    self?.indexingProgress = progress
                    self?.sidebarViewModel?.indexingProgress = progress
                }
            }

            try? await embedding.saveIndex()
            await MainActor.run { [weak self] in
                self?.indexingProgress = nil
                self?.sidebarViewModel?.indexingProgress = nil
            }
        }
    }

    // MARK: - iCloud Sync

    private func startCloudSync(for vaultURL: URL) {
        let service = CloudSyncService()
        cloudSyncService = service
        cloudSyncStatus = .current

        conflictingFileURLs = []
        syncMonitoringTask = Task {
            let stream = await service.startMonitoring(vaultRoot: vaultURL)
            var fileStatuses: [URL: CloudSyncStatus] = [:]
            for await (url, status) in stream {
                fileStatuses[url] = status
                cloudSyncStatus = Self.aggregateStatus(from: fileStatuses)
                sidebarViewModel?.cloudSyncStatus = cloudSyncStatus
                if cloudSyncStatus == .current {
                    lastSyncTimestamp = Date()
                }
                conflictingFileURLs = fileStatuses.filter { $0.value == .conflict }.map(\.key)
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
        sidebarViewModel?.cloudSyncStatus = .notApplicable
        conflictingFileURLs = []
        stopNoteLifecycleObservers()
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

    // MARK: - iCloud Vault Migration

    /// Whether the current vault is inside the app's iCloud ubiquity container.
    public var isVaultInICloud: Bool {
        guard let root = currentVaultRootURL else { return false }
        return Self.isICloudDriveURL(root)
    }

    /// Whether iCloud is available on this device.
    /// Resolves the container URL on a background thread to check availability.
    /// Cached after first check to avoid repeated blocking calls.
    public var isICloudAvailable: Bool = false

    /// Checks iCloud availability by resolving the ubiquity container.
    /// Call this once during vault load or settings open.
    public func checkICloudAvailability() {
        let token = FileManager.default.ubiquityIdentityToken
        print("[iCloud] ubiquityIdentityToken: \(String(describing: token))")
        Task {
            let url = await CloudSyncService.resolveContainerURL()
            print("[iCloud] resolveContainerURL: \(String(describing: url))")
            isICloudAvailable = url != nil
            print("[iCloud] isICloudAvailable set to: \(url != nil)")
        }
    }

    /// Migrates the current local vault into the app's iCloud ubiquity container.
    ///
    /// Copies the entire vault directory into `iCloud.olli.QuartzNotes/Documents/{vaultName}/`,
    /// then switches the app to use the iCloud copy as the active vault. The original local
    /// copy is left untouched as a backup.
    ///
    /// - Returns: The new iCloud vault URL, or `nil` if migration failed.
    @discardableResult
    public func migrateVaultToICloud() async -> URL? {
        guard let localRoot = currentVaultRootURL else { return nil }

        guard CloudSyncService.isAvailable else {
            cloudSyncStatus = .error
            return nil
        }

        // Resolve container URL on background thread (first call may block while
        // the system creates the container directory structure)
        guard let containerURL = await CloudSyncService.resolveContainerURL() else {
            cloudSyncStatus = .error
            return nil
        }

        let fm = FileManager.default
        let vaultName = localRoot.lastPathComponent
        let iCloudVaultURL = containerURL.appending(path: vaultName, directoryHint: .isDirectory)

        do {
            // Ensure the Documents directory exists
            if !fm.fileExists(atPath: containerURL.path(percentEncoded: false)) {
                try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
            }

            // If the vault already exists in iCloud, just switch to it
            if fm.fileExists(atPath: iCloudVaultURL.path(percentEncoded: false)) {
                switchToVault(at: iCloudVaultURL, name: vaultName)
                return iCloudVaultURL
            }

            // Copy the local vault to iCloud
            try fm.copyItem(at: localRoot, to: iCloudVaultURL)

            // Switch to the iCloud vault
            switchToVault(at: iCloudVaultURL, name: vaultName)

            return iCloudVaultURL
        } catch {
            cloudSyncStatus = .error
            return nil
        }
    }

    /// Switches the active vault to a new URL and reloads everything.
    private func switchToVault(at url: URL, name: String) {
        var vault = VaultConfig(name: name, rootURL: url, storageType: .iCloudDrive)
        vault.isDefault = true
        appState.switchVault(to: vault)
        // Reload vault is triggered by the app state change in ContentView
    }

    // MARK: - Command Handling

    /// Processes a keyboard shortcut command, routing UI actions through the coordinator.
    ///
    /// Replaces the previous 5-`inout` parameter signature with a single coordinator.
    /// Layout commands (toggle sidebar) route through `WorkspaceStore`.
    public func handleCommand(
        _ command: CommandAction,
        coordinator: AppCoordinator,
        workspaceStore: WorkspaceStore
    ) {
        switch command {
        case .newNote:
            if let root = sidebarViewModel?.vaultRootURL {
                coordinator.presentNewNote(in: root)
            }
        case .newFolder:
            if let root = sidebarViewModel?.vaultRootURL {
                coordinator.presentNewFolder(in: root)
            }
        case .search, .globalSearch:
            coordinator.activeSheet = .search
        case .toggleSidebar:
            withAnimation(QuartzAnimation.content) {
                workspaceStore.columnVisibility = workspaceStore.columnVisibility == .all
                    ? .detailOnly : .all
            }
        case .dailyNote:
            createDailyNote()
        case .format(let action):
            applyFormatting(action)
        case .none, .openVault, .createVault:
            break
        }
    }

    private func applyFormatting(_ action: FormattingAction) {
        editorSession?.applyFormatting(action)
    }
}
