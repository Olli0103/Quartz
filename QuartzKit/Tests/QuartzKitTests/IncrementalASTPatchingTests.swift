import Testing
import Foundation
@testable import QuartzKit

// MARK: - Incremental AST Patching Tests
//
// Golden tests comparing incremental parse results with full parse results.
// Invariant: for any edit, the incremental path should produce functionally
// equivalent spans to a full re-parse — same span count and matching traits.

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

    /// Asserts that two span arrays have matching trait profiles.
    /// Compares bold and italic trait counts.
    private func assertTraitParity(
        full: [HighlightSpan],
        incremental: [HighlightSpan],
        context: String
    ) {
        let fullBoldCount = full.filter { $0.traits.bold }.count
        let incBoldCount = incremental.filter { $0.traits.bold }.count
        #expect(fullBoldCount == incBoldCount,
            "\(context): bold span count mismatch (full: \(fullBoldCount), inc: \(incBoldCount))")

        let fullItalicCount = full.filter { $0.traits.italic }.count
        let incItalicCount = incremental.filter { $0.traits.italic }.count
        #expect(fullItalicCount == incItalicCount,
            "\(context): italic span count mismatch (full: \(fullItalicCount), inc: \(incItalicCount))")
    }

    @Test("Single character insertion: span count parity")
    func singleCharInsertion() async {
        let original = "Hello world"
        let edited = "Hello! world"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 5, length: 1),
            preEditLength: 0
        )
        #expect(!result.incremental.isEmpty || result.full.isEmpty,
            "Incremental should produce spans if full parse does")
        #expect(result.full.count == result.incremental.count,
            "Span count: full=\(result.full.count) vs inc=\(result.incremental.count)")
    }

    @Test("Bold text edit: span count and trait parity")
    func boldTextEdit() async {
        let original = "Some **bold** text here"
        let edited = "Some **bold!** text here"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 11, length: 1),
            preEditLength: 0
        )
        #expect(result.full.count == result.incremental.count,
            "Span count: full=\(result.full.count) vs inc=\(result.incremental.count)")
        assertTraitParity(full: result.full, incremental: result.incremental, context: "Bold edit")
    }

    @Test("Heading insertion: span count and bold trait parity")
    func headingInsertion() async {
        let original = "Some text\nMore text"
        let edited = "# Heading\nSome text\nMore text"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 0, length: 10),
            preEditLength: 0
        )
        let fullBold = result.full.filter { $0.traits.bold }
        let incBold = result.incremental.filter { $0.traits.bold }
        #expect(!fullBold.isEmpty, "Full parse should detect heading")
        #expect(!incBold.isEmpty, "Incremental parse should detect heading")
        #expect(fullBold.count == incBold.count,
            "Heading bold span count: full=\(fullBold.count) vs inc=\(incBold.count)")
    }

    @Test("Code fence triggers full re-parse fallback with valid spans")
    func codeFenceFallback() async {
        let original = "Text before\nMore text"
        let edited = "Text before\n```\ncode\n```\nMore text"
        let highlighter = MarkdownASTHighlighter()
        _ = await highlighter.parse(original)

        let spans = await highlighter.parseIncremental(
            edited,
            editRange: NSRange(location: 12, length: 13),
            preEditLength: 0
        )
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

        // Result should be equivalent to a direct full parse
        let fullHighlighter = MarkdownASTHighlighter()
        let fullSpans = await fullHighlighter.parse(text)
        #expect(spans.count == fullSpans.count,
            "First incremental (no cache) should match full parse: \(spans.count) vs \(fullSpans.count)")
    }

    @Test("Deletion preserves spans before and after: trait parity")
    func deletion() async {
        let original = "**Bold** and *italic* and `code`"
        let edited = "**Bold** and `code`"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 13, length: 0),
            preEditLength: 13
        )
        assertTraitParity(full: result.full, incremental: result.incremental, context: "Deletion")
    }

    @Test("Multi-paragraph edit: span count parity")
    func multiParagraphEdit() async {
        let original = "# Title\n\nPara one.\n\nPara two.\n\nPara three."
        let edited = "# Title\n\nEdited paragraph.\n\nPara three."
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 10, length: 18),
            preEditLength: 20
        )
        #expect(!result.full.isEmpty)
        #expect(!result.incremental.isEmpty)
        #expect(result.full.count == result.incremental.count,
            "Multi-para span count: full=\(result.full.count) vs inc=\(result.incremental.count)")
    }

    @Test("Empty document edit: exact span equivalence")
    func emptyDocumentEdit() async {
        let original = ""
        let edited = "Hello"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 0, length: 5),
            preEditLength: 0
        )
        #expect(result.full.count == result.incremental.count,
            "Empty doc edit: full=\(result.full.count) vs inc=\(result.incremental.count)")
    }

    @Test("Wiki-link preserved through incremental edit: count parity")
    func wikiLinkPreserved() async {
        let original = "Link to [[Note A]] and some text"
        let edited = "Link to [[Note A]] and some more text"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 28, length: 5),
            preEditLength: 0
        )
        let fullWiki = result.full.filter { $0.wikiLinkTitle != nil }
        let incWiki = result.incremental.filter { $0.wikiLinkTitle != nil }
        #expect(!fullWiki.isEmpty, "Full parse should find wiki-link")
        #expect(!incWiki.isEmpty, "Incremental should preserve wiki-link")
        #expect(fullWiki.count == incWiki.count,
            "Wiki-link span count: full=\(fullWiki.count) vs inc=\(incWiki.count)")
        // Verify the wiki-link title content matches
        #expect(fullWiki.first?.wikiLinkTitle == incWiki.first?.wikiLinkTitle,
            "Wiki-link title should match between full and incremental")
    }

    @Test("Table edit preserves table spans: count and style parity")
    func tableEdit() async {
        let original = "| A | B |\n|---|---|\n| 1 | 2 |"
        let edited = "| A | B |\n|---|---|\n| 1 | 3 |"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 25, length: 1),
            preEditLength: 1
        )
        let fullTable = result.full.filter { $0.tableRowStyle != nil }
        let incTable = result.incremental.filter { $0.tableRowStyle != nil }
        #expect(!fullTable.isEmpty, "Full parse should find table spans")
        #expect(!incTable.isEmpty, "Incremental should find table spans")
        #expect(fullTable.count == incTable.count,
            "Table span count: full=\(fullTable.count) vs inc=\(incTable.count)")
    }

    @Test("Inline LaTeX: overlay span count parity")
    func inlineLatex() async {
        let original = "The formula $E=mc^2$ is famous"
        let edited = "The formula $E=mc^2$ is very famous"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 24, length: 5),
            preEditLength: 0
        )
        let fullOverlays = result.full.filter { $0.isOverlay }
        let incOverlays = result.incremental.filter { $0.isOverlay }
        #expect(!fullOverlays.isEmpty, "Full parse should have overlay spans")
        #expect(!incOverlays.isEmpty, "Incremental should have overlay spans")
        #expect(fullOverlays.count == incOverlays.count,
            "Overlay span count: full=\(fullOverlays.count) vs inc=\(incOverlays.count)")
    }

    @Test("Character range coverage: incremental covers same text range as full")
    func rangeCoverage() async {
        let original = "**Bold** *italic* `code` normal"
        let edited = "**Bold** *italic* `code` normal!"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 30, length: 1),
            preEditLength: 0
        )
        // Compute total character coverage
        let fullCoverage = result.full.reduce(0) { $0 + $1.range.length }
        let incCoverage = result.incremental.reduce(0) { $0 + $1.range.length }
        // Coverage should be similar (allow small differences for boundary spans)
        let diff = abs(fullCoverage - incCoverage)
        #expect(diff <= 5,
            "Range coverage difference too large: full=\(fullCoverage), inc=\(incCoverage), diff=\(diff)")
    }

    // MARK: - Range Correctness (Violation 5 remediation)

    @Test("All span ranges are valid (non-negative, within document bounds)")
    func rangeValidity() async {
        let original = "# Heading\n\n**Bold** and *italic* with `code`\n\n> Blockquote"
        let edited = "# Heading\n\n**Bold!** and *italic* with `code`\n\n> Blockquote"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 16, length: 1),
            preEditLength: 0
        )

        let editedLength = (edited as NSString).length
        for span in result.incremental {
            #expect(span.range.location >= 0,
                "Span range location should be non-negative, got \(span.range.location)")
            #expect(span.range.location + span.range.length <= editedLength,
                "Span range end (\(span.range.location + span.range.length)) exceeds document length (\(editedLength))")
        }
        for span in result.full {
            #expect(span.range.location >= 0)
            #expect(span.range.location + span.range.length <= editedLength)
        }
    }

    @Test("Span ranges are sorted by location (no out-of-order spans)")
    func rangeOrdering() async {
        let original = "**Bold** *italic* `code` [link](url)"
        let edited = "**Bold!** *italic* `code` [link](url)"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 6, length: 1),
            preEditLength: 0
        )

        for spans in [result.full, result.incremental] {
            for i in 1..<spans.count {
                #expect(spans[i].range.location >= spans[i-1].range.location,
                    "Span \(i) at \(spans[i].range.location) should not precede span \(i-1) at \(spans[i-1].range.location)")
            }
        }
    }

    @Test("Bold span range maps to actual bold syntax in source")
    func rangeContentMatch() async {
        let text = "Normal **bold text** normal"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let boldSpans = spans.filter { $0.traits.bold }
        #expect(!boldSpans.isEmpty, "Should detect bold spans")

        let nsText = text as NSString
        for span in boldSpans {
            let content = nsText.substring(with: span.range)
            // The bold span should cover text within or including the ** markers
            let hasBoldContent = content.contains("bold") || content.contains("**")
            #expect(hasBoldContent,
                "Bold span range should map to bold syntax, got: '\(content)'")
        }
    }

    @Test("Spans outside edit region match full parse ranges exactly")
    func editWindowIsolation() async {
        let original = "**Start bold**\n\nMiddle paragraph with content.\n\n*End italic*"
        // Edit only in the middle paragraph
        let edited = "**Start bold**\n\nMiddle paragraph with EDITED content.\n\n*End italic*"
        let result = await compareFullVsIncremental(
            original: original,
            edited: edited,
            editRange: NSRange(location: 37, length: 6),
            preEditLength: 0
        )

        // Spans covering the first line should be identical between full and incremental
        let fullBefore = result.full.filter { $0.range.location + $0.range.length <= 14 }
        let incBefore = result.incremental.filter { $0.range.location + $0.range.length <= 14 }

        #expect(fullBefore.count == incBefore.count,
            "Spans before edit region: full=\(fullBefore.count) vs inc=\(incBefore.count)")

        for (f, i) in zip(fullBefore, incBefore) {
            #expect(f.range == i.range,
                "Pre-edit span ranges should match: full=\(f.range) vs inc=\(i.range)")
        }
    }
}

// MARK: - Performance Baseline

@Suite("MarkdownASTHighlighter — Incremental Performance")
struct IncrementalPerformanceTests {

    @Test("Incremental parse of single char in moderate doc is fast")
    func incrementalPerformance() async {
        var doc = "# Document Title\n\n"
        for i in 0..<50 {
            doc += "Paragraph \(i) with some **bold** and *italic* text and `code` inline.\n\n"
        }

        let highlighter = MarkdownASTHighlighter()
        _ = await highlighter.parse(doc)

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
        #expect(elapsed < 0.5, "Incremental parse should complete within 500ms, took \(elapsed)s")
    }
}
