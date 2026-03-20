import SwiftUI

/// Adaptive two-column layout for iPad, Mac, and iPhone.
///
/// - iPhone: Single-column navigation
/// - iPad / Mac: Sidebar + Detail (editor)
///
/// The sidebar column uses a native ``List`` with `.sidebar` style in ``SidebarView``.
public struct AdaptiveLayoutView<Sidebar: View, Detail: View>: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    let sidebar: () -> Sidebar
    let detail: () -> Detail

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self._columnVisibility = columnVisibility
        self.sidebar = sidebar
        self.detail = detail
    }

    public var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            sidebar()
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
                #else
                .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 380)
                #endif
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

// MARK: - iPad Keyboard Shortcuts

/// Keyboard shortcuts for iPad and Mac.
///
/// Registers productivity-related key combinations:
/// - ⌘N: New note
/// - ⌘⇧N: New folder
/// - ⌘F: Search
/// - ⌘⇧F: Vault-wide search
/// - ⌘/: Toggle sidebar
public struct KeyboardShortcutCommands: Commands {
    let onNewNote: () -> Void
    let onNewFolder: () -> Void
    let onSearch: () -> Void
    let onGlobalSearch: () -> Void
    let onToggleSidebar: () -> Void
    let onDailyNote: () -> Void

    public init(
        onNewNote: @escaping () -> Void,
        onNewFolder: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onGlobalSearch: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void,
        onDailyNote: @escaping () -> Void
    ) {
        self.onNewNote = onNewNote
        self.onNewFolder = onNewFolder
        self.onSearch = onSearch
        self.onGlobalSearch = onGlobalSearch
        self.onToggleSidebar = onToggleSidebar
        self.onDailyNote = onDailyNote
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Note", bundle: .module)) { onNewNote() }
                .keyboardShortcut("n", modifiers: .command)

            Button(String(localized: "New Folder", bundle: .module)) { onNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Daily Note", bundle: .module)) { onDailyNote() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button(String(localized: "Find in Note", bundle: .module)) { onSearch() }
                .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Search All Notes", bundle: .module)) { onGlobalSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button(String(localized: "Toggle Sidebar", bundle: .module)) { onToggleSidebar() }
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}

// MARK: - Stage Manager Support

/// Modifier for Stage Manager and window size on iPad.
@MainActor
public struct StageManagerModifier: ViewModifier {
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    var appState: AppState

    public func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "quartz" else { return }
        switch url.host() {
        case "note":
            // quartz://note/<filename> → open note
            let path = url.pathComponents.dropFirst().joined(separator: "/")
            guard !path.isEmpty,
                  let vaultRoot = appState.currentVault?.rootURL else { return }
            let noteURL = vaultRoot.appending(path: path)
            // Security: Ensure the resolved URL stays within the vault root
            guard noteURL.standardizedFileURL.path()
                    .hasPrefix(vaultRoot.standardizedFileURL.path()) else { return }
            guard FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) else { return }
            Task { @MainActor in
                let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
                if let note = try? await provider.readNote(at: noteURL) {
                    appState.selectedNote = note
                }
            }
        case "new":
            appState.pendingCommand = .newNote
        case "daily":
            appState.pendingCommand = .dailyNote
        case "scan":
            appState.pendingOpenDocumentScanner = true
        default:
            break
        }
    }
}

extension View {
    /// Enables Stage Manager support.
    public func stageManagerSupport(appState: AppState) -> some View {
        modifier(StageManagerModifier(appState: appState))
    }
}
