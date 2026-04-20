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
    @MainActor private static var lastLaunchedMacProcessIdentifier: pid_t?
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
        launchApp(arguments: defaultLaunchArguments, preserveExistingState: false)
    }

    @MainActor
    func relaunchAppPreservingState() {
        launchApp(arguments: statePreservingLaunchArguments, preserveExistingState: true)
    }

    /// Creates and launches the app with explicit launch arguments.
    @MainActor
    func launchApp(arguments: [String], preserveExistingState: Bool = false) {
        _ = Self.terminateCurrentApp(app, preferGraceful: preserveExistingState)
        #if os(macOS)
        XCTAssertTrue(
            Self.waitForNoRunningMacApp(timeout: 10),
            "Quartz must be fully terminated before launching the next macOS UI test instance"
        )
        app = XCUIApplication(bundleIdentifier: Self.macBundleIdentifier)
        XCTAssertTrue(
            Self.launchMacApp(arguments: arguments),
            "Quartz must launch successfully through the macOS app bundle for UI automation"
        )
        XCTAssertTrue(
            Self.waitForMacLaunchCompletion(timeout: 15),
            "Quartz must finish launching before macOS UI assertions begin"
        )
        // XCTest attaches to externally launched macOS apps a little after the
        // process is live; querying the accessibility tree immediately has been
        // host-sensitive and can wedge the first shell assertion pass.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        #endif
        #if !os(macOS)
        app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        #endif
        #if os(macOS)
        XCTAssertTrue(
            waitForMacInteractionReadiness(
                timeout: 15,
                requireWorkspaceSurface: arguments.contains("--mock-vault")
            ),
            arguments.contains("--mock-vault")
                ? "Quartz must load the mock-vault workspace before macOS UI assertions query fixture notes"
                : "Quartz must expose an interactive macOS window before UI assertions run"
        )
        #endif
    }

    #if os(macOS)
    @MainActor
    private func waitForMacInteractionReadiness(
        timeout: TimeInterval,
        requireWorkspaceSurface: Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var nextActivationAttempt = Date.distantPast

        while Date() < deadline {
            if hasInteractiveMacWindow(requireWorkspaceSurface: requireWorkspaceSurface) {
                return true
            }

            if Date() >= nextActivationAttempt {
                _ = activateRunningMacApp()
                nextActivationAttempt = Date().addingTimeInterval(1)
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return hasInteractiveMacWindow(requireWorkspaceSurface: requireWorkspaceSurface)
    }

    @MainActor
    private func waitForMacWorkspaceSurface(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if hasMacWorkspaceSurface() {
                return true
            }

            _ = activateRunningMacApp()

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return hasMacWorkspaceSurface()
    }

    @MainActor
    private func hasVisibleMacWindow() -> Bool {
        if let runningApp = Self.runningMacApplication(),
           !runningApp.isTerminated,
           runningApp.isFinishedLaunching
        {
            return true
        }

        return app.state == .runningForeground || app.state == .runningBackground
    }

    @MainActor
    private func hasForegroundMacWindow() -> Bool {
        if let runningApp = Self.runningMacApplication(), runningApp.isActive {
            return true
        }

        return app.state == .runningForeground
    }

    @MainActor
    private func hasInteractiveMacWindow(requireWorkspaceSurface: Bool) -> Bool {
        let surfaceReady = !requireWorkspaceSurface || hasMacWorkspaceSurface()
        guard surfaceReady else { return false }

        if hasForegroundMacWindow() {
            return true
        }

        return hasVisibleMacWindow()
    }

    @MainActor
    private func hasMacWorkspaceSurface() -> Bool {
        let readinessElements: [XCUIElement] = [
            element(matchingIdentifier: "sidebar-new-note"),
            element(matchingIdentifier: "note-list-new-note"),
            element(matchingIdentifier: "note-list-item-Welcome"),
            element(matchingIdentifier: "note-list-item-Todo"),
            element(matchingIdentifier: "dashboard-view"),
            element(matchingIdentifier: "editor-toolbar-link"),
            element(matchingIdentifier: "editor-text-view"),
            app.textViews.firstMatch
        ]

        for element in readinessElements where element.exists {
            return true
        }

        return false
    }

    @MainActor
    private func activateRunningMacApp() -> Bool {
        guard let runningApp = Self.runningMacApplication() else {
            return false
        }

        if runningApp.isActive {
            return true
        }

        guard runningApp.isFinishedLaunching else {
            return false
        }

        return runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    @MainActor
    private static func waitForNoRunningMacApp(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let runningApps = NSRunningApplication
                .runningApplications(withBundleIdentifier: Self.macBundleIdentifier)
                .filter { !$0.isTerminated }
            if runningApps.isEmpty {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.macBundleIdentifier)
            .allSatisfy(\.isTerminated)
    }

    @MainActor
    private static func waitForMacLaunchCompletion(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let runningApp = runningMacApplication(),
               !runningApp.isTerminated,
               runningApp.isFinishedLaunching
            {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        guard let runningApp = runningMacApplication() else { return false }
        return !runningApp.isTerminated && runningApp.isFinishedLaunching
    }

    @MainActor
    private static func runningMacApplication() -> NSRunningApplication? {
        let runningApps = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.macBundleIdentifier)
            .filter { !$0.isTerminated }

        if let preferredPID = Self.lastLaunchedMacProcessIdentifier,
           let preferredApp = runningApps.first(where: { $0.processIdentifier == preferredPID })
        {
            return preferredApp
        }

        return runningApps.max(by: { $0.processIdentifier < $1.processIdentifier })
    }

    @MainActor
    private static func launchMacApp(arguments: [String]) -> Bool {
        guard let appURL = macAppBundleURL() else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments

        var launchedApp: NSRunningApplication?
        var launchError: Error?

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { runningApp, error in
            launchedApp = runningApp
            launchError = error
        }

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if launchError != nil {
                return false
            }

            if let launchedApp, !launchedApp.isTerminated {
                Self.lastLaunchedMacProcessIdentifier = launchedApp.processIdentifier
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let launchedSuccessfully = launchError == nil && launchedApp?.isTerminated == false
        if launchedSuccessfully, let launchedApp {
            Self.lastLaunchedMacProcessIdentifier = launchedApp.processIdentifier
        }
        return launchedSuccessfully
    }

    private static func macAppBundleURL() -> URL? {
        let runnerProductsDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        let candidate = runnerProductsDirectory.appending(path: "Quartz.app")
        guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else {
            return nil
        }
        return candidate
    }
    #endif

    @discardableResult
    @MainActor
    private static func terminateCurrentApp(_ currentApp: XCUIApplication?, preferGraceful: Bool = false) -> Bool {
        let existingApp = currentApp ?? XCUIApplication()

        if preferGraceful, existingApp.state != .notRunning {
            existingApp.terminate()
            let appExited = existingApp.wait(for: .notRunning, timeout: 5)
            if appExited {
                #if os(macOS)
                if Self.waitForNoRunningMacApp(timeout: 5) {
                    return true
                }
                #else
                return true
                #endif
            }
        }

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
            let terminated = Self.waitForNoRunningMacApp(timeout: 10)
            if terminated {
                Self.lastLaunchedMacProcessIdentifier = nil
            }
            return terminated
        }
        #endif

        guard existingApp.state != .notRunning else {
            return false
        }

        existingApp.terminate()
        _ = existingApp.wait(for: .notRunning, timeout: 5)
        #if os(macOS)
        let terminated = Self.waitForNoRunningMacApp(timeout: 5)
        if terminated {
            Self.lastLaunchedMacProcessIdentifier = nil
        }
        return terminated
        #else
        return true
        #endif
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
        #if os(macOS)
        if let preferred = preferredMacElement(matchingIdentifier: identifier) {
            return preferred
        }
        #endif
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    #if os(macOS)
    @MainActor
    private func preferredMacElement(matchingIdentifier identifier: String) -> XCUIElement? {
        let targetedQueries: [XCUIElementQuery]

        switch identifier {
        case "workspace-split-view":
            targetedQueries = [
                app.descendants(matching: .splitGroup),
                app.descendants(matching: .group),
                app.windows
            ]
        case "note-list-view":
            targetedQueries = [
                app.descendants(matching: .outline),
                app.descendants(matching: .scrollView),
                app.descendants(matching: .collectionView),
                app.descendants(matching: .group)
            ]
        case "sidebar-new-note", "note-list-new-note", "editor-toolbar-link":
            targetedQueries = [
                app.buttons,
                app.descendants(matching: .button),
                app.toolbars.buttons
            ]
        case let value where value.hasPrefix("note-list-item-"):
            targetedQueries = [
                app.outlineRows,
                app.cells,
                app.buttons,
                app.staticTexts
            ]
        case "dashboard-view":
            targetedQueries = [
                app.descendants(matching: .group),
                app.descendants(matching: .other)
            ]
        case "editor-text-view", "editor-find-query":
            targetedQueries = [
                app.descendants(matching: .textView),
                app.descendants(matching: .textField),
                app.descendants(matching: .scrollView)
            ]
        default:
            targetedQueries = [
                app.descendants(matching: .button),
                app.descendants(matching: .textField),
                app.descendants(matching: .textView),
                app.descendants(matching: .menuItem),
                app.descendants(matching: .group),
                app.descendants(matching: .other)
            ]
        }

        for query in targetedQueries {
            let match = query.matching(identifier: identifier).firstMatch
            if match.exists {
                return match
            }
        }

        return targetedQueries.first?.matching(identifier: identifier).firstMatch
    }
    #endif

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
    func replaceEditorText(
        with text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let editor = focusEditor(file: file, line: line)
        #if os(macOS)
        app.typeKey("a", modifierFlags: .command)
        #endif
        editor.typeText(text)
        assertEditorContains(text, file: file, line: line)
        return editor
    }

    @MainActor
    func clearEditorText(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let editor = focusEditor(file: file, line: line)
        #if os(macOS)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        #endif
        return editor
    }

    @MainActor
    func editorTextValue(file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let text = editorTextValueIfAvailable() else {
            XCTFail("Editor value must be readable as text", file: file, line: line)
            return ""
        }

        return text
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
    func waitForEditorToContain(
        _ substring: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = editorTextValueIfAvailable(), text.contains(substring) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return editorTextValueIfAvailable()?.contains(substring) == true
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
    private func editorTextValueIfAvailable() -> String? {
        var candidateValues: [String] = []

        let identifiedEditor = element(matchingIdentifier: "editor-text-view")
        if identifiedEditor.exists {
            if let text = identifiedEditor.value as? String {
                candidateValues.append(text)
            }
            if let value = identifiedEditor.value {
                candidateValues.append(String(describing: value))
            }
        }

        let fallbackEditor = app.textViews.firstMatch
        if fallbackEditor.exists {
            if let text = fallbackEditor.value as? String {
                candidateValues.append(text)
            }
            if let value = fallbackEditor.value {
                candidateValues.append(String(describing: value))
            }
        }

        if let nonEmpty = candidateValues.first(where: { !$0.isEmpty }) {
            return nonEmpty
        }

        return candidateValues.first
    }

    @MainActor
    func openMockVaultNote(
        matchingAnyOf titles: [String],
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let filteredTitles = titles.filter { !$0.isEmpty }
        guard !filteredTitles.isEmpty else { return nil }

        let predicate = NSCompoundPredicate(
            orPredicateWithSubpredicates: filteredTitles.map {
                NSPredicate(format: "label CONTAINS[c] %@", $0)
            }
        )
        var scopedQueries: [XCUIElementQuery] = [
            app.outlineRows,
            app.cells,
            app.staticTexts,
            app.buttons
        ]
        var identifierQueries: [XCUIElementQuery] = [
            app.outlineRows,
            app.cells,
            app.buttons,
            app.staticTexts
        ]

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for title in filteredTitles {
                let identifier = "note-list-item-\(title)"
                for query in identifierQueries {
                    let match = query.matching(identifier: identifier).firstMatch
                    if match.exists {
                        interact(with: match)
                        _ = waitForEditorSurface(timeout: min(timeout, 5))
                        return match
                    }
                }
            }

            for query in scopedQueries {
                let match = query.matching(predicate).firstMatch
                if match.exists {
                    interact(with: match)
                    _ = waitForEditorSurface(timeout: min(timeout, 5))
                    return match
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return nil
    }

    @MainActor
    func createNewNote(timeout: TimeInterval = 10) -> Bool {
        let uniqueToken = "UITest\(UUID().uuidString.prefix(8))"
        let previousEditorText = waitForEditorSurface(timeout: 1) ? editorTextValue() : nil

        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        if finalizeNewNoteCreation(
            uniqueToken: uniqueToken,
            previousEditorText: previousEditorText,
            timeout: timeout
        ) {
            return true
        }
        #endif

        let candidates = [
            element(matchingIdentifier: "note-list-new-note"),
            element(matchingIdentifier: "sidebar-new-note"),
            app.buttons["New Note"]
        ]

        for candidate in candidates {
            if candidate.waitForExistence(timeout: min(timeout, 3)) {
                interact(with: candidate)
                _ = selectNewTextNoteMenuItemIfNeeded(timeout: min(timeout, 2))
                if finalizeNewNoteCreation(
                    uniqueToken: uniqueToken,
                    previousEditorText: previousEditorText,
                    timeout: timeout
                ) {
                    return true
                }
            }
        }

        return false
    }

    @MainActor
    private func finalizeNewNoteCreation(
        uniqueToken: String,
        previousEditorText: String?,
        timeout: TimeInterval
    ) -> Bool {
        guard completeNewNotePrompt(uniqueToken: uniqueToken, timeout: timeout) else {
            return false
        }

        guard waitForEditorSurface(timeout: timeout) else {
            return false
        }

        guard let previousEditorText else { return true }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if editorTextValue() != previousEditorText {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return false
    }

    @MainActor
    private func selectNewTextNoteMenuItemIfNeeded(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let menuCandidates = [
            app.buttons["New Text Note"],
            app.menuItems["New Text Note"],
            app.staticTexts["New Text Note"]
        ]

        while Date() < deadline {
            for candidate in menuCandidates where candidate.exists {
                interact(with: candidate)
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return false
    }

    @MainActor
    private func completeNewNotePrompt(uniqueToken: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let createButtons = [
            app.alerts.buttons["Create"],
            app.dialogs.buttons["Create"],
            app.sheets.buttons["Create"],
            app.buttons.matching(NSPredicate(format: "label == %@", "Create")).firstMatch
        ]

        while Date() < deadline {
            let textField = noteCreationTextField()
            if textField.exists {
                interact(with: textField)
                textField.typeText(uniqueToken)

                for createButton in createButtons where createButton.exists {
                    interact(with: createButton)
                    return true
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return false
    }

    @MainActor
    private func noteCreationTextField() -> XCUIElement {
        let predicate = NSPredicate(
            format: "label == %@ OR placeholderValue == %@ OR value == %@",
            "Note name",
            "Note name",
            "Note name"
        )

        let scopedCandidates = [
            app.alerts.textFields.matching(predicate).firstMatch,
            app.dialogs.textFields.matching(predicate).firstMatch,
            app.sheets.textFields.matching(predicate).firstMatch,
            app.textFields.matching(predicate).firstMatch
        ]

        for candidate in scopedCandidates where candidate.exists {
            return candidate
        }

        return app.textFields.matching(predicate).firstMatch
    }

    @MainActor
    func interact(with element: XCUIElement) {
        #if os(macOS)
        _ = activateRunningMacApp()
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
