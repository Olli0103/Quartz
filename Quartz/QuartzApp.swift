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
                onFormatAction: { action in appState.pendingCommand = .format(action) },
                onOpenVault: { appState.pendingCommand = .openVault },
                onCreateVault: { appState.pendingCommand = .createVault }
            )
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        #endif

        #if os(macOS)
        WindowGroup(id: "note-window", for: URL.self) { $noteURL in
            NoteWindowRoot(noteURL: $noteURL)
                .environment(appState)
                .environment(\.appearanceManager, appearanceManager)
                .environment(\.focusModeManager, focusModeManager)
                .preferredColorScheme(appearanceManager.theme.colorScheme)
                .tint(appearanceManager.accentColor)
                .task { ServiceContainer.shared.bootstrap() }
        }
        .defaultSize(width: 800, height: 600)
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
