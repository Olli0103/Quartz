import XCTest

#if os(macOS)
final class macOSEditorShellUITests: QuartzUITestCase {

    @MainActor
    func testEditorPreservesEditsAcrossNoteSwitching() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcome")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let marker = "\nmac-switch-\(UUID().uuidString.prefix(8))"
        editor.typeText(marker)
        assertEditorContains(marker)

        guard createNewNote() else {
            takeScreenshot(named: "macOS_EditorShell_NewNoteFailed")
            XCTFail("New note action must create a second editor context for note-switching coverage")
            return
        }

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_WelcomeMissingAfterSwitch")
            XCTFail("Welcome note must remain selectable after switching away")
            return
        }

        XCTAssertTrue(waitForEditorSurface(timeout: 10))
        assertEditorContains(marker)
    }

    @MainActor
    func testKeyboardBoldActionAppliesMarkdownInline() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForBold")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        editor.typeKey("b", modifierFlags: .command)

        let token = "macBold\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("**\(token)**")
    }

    @MainActor
    func testToolbarLinkActionInsertsMarkdownTemplate() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForLink")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let linkButton = element(matchingIdentifier: "editor-toolbar-link")
        XCTAssertTrue(linkButton.waitForExistence(timeout: 5),
                      "Link toolbar action must exist on macOS")

        interact(with: linkButton)

        let token = "macLink\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("[\(token)](url)")
    }

    @MainActor
    func testToolbarCheckboxActionInsertsTaskPrefix() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForCheckbox")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let checkboxButton = element(matchingIdentifier: "editor-toolbar-checkbox")
        XCTAssertTrue(checkboxButton.waitForExistence(timeout: 5),
                      "Checkbox toolbar action must exist on macOS")

        interact(with: checkboxButton)

        let token = "macTask\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("- [ ] \(token)")
    }

    @MainActor
    func testToolbarTableActionInsertsMarkdownTable() throws {
        launchApp()

        guard createNewNote() else {
            takeScreenshot(named: "macOS_EditorShell_NewNoteFailedForTable")
            XCTFail("New note action must succeed for macOS table toolbar coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("This is a test note for UI testing.")
        editor.typeText("\n")
        triggerOverflowFormattingAction("table", fallbackLabel: "Table")
        assertEditorContains("This is a test note for UI testing.")
        assertEditorContains("| Column 1 | Column 2 | Column 3 |")
        assertEditorContains("| --- | --- | --- |")
        assertEditorContains("| Cell 1 | Cell 2 | Cell 3 |")
    }

    @MainActor
    func testToolbarMermaidActionWrapsCurrentLineInFence() throws {
        launchApp()

        guard createNewNote() else {
            takeScreenshot(named: "macOS_EditorShell_NewNoteFailedForMermaid")
            XCTFail("New note action must succeed for macOS mermaid toolbar coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("This is a test note for UI testing.")
        editor.typeText("\n")
        triggerOverflowFormattingAction("mermaid", fallbackLabel: "Mermaid Diagram")
        let token = "graph TD"
        editor.typeText(token)
        assertEditorContains("This is a test note for UI testing.")
        assertEditorNotContains("```mermaid\nThis is a test note for UI testing.")
        assertEditorContains("```mermaid\n\(token)\n```")
    }

    @MainActor
    func testToolbarBoldActionWrapsCurrentSelection() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForToolbarBold")
            XCTFail("Welcome note must exist for toolbar selection coverage")
            return
        }

        let editor = focusEditor()
        let token = "macToolbarBold\(UUID().uuidString.prefix(6))"
        app.typeKey("a", modifierFlags: .command)
        editor.typeText(token)
        app.typeKey("a", modifierFlags: .command)

        let boldButton = element(matchingIdentifier: "editor-toolbar-bold")
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5),
                      "Bold toolbar action must exist on macOS")

        interact(with: boldButton)
        assertEditorContains("**\(token)**")
    }

    @MainActor
    func testPasteAndUndoRedoCommandsRoundTripEditorState() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForPaste")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        _ = focusEditor()
        setPasteboardText("Line 1\r\n\t- [ ] task  \r\n\t\tIndented\t \r")

        app.typeKey("v", modifierFlags: [.command, .option])
        assertEditorContains("Line 1\n    - [ ] task\n        Indented\n")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(editorTextValue().contains("Indented"),
                       "Undo must remove the pasted payload")

        app.typeKey("z", modifierFlags: [.command, .shift])
        assertEditorContains("Line 1\n    - [ ] task\n        Indented\n")
    }

    @MainActor
    func testEditorContextRestoresAcrossRelaunchWithoutReset() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForRestore")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let marker = "\nmac-restore-\(UUID().uuidString.prefix(8))"
        editor.typeText(marker)
        assertEditorContains(marker)

        app.typeKey("s", modifierFlags: .command)
        relaunchAppPreservingState()

        XCTAssertTrue(waitForEditorSurface(timeout: 10),
                      "Editor must return after relaunch without state reset")
        assertEditorContains(marker)
    }
}
#endif

