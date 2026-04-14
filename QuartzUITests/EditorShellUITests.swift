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
        app.typeKey("b", modifierFlags: .command)

        let token = "macBold\(UUID().uuidString.prefix(6))"
        editor.typeText(token)
        assertEditorContains("**\(token)**")
    }
}
#endif

#if os(iOS)
final class iPhoneEditorShellUITests: QuartzUITestCase {

    override func setUpWithError() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
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
}

final class iPadEditorShellUITests: QuartzUITestCase {

    override func setUpWithError() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
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
}
#endif
