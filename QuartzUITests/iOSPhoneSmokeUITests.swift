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

        XCTAssertTrue(waitForCompactPhoneNoteList(timeout: 15),
                      "iPhone must launch to the compact note list with mock vault")

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

        XCTAssertTrue(waitForEditorSurface(timeout: 10),
                      "Editor must appear after tapping note on iPhone")

        takeScreenshot(named: "iPhone_NoteOpen")
    }

    // MARK: - Accessibility

    @MainActor
    func testAccessibilityLabelsExist() throws {
        launchApp()

        XCTAssertTrue(waitForCompactPhoneNoteList(timeout: 15),
                      "Compact note list must exist on iPhone")

        let newNoteButton = compactNewNoteButton()
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5),
                      "New note action must exist on iPhone")
        XCTAssertTrue(newNoteButton.isHittable, "New note action must be hittable")
        assertAccessibilityLabelNonEmpty(newNoteButton, context: "iPhone new-note action")

        takeScreenshot(named: "iPhone_Accessibility")
    }

    // MARK: - Dynamic Type / Accessibility XL

    @MainActor
    func testAccessibilityXLLayout() throws {
        launchApp(arguments: [
            "--uitesting",
            "--reset-state",
            "--mock-vault",
            "--disable-animations",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraLarge"
        ])

        XCTAssertTrue(waitForCompactPhoneNoteList(timeout: 15),
                      "Compact note list must remain visible at Accessibility XL text size")

        let newNoteButton = compactNewNoteButton()
        if newNoteButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(newNoteButton.isHittable,
                          "New note action must be hittable at Accessibility XL text size")
        }

        assertScreenshotNonEmpty(named: "iPhone_AccessibilityXL")
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

private extension iOSPhoneSmokeUITests {
    @MainActor
    func waitForCompactPhoneNoteList(timeout: TimeInterval) -> Bool {
        let identifiedNoteList = element(matchingIdentifier: "note-list-view")
        if identifiedNoteList.waitForExistence(timeout: min(timeout, 2)) {
            return true
        }

        return app.staticTexts["Welcome"].waitForExistence(timeout: timeout)
    }

    @MainActor
    func compactNewNoteButton() -> XCUIElement {
        let identifiedButton = element(matchingIdentifier: "note-list-new-note")
        if identifiedButton.exists {
            return identifiedButton
        }

        return app.buttons["New Note"]
    }
}
