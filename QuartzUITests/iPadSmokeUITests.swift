import XCTest

/// iPad smoke tests — split view layout, side-by-side editing, screenshots.
///
/// These tests run on iPad simulators. They verify the regular-width layout
/// (NavigationSplitView with sidebar + content + detail visible).
final class iPadSmokeUITests: QuartzUITestCase {

    override func setUpWithError() throws {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Skipping iPad tests on iPhone")
        }
        #else
        throw XCTSkip("Skipping iPad tests on macOS")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Launch

    @MainActor
    func testLaunchShowsSplitView() throws {
        launchApp()

        // iPad must show both split view and sidebar simultaneously
        let splitView = app.otherElements["workspace-split-view"]
        let sidebar = app.otherElements["sidebar-file-tree"]

        XCTAssertTrue(splitView.waitForExistence(timeout: 15),
                      "iPad must launch with workspace split view")
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10),
                      "iPad must show sidebar in split view layout")

        takeScreenshot(named: "iPad_Launch_SplitView")
    }

    // MARK: - Side-by-Side

    @MainActor
    func testSidebarAndEditorVisible() throws {
        launchApp()

        let sidebar = app.otherElements["sidebar-file-tree"]
        guard sidebar.waitForExistence(timeout: 15) else {
            takeScreenshot(named: "iPad_NoSidebar")
            XCTFail("Sidebar should be visible on iPad")
            return
        }

        let welcomeCell = app.staticTexts["Welcome"]
        if welcomeCell.waitForExistence(timeout: 10) {
            welcomeCell.tap()

            let editor = app.otherElements["editor-text-view"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10),
                         "iPad must show editor after tapping note in split view")

            // Sidebar must remain visible alongside editor
            XCTAssertTrue(sidebar.exists,
                         "iPad sidebar must remain visible in split layout")
        }

        takeScreenshot(named: "iPad_SplitView_SidebarAndEditor")
    }

    // MARK: - Note Edit Round Trip

    @MainActor
    func testNoteEditRoundTrip() throws {
        launchApp()

        let welcomeCell = app.staticTexts["Welcome"]
        guard welcomeCell.waitForExistence(timeout: 15) else {
            takeScreenshot(named: "iPad_BeforeEdit")
            XCTFail("Welcome note not found")
            return
        }

        welcomeCell.tap()

        let editor = app.textViews.firstMatch
        guard editor.waitForExistence(timeout: 10) else {
            takeScreenshot(named: "iPad_NoEditor")
            XCTFail("Editor did not appear after selecting note")
            return
        }

        editor.tap()
        editor.typeText("\nEdited from iPad UI test")

        takeScreenshot(named: "iPad_AfterEdit")
    }

    // MARK: - Accessibility

    @MainActor
    func testAccessibilityLabelsExist() throws {
        launchApp()

        // Sidebar must be present and accessible
        let sidebar = app.otherElements["sidebar-file-tree"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "Sidebar must exist on iPad")
        XCTAssertTrue(sidebar.isEnabled, "Sidebar must be accessible on iPad")

        // Dashboard must be present and accessible
        let dashboard = app.otherElements["dashboard-view"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5),
                      "Dashboard must exist on iPad")
        XCTAssertTrue(dashboard.isEnabled, "Dashboard must be accessible on iPad")

        takeScreenshot(named: "iPad_Accessibility")
    }

    // MARK: - Dynamic Type / Accessibility XL

    @MainActor
    func testAccessibilityXLLayout() throws {
        // Launch with accessibility extra-large text
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "--reset-state",
            "--mock-vault",
            "--disable-animations",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraLarge"
        ]
        app.launch()

        // Split view must still be present at XL text size
        let splitView = app.otherElements["workspace-split-view"]
        let sidebar = app.otherElements["sidebar-file-tree"]

        XCTAssertTrue(splitView.waitForExistence(timeout: 15),
                      "Split view must remain visible at Accessibility XL text size")
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10),
                      "Sidebar must remain visible at Accessibility XL text size")

        assertScreenshotNonEmpty(named: "iPad_AccessibilityXL")
    }

    // MARK: - Screenshots

    @MainActor
    func testScreenshotCapture() throws {
        launchApp()
        assertScreenshotNonEmpty(named: "iPad_MainScreen")

        let welcomeCell = app.staticTexts["Welcome"]
        if welcomeCell.waitForExistence(timeout: 10) {
            welcomeCell.tap()
            _ = app.textViews.firstMatch.waitForExistence(timeout: 5)
            assertScreenshotNonEmpty(named: "iPad_Editor")
        }
    }
}
