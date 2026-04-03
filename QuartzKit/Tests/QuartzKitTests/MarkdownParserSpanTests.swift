import Testing
import Foundation
@testable import QuartzKit

// MARK: - Markdown Parser Tests

/// Verifies MarkdownASTHighlighter produces correct HighlightSpan output
/// for various markdown constructs.

@Suite("Markdown Parser Spans")
struct MarkdownParserTests {

    @Test("Headings produce bold spans")
    func headingBold() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("# Hello World")
        let bold = spans.filter { $0.traits.bold }
        #expect(!bold.isEmpty, "Heading should produce bold spans")
    }

    @Test("Bold text produces bold trait spans")
    func boldTraits() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("Some **bold** text")
        let bold = spans.filter { $0.traits.bold }
        #expect(!bold.isEmpty, "**bold** should produce bold trait spans")
    }

    @Test("Italic text produces italic trait spans")
    func italicTraits() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("Some *italic* text")
        let italic = spans.filter { $0.traits.italic }
        #expect(!italic.isEmpty, "*italic* should produce italic trait spans")
    }

    @Test("Wiki-links produce wikiLinkTitle spans")
    func wikiLinks() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("Link to [[My Note]] here")
        let wiki = spans.filter { $0.wikiLinkTitle != nil }
        #expect(!wiki.isEmpty, "[[My Note]] should produce wiki-link spans")
        #expect(wiki.first?.wikiLinkTitle == "My Note")
    }

    @Test("Tables produce tableRowStyle spans")
    func tableSpans() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("| A | B |\n|---|---|\n| 1 | 2 |")
        let table = spans.filter { $0.tableRowStyle != nil }
        #expect(!table.isEmpty, "Table should produce tableRowStyle spans")
    }

    @Test("Overlay spans for syntax delimiters")
    func overlaySpans() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("Some `code` here")
        let overlays = spans.filter { $0.isOverlay }
        #expect(!overlays.isEmpty, "Code delimiters should produce overlay spans")
    }
}
