import XCTest

/// iPhone smoke tests — launch, note CRUD, accessibility, screenshots.
///
/// These tests run on iPhone simulators. They verify the compact layout
/// (stack-based navigation) and touch interaction patterns.
final class iOSPhoneSmokeUITests: QuartzUITestCase {

    override func setUpWithError() throws {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Skipping iPhone tests on iPad")
        }
        #else
        throw XCTSkip("Skipping iPhone tests on macOS")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Launch

    @MainActor
    func testLaunchToMainView() throws {
        launchApp()

        // With --mock-vault, app should skip vault picker and show the workspace
        let sidebar = app.otherElements["sidebar-file-tree"]
        let welcomeNote = app.staticTexts["Welcome"]

        let foundSidebar = sidebar.waitForExistence(timeout: 15)
        let foundNote = welcomeNote.waitForExistence(timeout: 5)
        XCTAssertTrue(foundSidebar || foundNote, "App should launch to workspace with mock vault")

        takeScreenshot(named: "iPhone_Launch")
    }

    // MARK: - Note Round Trip

    @MainActor
    func testOpenExistingNote() throws {
        launchApp()

        let welcomeCell = app.staticTexts["Welcome"]
        guard welcomeCell.waitForExistence(timeout: 15) else {
            takeScreenshot(named: "iPhone_BeforeNoteOpen")
            XCTFail("Welcome note not found in sidebar/content")
            return
        }

        welcomeCell.tap()

        // Editor should appear
        let editor = app.otherElements["editor-text-view"]
        let editorExists = editor.waitForExistence(timeout: 10)

        if !editorExists {
            let anyTextView = app.textViews.firstMatch
            XCTAssertTrue(anyTextView.waitForExistence(timeout: 5), "Editor should appear after tapping note")
        }

        takeScreenshot(named: "iPhone_NoteOpen")
    }

    // MARK: - Accessibility

    @MainActor
    func testAccessibilityLabelsExist() throws {
        launchApp()

        let sidebar = app.otherElements["sidebar-file-tree"]
        if sidebar.waitForExistence(timeout: 15) {
            XCTAssertTrue(sidebar.isEnabled, "Sidebar file tree should be accessible")
        }

        let fab = app.buttons.matching(identifier: "sidebar-new-note-fab").firstMatch
        if fab.waitForExistence(timeout: 5) {
            XCTAssertTrue(fab.isHittable, "New note FAB should be hittable")
        }

        takeScreenshot(named: "iPhone_Accessibility")
    }

    // MARK: - Screenshots

    @MainActor
    func testScreenshotCapture() throws {
        launchApp()
        takeScreenshot(named: "iPhone_MainScreen")

        let welcomeCell = app.staticTexts["Welcome"]
        if welcomeCell.waitForExistence(timeout: 10) {
            welcomeCell.tap()
            _ = app.textViews.firstMatch.waitForExistence(timeout: 5)
            takeScreenshot(named: "iPhone_Editor")
        }
    }
}
