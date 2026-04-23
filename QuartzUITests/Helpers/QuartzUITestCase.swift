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
    private static let macShellModeArgument = "--ui-test-shell-mode"
    private static let knownInterruptingMacBundleIdentifiers: Set<String> = [
        "com.microsoft.Outlook",
        "com.granola.app",
        "com.raycast.macos",
        "com.google.Chrome"
    ]
    private static let macToolbarAccessibilityLabelsByIdentifier = [
        "editor-formatting-toolbar": "Formatting Toolbar",
        "editor-toolbar-undo": "Undo",
        "editor-toolbar-redo": "Redo",
        "editor-toolbar-bold": "Bold",
        "editor-toolbar-italic": "Italic",
        "editor-toolbar-strikethrough": "Strikethrough",
        "editor-toolbar-heading-menu": "Heading level",
        "editor-toolbar-bulletList": "Bullet List",
        "editor-toolbar-numberedList": "Numbered List",
        "editor-toolbar-checkbox": "Checkbox",
        "editor-toolbar-code": "Inline Code",
        "editor-toolbar-link": "Link",
        "editor-toolbar-overflow-menu": "More formatting options",
        "editor-toolbar-ai-assistant": "AI Assistant",
        "editor-toolbar-export": "Export note",
        "editor-find-button": "Find in Note",
        "editor-toolbar-focus-mode": "Focus Mode",
        "editor-toolbar-inspector": "Inspector",
        "editor-toolbar-paragraph": "Paragraph",
        "editor-toolbar-heading1": "Heading 1",
        "editor-toolbar-heading2": "Heading 2",
        "editor-toolbar-heading3": "Heading 3",
        "editor-toolbar-heading4": "Heading 4",
        "editor-toolbar-heading5": "Heading 5",
        "editor-toolbar-heading6": "Heading 6",
        "editor-toolbar-codeBlock": "Code Block",
        "editor-toolbar-blockquote": "Quote",
        "editor-toolbar-table": "Table",
        "editor-toolbar-image": "Image",
        "editor-toolbar-math": "Math",
        "editor-toolbar-mermaid": "Mermaid Diagram"
    ]
    private static let macTopLevelFormattingToolbarIdentifiers = [
        "editor-toolbar-undo",
        "editor-toolbar-redo",
        "editor-toolbar-bold",
        "editor-toolbar-italic",
        "editor-toolbar-strikethrough",
        "editor-toolbar-heading-menu",
        "editor-toolbar-bulletList",
        "editor-toolbar-numberedList",
        "editor-toolbar-checkbox",
        "editor-toolbar-code",
        "editor-toolbar-link",
        "editor-toolbar-overflow-menu",
        "editor-toolbar-ai-assistant"
    ]
    private static let macFormattingToolbarReadyIdentifiers = [
        "editor-toolbar-bold",
        "editor-toolbar-heading-menu",
        "editor-toolbar-overflow-menu"
    ]
    private static let macHeadingToolbarMenuActionIdentifiers: Set<String> = [
        "editor-toolbar-paragraph",
        "editor-toolbar-heading1",
        "editor-toolbar-heading2",
        "editor-toolbar-heading3",
        "editor-toolbar-heading4",
        "editor-toolbar-heading5",
        "editor-toolbar-heading6"
    ]
    private static let macOverflowToolbarPanelActionIdentifiers: Set<String> = [
        "editor-toolbar-codeBlock",
        "editor-toolbar-blockquote",
        "editor-toolbar-table",
        "editor-toolbar-image",
        "editor-toolbar-math",
        "editor-toolbar-mermaid"
    ]
    private static let macToolbarTopLevelMenuIdentifiers: Set<String> = [
        "editor-toolbar-heading-menu"
    ]
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
        XCTAssertTrue(
            waitForEditorSurface(timeout: 20),
            "Editor surface must return after a state-preserving relaunch before downstream assertions run"
        )
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
        app = XCUIApplication()
        app.launchArguments = arguments + [Self.macShellModeArgument]
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "Quartz must launch into a foreground automatable state under macOS XCTest"
        )
        #endif
        #if !os(macOS)
        app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        #endif
        #if os(macOS)
        XCTAssertTrue(
            waitForMacShellReadiness(
                timeout: 15,
                requireWorkspaceSurface: arguments.contains("--mock-vault")
            ),
            arguments.contains("--mock-vault")
                ? "Quartz must expose a queryable mock-vault workspace before macOS UI assertions query fixture notes"
                : "Quartz must expose a queryable macOS shell window before UI assertions run"
        )
        #endif
    }

    #if os(macOS)
    @MainActor
    private func waitForMacShellReadiness(
        timeout: TimeInterval,
        requireWorkspaceSurface: Bool
    ) -> Bool {
        if !app.windows.firstMatch.waitForExistence(timeout: timeout) {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if requireWorkspaceSurface {
                let workspaceReady = element(matchingIdentifier: "ui-test-workspace-ready")
                if workspaceReady.exists || hasMacWorkspaceSurface() {
                    return true
                }
            } else if app.state == .runningForeground {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return requireWorkspaceSurface ? hasMacWorkspaceSurface() : app.state == .runningForeground
    }

    @MainActor
    private func hasMacWorkspaceSurface() -> Bool {
        let readinessElements: [XCUIElement] = [
            app.outlines.firstMatch,
            app.outlineRows.firstMatch,
            element(matchingIdentifier: "sidebar-new-note"),
            element(matchingIdentifier: "note-list-new-note"),
            element(matchingIdentifier: "note-list-item-Welcome"),
            element(matchingIdentifier: "note-list-item-Todo"),
            element(matchingIdentifier: "dashboard-view"),
            element(matchingIdentifier: "editor-toolbar-bold"),
            element(matchingIdentifier: "editor-text-view"),
            app.textViews.firstMatch
        ]

        for element in readinessElements where element.exists {
            return true
        }

        return false
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
    #endif

    @discardableResult
    @MainActor
    private static func terminateCurrentApp(_ currentApp: XCUIApplication?, preferGraceful: Bool = false) -> Bool {
        let existingApp = currentApp ?? XCUIApplication()

        if preferGraceful, existingApp.state != .notRunning {
            #if os(macOS)
            if existingApp.state != .runningForeground {
                existingApp.activate()
                _ = existingApp.wait(for: .runningForeground, timeout: 5)
            }
            existingApp.typeKey("q", modifierFlags: .command)
            #else
            existingApp.terminate()
            #endif
            let appExited = existingApp.wait(for: .notRunning, timeout: 10)
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
            return terminated
        }
        #endif

        guard existingApp.state != .notRunning else {
            return false
        }

        existingApp.terminate()
        _ = existingApp.wait(for: .notRunning, timeout: 5)
        #if os(macOS)
        return Self.waitForNoRunningMacApp(timeout: 5)
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
        let activeWindow = app.windows.firstMatch
        let targetedQueries: [XCUIElementQuery]

        switch identifier {
        case "ui-test-workspace-ready":
            targetedQueries = [
                app.staticTexts,
                app.descendants(matching: .staticText),
                app.descendants(matching: .group),
                app.descendants(matching: .other)
            ]
        case "workspace-split-view":
            targetedQueries = [
                app.descendants(matching: .splitGroup),
                app.descendants(matching: .group),
                app.windows
            ]
        case "editor-formatting-toolbar":
            targetedQueries = [
                app.toolbars.descendants(matching: .group),
                app.descendants(matching: .group),
                app.descendants(matching: .other)
            ]
        case "editor-toolbar-overflow-panel":
            targetedQueries = [
                activeWindow.descendants(matching: .group),
                activeWindow.descendants(matching: .other)
            ]
        case "note-list-view":
            targetedQueries = [
                app.descendants(matching: .outline),
                app.descendants(matching: .scrollView),
                app.descendants(matching: .collectionView),
                app.descendants(matching: .group)
            ]
        case "sidebar-new-note", "note-list-new-note":
            targetedQueries = [
                app.buttons,
                app.descendants(matching: .button),
                app.toolbars.buttons
            ]
        case let value where Self.macHeadingToolbarMenuActionIdentifiers.contains(value):
            targetedQueries = [
                app.descendants(matching: .menuItem),
                app.menuItems
            ]
        case let value where Self.macOverflowToolbarPanelActionIdentifiers.contains(value):
            targetedQueries = [
                activeWindow.descendants(matching: .button),
                app.buttons,
                activeWindow.descendants(matching: .group),
                activeWindow.descendants(matching: .other)
            ]
        case let value where Self.macToolbarTopLevelMenuIdentifiers.contains(value):
            targetedQueries = [
                app.toolbars.descendants(matching: .menuButton),
                activeWindow.descendants(matching: .menuButton),
                app.toolbars.buttons,
                activeWindow.descendants(matching: .button),
                activeWindow.descendants(matching: .image),
                activeWindow.descendants(matching: .group),
                activeWindow.descendants(matching: .other)
            ]
        case let value where value.hasPrefix("editor-toolbar-") || value == "editor-find-button":
            targetedQueries = [
                app.toolbars.buttons,
                app.toolbars.descendants(matching: .menuButton),
                activeWindow.descendants(matching: .button),
                activeWindow.descendants(matching: .menuButton),
                activeWindow.descendants(matching: .image),
                activeWindow.descendants(matching: .group),
                activeWindow.descendants(matching: .other)
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
                app.descendants(matching: .staticText),
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

        if let fallbackLabel = Self.macToolbarAccessibilityLabelsByIdentifier[identifier] {
            let labelPredicate = NSPredicate(format: "label == %@", fallbackLabel)
            let labelQueries: [XCUIElement]

            if Self.macHeadingToolbarMenuActionIdentifiers.contains(identifier) {
                labelQueries = [
                    app.menuItems[fallbackLabel],
                    app.descendants(matching: .menuItem).matching(labelPredicate).firstMatch
                ]
            } else if Self.macOverflowToolbarPanelActionIdentifiers.contains(identifier) {
                labelQueries = [
                    activeWindow.descendants(matching: .button).matching(labelPredicate).firstMatch,
                    app.buttons[fallbackLabel],
                    activeWindow.descendants(matching: .group).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .other).matching(labelPredicate).firstMatch
                ]
            } else if Self.macToolbarTopLevelMenuIdentifiers.contains(identifier) {
                labelQueries = [
                    app.toolbars.menuButtons[fallbackLabel],
                    activeWindow.descendants(matching: .menuButton).matching(labelPredicate).firstMatch,
                    app.toolbars.buttons[fallbackLabel],
                    activeWindow.descendants(matching: .button).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .image).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .group).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .other).matching(labelPredicate).firstMatch
                ]
            } else if identifier.hasPrefix("editor-toolbar-") || identifier == "editor-find-button" {
                labelQueries = [
                    app.toolbars.buttons[fallbackLabel],
                    app.toolbars.menuButtons[fallbackLabel],
                    activeWindow.descendants(matching: .button).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .menuButton).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .image).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .group).matching(labelPredicate).firstMatch,
                    activeWindow.descendants(matching: .other).matching(labelPredicate).firstMatch
                ]
            } else {
                labelQueries = [
                    app.buttons[fallbackLabel],
                    app.menuButtons[fallbackLabel],
                    app.menuItems[fallbackLabel],
                    app.images[fallbackLabel],
                    app.staticTexts[fallbackLabel],
                    app.descendants(matching: .button).matching(labelPredicate).firstMatch,
                    app.descendants(matching: .menuButton).matching(labelPredicate).firstMatch,
                    app.descendants(matching: .menuItem).matching(labelPredicate).firstMatch,
                    app.descendants(matching: .image).matching(labelPredicate).firstMatch,
                    app.descendants(matching: .group).matching(labelPredicate).firstMatch,
                    app.descendants(matching: .other).matching(labelPredicate).firstMatch
                ]
            }
            for match in labelQueries where match.exists {
                return match
            }
        }

        return targetedQueries.first?.matching(identifier: identifier).firstMatch
    }
    #endif

    @MainActor
    func waitForEditorSurface(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if editorSurfaceCandidate().exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return editorSurfaceCandidate().exists
    }

    #if os(macOS)
    @MainActor
    func waitForMacFormattingToolbar(
        timeout: TimeInterval,
        requiredIdentifiers: [String]? = nil
    ) -> Bool {
        let requiredIdentifiers = requiredIdentifiers ?? Self.macTopLevelFormattingToolbarIdentifiers
        let deadline = Date().addingTimeInterval(timeout)

        for identifier in requiredIdentifiers {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                break
            }

            let element = element(matchingIdentifier: identifier)
            if !element.waitForExistence(timeout: remaining) {
                let missingIdentifiers = requiredIdentifiers.filter {
                    !self.element(matchingIdentifier: $0).exists
                }
                let labelDiagnostics = missingIdentifiers.map { missingIdentifier in
                    let label = Self.macToolbarAccessibilityLabelsByIdentifier[missingIdentifier] ?? "<none>"
                    return "\(missingIdentifier) [label=\(label)]"
                }.joined(separator: "\n")
                let attachment = XCTAttachment(string: """
                Missing top-level macOS toolbar actions:
                \(labelDiagnostics)

                App debug description:
                \(app.debugDescription)
                """)
                attachment.name = "macOS-toolbar-diagnostics"
                attachment.lifetime = .keepAlways
                add(attachment)

                return false
            }
        }

        return true
    }

    @MainActor
    func waitForMacFormattingToolbarReady(timeout: TimeInterval) -> Bool {
        waitForMacFormattingToolbar(
            timeout: timeout,
            requiredIdentifiers: Self.macFormattingToolbarReadyIdentifiers
        )
    }

    @MainActor
    func openMacToolbarMenu(
        menuIdentifier: String,
        expectedActionIdentifier: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let menu = element(matchingIdentifier: menuIdentifier)
        XCTAssertTrue(
            menu.waitForExistence(timeout: timeout),
            "Toolbar menu '\(menuIdentifier)' must exist before opening it",
            file: file,
            line: line
        )
        interact(with: menu)

        let action = element(matchingIdentifier: expectedActionIdentifier)
        XCTAssertTrue(
            action.waitForExistence(timeout: timeout),
            "Toolbar action '\(expectedActionIdentifier)' must appear after opening '\(menuIdentifier)'",
            file: file,
            line: line
        )
    }

    @MainActor
    func dismissMacToolbarMenu() {
        let overflowPanel = element(matchingIdentifier: "editor-toolbar-overflow-panel")
        if overflowPanel.exists {
            let overflowButton = element(matchingIdentifier: "editor-toolbar-overflow-menu")
            if overflowButton.exists {
                interact(with: overflowButton)
                return
            }
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func triggerMacToolbarMenuAction(
        menuIdentifier: String,
        actionIdentifier: String,
        fallbackLabel: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        openMacToolbarMenu(
            menuIdentifier: menuIdentifier,
            expectedActionIdentifier: actionIdentifier,
            timeout: timeout,
            file: file,
            line: line
        )

        let identifiedAction = element(matchingIdentifier: actionIdentifier)
        if identifiedAction.waitForExistence(timeout: min(timeout, 2)) {
            interact(with: identifiedAction)
            return
        }

        let labeledAction = app.buttons[fallbackLabel]
        XCTAssertTrue(
            labeledAction.waitForExistence(timeout: timeout),
            "Toolbar action '\(fallbackLabel)' must exist",
            file: file,
            line: line
        )
        interact(with: labeledAction)
    }
    #endif

    @MainActor
    func editorSurface(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let candidate = editorSurfaceCandidate()
        if candidate.exists {
            return candidate
        }

        XCTAssertTrue(candidate.exists,
                      "Editor surface must exist before querying it",
                      file: file,
                      line: line)
        return candidate
    }

    @MainActor
    func focusEditor(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForEditorSurface(timeout: 10),
                      "Editor surface must exist before focusing it",
                      file: file,
                      line: line)
        let surface = editorSurface(file: file, line: line)
        let initialTextInput = textInputEditorCandidate()
        let initialTarget: XCUIElement
        if initialTextInput.exists {
            initialTarget = initialTextInput
        } else {
            initialTarget = surface
        }
        interact(with: initialTarget)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let textInput = textInputEditorCandidate()
            if textInput.exists {
                if textInput.elementType != initialTarget.elementType || textInput.identifier != initialTarget.identifier {
                    interact(with: textInput)
                }
                return textInput
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return surface
    }

    @MainActor
    func replaceEditorText(
        with text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let editor = focusMacEditorForKeyboardInput(file: file, line: line)
        #if os(macOS)
        typeKeyInFocusedMacEditor("a", modifierFlags: .command, file: file, line: line)
        #endif
        typeTextInFocusedMacEditor(text, file: file, line: line)
        assertEditorContains(text, file: file, line: line)
        return editor
    }

    @MainActor
    func clearEditorText(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let editor = focusMacEditorForKeyboardInput(file: file, line: line)
        #if os(macOS)
        typeKeyInFocusedMacEditor("a", modifierFlags: .command, file: file, line: line)
        typeKeyInFocusedMacEditor(
            XCUIKeyboardKey.delete.rawValue,
            modifierFlags: [],
            file: file,
            line: line
        )
        #endif
        return editor
    }

    #if os(macOS)
    @MainActor
    func focusMacEditorForKeyboardInput(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            waitForEditorSurface(timeout: 10),
            "Editor surface must exist before keyboard synthesis",
            file: file,
            line: line
        )
        let editor = focusEditor(file: file, line: line)
        prepareFocusedMacEditorForKeyboardInput(file: file, line: line)
        return editor
    }

    @MainActor
    private func prepareFocusedMacEditorForKeyboardInput(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            waitForEditorSurface(timeout: 10),
            "Editor surface must exist before keyboard synthesis",
            file: file,
            line: line
        )
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "Quartz must be foreground before keyboard synthesis",
            file: file,
            line: line
        )
    }

    @MainActor
    func typeTextInFocusedMacEditor(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        prepareFocusedMacEditorForKeyboardInput(file: file, line: line)
        app.typeText(text)
    }

    @MainActor
    func typeKeyInFocusedMacEditor(
        _ key: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        prepareFocusedMacEditorForKeyboardInput(file: file, line: line)
        app.typeKey(key, modifierFlags: modifierFlags)
    }
    #endif

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

        for editor in editorTextCandidates() where editor.exists {
            if let text = editor.value as? String {
                candidateValues.append(text)
            }
            if let value = editor.value {
                candidateValues.append(String(describing: value))
            }
        }

        if let nonEmpty = candidateValues.first(where: { !$0.isEmpty }) {
            return nonEmpty
        }

        return candidateValues.first
    }

    @MainActor
    private func editorSurfaceCandidate() -> XCUIElement {
        for candidate in editorSurfaceCandidates() where candidate.exists {
            return candidate
        }

        return editorSurfaceCandidates().first ?? app.otherElements.firstMatch
    }

    @MainActor
    private func textInputEditorCandidate() -> XCUIElement {
        let surface = editorSurfaceCandidate()

        if surface.exists, surface.elementType == .textView || surface.elementType == .textField {
            return surface
        }

        for candidate in textInputEditorCandidates(surface: surface) where candidate.exists {
            return candidate
        }

        return textInputEditorCandidates(surface: surface).first ?? surface
    }

    @MainActor
    private func editorTextCandidates() -> [XCUIElement] {
        let surface = editorSurfaceCandidate()
        var candidates = textInputEditorCandidates(surface: surface)
        if surface.exists {
            candidates.append(surface)
        }
        return candidates
    }

    @MainActor
    private func editorSurfaceCandidates() -> [XCUIElement] {
        [
            app.descendants(matching: .textView).matching(identifier: "editor-text-view").firstMatch,
            app.descendants(matching: .textField).matching(identifier: "editor-text-view").firstMatch,
            app.descendants(matching: .scrollView).matching(identifier: "editor-text-view").firstMatch,
            app.scrollViews.matching(identifier: "editor-text-view").firstMatch,
            app.descendants(matching: .other).matching(identifier: "editor-text-view").firstMatch
        ]
    }

    @MainActor
    private func textInputEditorCandidates(surface: XCUIElement) -> [XCUIElement] {
        var candidates: [XCUIElement] = [
            app.descendants(matching: .textView).matching(identifier: "editor-text-view").firstMatch,
            app.descendants(matching: .textField).matching(identifier: "editor-text-view").firstMatch
        ]

        if surface.exists {
            candidates.append(surface.descendants(matching: .textView).firstMatch)
            candidates.append(surface.descendants(matching: .textField).firstMatch)
        }

        return candidates
    }

    @MainActor
    func openMockVaultNote(
        matchingAnyOf titles: [String],
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let filteredTitles = titles.filter { !$0.isEmpty }
        guard !filteredTitles.isEmpty else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let noteList = element(matchingIdentifier: "note-list-view")
            let scopedQueries = noteList.exists
                ? [
                    noteList.descendants(matching: .outlineRow),
                    noteList.descendants(matching: .cell),
                    noteList.descendants(matching: .button),
                    noteList.descendants(matching: .staticText)
                ]
                : [
                    app.outlineRows,
                    app.cells,
                    app.buttons,
                    app.staticTexts
                ]

            for title in filteredTitles {
                let identifier = "note-list-item-\(title)"
                for query in scopedQueries {
                    let match = query.matching(identifier: identifier).firstMatch
                    if match.exists {
                        interact(with: match)
                        _ = waitForEditorSurface(timeout: min(timeout, 5))
                        return match
                    }
                }
            }

            for title in filteredTitles {
                let labelPredicate = NSPredicate(format: "label CONTAINS[c] %@", title)
                for query in scopedQueries {
                    let match = query.matching(labelPredicate).firstMatch
                    if match.exists {
                        interact(with: match)
                        _ = waitForEditorSurface(timeout: min(timeout, 5))
                        return match
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return nil
    }

    @MainActor
    func createNewNote(timeout: TimeInterval = 10) -> Bool {
        let uniqueToken = "UT\(UUID().uuidString.prefix(4))"
        let previousEditorText = waitForEditorSurface(timeout: 1) ? editorTextValue() : nil

        #if os(macOS)
        app.activate()
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
            app.buttons["New Note"],
            element(matchingIdentifier: "note-list-new-note"),
            element(matchingIdentifier: "sidebar-new-note"),
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
        Self.hideKnownInterruptingMacApps()
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 5)
        element.click()
        #else
        element.tap()
        #endif
    }

    #if os(macOS)
    @MainActor
    private static func hideKnownInterruptingMacApps() {
        for runningApp in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = runningApp.bundleIdentifier else { continue }
            guard knownInterruptingMacBundleIdentifiers.contains(bundleIdentifier) else { continue }
            guard !runningApp.isTerminated else { continue }
            if !runningApp.terminate() {
                runningApp.forceTerminate()
                continue
            }

            let deadline = Date().addingTimeInterval(1)
            while !runningApp.isTerminated && deadline.timeIntervalSinceNow > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }

            if !runningApp.isTerminated {
                runningApp.forceTerminate()
            }
        }
    }
    #endif

    @MainActor
    func triggerOverflowFormattingAction(
        _ actionIdentifier: String,
        fallbackLabel: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        triggerMacToolbarMenuAction(
            menuIdentifier: "editor-toolbar-overflow-menu",
            actionIdentifier: "editor-toolbar-\(actionIdentifier)",
            fallbackLabel: fallbackLabel,
            timeout: timeout,
            file: file,
            line: line
        )
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
