import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()
    @State private var focusModeManager = FocusModeManager()
    @AppStorage("quartz.appLockEnabled") private var appLockEnabled = false
    private let biometricAuthService = BiometricAuthService()

    /// Returns true if the app was launched with UI testing flags.
    private static var isUITesting: Bool {
        CommandLine.arguments.contains("--uitesting")
    }

    init() {
        // Reset state for UI testing to ensure a clean slate
        if Self.isUITesting {
            Self.resetUITestingState()
        }
    }

    /// Clears persisted state for UI testing.
    private static func resetUITestingState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "quartz.hasCompletedOnboarding")
        defaults.removeObject(forKey: "quartz.lastVault.bookmark")
        defaults.removeObject(forKey: "quartz.lastVault.name")
        defaults.removeObject(forKey: "quartz.appLockEnabled")
        defaults.synchronize()
    }

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
                onDailyNote: { appState.pendingCommand = .dailyNote },
                onFormatAction: { action in appState.pendingCommand = .format(action) }
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
///
/// Binds this window to a **snapshot** of the vault that contained the note when it was first resolved, plus a
/// dedicated security-scoped access on that vault root. That keeps the editor consistent when the main window
/// switches to another vault (this window is not re-parented to `appState.currentVault`).
private struct NoteWindowRoot: View {
    @Environment(AppState.self) private var appState
    @Binding var noteURL: URL?
    @State private var editorVM: NoteEditorViewModel?
    @State private var loadError: String?
    /// Vault for this window only; does not track main-window vault switches.
    @State private var windowVault: VaultConfig?
    /// Balances `startAccessingSecurityScopedResource` for `windowVault` (independent of the main scene).
    @State private var windowVaultAccessing = false
    @State private var trackedNoteURL: URL?

    /// Handoff element only when the secondary editor finished loading successfully (mirrors main-window eligibility).
    private var handoffNoteElementURL: URL? {
        guard loadError == nil, editorVM != nil, let url = noteURL else { return nil }
        return url
    }

    private var vaultRootForHandoff: URL? {
        windowVault?.rootURL ?? appState.currentVault?.rootURL
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
            } else if noteURL != nil, loadError == nil, editorVM == nil {
                if windowVault == nil, appState.currentVault == nil {
                    Text(String(localized: "Open a vault from the main window first."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(String(localized: "No note selected"))
                    .foregroundStyle(.secondary)
            }
        }
        .quartzAmbientShellBackground()
        .userActivity(QuartzUserActivity.openNoteActivityType, element: handoffNoteElementURL) { activeFileURL, activity in
            guard let vaultRoot = vaultRootForHandoff else {
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
        .task(id: noteURL) {
            await loadEditorIfNeeded()
        }
        .onDisappear {
            releaseWindowVaultAccessIfNeeded()
        }
    }

    private func releaseWindowVaultAccessIfNeeded() {
        if windowVaultAccessing, let v = windowVault {
            v.rootURL.stopAccessingSecurityScopedResource()
            windowVaultAccessing = false
        }
    }

    private func loadEditorIfNeeded() async {
        loadError = nil
        editorVM = nil

        guard let url = noteURL else {
            trackedNoteURL = nil
            releaseWindowVaultAccessIfNeeded()
            windowVault = nil
            return
        }

        let normalized = url.standardizedFileURL
        if trackedNoteURL != normalized {
            releaseWindowVaultAccessIfNeeded()
            windowVault = nil
            trackedNoteURL = normalized
        }

        let vault: VaultConfig?
        if let w = windowVault {
            vault = w
        } else if let appVault = appState.currentVault,
                  normalized.path(percentEncoded: false).hasPrefix(appVault.rootURL.standardizedFileURL.path(percentEncoded: false)) {
            vault = appVault
            windowVault = appVault
            windowVaultAccessing = appVault.rootURL.startAccessingSecurityScopedResource()
        } else {
            if appState.currentVault == nil {
                return
            }
            loadError = String(localized: "That note is not inside the open vault.")
            return
        }

        guard let vault else { return }

        guard normalized.path(percentEncoded: false).hasPrefix(vault.rootURL.standardizedFileURL.path(percentEncoded: false)) else {
            loadError = String(localized: "That note is not inside the open vault.")
            return
        }
        guard FileManager.default.fileExists(atPath: normalized.path(percentEncoded: false)) else {
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
        await vm.loadNote(at: normalized)
        editorVM = vm
    }
}
#endif
