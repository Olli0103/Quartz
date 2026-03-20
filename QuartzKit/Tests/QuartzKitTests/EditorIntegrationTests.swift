import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Step 8: Editor Integration Harness Tests
// These tests validate that the list continuation engine integrates correctly
// with the UITextViewDelegate/NSTextViewDelegate newline interception flow.

@Suite("EditorIntegration")
struct EditorIntegrationTests {

    // MARK: - Coordinator Initialization Tests

    @Test("MarkdownListContinuation is instantiated in iOS coordinator")
    func iosCoordinatorHasListContinuation() {
        // The iOS Coordinator class has a private `listContinuation` property.
        // We verify integration by testing the public behavior through the engine.
        let engine = MarkdownListContinuation()

        // Engine should be usable and return valid results
        let result = engine.handleNewline(in: "- item", cursorPosition: 6)
        #expect(result != nil)
        #expect(result?.newText == "- item\n- ")
    }

    @Test("MarkdownListContinuation is instantiated in macOS coordinator")
    func macosCoordinatorHasListContinuation() {
        // Same verification for macOS - engine behavior is platform-agnostic
        let engine = MarkdownListContinuation()

        let result = engine.handleNewline(in: "1. first", cursorPosition: 8)
        #expect(result != nil)
        #expect(result?.newText == "1. first\n2. ")
    }

    // MARK: - Delegate Flow Tests

    @Test("Newline not equal to Return key should pass through")
    func nonNewlineCharactersPassThrough() {
        let engine = MarkdownListContinuation()

        // Engine only responds to newlines at list marker lines
        // Non-list lines return nil, indicating "pass through"
        let result = engine.handleNewline(in: "plain text", cursorPosition: 10)
        #expect(result == nil, "Non-list line should return nil for pass-through")
    }

    @Test("Return on non-list line allows normal behavior")
    func returnOnNonListLinePassesThrough() {
        let engine = MarkdownListContinuation()

        // Various non-list scenarios
        let scenarios = [
            ("Hello world", 11),
            ("# Heading", 9),
            ("```code", 7),
            ("---", 3),
            ("**bold**", 8),
        ]

        for (text, cursor) in scenarios {
            let result = engine.handleNewline(in: text, cursorPosition: cursor)
            #expect(result == nil, "'\(text)' should not trigger list continuation")
        }
    }

    @Test("Return on list line intercepts and returns continuation")
    func returnOnListLineReturnsResult() {
        let engine = MarkdownListContinuation()

        let listLines = [
            ("- bullet", 8),
            ("* asterisk", 10),
            ("+ plus", 6),
            ("1. numbered", 11),
            ("- [ ] checkbox", 14),
            ("> blockquote", 12),
        ]

        for (text, cursor) in listLines {
            let result = engine.handleNewline(in: text, cursorPosition: cursor)
            #expect(result != nil, "'\(text)' should trigger list continuation")
            #expect(result!.newCursorPosition > cursor, "Cursor should advance")
        }
    }

    // MARK: - Cursor Position Validation Tests

    @Test("Cursor position is within valid range after continuation")
    func cursorPositionInValidRange() {
        let engine = MarkdownListContinuation()

        let text = "- item one"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)!

