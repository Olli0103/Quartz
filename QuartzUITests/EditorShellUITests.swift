import XCTest

#if os(macOS)
final class macOSEditorShellUITests: QuartzUITestCase {
    private struct ToolbarActionSpec {
        let identifier: String
        let label: String
    }

    private let preferredExistingNoteTitles = ["Welcome", "Todo"]
    private let preferredInlineFormattingNoteTitles = ["Welcome", "Release Notes", "Todo"]
    private let longFixtureNoteTitle = "Release Notes"
    private let macTopLevelFormattingActions = [
        ToolbarActionSpec(identifier: "editor-toolbar-undo", label: "Undo"),
        ToolbarActionSpec(identifier: "editor-toolbar-redo", label: "Redo"),
        ToolbarActionSpec(identifier: "editor-toolbar-bold", label: "Bold"),
        ToolbarActionSpec(identifier: "editor-toolbar-italic", label: "Italic"),
        ToolbarActionSpec(identifier: "editor-toolbar-strikethrough", label: "Strikethrough"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading-menu", label: "Heading level"),
        ToolbarActionSpec(identifier: "editor-toolbar-bulletList", label: "Bullet List"),
        ToolbarActionSpec(identifier: "editor-toolbar-numberedList", label: "Numbered List"),
        ToolbarActionSpec(identifier: "editor-toolbar-checkbox", label: "Checkbox"),
        ToolbarActionSpec(identifier: "editor-toolbar-code", label: "Inline Code"),
        ToolbarActionSpec(identifier: "editor-toolbar-link", label: "Link"),
        ToolbarActionSpec(identifier: "editor-toolbar-overflow-menu", label: "More formatting options"),
        ToolbarActionSpec(identifier: "editor-toolbar-ai-assistant", label: "AI Assistant")
    ]
    private let macAuxiliaryToolbarActions = [
        ToolbarActionSpec(identifier: "editor-toolbar-export", label: "Export note"),
        ToolbarActionSpec(identifier: "editor-find-button", label: "Find in Note"),
        ToolbarActionSpec(identifier: "editor-toolbar-focus-mode", label: "Focus Mode"),
        ToolbarActionSpec(identifier: "editor-toolbar-inspector", label: "Inspector")
    ]
    private let macHeadingMenuActions = [
        ToolbarActionSpec(identifier: "editor-toolbar-paragraph", label: "Paragraph"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading1", label: "Heading 1"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading2", label: "Heading 2"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading3", label: "Heading 3"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading4", label: "Heading 4"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading5", label: "Heading 5"),
        ToolbarActionSpec(identifier: "editor-toolbar-heading6", label: "Heading 6")
    ]
    private let macOverflowMenuActions = [
        ToolbarActionSpec(identifier: "editor-toolbar-codeBlock", label: "Code Block"),
        ToolbarActionSpec(identifier: "editor-toolbar-blockquote", label: "Quote"),
        ToolbarActionSpec(identifier: "editor-toolbar-table", label: "Table"),
        ToolbarActionSpec(identifier: "editor-toolbar-image", label: "Image"),
        ToolbarActionSpec(identifier: "editor-toolbar-math", label: "Math"),
        ToolbarActionSpec(identifier: "editor-toolbar-mermaid", label: "Mermaid Diagram")
    ]

    @MainActor
    func testEditorPreservesEditsAcrossNoteSwitching() throws {
        launchApp()

        guard let originalNote = openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcome")
            XCTFail("An existing fixture note must exist in the mock vault")
            return
        }

        let editor = clearEditorText()
        let marker = "mac-switch-\(UUID().uuidString.prefix(8))"
        editor.typeText(marker)
        assertEditorContains(marker)

        guard createNewNote() else {
            takeScreenshot(named: "macOS_EditorShell_NewNoteFailed")
            XCTFail("New note action must create a second editor context for note-switching coverage")
            return
        }

        if originalNote.waitForExistence(timeout: 10) {
            interact(with: originalNote)
        } else if openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) == nil {
            takeScreenshot(named: "macOS_EditorShell_WelcomeMissingAfterSwitch")
            XCTFail("A fixture note must remain selectable after switching away")
            return
        }

        XCTAssertTrue(waitForEditorSurface(timeout: 10))
        assertEditorContains(marker)
    }

