import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()
    @State private var focusModeManager = FocusModeManager()

    /// Returns true if the app was launched with UI testing flags.
    private static var isUITesting: Bool {
        CommandLine.arguments.contains("--uitesting")
    }

    /// Auto-create and open a fixture vault instead of showing the vault picker.
    private static var shouldMockVault: Bool {
        CommandLine.arguments.contains("--mock-vault")
    }

    /// Disable animations for deterministic UI testing.
    private static var shouldDisableAnimations: Bool {
        CommandLine.arguments.contains("--disable-animations")
    }

    init() {
        // Reset state for UI testing to ensure a clean slate
        if Self.isUITesting {
            Self.resetUITestingState()
        }
        if Self.shouldDisableAnimations {
            Self.disableAnimations()
        }
        if Self.shouldMockVault {
            Self.setupMockVault()
        }
    }

    /// Clears persisted state for UI testing.
    private static func resetUITestingState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "quartz.hasCompletedOnboarding")
        defaults.removeObject(forKey: "quartz.lastVault.bookmark")
        defaults.removeObject(forKey: "quartz.lastVault.name")
        defaults.removeObject(forKey: "quartz.appLockEnabled")
        defaults.removeObject(forKey: "quartz.lockTimeoutMinutes")
        defaults.synchronize()
    }

    /// Disable all animations for deterministic UI test snapshots.
    private static func disableAnimations() {
        #if os(iOS)
        UIView.setAnimationsEnabled(false)
        #elseif os(macOS)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.endGrouping()
        #endif
    }

    /// Create a fixture vault and mark onboarding as complete so the app launches
    /// directly into the workspace with known content.
    private static func setupMockVault() {
        do {
            let vault = try UITestFixtureVault.create()
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "quartz.hasCompletedOnboarding")
            defaults.set(vault.name, forKey: "quartz.lastVault.name")
            // Persist a bookmark matching VaultAccessManager's expected format
            #if os(macOS)
            let bookmarkData = try vault.rootURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            let bookmarkData = try vault.rootURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif
            defaults.set(bookmarkData, forKey: "quartz.lastVault.bookmark")
            defaults.synchronize()
        } catch {
            print("UITest: Failed to create fixture vault: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.appearanceManager, appearanceManager)
                .environment(\.focusModeManager, focusModeManager)
                .preferredColorScheme(appearanceManager.theme.colorScheme)
                .tint(appearanceManager.accentColor)
                .task {
                    ServiceContainer.shared.bootstrap()
                    VaultAccessManager.shared.startObservingRemoteChanges()
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
