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

        // With --mock-vault, app must skip vault picker and show the sidebar
        let sidebar = app.otherElements["sidebar-file-tree"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "iPhone must launch to sidebar file tree with mock vault")

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

        // Editor must appear
        let editor = app.otherElements["editor-text-view"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10),
                      "Editor must appear after tapping note on iPhone")

        takeScreenshot(named: "iPhone_NoteOpen")
    }

    // MARK: - Accessibility

    @MainActor
    func testAccessibilityLabelsExist() throws {
        launchApp()

        // Sidebar must be present and accessible
        let sidebar = app.otherElements["sidebar-file-tree"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "Sidebar file tree must exist on iPhone")
        XCTAssertTrue(sidebar.isEnabled, "Sidebar file tree must be accessible")

        // FAB must exist, be hittable, and have an accessibility label
        let fab = app.buttons.matching(identifier: "sidebar-new-note-fab").firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 5),
                      "New note FAB must exist on iPhone")
        XCTAssertTrue(fab.isHittable, "New note FAB must be hittable")
        assertAccessibilityLabelNonEmpty(fab, context: "iPhone new-note FAB")

        takeScreenshot(named: "iPhone_Accessibility")
    }

    // MARK: - Screenshots

    @MainActor
    func testScreenshotCapture() throws {
        launchApp()
        assertScreenshotNonEmpty(named: "iPhone_MainScreen")

        let welcomeCell = app.staticTexts["Welcome"]
        if welcomeCell.waitForExistence(timeout: 10) {
            welcomeCell.tap()
            _ = app.textViews.firstMatch.waitForExistence(timeout: 5)
            assertScreenshotNonEmpty(named: "iPhone_Editor")
        }
    }
}