    @MainActor
    func testKeyboardBoldActionAppliesMarkdownInline() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForBold")
            XCTFail("An existing fixture note must exist in the mock vault")
            return
        }

        _ = replaceEditorText(with: "Keyboard bold baseline")
        typeKeyInFocusedMacEditor("b", modifierFlags: .command)

        let token = "macBold\(UUID().uuidString.prefix(6))"
        typeTextInFocusedMacEditor(token)
        assertEditorContains("**\(token)**")
    }

    @MainActor
    func testCommandFindInNoteOpensEditorScopedFindBar() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForFind")
            XCTFail("An existing fixture note must exist for in-note find coverage")
            return
        }

        _ = focusEditor()
        app.typeKey("f", modifierFlags: .command)

        let findField = element(matchingIdentifier: "editor-find-query")
        XCTAssertTrue(findField.waitForExistence(timeout: 5),
                      "Command-F must open the editor-scoped find bar on macOS")
    }

    @MainActor
    func testCommandSearchNotesRemainsSeparateFromFindInNote() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForSearchNotes")
            XCTFail("An existing fixture note must exist for search-notes coverage")
            return
        }

        _ = focusEditor()
        app.typeKey("f", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5),
                      "Command-Shift-F must keep opening the vault-wide Search Notes sheet")
        XCTAssertFalse(element(matchingIdentifier: "editor-find-query").exists,
                       "Vault-wide search must remain separate from the editor-scoped find bar")
    }

    @MainActor
    func testToolbarLinkActionInsertsMarkdownTemplate() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForLink")
            XCTFail("An existing fixture note must exist in the mock vault")
            return
        }

        let editor = replaceEditorText(with: "Toolbar link baseline")
        let linkButton = element(matchingIdentifier: "editor-toolbar-link")
        XCTAssertTrue(linkButton.waitForExistence(timeout: 5),
                      "Link toolbar action must exist on macOS")

        interact(with: linkButton)

        let token = "macLink\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("[\(token)](url)")
    }

    @MainActor
    func testToolbarVisibilityMatrixExposesEveryVisibleMacAction() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredInlineFormattingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoFixtureForToolbarMatrix")
            XCTFail("A visible fixture note must exist for macOS toolbar matrix coverage")
            return
        }

        prepareMacFormattingToolbar(
            failureMessage: "The visible macOS formatting toolbar surface must become queryable before matrix assertions run"
        )

        assertToolbarSpecsExist(macTopLevelFormattingActions)
        assertToolbarSpecsExist(macAuxiliaryToolbarActions)

        openMacToolbarMenu(
            menuIdentifier: "editor-toolbar-heading-menu",
            expectedActionIdentifier: "editor-toolbar-paragraph"
        )
        assertToolbarSpecsExist(macHeadingMenuActions)
        dismissMacToolbarMenu()

        openMacToolbarMenu(
            menuIdentifier: "editor-toolbar-overflow-menu",
            expectedActionIdentifier: "editor-toolbar-codeBlock"
        )
        assertToolbarSpecsExist(macOverflowMenuActions)
        dismissMacToolbarMenu()
    }

    @MainActor
    func testTypingWikiLinkTriggerShowsSuggestionsAndInsertsLinkedNote() throws {
        launchApp()

        guard createNewNote() else {
            takeScreenshot(named: "macOS_EditorShell_NewNoteFailedForWikiLink")
            XCTFail("A fresh editor note must be creatable for wiki-link insertion coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n[[To")

        let picker = element(matchingIdentifier: "editor-link-picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "Typing [[ in the active editor must open note-link suggestions")

        let suggestion = element(matchingIdentifier: "editor-link-suggestion-0")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5),
                      "A matching note suggestion must be visible for keyboard-friendly linking")

        interact(with: suggestion)
        assertEditorContains("[[Todo]]")
    }

    @MainActor
    func testToolbarBoldActionAppliesMarkdownInline() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredInlineFormattingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForToolbarBoldInline")
            XCTFail("A visible fixture note must exist for macOS toolbar inline bold coverage")
            return
        }

        let editor = focusEditor()
        let boldButton = element(matchingIdentifier: "editor-toolbar-bold")
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5),
                      "Bold toolbar action must exist on macOS")

        interact(with: boldButton)

        let token = "macToolbarBold\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("**\(token)**")
    }

    @MainActor
    func testToolbarInlineActionMatrixAppliesExpectedFormatting() throws {
        launchApp()

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForInlineToolbarMatrix",
            failureMessage: "A fresh editor note must be creatable for macOS inline toolbar matrix coverage"
        )
        assertInlineWrapperActionOnFreshNote(
            identifier: "editor-toolbar-bold",
            tokenPrefix: "b",
            expectedPrefix: "**",
            expectedSuffix: "**"
        )

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForInlineToolbarMatrix",
            failureMessage: "A second fresh editor note must be creatable for macOS inline toolbar matrix coverage"
        )
        assertInlineWrapperActionOnFreshNote(
            identifier: "editor-toolbar-link",
            tokenPrefix: "l",
            expectedPrefix: "[",
            expectedSuffix: "](url)"
        )

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForInlineToolbarMatrix",
            failureMessage: "A third fresh editor note must be creatable for macOS inline toolbar matrix coverage"
        )
        assertLinePrefixActionOnFreshNote(
            identifier: "editor-toolbar-checkbox",
            tokenPrefix: "c",
            expectedPrefix: "- [ ] "
        )
    }

    @MainActor
    func testToolbarHeadingMenuRepresentativeActionsApplyExpectedFormatting() throws {
        launchApp()

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForMenuToolbarMatrix",
            failureMessage: "A fresh editor note must be creatable for macOS menu-toolbar matrix coverage"
        )
        let headingToken = "h"
        let headingEditor = focusEditor()
        triggerMacToolbarMenuAction(
            menuIdentifier: "editor-toolbar-heading-menu",
            actionIdentifier: "editor-toolbar-heading2",
            fallbackLabel: "Heading 2"
        )
        headingEditor.typeText(headingToken)
        assertEditorContains("## " + headingToken)

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForMenuToolbarMatrix",
            failureMessage: "A second fresh editor note must be creatable for macOS menu-toolbar matrix coverage"
        )
        let paragraphToken = "p"
        let paragraphEditor = focusEditor()
        paragraphEditor.typeText("## \(paragraphToken)")
        app.typeKey("a", modifierFlags: .command)
        triggerMacToolbarMenuAction(
            menuIdentifier: "editor-toolbar-heading-menu",
            actionIdentifier: "editor-toolbar-paragraph",
            fallbackLabel: "Paragraph"
        )
        XCTAssertTrue(waitForEditorSurface(timeout: 5))
        _ = paragraphEditor
        assertEditorContains(paragraphToken)
        assertEditorNotContains("# \(paragraphToken)")
    }

    @MainActor
    func testToolbarOverflowMenuRepresentativeActionsApplyExpectedFormatting() throws {
        launchApp()

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForMenuToolbarMatrix",
            failureMessage: "A third fresh editor note must be creatable for macOS menu-toolbar matrix coverage"
        )
        assertMenuWrappedActionOnFreshNote(
            menuIdentifier: "editor-toolbar-overflow-menu",
            actionIdentifier: "editor-toolbar-blockquote",
            fallbackLabel: "Quote",
            tokenPrefix: "q",
            expectedPrefix: "> ",
            expectedSuffix: ""
        )

        prepareFreshMacToolbarActionNote(
            failureScreenshotName: "macOS_EditorShell_NewNoteFailedForMenuToolbarMatrix",
            failureMessage: "A fourth fresh editor note must be creatable for macOS menu-toolbar matrix coverage"
        )
        let tableEditor = focusEditor()
        _ = tableEditor
        triggerMacToolbarMenuAction(
            menuIdentifier: "editor-toolbar-overflow-menu",
            actionIdentifier: "editor-toolbar-table",
            fallbackLabel: "Table"
        )
        assertEditorContains("| Column 1 | Column 2 | Column 3 |")
        assertEditorContains("| --- | --- | --- |")
        assertEditorContains("| Cell 1 | Cell 2 | Cell 3 |")
    }

    @MainActor
    func testToolbarUndoRedoButtonsRoundTripSelectionFormatting() throws {
        launchApp()

        guard createNewNote() else {
            takeScreenshot(named: "macOS_EditorShell_NewNoteFailedForUndoRedoToolbar")
            XCTFail("A fresh editor note must be creatable for macOS undo/redo toolbar coverage")
            return
        }

        prepareMacFormattingToolbar(
            failureMessage: "The visible macOS formatting toolbar surface must become queryable before undo/redo coverage runs"
        )

        let token = "u"
        let editor = replaceEditorText(with: token)
        app.typeKey("a", modifierFlags: .command)

        interact(with: element(matchingIdentifier: "editor-toolbar-bold"))
        assertEditorContains("**\(token)**")

        interact(with: element(matchingIdentifier: "editor-toolbar-undo"))
        assertEditorContains(token)
        assertEditorNotContains("**\(token)**")

        interact(with: element(matchingIdentifier: "editor-toolbar-redo"))
        assertEditorContains("**\(token)**")
        _ = editor
    }

    @MainActor
    func testToolbarTableActionOnLongFixtureKeepsContextAndInsertsMarkdownTable() throws {
        launchApp()

        guard openMockVaultNote(named: longFixtureNoteTitle) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoLongFixtureForTable")
            XCTFail("The long release-notes fixture must exist for macOS table toolbar coverage")
            return
        }

        _ = focusEditor()
        triggerOverflowFormattingAction("table", fallbackLabel: "Table")

        assertEditorContains("# Release Notes")
        assertEditorContains("## Writing Workflow")
        assertEditorContains("### Formatting Guarantees")
        assertEditorContains("| Column 1 | Column 2 | Column 3 |")
        assertEditorContains("| --- | --- | --- |")
        assertEditorContains("| Cell 1 | Cell 2 | Cell 3 |")
    }

    @MainActor
    func testToolbarCheckboxActionInsertsTaskPrefix() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForCheckbox")
            XCTFail("An existing fixture note must exist in the mock vault")
            return
        }

        let editor = clearEditorText()
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

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoFixtureForTable")
            XCTFail("An existing fixture note must exist for macOS table toolbar coverage")
            return
        }

        let editor = focusEditor()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("This is a test note for UI testing.\n")
        triggerOverflowFormattingAction("table", fallbackLabel: "Table")
        assertEditorContains("This is a test note for UI testing.")
        assertEditorContains("| Column 1 | Column 2 | Column 3 |")
        assertEditorContains("| --- | --- | --- |")
        assertEditorContains("| Cell 1 | Cell 2 | Cell 3 |")
    }

    @MainActor
    func testToolbarMermaidActionWrapsCurrentLineInFence() throws {
        launchApp()

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoFixtureForMermaid")
            XCTFail("An existing fixture note must exist for macOS mermaid toolbar coverage")
            return
        }

        let editor = focusEditor()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("This is a test note for UI testing.\n")
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

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForToolbarBold")
            XCTFail("An existing fixture note must exist for toolbar selection coverage")
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

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForPaste")
            XCTFail("An existing fixture note must exist in the mock vault")
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

        guard openMockVaultNote(matchingAnyOf: preferredExistingNoteTitles) != nil else {
            takeScreenshot(named: "macOS_EditorShell_NoWelcomeForRestore")
            XCTFail("An existing fixture note must exist in the mock vault")
            return
        }

        let editor = clearEditorText()
        let marker = "mac-restore-\(UUID().uuidString.prefix(8))"
        editor.typeText(marker)
        assertEditorContains(marker)

        app.typeKey("s", modifierFlags: .command)
        relaunchAppPreservingState()
        _ = focusEditor()

        XCTAssertTrue(
            waitForEditorToContain(marker, timeout: 15),
            "Editor must return with restored note content after relaunch without state reset"
        )
    }

    @MainActor
    private func assertToolbarSpecsExist(
        _ specs: [ToolbarActionSpec],
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for spec in specs {
            let element = element(matchingIdentifier: spec.identifier)
            XCTAssertTrue(
                element.waitForExistence(timeout: timeout),
                "\(spec.label) must be queryable in the macOS toolbar accessibility tree",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func prepareMacFormattingToolbar(
        timeout: TimeInterval = 10,
        failureMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        _ = focusEditor(file: file, line: line)
        XCTAssertTrue(
            waitForMacFormattingToolbarReady(timeout: timeout),
            failureMessage,
            file: file,
            line: line
        )
    }

    @MainActor
    private func prepareFreshMacToolbarActionNote(
        failureScreenshotName: String,
        failureMessage: String
    ) {
        guard createNewNote() else {
            takeScreenshot(named: failureScreenshotName)
            XCTFail(failureMessage)
            return
        }

        prepareMacFormattingToolbar(
            failureMessage: "The visible macOS formatting toolbar surface must become queryable before representative action coverage runs"
        )
    }

    @MainActor
    private func assertInlineWrapperActionOnFreshNote(
        identifier: String,
        tokenPrefix: String,
        expectedPrefix: String,
        expectedSuffix: String
    ) {
        let token = tokenPrefix
        let editor = focusEditor()
        interact(with: element(matchingIdentifier: identifier))
        editor.typeText(token)
        assertEditorContains("\(expectedPrefix)\(token)\(expectedSuffix)")
    }

    @MainActor
    private func assertLinePrefixActionOnFreshNote(
        identifier: String,
        tokenPrefix: String,
        expectedPrefix: String
    ) {
        let token = tokenPrefix
        let editor = focusEditor()
        interact(with: element(matchingIdentifier: identifier))
        editor.typeText(token)
        assertEditorContains("\(expectedPrefix)\(token)")
    }

    @MainActor
    private func assertMenuWrappedActionOnFreshNote(
        menuIdentifier: String,
        actionIdentifier: String,
        fallbackLabel: String,
        tokenPrefix: String,
        expectedPrefix: String,
        expectedSuffix: String
    ) {
        let token = tokenPrefix
        let editor = focusEditor()
        triggerMacToolbarMenuAction(
            menuIdentifier: menuIdentifier,
            actionIdentifier: actionIdentifier,
            fallbackLabel: fallbackLabel
        )
        editor.typeText(token)
        assertEditorContains("\(expectedPrefix)\(token)\(expectedSuffix)")
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
    func testTypingWikiLinkTriggerShowsSuggestionsAndInsertsLinkedNote() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForWikiLink")
            XCTFail("Welcome note must exist for iPhone wiki-link insertion coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n[[To")

        let picker = element(matchingIdentifier: "editor-link-picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "Typing [[ on iPhone must open note-link suggestions")

        let suggestion = element(matchingIdentifier: "editor-link-suggestion-0")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5),
                      "A matching note suggestion must be visible on iPhone")

        interact(with: suggestion)
        assertEditorContains("[[Todo]]")
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

    @MainActor
    func testToolbarFindButtonOpensEditorScopedFindBar() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPhone_EditorShell_NoWelcomeForFind")
            XCTFail("Welcome note must exist for iPhone in-note find coverage")
            return
        }

        let findButton = element(matchingIdentifier: "editor-find-button")
        XCTAssertTrue(findButton.waitForExistence(timeout: 5),
                      "iPhone must expose a real Find in Note affordance")

        interact(with: findButton)
        XCTAssertTrue(element(matchingIdentifier: "editor-find-query").waitForExistence(timeout: 5),
                      "Tapping the iPhone find affordance must open the editor-scoped find UI")
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
    func testTypingWikiLinkTriggerShowsSuggestionsAndInsertsLinkedNote() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForWikiLink")
            XCTFail("Welcome note must exist for iPad wiki-link insertion coverage")
            return
        }

        let editor = focusEditor()
        editor.typeText("\n[[To")

        let picker = element(matchingIdentifier: "editor-link-picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "Typing [[ on iPad must open note-link suggestions")

        let suggestion = element(matchingIdentifier: "editor-link-suggestion-0")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5),
                      "A matching note suggestion must be visible on iPad")

        interact(with: suggestion)
        assertEditorContains("[[Todo]]")
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

    @MainActor
    func testSplitViewFindButtonOpensEditorScopedFindBar() throws {
        launchApp()

        guard openMockVaultNote(named: "Welcome") != nil else {
            takeScreenshot(named: "iPad_EditorShell_NoWelcomeForFind")
            XCTFail("Welcome note must exist for iPad in-note find coverage")
            return
        }

        let findButton = element(matchingIdentifier: "editor-find-button")
        XCTAssertTrue(findButton.waitForExistence(timeout: 5),
                      "iPad must expose a real Find in Note affordance")

        interact(with: findButton)
        XCTAssertTrue(element(matchingIdentifier: "editor-find-query").waitForExistence(timeout: 5),
                      "Tapping the iPad find affordance must open the editor-scoped find UI")
    }

}
#endif