#if os(iOS)
final class iPhoneEditorShellUITests: QuartzUITestCase {

    override func setUpWithError() throws {
        guard MainActor.assumeIsolated({ UIDevice.current.userInterfaceIdiom }) == .phone else {
            throw XCTSkip("Skipping iPhone editor shell tests on iPad")
        }
        try super.setUpWithError()
    }

    @MainActor
    func testEditingSurvivesBackgroundForeground() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcome")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let marker = "\nphone-bg-\(UUID().uuidString.prefix(8))"
        editor.typeText(marker)
        assertEditorContains(marker)

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(waitForEditorSurface(timeout: 10),
                      "Editor must return after foregrounding the app on iPhone")
        assertEditorContains(marker)
    }

    @MainActor
    func testCompactToolbarBoldActionAppliesMarkdownInline() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForBold")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let boldButton = element(matchingIdentifier: "editor-toolbar-bold")
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5),
                      "Bold floating-toolbar action must exist on iPhone")

        interact(with: boldButton)

        let token = "iosBold\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("**\(token)**")
    }

    @MainActor
    func testCompactToolbarLinkActionInsertsMarkdownTemplate() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForLink")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let linkButton = element(matchingIdentifier: "editor-toolbar-link")
        XCTAssertTrue(linkButton.waitForExistence(timeout: 5),
                      "Link floating-toolbar action must exist on iPhone")

        interact(with: linkButton)

        let token = "iosLink\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("[\(token)](url)")
    }

    @MainActor
    func testCompactToolbarCheckboxActionInsertsTaskPrefix() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForCheckbox")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let checkboxButton = element(matchingIdentifier: "editor-toolbar-checkbox")
        XCTAssertTrue(checkboxButton.waitForExistence(timeout: 5),
                      "Checkbox floating-toolbar action must exist on iPhone")

        interact(with: checkboxButton)

        let token = "iosTask\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("- [ ] \(token)")
    }

    @MainActor
    func testCompactToolbarTableActionInsertsMarkdownTable() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForTable")
            XCTFail("Welcome note must exist for iPhone table toolbar coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n")
        triggerOverflowFormattingAction("table", fallbackLabel: "Table")
        assertEditorContains("This is a test note for UI testing.")
        assertEditorContains("| Column 1 | Column 2 | Column 3 |")
        assertEditorContains("| --- | --- | --- |")
        assertEditorContains("| Cell 1 | Cell 2 | Cell 3 |")
    }

    @MainActor
    func testCompactToolbarMermaidActionWrapsCurrentLineInFence() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForMermaid")
            XCTFail("Welcome note must exist for iPhone mermaid toolbar coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n")
        triggerOverflowFormattingAction("mermaid", fallbackLabel: "Mermaid Diagram")
        let token = "graph TD"
        editor.typeText(token)
        assertEditorContains("This is a test note for UI testing.")
        assertEditorNotContains("```mermaid\nThis is a test note for UI testing.")
        assertEditorContains("```mermaid\n\(token)\n```")
    }
}

final class iPadEditorShellUITests: QuartzUITestCase {

