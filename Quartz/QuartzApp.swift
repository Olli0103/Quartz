import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()
    @State private var focusModeManager = FocusModeManager()
    @AppStorage("quartz.appLockEnabled") private var appLockEnabled = false
    private let featureGate = DefaultFeatureGate()
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
            .environment(\.featureGate, featureGate)
            .environment(\.appearanceManager, appearanceManager)
            .environment(\.focusModeManager, focusModeManager)
            .preferredColorScheme(appearanceManager.theme.colorScheme)
            .tint(appearanceManager.accentColor)
            .task {
                ServiceContainer.shared.bootstrap(featureGate: featureGate)
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
        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.appearanceManager, appearanceManager)
                .environment(\.focusModeManager, focusModeManager)
                .environment(\.featureGate, featureGate)
        }
        #endif
    }
}
