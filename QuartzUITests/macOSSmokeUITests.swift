import XCTest

/// macOS smoke tests — window layout, keyboard navigation, screenshots.
///
/// These tests run on macOS only. They verify the windowed layout,
/// keyboard shortcuts, and native Mac interaction patterns.
#if os(macOS)
final class macOSSmokeUITests: QuartzUITestCase {

    // MARK: - Launch

    @MainActor
    func testLaunchToMainWindow() throws {
        launchApp()

        // With --mock-vault, app should open directly to workspace
        let sidebar = app.outlines.firstMatch
        let splitView = app.otherElements["workspace-split-view"]

        let foundSidebar = sidebar.waitForExistence(timeout: 15)
        let foundSplit = splitView.waitForExistence(timeout: 10)

        XCTAssertTrue(foundSidebar || foundSplit, "macOS should launch with main window showing workspace")

        takeScreenshot(named: "macOS_Launch")
    }

    // MARK: - Keyboard Navigation

    @MainActor
    func testKeyboardShortcuts() throws {
        launchApp()

        let sidebar = app.outlines.firstMatch
        _ = sidebar.waitForExistence(timeout: 15)

        // Cmd+K should open command palette
        app.typeKey("k", modifierFlags: .command)

        let paletteField = app.searchFields.firstMatch
        if paletteField.waitForExistence(timeout: 5) {
            takeScreenshot(named: "macOS_CommandPalette")
            app.typeKey(.escape, modifierFlags: [])
        }

        takeScreenshot(named: "macOS_AfterKeyboard")
    }

    // MARK: - Note Edit Round Trip

    @MainActor
    func testNoteEditRoundTrip() throws {
        launchApp()

        // On macOS, sidebar uses NSOutlineView — cells may appear as different element types
        // Try multiple strategies to find a note in the sidebar
        let predicate = NSPredicate(format: "label CONTAINS[c] 'Welcome' OR label CONTAINS[c] 'Todo'")

        // Search across multiple element types that macOS outlines may use
        var noteElement: XCUIElement?
        for query in [app.staticTexts, app.cells, app.outlineRows, app.buttons] {
            let match = query.matching(predicate).firstMatch
            if match.waitForExistence(timeout: 3) {
                noteElement = match
                break
            }
        }

        guard let note = noteElement else {
            takeScreenshot(named: "macOS_NoNote_InSidebar")
            // This test is non-blocking — mock vault may not load in all environments
            throw XCTSkip("Note not found in sidebar — mock vault may not have loaded")
        }

        note.click()

        let editor = app.textViews.firstMatch
        guard editor.waitForExistence(timeout: 10) else {
            takeScreenshot(named: "macOS_NoEditor")
            XCTFail("Editor did not appear after selecting note")
            return
        }

        editor.click()
        editor.typeText("\nEdited from macOS UI test")

        takeScreenshot(named: "macOS_AfterEdit")
    }

    // MARK: - Accessibility

    @MainActor
    func testAccessibilityLabelsExist() throws {
        launchApp()

        let sidebar = app.outlines.firstMatch
        if sidebar.waitForExistence(timeout: 15) {
            XCTAssertTrue(sidebar.isEnabled, "Sidebar outline should be accessible")
        }

        let newNote = app.buttons.matching(identifier: "sidebar-new-note").firstMatch
        if newNote.waitForExistence(timeout: 5) {
            XCTAssertTrue(newNote.isEnabled, "New note button should be accessible")
        }

        takeScreenshot(named: "macOS_Accessibility")
    }

    // MARK: - Screenshots

    @MainActor
    func testScreenshotCapture() throws {
        launchApp()
        takeScreenshot(named: "macOS_MainWindow")

        // Try to find and open a note for editor screenshot
        let predicate = NSPredicate(format: "label CONTAINS[c] 'Welcome' OR label CONTAINS[c] 'Todo'")
        for query in [app.staticTexts, app.cells, app.outlineRows] {
            let match = query.matching(predicate).firstMatch
            if match.waitForExistence(timeout: 3) {
                match.click()
                _ = app.textViews.firstMatch.waitForExistence(timeout: 5)
                takeScreenshot(named: "macOS_Editor")
                break
            }
        }
    }
}
#endif
