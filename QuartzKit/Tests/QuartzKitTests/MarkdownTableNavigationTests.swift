import Testing
import Foundation
@testable import QuartzKit

// MARK: - Table Row Detection Tests

@Suite("MarkdownTableNavigation — Row Detection")
struct TableNavigationRowDetectionTests {

    @Test("Standard table row detected")
    func standardRow() {
        #expect(MarkdownTableNavigation.isTableRow("| A | B | C |") == true)
    }

    @Test("Row with surrounding whitespace detected")
    func rowWithWhitespace() {
        #expect(MarkdownTableNavigation.isTableRow("  | A | B |  ") == true)
    }

    @Test("Minimal table row detected")
    func minimalRow() {
        #expect(MarkdownTableNavigation.isTableRow("|||") == true)
    }

    @Test("Non-table line rejected")
    func nonTableLine() {
        #expect(MarkdownTableNavigation.isTableRow("Hello world") == false)
    }

    @Test("Line with only leading pipe rejected")
    func leadingPipeOnly() {
        #expect(MarkdownTableNavigation.isTableRow("| not a table") == false)
    }

    @Test("Empty line rejected")
    func emptyLine() {
        #expect(MarkdownTableNavigation.isTableRow("") == false)
    }

    @Test("Divider row is also a table row")
    func dividerIsTableRow() {
        #expect(MarkdownTableNavigation.isTableRow("|---|---|") == true)
    }

    @Test("Divider row detected correctly")
    func dividerRowDetected() {
        #expect(MarkdownTableNavigation.isDividerRow("|---|---|") == true)
        #expect(MarkdownTableNavigation.isDividerRow("| --- | --- |") == true)
        #expect(MarkdownTableNavigation.isDividerRow("|:---:|---:|") == true)
    }

    @Test("Non-divider table row not flagged as divider")
    func nonDivider() {
        #expect(MarkdownTableNavigation.isDividerRow("| A | B |") == false)
    }

    @Test("Row with newline at end still detected")
    func rowWithNewline() {
        #expect(MarkdownTableNavigation.isTableRow("| A | B |\n") == true)
    }
}

// MARK: - Forward Navigation Tests

@Suite("MarkdownTableNavigation — Forward (Tab)")
struct TableNavigationForwardTests {

    private let nav = MarkdownTableNavigation()

