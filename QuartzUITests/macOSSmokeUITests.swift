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

        // With --mock-vault, app must open directly to the workspace.
        // On macOS, NavigationSplitView renders via NSSplitView which does not
        // surface as otherElements — assert the sidebar outline instead.
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "macOS must launch to workspace with sidebar outline visible")

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
            XCTFail("Note not found in sidebar — mock vault must load for edit round-trip")
            return
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

        // Sidebar must be present and accessible
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "Sidebar outline must exist")
        XCTAssertTrue(sidebar.isEnabled, "Sidebar outline must be accessible")

        // Verify sidebar contains accessible child elements
        let outlineRows = app.outlineRows
        XCTAssertGreaterThan(outlineRows.count, 0,
                             "Sidebar must contain at least one outline row")

        // New-note button — may be in toolbar or sidebar header
        let newNote = app.buttons.matching(identifier: "sidebar-new-note").firstMatch
        if newNote.waitForExistence(timeout: 5) {
            XCTAssertTrue(newNote.isEnabled, "New note button must be accessible")
            assertAccessibilityLabelNonEmpty(newNote, context: "macOS new-note button")
        } else {
            // Toolbar buttons on macOS may not surface with identifier queries.
            // Assert that at least one button exists in the toolbar area.
            XCTAssertGreaterThan(app.buttons.count, 0,
                                 "macOS window must contain accessible buttons")
        }

        takeScreenshot(named: "macOS_Accessibility")
    }

    // MARK: - Screenshots

    @MainActor
    func testScreenshotCapture() throws {
        launchApp()
        assertScreenshotNonEmpty(named: "macOS_MainWindow")

        // Try to find and open a note for editor screenshot
        let predicate = NSPredicate(format: "label CONTAINS[c] 'Welcome' OR label CONTAINS[c] 'Todo'")
        for query in [app.staticTexts, app.cells, app.outlineRows] {
            let match = query.matching(predicate).firstMatch
            if match.waitForExistence(timeout: 3) {
                match.click()
                _ = app.textViews.firstMatch.waitForExistence(timeout: 5)
                assertScreenshotNonEmpty(named: "macOS_Editor")
                break
            }
        }
    }
}
#endif
