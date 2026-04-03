import Testing
import Foundation
@testable import QuartzKit

// MARK: - Dirty Range (Post-Edit Coordinates) Tests

@Suite("ASTDirtyRegionTracker — dirtyRange")
struct ASTDirtyRegionTrackerDirtyRangeTests {

    @Test("Empty text returns nil")
    func emptyText() {
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: "",
            editRange: NSRange(location: 0, length: 0)
        )
        #expect(result == nil)
    }

    @Test("Single character edit in single-line doc covers entire line")
    func singleCharSingleLine() {
        let text = "Hello world"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 5, length: 1)
        )
        #expect(result == NSRange(location: 0, length: 11))
    }

    @Test("Edit at start of line covers that paragraph")
    func editAtLineStart() {
        let text = "Line one\nLine two\nLine three"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 9, length: 1)
        )
        // Should cover "Line two\n" = location 9, length 9
        #expect(result != nil)
        #expect(result!.location == 9)
        #expect(result!.location + result!.length <= 18)
    }

    @Test("Edit spanning two lines covers both paragraphs")
    func editSpansTwoLines() {
        let text = "AAA\nBBB\nCCC"
        // Edit covers end of "AAA\n" into start of "BBB\n"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 2, length: 4)
        )
        #expect(result != nil)
        // Should cover from "AAA\n" start to "BBB\n" end
        #expect(result!.location == 0)
        #expect(result!.location + result!.length >= 8)
    }

    @Test("Zero-length edit (cursor position) covers containing paragraph")
    func zeroLengthEdit() {
        let text = "First\nSecond\nThird"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 8, length: 0)
        )
        #expect(result != nil)
        // Cursor is in "Second\n" paragraph
        #expect(result!.location == 6)
    }

    @Test("Edit at end of document covers last paragraph")
    func editAtEnd() {
        let text = "First\nLast"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 10, length: 0)
        )
        #expect(result != nil)
        // Last paragraph "Last" starts at 6
        #expect(result!.location == 6)
        #expect(result!.location + result!.length == 10)
    }

    @Test("Edit range clamped to text bounds")
    func clampedRange() {
        let text = "Short"
        // Range exceeds text length
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 100, length: 50)
        )
        #expect(result != nil)
        // Should clamp to valid range
        #expect(result!.location >= 0)
        #expect(result!.location + result!.length <= 5)
    }

    @Test("Newline-only document")
    func newlineOnlyDoc() {
        let text = "\n\n\n"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 1, length: 0)
        )
        #expect(result != nil)
    }
}

// MARK: - Dirty Range (Pre-Edit Coordinates) Tests

@Suite("ASTDirtyRegionTracker — dirtyRange from preEditRange")
struct ASTDirtyRegionTrackerPreEditTests {

    @Test("Insertion (zero-length pre-edit range) with replacement")
    func insertion() {
        // Inserted "XY" at position 5 in "Hello world" → "HelloXY world"
        let text = "HelloXY world"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            preEditRange: NSRange(location: 5, length: 0),
            replacementLength: 2
        )
        #expect(result != nil)
        // Single line, should cover entire line
        #expect(result!.location == 0)
        #expect(result!.location + result!.length == 13)
    }

    @Test("Deletion (non-zero pre-edit range, zero replacement)")
    func deletion() {
        // Deleted 3 chars starting at position 5 in some text → "HelloWorld"
        let text = "HelloWorld"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            preEditRange: NSRange(location: 5, length: 3),
            replacementLength: 0
        )
        #expect(result != nil)
        #expect(result!.location == 0)
    }

    @Test("Replacement across paragraph boundary")
    func replacementAcrossParagraphs() {
        // After edit: "AAA\nXXXXX\nCCC"
        let text = "AAA\nXXXXX\nCCC"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            preEditRange: NSRange(location: 4, length: 3),
            replacementLength: 5
        )
        #expect(result != nil)
        // The replacement "XXXXX" is on line 2, should cover at least that paragraph
        #expect(result!.location <= 4)
    }

    @Test("Newline insertion creates new paragraph in dirty range")
    func newlineInsertion() {
        // Inserted "\n" at position 5: "Hello\n world"
        let text = "Hello\n world"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            preEditRange: NSRange(location: 5, length: 0),
            replacementLength: 1
        )
        #expect(result != nil)
        // Should cover both paragraphs since the newline is the edit
        #expect(result!.location == 0)
    }
}

// MARK: - Expanded Dirty Range Tests

@Suite("ASTDirtyRegionTracker — expandedDirtyRange")
struct ASTDirtyRegionTrackerExpandedTests {

