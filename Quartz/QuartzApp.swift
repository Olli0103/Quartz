import SwiftUI
import QuartzKit
#if os(macOS)
import AppKit
#endif

#if os(macOS)
@MainActor
private enum QuartzUITestActivationCoordinator {
    static func activateIfNeeded() async {
        guard CommandLine.arguments.contains("--uitesting") else { return }

        for _ in 0..<80 {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)

            if let window = NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized }) ?? NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

@MainActor
private final class QuartzUITestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await QuartzUITestActivationCoordinator.activateIfNeeded() }
    }
}
#endif

@main
struct QuartzApp: App {
    private static let fixtureVaultPathKey = "quartz.uitest.fixtureVaultPath"
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()
    @State private var focusModeManager = FocusModeManager()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(QuartzUITestAppDelegate.self) private var uiTestAppDelegate
    #endif

    /// Returns true if the app was launched with UI testing flags.
    private static var isUITesting: Bool {
        CommandLine.arguments.contains("--uitesting")
    }

    /// UI tests only reset state when explicitly requested.
    private static var shouldResetUITestingState: Bool {
        CommandLine.arguments.contains("--reset-state")
    }

    /// Auto-create and open a fixture vault instead of showing the vault picker.
    private static var shouldMockVault: Bool {
        CommandLine.arguments.contains("--mock-vault")
            && !CommandLine.arguments.contains("--force-onboarding")
    }

    /// Disable animations for deterministic UI testing.
    private static var shouldDisableAnimations: Bool {
        CommandLine.arguments.contains("--disable-animations")
    }

    init() {
        // Reset state for UI testing to ensure a clean slate
        if Self.shouldResetUITestingState {
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
        defaults.removeObject(forKey: fixtureVaultPathKey)
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
            let defaults = UserDefaults.standard

            if !Self.shouldResetUITestingState,
               let fixtureVaultPath = defaults.string(forKey: fixtureVaultPathKey) {
                let fixtureURL = URL(fileURLWithPath: fixtureVaultPath, isDirectory: true)
                if FileManager.default.fileExists(atPath: fixtureURL.path(percentEncoded: false)) {
                    defaults.set(true, forKey: "quartz.hasCompletedOnboarding")
                    defaults.set(
                        defaults.string(forKey: "quartz.lastVault.name") ?? fixtureURL.lastPathComponent,
                        forKey: "quartz.lastVault.name"
                    )
                    defaults.set(fixtureURL.path(percentEncoded: false), forKey: fixtureVaultPathKey)
                    defaults.synchronize()
                    return
                }
            }

            let vault = try UITestFixtureVault.create()
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
            defaults.set(vault.rootURL.path(percentEncoded: false), forKey: fixtureVaultPathKey)
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
                    #if os(macOS)
                    await QuartzUITestActivationCoordinator.activateIfNeeded()
                    #endif
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
                onPasteAction: { mode in appState.pendingCommand = .paste(mode) },
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
