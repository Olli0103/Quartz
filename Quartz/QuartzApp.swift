import SwiftUI
import QuartzKit
#if os(macOS)
import AppKit
#endif

#if os(macOS)
@MainActor
private enum QuartzUITestLaunchOptions {
    static let shellModeArgument = "--ui-test-shell-mode"

    static var isUITesting: Bool {
        CommandLine.arguments.contains("--uitesting")
    }

    static var isShellMode: Bool {
        isUITesting && CommandLine.arguments.contains(shellModeArgument)
    }
}

@MainActor
private enum QuartzUITestActivationCoordinator {
    private static var announcedWindowIDs: Set<ObjectIdentifier> = []

    static func primaryWindow() -> NSWindow? {
        NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized })
            ?? NSApp.windows.first(where: { !$0.isMiniaturized })
            ?? NSApp.windows.first
    }

    static func configureApplication() {
        guard QuartzUITestLaunchOptions.isShellMode else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
    }

    static func promotePrimaryWindow(reason _: String) {
        guard QuartzUITestLaunchOptions.isShellMode else { return }

        configureApplication()
        NSApp.activate()
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])

        guard let window = primaryWindow() else { return }

        window.isRestorable = false
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        let windowID = ObjectIdentifier(window)
        if announcedWindowIDs.insert(windowID).inserted {
            NSAccessibility.post(element: window, notification: .windowCreated)
        }
    }
}

@MainActor
private enum QuartzUITestWindowBootstrap {
    static var makeRootView: (() -> AnyView)?
    private static var fallbackWindow: NSWindow?

    static func ensureFallbackWindow() {
        guard QuartzUITestLaunchOptions.isShellMode else { return }
        guard QuartzUITestActivationCoordinator.primaryWindow() == nil else { return }

        if let window = fallbackWindow {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "fallback-window-reuse")
            return
        }

        guard let makeRootView else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("ui-test-main-window")
        window.title = "Quartz Notes"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.contentViewController = NSHostingController(rootView: makeRootView())

        fallbackWindow = window
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSAccessibility.post(element: window, notification: .windowCreated)
        QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "fallback-window-create")
    }

    static func clearFallbackWindow() {
        fallbackWindow?.close()
        fallbackWindow = nil
        makeRootView = nil
    }
}

extension Notification.Name {
    static let quartzApplicationWillTerminate = Notification.Name("quartzApplicationWillTerminate")
}

@MainActor
private final class QuartzUITestAppDelegate: NSObject, NSApplicationDelegate {
    private var activationObservers: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        QuartzUITestActivationCoordinator.configureApplication()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "did-finish-launching")

        guard QuartzUITestLaunchOptions.isShellMode else { return }
        Task { @MainActor in
            await Task.yield()
            QuartzUITestWindowBootstrap.ensureFallbackWindow()
        }
        let center = NotificationCenter.default
        activationObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "window-became-key")
                }
            }
        )
        activationObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "window-became-main")
                }
            }
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "application-did-become-active")
        QuartzUITestWindowBootstrap.ensureFallbackWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        QuartzUITestWindowBootstrap.ensureFallbackWindow()
        QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "application-reopen")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        activationObservers.forEach(NotificationCenter.default.removeObserver)
        activationObservers.removeAll()
        QuartzUITestWindowBootstrap.clearFallbackWindow()
        NotificationCenter.default.post(name: .quartzApplicationWillTerminate, object: nil)
    }
}
#endif

@main
struct QuartzApp: App {
    private static let fixtureVaultPathKey = "quartz.uitest.fixtureVaultPath"
    @State private var appState: AppState
    @State private var appearanceManager: AppearanceManager
    @State private var focusModeManager: FocusModeManager
    #if os(macOS)
    @NSApplicationDelegateAdaptor(QuartzUITestAppDelegate.self) private var uiTestAppDelegate
    #endif

    /// Returns true if the app was launched with UI testing flags.
    private static var isUITesting: Bool {
        #if os(macOS)
        QuartzUITestLaunchOptions.isUITesting
        #else
        CommandLine.arguments.contains("--uitesting")
        #endif
    }

    private static var isUITestShellMode: Bool {
        #if os(macOS)
        QuartzUITestLaunchOptions.isShellMode
        #else
        false
        #endif
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
        let appState = AppState()
        let appearanceManager = AppearanceManager()
        let focusModeManager = FocusModeManager()
        _appState = State(initialValue: appState)
        _appearanceManager = State(initialValue: appearanceManager)
        _focusModeManager = State(initialValue: focusModeManager)
        #if os(macOS)
        QuartzUITestWindowBootstrap.makeRootView = {
            AnyView(
                Self.makeMainRootView(
                    appState: appState,
                    appearanceManager: appearanceManager,
                    focusModeManager: focusModeManager
                )
            )
        }
        #endif
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
        defaults.removeObject(forKey: "quartz.restoration.selectedNotePath")
        defaults.removeObject(forKey: "quartz.restoration.cursorLocation")
        defaults.removeObject(forKey: "quartz.restoration.cursorLength")
        defaults.removeObject(forKey: "quartz.restoration.scrollOffset")
        defaults.removeObject(forKey: "quartz.restoration.sidebarSource")
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

    @ViewBuilder
    private var mainSceneRootView: some View {
        Self.makeMainRootView(
            appState: appState,
            appearanceManager: appearanceManager,
            focusModeManager: focusModeManager
        )
    }

    @ViewBuilder
    private static func makeMainRootView(
        appState: AppState,
        appearanceManager: AppearanceManager,
        focusModeManager: FocusModeManager
    ) -> some View {
        ContentView()
            .environment(appState)
            .environment(\.appearanceManager, appearanceManager)
            .environment(\.focusModeManager, focusModeManager)
            .preferredColorScheme(appearanceManager.theme.colorScheme)
            .tint(appearanceManager.accentColor)
            .task {
                #if os(macOS)
                QuartzUITestActivationCoordinator.promotePrimaryWindow(reason: "main-window-task")
                QuartzUITestWindowBootstrap.ensureFallbackWindow()
                #endif
                ServiceContainer.shared.bootstrap()
                if !Self.isUITestShellMode {
                    VaultAccessManager.shared.startObservingRemoteChanges()
                }
            }
    }

    var body: some Scene {
        #if os(macOS)
        Window("Quartz Notes", id: "ui-test-main-window") {
            if Self.isUITestShellMode {
                mainSceneRootView
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 1100, height: 700)
        .defaultLaunchBehavior(Self.isUITestShellMode ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        WindowGroup {
            if Self.isUITestShellMode {
                EmptyView()
            } else {
                mainSceneRootView
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
        .defaultSize(width: 1100, height: 700)
        .defaultLaunchBehavior(Self.isUITestShellMode ? .suppressed : .presented)
        #else
        WindowGroup {
            mainSceneRootView
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
