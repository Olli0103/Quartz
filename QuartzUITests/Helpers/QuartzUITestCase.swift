import XCTest
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
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

    private let statePreservingLaunchArguments = [
        "--uitesting",
        "--mock-vault",
        "--disable-animations"
    ]

    /// Set by `launchApp()` — available to all test methods.
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let currentApp = app
        _ = MainActor.assumeIsolated { Self.terminateCurrentApp(currentApp) }
        app = nil
    }

    // MARK: - Launch

    /// Creates and launches the app with standard UI-testing arguments.
    /// Call this at the start of each `@MainActor` test method.
    @MainActor
    func launchApp() {
        launchApp(arguments: defaultLaunchArguments)
    }

    @MainActor
    func relaunchAppPreservingState() {
        launchApp(arguments: statePreservingLaunchArguments)
    }

    /// Creates and launches the app with explicit launch arguments.
    @MainActor
    func launchApp(arguments: [String]) {
        _ = Self.terminateCurrentApp(app)
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
    @MainActor
    private static func terminateCurrentApp(_ currentApp: XCUIApplication?) -> Bool {
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

        let existingApp = currentApp ?? XCUIApplication()
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

    @MainActor
    func editorSurface(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let fallback = app.textViews.firstMatch
        if fallback.exists {
            return fallback
        }

        let identifiedEditor = element(matchingIdentifier: "editor-text-view")
        XCTAssertTrue(identifiedEditor.exists || fallback.exists,
                      "Editor surface must exist before querying it",
                      file: file,
                      line: line)
        return identifiedEditor
    }

    @MainActor
    func focusEditor(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForEditorSurface(timeout: 10),
                      "Editor surface must exist before focusing it",
                      file: file,
                      line: line)
        let editor = editorSurface(file: file, line: line)
        interact(with: editor)
        return editor
    }

    @MainActor
    func editorTextValue(file: StaticString = #filePath, line: UInt = #line) -> String {
        let editor = editorSurface(file: file, line: line)
        if let text = editor.value as? String {
            return text
        }
        if let value = editor.value {
            return String(describing: value)
        }

        XCTFail("Editor value must be readable as text", file: file, line: line)
        return ""
    }

    @MainActor
    func assertEditorContains(
        _ substring: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if editorTextValue(file: file, line: line).contains(substring) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let actual = editorTextValue(file: file, line: line)
        XCTFail(
            "Editor text must contain '\(substring)'. Actual editor text:\n\(actual)",
            file: file,
            line: line
        )
    }

    @MainActor
    func assertEditorNotContains(
        _ substring: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !editorTextValue(file: file, line: line).contains(substring) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let actual = editorTextValue(file: file, line: line)
        XCTFail(
            "Editor text must not contain '\(substring)'. Actual editor text:\n\(actual)",
            file: file,
            line: line
        )
    }

    @MainActor
    func openMockVaultNote(named title: String, timeout: TimeInterval = 10) -> XCUIElement? {
        openMockVaultNote(matchingAnyOf: [title], timeout: timeout)
    }

    @MainActor
    func openMockVaultNote(
        matchingAnyOf titles: [String],
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let filteredTitles = titles.filter { !$0.isEmpty }
        guard !filteredTitles.isEmpty else { return nil }

        let noteList = element(matchingIdentifier: "note-list-view")
        _ = noteList.waitForExistence(timeout: timeout)

        let predicate = NSCompoundPredicate(
            orPredicateWithSubpredicates: filteredTitles.map {
                NSPredicate(format: "label CONTAINS[c] %@", $0)
            }
        )
        let scopedQueries: [XCUIElementQuery] = [
            noteList.descendants(matching: .any),
            app.outlineRows,
            app.cells,
            app.staticTexts,
            app.buttons
        ]

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in scopedQueries {
                let match = query.matching(predicate).firstMatch
                if match.exists {
                    interact(with: match)
                    return match
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return nil
    }

    @MainActor
    func createNewNote(timeout: TimeInterval = 10) -> Bool {
        let candidates = [
            element(matchingIdentifier: "note-list-new-note"),
            element(matchingIdentifier: "sidebar-new-note"),
            app.buttons["New Note"]
        ]

        for candidate in candidates {
            if candidate.waitForExistence(timeout: min(timeout, 3)) {
                interact(with: candidate)
                return waitForEditorSurface(timeout: timeout)
            }
        }

        return false
    }

    @MainActor
    func interact(with element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    @MainActor
    func triggerOverflowFormattingAction(
        _ actionIdentifier: String,
        fallbackLabel: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let overflowMenu = element(matchingIdentifier: "editor-toolbar-overflow-menu")
        XCTAssertTrue(
            overflowMenu.waitForExistence(timeout: timeout),
            "Overflow formatting menu must exist before selecting \(actionIdentifier)",
            file: file,
            line: line
        )
        interact(with: overflowMenu)

        let identifiedAction = element(matchingIdentifier: "editor-toolbar-\(actionIdentifier)")
        if identifiedAction.waitForExistence(timeout: min(timeout, 2)) {
            interact(with: identifiedAction)
            return
        }

        let labeledAction = app.buttons[fallbackLabel]
        XCTAssertTrue(
            labeledAction.waitForExistence(timeout: timeout),
            "Overflow action '\(fallbackLabel)' must exist",
            file: file,
            line: line
        )
        interact(with: labeledAction)
    }

    @MainActor
    func setPasteboardText(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        #else
        false
        #endif
    }

    var isPad: Bool {
        #if os(iOS)
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
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
