import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import QuartzKit

// MARK: - Markdown Parser Tests

/// Verifies MarkdownASTHighlighter produces correct HighlightSpan output
/// for various markdown constructs.

@Suite("Markdown Parser Spans")
struct MarkdownParserTests {

    #if canImport(UIKit)
    private func writeTestImage(to url: URL) throws {
        UIGraphicsBeginImageContext(CGSize(width: 8, height: 8))
        UIColor.red.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(UIGraphicsGetImageFromCurrentImageContext())
        UIGraphicsEndImageContext()
        let data = try #require(image.pngData())
        try data.write(to: url)
    }
    #elseif canImport(AppKit)
    private func writeTestImage(to url: URL) throws {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 8, height: 8))
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: url)
    }
    #endif

    private func conceals(_ span: HighlightSpan, revealRange: NSRange) -> Bool {
        guard span.isOverlay else { return false }
        if case let .concealWhenInactive(actualRange) = span.overlayVisibilityBehavior {
            return NSEqualRanges(actualRange, revealRange)
        }
        return false
    }

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

    @Test("Bold text uses a single authoritative semantic span")
    func boldSemanticAuthority() async {
        let text = "Some **bold** text"
        let nsText = text as NSString
        let fullRange = nsText.range(of: "**bold**")
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let semantic = spans.filter { !$0.isOverlay && $0.semanticRole == .bold }
        let overlays = spans.filter { conceals($0, revealRange: fullRange) }

        #expect(semantic.count == 1)
        #expect(semantic.first?.range == fullRange)
        #expect(overlays.count == 2)
    }

    @Test("Italic text produces italic trait spans")
    func italicTraits() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("Some *italic* text")
        let italic = spans.filter { $0.traits.italic }
        #expect(!italic.isEmpty, "*italic* should produce italic trait spans")
    }

    @Test("Markdown links use a single authoritative span set")
    func markdownLinkSemanticAuthority() async {
        let text = "Go to [Link](url)"
        let nsText = text as NSString
        let fullRange = nsText.range(of: "[Link](url)")
        let labelRange = nsText.range(of: "Link")
        let destinationRange = nsText.range(of: "url")
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let labelSpans = spans.filter { !$0.isOverlay && $0.range == labelRange }
        let overlays = spans.filter { conceals($0, revealRange: fullRange) }

        #expect(labelSpans.count == 1)
        #expect(overlays.contains { $0.range == destinationRange })
        #expect(overlays.count == 4)
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

    @Test("Inline code uses a single authoritative semantic span")
    func inlineCodeSemanticAuthority() async {
        let text = "Use `code` here"
        let nsText = text as NSString
        let fullRange = nsText.range(of: "`code`")
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let semantic = spans.filter { !$0.isOverlay && $0.semanticRole == .inlineCode }
        let overlays = spans.filter { conceals($0, revealRange: fullRange) }

        #expect(semantic.count == 1)
        #expect(semantic.first?.range == fullRange)
        #expect(overlays.count == 2)
    }

    @Test("Fenced code uses a single authoritative semantic span")
    func fencedCodeSemanticAuthority() async {
        let text = """
        ```swift
        let x = 1
        ```
        """
        let nsText = text as NSString
        let fullRange = nsText.range(of: text)
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let semantic = spans.filter { $0.semanticRole == .codeBlock }
        #expect(semantic.count == 1)
        #expect(semantic.first?.range == fullRange)
    }

    @Test("Inline math uses a single authoritative semantic span set")
    func inlineMathSemanticAuthority() async {
        let text = "Formula $x^2$ end"
        let nsText = text as NSString
        let fullRange = nsText.range(of: "$x^2$")
        let contentRange = nsText.range(of: "x^2")
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let contentSpans = spans.filter {
            !$0.isOverlay &&
            $0.backgroundColor != nil &&
            $0.range == contentRange
        }
        let overlays = spans.filter { conceals($0, revealRange: fullRange) }

        #expect(contentSpans.count == 1)
        #expect(overlays.count == 2)
    }

    @Test("Tables produce tableRowStyle spans")
    func tableSpans() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("| A | B |\n|---|---|\n| 1 | 2 |")
        let table = spans.filter { $0.tableRowStyle != nil }
        #expect(!table.isEmpty, "Table should produce tableRowStyle spans")
    }

    @Test("Local images resolve to attachment spans")
    func localImageAttachmentSpans() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let noteURL = tempDir.appendingPathComponent("note.md")
        let imageURL = tempDir.appendingPathComponent("inline.png")
        try writeTestImage(to: imageURL)

        let highlighter = MarkdownASTHighlighter()
        await highlighter.updateSettings(
            fontFamily: .system,
            lineSpacing: 1.5,
            vaultRootURL: tempDir,
            noteURL: noteURL
        )

        let spans = await highlighter.parse("![Alt](inline.png)")
        let attachmentSpans = spans.filter { $0.attachment != nil }

        #expect(attachmentSpans.count == 1)
        #expect(attachmentSpans.first?.range.location == 0)
    }

    @Test("Overlay spans for syntax delimiters")
    func overlaySpans() async {
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse("Some `code` here")
        let overlays = spans.filter { $0.isOverlay }
        #expect(!overlays.isEmpty, "Code delimiters should produce overlay spans")
    }
}
