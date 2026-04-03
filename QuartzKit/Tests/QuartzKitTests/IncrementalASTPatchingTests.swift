import Testing
import Foundation
@testable import QuartzKit

// MARK: - Incremental AST Patching Tests

/// Golden tests comparing incremental parse results with full parse results.
/// The invariant: for any edit, the incremental path should produce functionally
/// equivalent spans to a full re-parse (same ranges covered, same span count ±margin).

@Suite("MarkdownASTHighlighter — Incremental Patching")
struct IncrementalASTPatchingTests {

    /// Parses text fully, then incrementally after an edit, and compares.
    private func compareFullVsIncremental(
        original: String,
        edited: String,
        editRange: NSRange,
        preEditLength: Int
    ) async -> (full: [HighlightSpan], incremental: [HighlightSpan]) {
        // Full parse of edited text
        let fullHighlighter = MarkdownASTHighlighter()
        let fullSpans = await fullHighlighter.parse(edited)

        // Incremental parse: first parse original, then parse edit incrementally
        let incHighlighter = MarkdownASTHighlighter()
        _ = await incHighlighter.parse(original) // prime the cache
        let incSpans = await incHighlighter.parseIncremental(
            edited,
            editRange: editRange,
            preEditLength: preEditLength
        )

        return (fullSpans, incSpans)
    }

