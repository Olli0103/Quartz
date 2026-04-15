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

    @Test("Multiline bold delimiters keep global ranges")
    func multilineBoldDelimiterRanges() async {
        let text = "# Welcome to Quartz Notes\n\n**How are you?**"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)
        let nsText = text as NSString
        let fullRange = nsText.range(of: "**How are you?**")
        let openRange = NSRange(location: fullRange.location, length: 2)
        let closeRange = NSRange(location: NSMaxRange(fullRange) - 2, length: 2)
        let headingVisiblePrefix = NSRange(location: 2, length: 2)

        let boldOverlays = spans.filter { $0.isOverlay && $0.traits.bold }
        #expect(boldOverlays.contains { NSEqualRanges($0.range, openRange) })
        #expect(boldOverlays.contains { NSEqualRanges($0.range, closeRange) })
        #expect(!boldOverlays.contains { NSIntersectionRange($0.range, headingVisiblePrefix).length > 0 })
    }

    @Test("Multiline italic delimiters keep global ranges")
    func multilineItalicDelimiterRanges() async {
        let text = "# Welcome to Quartz Notes\n\n*How are you?*"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)
        let nsText = text as NSString
        let fullRange = nsText.range(of: "*How are you?*")
        let openRange = NSRange(location: fullRange.location, length: 1)
        let closeRange = NSRange(location: NSMaxRange(fullRange) - 1, length: 1)
        let headingVisiblePrefix = NSRange(location: 2, length: 2)

        let italicOverlays = spans.filter { $0.isOverlay && $0.traits.italic }
        #expect(italicOverlays.contains { NSEqualRanges($0.range, openRange) })
        #expect(italicOverlays.contains { NSEqualRanges($0.range, closeRange) })
        #expect(!italicOverlays.contains { NSIntersectionRange($0.range, headingVisiblePrefix).length > 0 })
    }

    @Test("Multiline markdown links keep global ranges")
    func multilineMarkdownLinkRanges() async {
        let text = "# Welcome to Quartz Notes\n\n[How are you?](url)"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)
        let nsText = text as NSString
        let fullRange = nsText.range(of: "[How are you?](url)")
        let labelRange = nsText.range(of: "How are you?")
        let destinationRange = nsText.range(of: "url")
        let headingVisiblePrefix = NSRange(location: 2, length: 2)

        let primaryLinkSpan = spans.first {
            !$0.isOverlay && $0.color != nil && NSEqualRanges($0.range, labelRange)
        }
        let linkOverlays = spans.filter { $0.isOverlay }

        #expect(primaryLinkSpan != nil)
        #expect(linkOverlays.contains { NSEqualRanges($0.range, destinationRange) })
        #expect(linkOverlays.contains { NSIntersectionRange($0.range, fullRange).length > 0 })
        #expect(!linkOverlays.contains { NSIntersectionRange($0.range, headingVisiblePrefix).length > 0 })
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
