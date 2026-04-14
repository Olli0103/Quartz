import XCTest
#if os(macOS)
import AppKit
#endif

/// Shared base class for Quartz UI smoke tests.
///
/// Provides:
/// - Standard launch arguments (`--uitesting`, `--reset-state`, `--mock-vault`, `--disable-animations`)
/// - Screenshot attachment helper
/// - Platform detection helpers
///
/// Each `@MainActor` test method must call `launchApp()` at the start.
class QuartzUITestCase: XCTestCase {
    #if os(macOS)
    private static let macBundleIdentifier = "olli.QuartzNotes"
    #endif

    private let defaultLaunchArguments = [
        "--uitesting",
        "--reset-state",
        "--mock-vault",
        "--disable-animations"
    ]

    /// Set by `launchApp()` — available to all test methods.
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        terminateCurrentAppIfNeeded()
        app = nil
    }

    // MARK: - Launch

    /// Creates and launches the app with standard UI-testing arguments.
    /// Call this at the start of each `@MainActor` test method.
    @MainActor
    func launchApp() {
        launchApp(arguments: defaultLaunchArguments)
    }

    /// Creates and launches the app with explicit launch arguments.
    @MainActor
    func launchApp(arguments: [String]) {
        terminateCurrentAppIfNeeded()
        app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        #if os(macOS)
        if app.state == .runningBackground {
            app.activate()
        }
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Quartz must reach the foreground on macOS before UI assertions run"
        )
        #endif
    }

    @discardableResult
    private func terminateCurrentAppIfNeeded() -> Bool {
        #if os(macOS)
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.macBundleIdentifier)
        var terminatedAny = false
        for runningApp in runningApps {
            terminatedAny = true
            runningApp.terminate()
            let deadline = Date().addingTimeInterval(5)
            while !runningApp.isTerminated && deadline.timeIntervalSinceNow > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if !runningApp.isTerminated {
                runningApp.forceTerminate()
            }
        }

        if terminatedAny {
            return true
        }
        #endif

        let existingApp = app ?? XCUIApplication()
        guard existingApp.state != .notRunning else {
            return false
        }

        existingApp.terminate()
        _ = existingApp.wait(for: .notRunning, timeout: 5)
        return true
    }

    // MARK: - Helpers

    /// Captures a screenshot and attaches it to the test report with `.keepAlways` lifetime.
    @MainActor
    func takeScreenshot(named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Captures a screenshot, asserts it has non-zero dimensions (proves rendering occurred),
    /// and attaches it to the test report. Use in `testScreenshotCapture` methods to create
    /// deterministic visual baselines.
    ///
    /// - Note: For pixel-level diffing, adopt `swift-snapshot-testing` and compare against
    ///   reference images stored under a `__Snapshots__` directory.
    @MainActor
    func assertScreenshotNonEmpty(named name: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = app.screenshot()
        let image = screenshot.image
        #if os(macOS)
        let size = image.size
        #else
        let size = image.size  // UIImage.size is in points
        #endif
        XCTAssertGreaterThan(size.width, 0,
                             "\(name): screenshot width must be > 0", file: file, line: line)
        XCTAssertGreaterThan(size.height, 0,
                             "\(name): screenshot height must be > 0", file: file, line: line)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Accessibility Helpers

    @MainActor
    func element(matchingIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func waitForEditorSurface(timeout: TimeInterval) -> Bool {
        let identifiedEditor = element(matchingIdentifier: "editor-text-view")
        if identifiedEditor.waitForExistence(timeout: timeout) {
            return true
        }

        return app.textViews.firstMatch.waitForExistence(timeout: min(timeout, 5))
    }

    /// Asserts that the element has a non-empty accessibility label.
    /// Use this to enforce that UI controls are properly labeled for VoiceOver.
    @MainActor
    func assertAccessibilityLabelNonEmpty(_ element: XCUIElement, context: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let label = element.label
        XCTAssertFalse(label.isEmpty,
                       "\(context): accessibility label must not be empty",
                       file: file, line: line)
    }

    // MARK: - Platform Detection

    var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}