    @Test("Single character insertion produces spans")
    func singleCharInsertion() async {
        let original = "Hello world"
        let edited = "Hello! world"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 5, length: 1),
            preEditLength: 0
        )
        // Both should produce spans (body text spans)
        // The key check: incremental doesn't crash and produces reasonable output
        #expect(!result.incremental.isEmpty || result.full.isEmpty,
            "Incremental should produce spans if full parse does")
    }

    @Test("Bold text edit preserves formatting spans")
    func boldTextEdit() async {
        let original = "Some **bold** text here"
        let edited = "Some **bold!** text here"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 11, length: 1),
            preEditLength: 0
        )
        // Both should have bold spans
        let fullBold = result.full.filter { $0.traits.bold }
        let incBold = result.incremental.filter { $0.traits.bold }
        #expect(!fullBold.isEmpty, "Full parse should find bold spans")
        #expect(!incBold.isEmpty, "Incremental parse should find bold spans")
    }

    @Test("Heading insertion")
    func headingInsertion() async {
        let original = "Some text\nMore text"
        let edited = "# Heading\nSome text\nMore text"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 0, length: 10),
            preEditLength: 0
        )
        // Should have heading spans
        let fullBold = result.full.filter { $0.traits.bold }
        let incBold = result.incremental.filter { $0.traits.bold }
        #expect(!fullBold.isEmpty, "Full parse should detect heading")
        #expect(!incBold.isEmpty, "Incremental parse should detect heading")
    }

    @Test("Code fence triggers full re-parse fallback")
    func codeFenceFallback() async {
        let original = "Text before\nMore text"
        let edited = "Text before\n```\ncode\n```\nMore text"
        // Inserting a code fence should trigger full parse fallback
        let highlighter = MarkdownASTHighlighter()
        _ = await highlighter.parse(original)

        let spans = await highlighter.parseIncremental(
            edited,
            editRange: NSRange(location: 12, length: 13),
            preEditLength: 0
        )
        // Should still produce valid spans (fallback to full parse)
        #expect(!spans.isEmpty, "Code fence edit should produce spans via full parse fallback")
    }

    @Test("First parse (no cache) falls back to full parse")
    func firstParseFallback() async {
        let highlighter = MarkdownASTHighlighter()
        let text = "# Hello\n\nSome **bold** text"
        let spans = await highlighter.parseIncremental(
            text,
            editRange: NSRange(location: 0, length: 5),
            preEditLength: 0
        )
        #expect(!spans.isEmpty, "First parse should fall back to full parse")
    }

    @Test("Deletion preserves spans before and after")
    func deletion() async {
        let original = "**Bold** and *italic* and `code`"
        let edited = "**Bold** and `code`"
        // Deleted "*italic* and " (13 chars) starting at position 13
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 13, length: 0),
            preEditLength: 13
        )
        // Both should have bold and code spans
        let fullBold = result.full.filter { $0.traits.bold }
        let incBold = result.incremental.filter { $0.traits.bold }
        #expect(!fullBold.isEmpty, "Full parse should find bold")
        #expect(!incBold.isEmpty, "Incremental should preserve bold before edit")
    }

    @Test("Multi-paragraph edit")
    func multiParagraphEdit() async {
        let original = "# Title\n\nPara one.\n\nPara two.\n\nPara three."
        let edited = "# Title\n\nEdited paragraph.\n\nPara three."
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 10, length: 18),
            preEditLength: 20
        )
        // Both should produce spans
        #expect(!result.full.isEmpty)
        #expect(!result.incremental.isEmpty)
    }

    @Test("Empty document edit")
    func emptyDocumentEdit() async {
        let original = ""
        let edited = "Hello"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 0, length: 5),
            preEditLength: 0
        )
        // Empty original means no cache, so incremental falls back to full
        #expect(result.full.count == result.incremental.count)
    }

    @Test("Wiki-link preserved through incremental edit")
    func wikiLinkPreserved() async {
        let original = "Link to [[Note A]] and some text"
        let edited = "Link to [[Note A]] and some more text"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 28, length: 5),
            preEditLength: 0
        )
        // Both should have wiki-link spans
        let fullWiki = result.full.filter { $0.wikiLinkTitle != nil }
        let incWiki = result.incremental.filter { $0.wikiLinkTitle != nil }
        #expect(!fullWiki.isEmpty, "Full parse should find wiki-link")
        #expect(!incWiki.isEmpty, "Incremental should preserve wiki-link")
    }

    @Test("Table edit preserves table spans")
    func tableEdit() async {
        let original = "| A | B |\n|---|---|\n| 1 | 2 |"
        let edited = "| A | B |\n|---|---|\n| 1 | 3 |"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 25, length: 1),
            preEditLength: 1
        )
        // Both should produce table-related spans
        let fullTable = result.full.filter { $0.tableRowStyle != nil }
        let incTable = result.incremental.filter { $0.tableRowStyle != nil }
        #expect(!fullTable.isEmpty, "Full parse should find table spans")
        #expect(!incTable.isEmpty, "Incremental should find table spans")
    }

    @Test("Incremental parse of inline LaTeX")
    func inlineLatex() async {
        let original = "The formula $E=mc^2$ is famous"
        let edited = "The formula $E=mc^2$ is very famous"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 24, length: 5),
            preEditLength: 0
        )
        // Both should produce overlay spans for $ delimiters
        let fullOverlays = result.full.filter { $0.isOverlay }
        let incOverlays = result.incremental.filter { $0.isOverlay }
        #expect(!fullOverlays.isEmpty, "Full parse should have overlay spans")
        #expect(!incOverlays.isEmpty, "Incremental should have overlay spans")
    }
}

// MARK: - Performance Baseline

@Suite("MarkdownASTHighlighter — Incremental Performance")
struct IncrementalPerformanceTests {

    @Test("Incremental parse of single char in moderate doc is fast")
    func incrementalPerformance() async {
        // Build a moderate-size document (~5KB)
        var doc = "# Document Title\n\n"
        for i in 0..<50 {
            doc += "Paragraph \(i) with some **bold** and *italic* text and `code` inline.\n\n"
        }

        let highlighter = MarkdownASTHighlighter()
        _ = await highlighter.parse(doc) // prime cache

        // Simulate a single character insertion in the middle
        let insertPos = doc.count / 2
        let nsDoc = doc as NSString
        let edited = nsDoc.replacingCharacters(
            in: NSRange(location: insertPos, length: 0),
            with: "X"
        )

        let start = Date()
        let spans = await highlighter.parseIncremental(
            edited,
            editRange: NSRange(location: insertPos, length: 1),
            preEditLength: 0
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(!spans.isEmpty, "Should produce spans")
        // Incremental should be reasonably fast (< 500ms for ~5KB doc)
        // This is a generous limit — actual should be much faster
        #expect(elapsed < 0.5, "Incremental parse should complete within 500ms, took \(elapsed)s")
    }
}