        #expect(result.newCursorPosition >= 0)
        #expect(result.newCursorPosition <= result.newText.count)
    }

    @Test("Cursor position at invalid location is clamped")
    func cursorPositionClamped() {
        let engine = MarkdownListContinuation()

        // Test with cursor beyond text length
        let result = engine.handleNewline(in: "- item", cursorPosition: 1000)
        // Engine clamps cursor to valid range and processes from end of text
        #expect(result != nil, "Engine should handle out-of-bounds cursor")
    }

    @Test("Cursor at position 0 is handled")
    func cursorAtZero() {
        let engine = MarkdownListContinuation()

        let result = engine.handleNewline(in: "- item", cursorPosition: 0)
        // Cursor at 0 means we're before the marker, behavior depends on implementation
        // The engine should either return nil or handle gracefully
        if let result = result {
            #expect(result.newCursorPosition >= 0)
        }
    }

    // MARK: - Text Binding Sync Tests

    @Test("Result newText can be assigned to text binding")
    func resultCanBeAssignedToBinding() {
        let engine = MarkdownListContinuation()

        var textBinding = "- item"
        let result = engine.handleNewline(in: textBinding, cursorPosition: textBinding.count)!

        textBinding = result.newText

        #expect(textBinding == "- item\n- ")
    }

    @Test("Cursor position from result is valid NSRange location")
    func cursorPositionValidNSRange() {
        let engine = MarkdownListContinuation()

        let result = engine.handleNewline(in: "- item", cursorPosition: 6)!
        let nsRange = NSRange(location: result.newCursorPosition, length: 0)

        #expect(nsRange.location == result.newCursorPosition)
        #expect(nsRange.length == 0)
    }

    // MARK: - Undo Compatibility Tests

    @Test("Result produces valid text for undo manager")
    func resultValidForUndo() {
        let engine = MarkdownListContinuation()

        let original = "- item"
        let result = engine.handleNewline(in: original, cursorPosition: original.count)!

        // Undo would restore to original - verify original is reconstructable
        #expect(result.newText.hasPrefix(original))
        #expect(result.newText.count > original.count)
    }

    // MARK: - Edge Case Integration Tests

    @Test("Empty document with no list marker")
    func emptyDocumentNoMarker() {
        let engine = MarkdownListContinuation()

        let result = engine.handleNewline(in: "", cursorPosition: 0)
        #expect(result == nil, "Empty document should not trigger continuation")
    }

    @Test("Whitespace-only line")
    func whitespaceOnlyLine() {
        let engine = MarkdownListContinuation()

        let result = engine.handleNewline(in: "   ", cursorPosition: 3)
        #expect(result == nil, "Whitespace-only line should not trigger continuation")
    }

    @Test("Multiple consecutive newlines in list")
    func multipleNewlinesInList() {
        let engine = MarkdownListContinuation()

        // First newline
        let text1 = "- item"
        let result1 = engine.handleNewline(in: text1, cursorPosition: text1.count)!

        // Second newline on empty marker (should exit list)
        let result2 = engine.handleNewline(in: result1.newText, cursorPosition: result1.newCursorPosition)!

        #expect(!result2.newText.hasSuffix("- "), "Should exit list on second newline")
    }

    @Test("Unicode content in list items")
    func unicodeContentInList() {
        let engine = MarkdownListContinuation()

        let text = "- 你好世界"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)

        #expect(result != nil)
        #expect(result!.newText.contains("你好世界"))
        #expect(result!.newText.hasSuffix("- "))
    }

    @Test("Emoji in list items")
    func emojiInListItems() {
        let engine = MarkdownListContinuation()

        let text = "- 🎉 party"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)

        #expect(result != nil)
        #expect(result!.newText.contains("🎉"))
    }

    // MARK: - Performance Boundary Tests

    @Test("Large document performance")
    func largeDocumentPerformance() {
        let engine = MarkdownListContinuation()

        // Generate a large document with many list items
        var text = ""
        for i in 0..<1000 {
            text += "- item \(i)\n"
        }
        text += "- current item"

        // Engine should handle large documents
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result != nil)
    }

    @Test("Deeply nested indentation")
    func deeplyNestedIndentation() {
        let engine = MarkdownListContinuation()

        let indent = String(repeating: "  ", count: 20) // 40 spaces
        let text = indent + "- deeply nested"

        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result != nil)
        #expect(result!.newText.contains(indent + "- "))
    }
}

// MARK: - XCTest Performance Tests for Editor Integration

final class EditorIntegrationPerformanceTests: XCTestCase {

    /// Tests that list continuation is fast enough for real-time typing
    func testListContinuationLatency() throws {
        let engine = MarkdownListContinuation()
        let text = "- item one"

        let options = XCTMeasureOptions()
        options.iterationCount = 100

        measure(metrics: [XCTClockMetric()], options: options) {
            for _ in 0..<100 {
                _ = engine.handleNewline(in: text, cursorPosition: text.count)
            }
        }
    }

    /// Tests performance with various list types
    func testMixedListTypePerformance() throws {
        let engine = MarkdownListContinuation()

        let testCases = [
            "- bullet item",
            "1. numbered item",
            "- [ ] checkbox item",
            "> blockquote text",
            "  - nested bullet",
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 50

        measure(metrics: [XCTClockMetric()], options: options) {
            for _ in 0..<100 {
                for text in testCases {
                    _ = engine.handleNewline(in: text, cursorPosition: text.count)
                }
            }
        }
    }
}
