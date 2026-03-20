import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()
    @State private var focusModeManager = FocusModeManager()
    @AppStorage("quartz.appLockEnabled") private var appLockEnabled = false
    private let biometricAuthService = BiometricAuthService()

    var body: some Scene {
        WindowGroup {
            Group {
                if appLockEnabled {
                    AppLockView(authService: biometricAuthService) {
                        ContentView()
                    }
                } else {
                    ContentView()
                }
            }
            .environment(appState)
            .environment(\.appearanceManager, appearanceManager)
            .environment(\.focusModeManager, focusModeManager)
            .preferredColorScheme(appearanceManager.theme.colorScheme)
            .tint(appearanceManager.accentColor)
            .task {
                ServiceContainer.shared.bootstrap()
            }
        }
        .commands {
            KeyboardShortcutCommands(
                onNewNote: { appState.pendingCommand = .newNote },
                onNewFolder: { appState.pendingCommand = .newFolder },
                onSearch: { appState.pendingCommand = .search },
                onGlobalSearch: { appState.pendingCommand = .globalSearch },
                onToggleSidebar: { appState.pendingCommand = .toggleSidebar },
                onDailyNote: { appState.pendingCommand = .dailyNote }
            )
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        #endif

        #if os(macOS)
        WindowGroup(for: URL.self) { $noteURL in
            NoteWindowRoot(noteURL: $noteURL)
                .environment(appState)
                .environment(\.appearanceManager, appearanceManager)
                .environment(\.focusModeManager, focusModeManager)
                .preferredColorScheme(appearanceManager.theme.colorScheme)
                .tint(appearanceManager.accentColor)
                .task {
                    ServiceContainer.shared.bootstrap()
                }
        }
        .defaultSize(width: 900, height: 650)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.appearanceManager, appearanceManager)
                .environment(\.focusModeManager, focusModeManager)
        }
        #endif
    }
}

#if os(macOS)
/// Isolated editor surface for `WindowGroup(for: URL.self)` — does not share `ContentViewModel` with the main window.
private struct NoteWindowRoot: View {
    @Environment(AppState.self) private var appState
    @Binding var noteURL: URL?
    @State private var editorVM: NoteEditorViewModel?
    @State private var loadError: String?

    /// Handoff element only when the secondary editor finished loading successfully (mirrors main-window eligibility).
    private var handoffNoteElementURL: URL? {
        guard loadError == nil, editorVM != nil, let url = noteURL else { return nil }
        return url
    }

    var body: some View {
        Group {
            if let err = loadError {
                Text(err)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if let vm = editorVM, let url = noteURL {
                NoteEditorView(
                    viewModel: vm,
                    embeddingService: nil,
                    onSearch: nil,
                    onNewNote: nil,
                    onRefresh: nil,
                    searchDisabled: true,
                    newNoteDisabled: true,
                    refreshDisabled: true
                )
                .id(url)
            } else if noteURL != nil, appState.currentVault != nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if noteURL != nil {
                Text(String(localized: "Open a vault from the main window first."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                Text(String(localized: "No note selected"))
                    .foregroundStyle(.secondary)
            }
        }
        .quartzAmbientShellBackground()
        .userActivity(QuartzUserActivity.openNoteActivityType, element: handoffNoteElementURL) { activeFileURL, activity in
            guard let vaultRoot = appState.currentVault?.rootURL else {
                activity.isEligibleForHandoff = false
                activity.isEligibleForSearch = false
                return
            }
            let title = editorVM?.note?.displayName ?? activeFileURL.deletingPathExtension().lastPathComponent
            QuartzUserActivity.configureOpenNoteActivity(
                activity,
                noteURL: activeFileURL,
                displayTitle: title,
                vaultRoot: vaultRoot
            )
        }
        .task(id: (noteURL, appState.currentVault?.id)) {
            await loadEditorIfNeeded()
        }
    }

    private func loadEditorIfNeeded() async {
        loadError = nil
        editorVM = nil
        guard let url = noteURL, let vault = appState.currentVault else { return }
        guard url.standardizedFileURL.path().hasPrefix(vault.rootURL.standardizedFileURL.path()) else {
            loadError = String(localized: "That note is not inside the open vault.")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            loadError = String(localized: "That note could not be found on disk.")
            return
        }
        let container = ServiceContainer.shared
        let vm = NoteEditorViewModel(
            vaultProvider: container.resolveVaultProvider(),
            frontmatterParser: container.resolveFrontmatterParser()
        )
        vm.vaultRootURL = vault.rootURL
        let sidebarVM = SidebarViewModel(vaultProvider: container.resolveVaultProvider())
        await sidebarVM.loadTree(at: vault.rootURL)
        vm.fileTree = sidebarVM.fileTree
        await vm.loadNote(at: url)
        editorVM = vm
    }
}
#endif