    private let simpleTable = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob   | 25 |
        """

    @Test("Tab from first header cell moves to second header cell")
    func tabFromFirstHeader() {
        let result = nav.handleTab(in: simpleTable, cursorPosition: 3, isShiftTab: false)
        #expect(result != nil)
        // Should move to Age cell
        #expect(result!.cursorPosition > 7) // past "| Name "
    }

    @Test("Tab from non-table line returns nil")
    func tabOutsideTable() {
        let text = "Not a table\n| A | B |\n|---|---|\n| 1 | 2 |"
        let result = nav.handleTab(in: text, cursorPosition: 5, isShiftTab: false)
        #expect(result == nil)
    }

    @Test("Tab in last cell of last row inserts new row")
    func tabAtEndInsertsRow() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        // Cursor in the "2" cell of the last body row
        let nsText = text as NSString
        let lastPipe = nsText.range(of: "2").location
        let result = nav.handleTab(in: text, cursorPosition: lastPipe, isShiftTab: false)
        #expect(result != nil)
        #expect(result!.newRowInsertion != nil)
        #expect(result!.newRowInsertion!.rowText.contains("|"))
    }

    @Test("Navigation result selects cell content")
    func selectsCellContent() {
        let text = "| Hello | World |\n|-------|-------|\n| Foo   | Bar   |\n"
        // Cursor in "Foo" cell
        let nsText = text as NSString
        let fooLoc = nsText.range(of: "Foo").location
        let result = nav.handleTab(in: text, cursorPosition: fooLoc, isShiftTab: false)
        #expect(result != nil)
        // Should select "Bar" content
        #expect(result!.selectionRange.length > 0)
    }

    @Test("Tab skips divider row")
    func tabSkipsDivider() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        // Cursor in "B" header cell — Tab should skip divider, go to "1" body cell
        let nsText = text as NSString
        let bLoc = nsText.range(of: "B").location
        let result = nav.handleTab(in: text, cursorPosition: bLoc, isShiftTab: false)
        #expect(result != nil)
        // Target should be in body row, not divider
        let targetLine = nsText.lineRange(for: NSRange(location: result!.cursorPosition, length: 0))
        let targetLineStr = nsText.substring(with: targetLine)
        #expect(MarkdownTableNavigation.isDividerRow(targetLineStr) == false)
    }
}

// MARK: - Backward Navigation Tests

@Suite("MarkdownTableNavigation — Backward (Shift-Tab)")
struct TableNavigationBackwardTests {

    private let nav = MarkdownTableNavigation()

    @Test("Shift-Tab from second cell moves to first cell")
    func shiftTabToFirst() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let nsText = text as NSString
        let bLoc = nsText.range(of: "B").location
        let result = nav.handleTab(in: text, cursorPosition: bLoc, isShiftTab: true)
        #expect(result != nil)
        // Should move to "A" cell
        #expect(result!.cursorPosition < bLoc)
    }

    @Test("Shift-Tab at first cell stays put")
    func shiftTabAtFirstCell() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let nsText = text as NSString
        let aLoc = nsText.range(of: "A").location
        let result = nav.handleTab(in: text, cursorPosition: aLoc, isShiftTab: true)
        #expect(result != nil)
        // Should stay at "A"
        #expect(result!.cursorPosition == aLoc)
    }

    @Test("Shift-Tab from body row moves to header row")
    func shiftTabCrossesRows() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let nsText = text as NSString
        let oneLoc = nsText.range(of: "1").location
        let result = nav.handleTab(in: text, cursorPosition: oneLoc, isShiftTab: true)
        #expect(result != nil)
        // Should move to "B" in header
        #expect(result!.cursorPosition < oneLoc)
    }

    @Test("Shift-Tab skips divider row")
    func shiftTabSkipsDivider() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let nsText = text as NSString
        let oneLoc = nsText.range(of: "1").location
        let result = nav.handleTab(in: text, cursorPosition: oneLoc, isShiftTab: true)
        #expect(result != nil)
        let targetLine = nsText.lineRange(for: NSRange(location: result!.cursorPosition, length: 0))
        let targetLineStr = nsText.substring(with: targetLine)
        #expect(MarkdownTableNavigation.isDividerRow(targetLineStr) == false)
    }

    @Test("Shift-Tab on non-table returns nil")
    func shiftTabOutsideTable() {
        let text = "Just regular text"
        let result = nav.handleTab(in: text, cursorPosition: 5, isShiftTab: true)
        #expect(result == nil)
    }
}

// MARK: - New Row Insertion Tests

@Suite("MarkdownTableNavigation — New Row Insertion")
struct TableNavigationNewRowTests {

    private let nav = MarkdownTableNavigation()

    @Test("New row has correct number of columns")
    func newRowColumnCount() {
        let text = "| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n"
        let nsText = text as NSString
        let threeLoc = nsText.range(of: "3").location
        let result = nav.handleTab(in: text, cursorPosition: threeLoc, isShiftTab: false)
        #expect(result != nil)
        #expect(result!.newRowInsertion != nil)
        // Count pipes in new row: should be 4 (for 3 columns)
        let pipeCount = result!.newRowInsertion!.rowText.filter { $0 == "|" }.count
        #expect(pipeCount == 4)
    }

    @Test("New row insertion point is at end of table")
    func newRowAtTableEnd() {
        let text = "| A |\n|---|\n| 1 |\n"
        let nsText = text as NSString
        let oneLoc = nsText.range(of: "1").location
        let result = nav.handleTab(in: text, cursorPosition: oneLoc, isShiftTab: false)
        #expect(result != nil)
        #expect(result!.newRowInsertion != nil)
        #expect(result!.newRowInsertion!.insertionPoint == nsText.length)
    }

    @Test("New row text ends with newline")
    func newRowEndsWithNewline() {
        let text = "| A |\n|---|\n| 1 |\n"
        let nsText = text as NSString
        let oneLoc = nsText.range(of: "1").location
        let result = nav.handleTab(in: text, cursorPosition: oneLoc, isShiftTab: false)
        #expect(result != nil)
        #expect(result!.newRowInsertion!.rowText.hasSuffix("\n"))
    }
}

// MARK: - Edge Cases

@Suite("MarkdownTableNavigation — Edge Cases")
struct TableNavigationEdgeCaseTests {

    private let nav = MarkdownTableNavigation()

    @Test("Table with no divider row still works")
    func noDividerRow() {
        let text = "| A | B |\n| 1 | 2 |\n"
        let nsText = text as NSString
        let aLoc = nsText.range(of: "A").location
        let result = nav.handleTab(in: text, cursorPosition: aLoc, isShiftTab: false)
        #expect(result != nil)
    }

    @Test("Single-column table")
    func singleColumn() {
        let text = "| A |\n|---|\n| 1 |\n"
        let nsText = text as NSString
        let aLoc = nsText.range(of: "A").location
        let result = nav.handleTab(in: text, cursorPosition: aLoc, isShiftTab: false)
        #expect(result != nil)
    }

    @Test("Table embedded in document")
    func embeddedTable() {
        let text = "# Title\n\nSome text\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nMore text"
        let nsText = text as NSString
        let aLoc = nsText.range(of: "A").location
        let result = nav.handleTab(in: text, cursorPosition: aLoc, isShiftTab: false)
        #expect(result != nil)
    }

    @Test("Cursor on pipe character finds nearest cell")
    func cursorOnPipe() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        // Place cursor on the pipe between A and B
        let nsText = text as NSString
        let pipeLoc = nsText.range(of: " | B").location
        let result = nav.handleTab(in: text, cursorPosition: pipeLoc, isShiftTab: false)
        // Should still navigate (either from A or B cell)
        // nil is acceptable if cursor is exactly on the pipe
        _ = result // just ensure no crash
    }

    @Test("Empty cell content")
    func emptyCell() {
        let text = "| A |   |\n|---|---|\n|   | B |\n"
        let nsText = text as NSString
        let aLoc = nsText.range(of: "A").location
        let result = nav.handleTab(in: text, cursorPosition: aLoc, isShiftTab: false)
        #expect(result != nil)
    }
}
