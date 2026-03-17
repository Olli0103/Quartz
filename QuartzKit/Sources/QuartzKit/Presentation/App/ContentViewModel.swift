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

    private let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Vault Loading

    /// Loads a vault: creates sidebar VM, search index, and builds the file tree.
    public func loadVault(_ vault: VaultConfig) {
        // Cancel previous editor tasks before switching vault
        editorViewModel?.cancelAllTasks()
        editorViewModel = nil

        let provider = ServiceContainer.shared.resolveVaultProvider()
        let viewModel = SidebarViewModel(vaultProvider: provider)
        sidebarViewModel = viewModel

        let index = VaultSearchIndex(vaultProvider: provider)
        searchIndex = index

        Task {
            await viewModel.loadTree(at: vault.rootURL)
            // Use the already-loaded tree for the search index to avoid double I/O
            await index.indexFromPreloadedTree(viewModel.fileTree)
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
