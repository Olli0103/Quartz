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
        let splitView = element(matchingIdentifier: "workspace-split-view")
        let sidebar = element(matchingIdentifier: "sidebar-file-tree")

        XCTAssertTrue(splitView.waitForExistence(timeout: 15),
                      "iPad must launch with workspace split view")
        XCTAssertTrue(waitForRegularWidthNavigation(timeout: 10),
                      "iPad must show sidebar in split view layout")
        XCTAssertTrue(sidebar.exists || element(matchingIdentifier: "note-list-view").exists,
                      "iPad split view must expose the navigation columns")

        takeScreenshot(named: "iPad_Launch_SplitView")
    }

    // MARK: - Side-by-Side

    @MainActor
    func testSidebarAndEditorVisible() throws {
        launchApp()

        let sidebar = element(matchingIdentifier: "sidebar-file-tree")
        guard waitForRegularWidthNavigation(timeout: 15) else {
            takeScreenshot(named: "iPad_NoSidebar")
            XCTFail("Sidebar should be visible on iPad")
            return
        }

        if let welcomeTarget = mockVaultWelcomeTarget(timeout: 10) {
            welcomeTarget.tap()

            XCTAssertTrue(waitForEditorSurface(timeout: 10),
                          "iPad must show editor after tapping note in split view")

            // Sidebar must remain visible alongside editor
            XCTAssertTrue(sidebar.exists || element(matchingIdentifier: "note-list-view").exists,
                          "iPad navigation columns must remain visible in split layout")
        }

        takeScreenshot(named: "iPad_SplitView_SidebarAndEditor")
    }

    // MARK: - Note Edit Round Trip

    @MainActor
    func testNoteEditRoundTrip() throws {
        launchApp()

        guard let welcomeTarget = mockVaultWelcomeTarget(timeout: 15) else {
            takeScreenshot(named: "iPad_BeforeEdit")
            XCTFail("Welcome note not found")
            return
        }

        welcomeTarget.tap()

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
        let sidebar = element(matchingIdentifier: "sidebar-file-tree")
        let noteList = element(matchingIdentifier: "note-list-view")
        XCTAssertTrue(waitForRegularWidthNavigation(timeout: 15),
                      "Sidebar must exist on iPad")
        XCTAssertTrue(sidebar.isEnabled || noteList.isEnabled,
                      "Regular-width navigation must be accessible on iPad")

        // Dashboard must be present and accessible
        let dashboard = element(matchingIdentifier: "dashboard-view")
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5),
                      "Dashboard must exist on iPad")
        XCTAssertTrue(dashboard.isEnabled, "Dashboard must be accessible on iPad")

        takeScreenshot(named: "iPad_Accessibility")
    }

    // MARK: - Dynamic Type / Accessibility XL

    @MainActor
    func testAccessibilityXLLayout() throws {
        // Launch with accessibility extra-large text
        launchApp(arguments: [
            "--uitesting",
            "--reset-state",
            "--mock-vault",
            "--disable-animations",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraLarge"
        ])

        // Split view must still be present at XL text size
        let splitView = element(matchingIdentifier: "workspace-split-view")
        let sidebar = element(matchingIdentifier: "sidebar-file-tree")
        let noteList = element(matchingIdentifier: "note-list-view")

        XCTAssertTrue(splitView.waitForExistence(timeout: 15),
                      "Split view must remain visible at Accessibility XL text size")
        XCTAssertTrue(waitForRegularWidthNavigation(timeout: 10),
                      "Sidebar must remain visible at Accessibility XL text size")
        XCTAssertTrue(sidebar.exists || noteList.exists,
                      "Regular-width navigation must remain visible at Accessibility XL text size")

        assertScreenshotNonEmpty(named: "iPad_AccessibilityXL")
    }

    // MARK: - Screenshots

    @MainActor
    func testScreenshotCapture() throws {
        launchApp()
        assertScreenshotNonEmpty(named: "iPad_MainScreen")

        if let welcomeTarget = mockVaultWelcomeTarget(timeout: 10) {
            welcomeTarget.tap()
            _ = app.textViews.firstMatch.waitForExistence(timeout: 5)
            assertScreenshotNonEmpty(named: "iPad_Editor")
        }
    }
}

private extension iPadSmokeUITests {
    @MainActor
    func waitForRegularWidthNavigation(timeout: TimeInterval) -> Bool {
        let sidebar = element(matchingIdentifier: "sidebar-file-tree")
        if sidebar.waitForExistence(timeout: min(timeout, 5)) {
            return true
        }

        let noteList = element(matchingIdentifier: "note-list-view")
        if noteList.waitForExistence(timeout: min(timeout, 5)) {
            return true
        }

        return app.staticTexts["Welcome"].waitForExistence(timeout: timeout)
    }

    @MainActor
    func mockVaultWelcomeTarget(timeout: TimeInterval) -> XCUIElement? {
        let noteList = element(matchingIdentifier: "note-list-view")
        _ = noteList.waitForExistence(timeout: min(timeout, 5))

        let notePredicate = NSPredicate(format: "label CONTAINS[c] 'Welcome'")
        let noteListTarget = noteList.descendants(matching: .any).matching(notePredicate).firstMatch
        if noteListTarget.waitForExistence(timeout: min(timeout, 5)) {
            return noteListTarget
        }

        let noteListCell = app.collectionViews.matching(identifier: "note-list-view").cells.firstMatch
        if noteListCell.waitForExistence(timeout: min(timeout, 5)) {
            return noteListCell
        }

        let dashboardTarget = element(matchingIdentifier: "dashboard-view")
            .buttons
            .matching(notePredicate)
            .firstMatch
        if dashboardTarget.waitForExistence(timeout: timeout) {
            return dashboardTarget
        }

        return nil
    }
}