    override func setUpWithError() throws {
        guard MainActor.assumeIsolated({ UIDevice.current.userInterfaceIdiom }) == .pad else {
            throw XCTSkip("Skipping iPad editor shell tests on iPhone")
        }
        try super.setUpWithError()
    }

    @MainActor
    func testSplitViewEditingSurvivesNoteSwitching() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcome")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let marker = "\nipad-switch-\(UUID().uuidString.prefix(8))"
        editor.typeText(marker)
        assertEditorContains(marker)

        guard createNewNote() else {
            takeScreenshot(named: "iPad_EditorShell_NewNoteFailed")
            XCTFail("New note action must create a second editor context for split-view coverage")
            return
        }

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_WelcomeMissingAfterSwitch")
            XCTFail("Welcome note must remain selectable after switching away")
            return
        }

        XCTAssertTrue(waitForEditorSurface(timeout: 10),
                      "Editor must remain available after switching notes on iPad")
        assertEditorContains(marker)
    }

    @MainActor
    func testSplitViewToolbarBoldActionAppliesMarkdownInline() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForBold")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let boldButton = element(matchingIdentifier: "editor-toolbar-bold")
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5),
                      "Bold floating-toolbar action must exist on iPad")

        interact(with: boldButton)

        let token = "ipadBold\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("**\(token)**")
    }

    @MainActor
    func testSplitViewToolbarLinkActionInsertsMarkdownTemplate() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForLink")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let linkButton = element(matchingIdentifier: "editor-toolbar-link")
        XCTAssertTrue(linkButton.waitForExistence(timeout: 5),
                      "Link floating-toolbar action must exist on iPad")

        interact(with: linkButton)

        let token = "ipadLink\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("[\(token)](url)")
    }

    @MainActor
    func testSplitViewToolbarCheckboxActionInsertsTaskPrefix() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForCheckbox")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let checkboxButton = element(matchingIdentifier: "editor-toolbar-checkbox")
        XCTAssertTrue(checkboxButton.waitForExistence(timeout: 5),
                      "Checkbox floating-toolbar action must exist on iPad")

        interact(with: checkboxButton)

        let token = "ipadTask\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("- [ ] \(token)")
    }

    @MainActor
    func testSplitViewToolbarTableActionInsertsMarkdownTable() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForTable")
            XCTFail("Welcome note must exist for iPad table toolbar coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n")
        triggerOverflowFormattingAction("table", fallbackLabel: "Table")
        assertEditorContains("This is a test note for UI testing.")
        assertEditorContains("| Column 1 | Column 2 | Column 3 |")
        assertEditorContains("| --- | --- | --- |")
        assertEditorContains("| Cell 1 | Cell 2 | Cell 3 |")
    }

    @MainActor
    func testSplitViewToolbarMermaidActionWrapsCurrentLineInFence() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForMermaid")
            XCTFail("Welcome note must exist for iPad mermaid toolbar coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n")
        triggerOverflowFormattingAction("mermaid", fallbackLabel: "Mermaid Diagram")
        let token = "graph TD"
        editor.typeText(token)
        assertEditorContains("This is a test note for UI testing.")
        assertEditorNotContains("```mermaid\nThis is a test note for UI testing.")
        assertEditorContains("```mermaid\n\(token)\n```")
    }

    @MainActor
    func testSplitViewHeadingMenuRoundTripAppliesAndRemovesHeadingSyntax() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForHeadingMenu")
            XCTFail("Welcome note must exist in the mock vault")
            return
        }

        let editor = focusEditor()
        let token = "ipadHeading\(UUID().uuidString.prefix(6))"
        let headingMenu = element(matchingIdentifier: "editor-toolbar-heading-menu")
        XCTAssertTrue(headingMenu.waitForExistence(timeout: 5),
                      "Heading floating-toolbar menu must exist on iPad")

        interact(with: headingMenu)
        interact(with: app.buttons["Heading 2"])
        editor.typeText(token)
        assertEditorContains("## \(token)")

        interact(with: headingMenu)
        interact(with: app.buttons["Paragraph"])
        assertEditorContains(token)
        assertEditorNotContains("## \(token)")
    }

}
#endif