    @Test("Expanded range includes previous paragraph")
    func includesPreviousParagraph() {
        let text = "Para one\nPara two\nPara three\nPara four"
        // Edit in "Para two"
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: text,
            editRange: NSRange(location: 12, length: 1)
        )
        #expect(result != nil)
        // Should include "Para one" (start at 0) through at least "Para three"
        #expect(result!.location == 0)
        #expect(result!.location + result!.length > 18) // extends past "Para two\n"
    }

    @Test("Expanded range includes next paragraph")
    func includesNextParagraph() {
        let text = "AAA\nBBB\nCCC\nDDD"
        // Edit in "BBB"
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: text,
            editRange: NSRange(location: 5, length: 1)
        )
        #expect(result != nil)
        // Should span from "AAA\n" through at least "CCC\n"
        #expect(result!.location == 0) // includes "AAA"
        let end = result!.location + result!.length
        #expect(end >= 12) // extends past "CCC\n"
    }

    @Test("Expanded range at document start doesn't go negative")
    func expandedAtStart() {
        let text = "First line\nSecond line"
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: text,
            editRange: NSRange(location: 3, length: 1)
        )
        #expect(result != nil)
        #expect(result!.location == 0) // Can't go before start
        // Should include "Second line"
        #expect(result!.location + result!.length == 22)
    }

    @Test("Expanded range at document end doesn't exceed length")
    func expandedAtEnd() {
        let text = "First line\nLast line"
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: text,
            editRange: NSRange(location: 15, length: 1)
        )
        #expect(result != nil)
        let end = result!.location + result!.length
        #expect(end == 20) // "First line\nLast line".count == 20
    }

    @Test("Expanded range on single-line doc returns entire doc")
    func expandedSingleLine() {
        let text = "Only one line here"
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: text,
            editRange: NSRange(location: 5, length: 1)
        )
        #expect(result != nil)
        #expect(result!.location == 0)
        #expect(result!.location + result!.length == 18)
    }

    @Test("Empty text returns nil for expanded range")
    func expandedEmptyText() {
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: "",
            editRange: NSRange(location: 0, length: 0)
        )
        #expect(result == nil)
    }

    @Test("Expanded from pre-edit coordinates")
    func expandedPreEdit() {
        let text = "AAA\nBBB\nCCC\nDDD"
        let result = ASTDirtyRegionTracker.expandedDirtyRange(
            in: text,
            preEditRange: NSRange(location: 4, length: 3),
            replacementLength: 3
        )
        #expect(result != nil)
        #expect(result!.location == 0) // Includes "AAA"
    }
}

// MARK: - Code Fence Boundary Detection Tests

@Suite("ASTDirtyRegionTracker — containsCodeFenceBoundary")
struct ASTDirtyRegionTrackerCodeFenceTests {

    @Test("Detects triple backtick fence")
    func detectsBacktickFence() {
        let text = "Some text\n```swift\ncode\n```\nMore text"
        let range = NSRange(location: 10, length: 8) // "```swift"
        #expect(ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range) == true)
    }

    @Test("Detects tilde fence")
    func detectsTildeFence() {
        let text = "Some text\n~~~\ncode\n~~~"
        let range = NSRange(location: 10, length: 3) // "~~~"
        #expect(ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range) == true)
    }

    @Test("No fence in plain text")
    func noFenceInPlainText() {
        let text = "Hello world\nNo fences here"
        let range = NSRange(location: 0, length: 11)
        #expect(ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range) == false)
    }

    @Test("Inline backticks are not fences")
    func inlineBackticksNotFences() {
        let text = "Use `code` here"
        let range = NSRange(location: 0, length: 15)
        #expect(ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range) == false)
    }

    @Test("Double backticks are not fences")
    func doubleBackticksNotFences() {
        let text = "Use ``code`` here"
        let range = NSRange(location: 0, length: 17)
        #expect(ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range) == false)
    }

    @Test("Invalid range returns false")
    func invalidRange() {
        let text = "Short"
        let range = NSRange(location: 0, length: 100)
        #expect(ASTDirtyRegionTracker.containsCodeFenceBoundary(in: text, range: range) == false)
    }
}

// MARK: - Edge Cases

@Suite("ASTDirtyRegionTracker — Edge Cases")
struct ASTDirtyRegionTrackerEdgeCaseTests {

    @Test("Document with only newlines")
    func onlyNewlines() {
        let text = "\n\n\n\n"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 2, length: 0)
        )
        #expect(result != nil)
        // Each newline is its own paragraph
        #expect(result!.length >= 1)
    }

    @Test("Very long single line")
    func veryLongSingleLine() {
        let text = String(repeating: "x", count: 10_000)
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 5000, length: 1)
        )
        #expect(result != nil)
        #expect(result!.location == 0)
        #expect(result!.length == 10_000)
    }

    @Test("Edit at exact paragraph boundary (newline character)")
    func editAtParagraphBoundary() {
        let text = "AAA\nBBB\nCCC"
        // Edit at the newline between AAA and BBB
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 3, length: 1)
        )
        #expect(result != nil)
        // The newline is part of "AAA\n" paragraph
        #expect(result!.location == 0)
    }

    @Test("Paste spanning multiple paragraphs")
    func pasteMultipleParagraphs() {
        let text = "Before\nLine A\nLine B\nLine C\nAfter"
        // Pasted text covers "Line A\nLine B\nLine C"
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: 7, length: 21)
        )
        #expect(result != nil)
        // Should cover all three middle paragraphs
        #expect(result!.location == 7) // Start of "Line A"
        let end = result!.location + result!.length
        #expect(end >= 28) // End of "Line C\n"
    }

    @Test("Unicode text with multi-byte characters")
    func unicodeText() {
        let text = "Hello 🌍\nWorld 🚀\nEnd"
        let nsString = text as NSString
        // Find where "World" line starts
        let worldStart = nsString.range(of: "World").location
        let result = ASTDirtyRegionTracker.dirtyRange(
            in: text,
            editRange: NSRange(location: worldStart, length: 1)
        )
        #expect(result != nil)
        // Should align to the "World 🚀\n" paragraph
        #expect(result!.location <= worldStart)
    }
}
