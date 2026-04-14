import XCTest
@testable import QuartzKit

final class EditorSemanticDocumentTests: XCTestCase {
    func testSemanticDocumentBuildsHeadingBlankAndParagraphBlocks() {
        let markdown = """
        # Welcome

        Body paragraph
        """

        let document = EditorSemanticDocument.build(markdown: markdown, spans: [])

        XCTAssertEqual(document.blocks.count, 3)
        XCTAssertEqual(document.blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(document.blocks[1].kind, .blank)
        XCTAssertEqual(document.blocks[2].kind, .paragraph)
        XCTAssertEqual(document.typingContext(at: 2), .heading(level: 1))
        XCTAssertTrue(document.isBlankBlock(at: document.blocks[1].range.location))
    }

    func testHeadingBlockIDSurvivesEditsOutsideTheBlock() throws {
        let base = """
        Intro

        ## Stable Heading
        Body
        """
        let edited = """
        New intro line
        Intro

        ## Stable Heading
        Body
        """

        let baseDocument = EditorSemanticDocument.build(markdown: base, spans: [])
        let editedDocument = EditorSemanticDocument.build(markdown: edited, spans: [])

        let baseHeading = try XCTUnwrap(baseDocument.blocks.first(where: {
            if case .heading(level: 2) = $0.kind { return true }
            return false
        }))
        let editedHeading = try XCTUnwrap(editedDocument.blocks.first(where: {
            if case .heading(level: 2) = $0.kind { return true }
            return false
        }))

        XCTAssertEqual(baseHeading.id, editedHeading.id)
    }

    func testRevealedInlineTokenIDsOnlyChangeWhenSelectionEntersSemanticToken() {
        let markdown = "Alpha **bold** and `code` suffix"
        let boldReveal = NSRange(location: 6, length: 8)
        let codeReveal = NSRange(location: 19, length: 6)
        let spans = [
            makeOverlaySpan(range: NSRange(location: 6, length: 2), revealRange: boldReveal),
            makeOverlaySpan(range: NSRange(location: 12, length: 2), revealRange: boldReveal),
            makeOverlaySpan(range: NSRange(location: 19, length: 1), revealRange: codeReveal),
            makeOverlaySpan(range: NSRange(location: 24, length: 1), revealRange: codeReveal)
        ]

        let document = EditorSemanticDocument.build(markdown: markdown, spans: spans)

        XCTAssertEqual(document.revealedInlineTokenIDs(for: NSRange(location: 2, length: 0)), [])
        XCTAssertEqual(document.revealedInlineTokenIDs(for: NSRange(location: 8, length: 0)).count, 2)
        XCTAssertEqual(document.revealedInlineTokenIDs(for: NSRange(location: 22, length: 0)).count, 2)
    }

    func testRenderPlanSeparatesInlineBlockOverlayAndAttachmentSpans() {
        let attachment = NSTextAttachment()
        let spans = [
            HighlightSpan(
                range: NSRange(location: 0, length: 5),
                font: EditorFontFactory.makeFont(family: .system, size: 14),
                color: nil,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false
            ),
            HighlightSpan(
                range: NSRange(location: 0, length: 5),
                font: EditorFontFactory.makeFont(family: .system, size: 14),
                color: nil,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                paragraphStyle: NSParagraphStyle.default,
                tableRowStyle: .header
            ),
            makeOverlaySpan(range: NSRange(location: 0, length: 2), revealRange: NSRange(location: 0, length: 5)),
            HighlightSpan(
                range: NSRange(location: 0, length: 1),
                font: EditorFontFactory.makeFont(family: .system, size: 14),
                color: nil,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                attachment: attachment
            )
        ]

        let plan = EditorRenderPlan(spans: spans)

        XCTAssertEqual(plan.primaryTextSpans.count, 3)
        XCTAssertEqual(plan.blockStylingSpans.count, 1)
        XCTAssertEqual(plan.inlineStylingSpans.count, 2)
        XCTAssertEqual(plan.overlaySpans.count, 1)
        XCTAssertEqual(plan.concealmentStylingSpans.count, 1)
        XCTAssertEqual(plan.attachmentSpans.count, 1)
    }

    func testRenderPlanPrimarySegmentsRespectSemanticBlockBoundaries() {
        let markdown = "## Heading\n\nParagraph"
        let document = EditorSemanticDocument.build(markdown: markdown, spans: [])
        let headingFont = EditorFontFactory.makeFont(family: .system, size: 20)
        let spans = [
            HighlightSpan(
                range: NSRange(location: 0, length: 10),
                font: headingFont,
                color: nil,
                traits: FontTraits(bold: true, italic: false),
                backgroundColor: nil,
                strikethrough: false
            )
        ]
        let plan = EditorRenderPlan(spans: spans)
        let segments = plan.primarySegments(
            for: document,
            defaultFont: EditorFontFactory.makeFont(family: .system, size: 14),
            defaultColor: platformLabelColor()
        )

        XCTAssertEqual(segments.map(\.range), [
            NSRange(location: 0, length: 10),
            NSRange(location: 10, length: 1),
            NSRange(location: 11, length: 1),
            NSRange(location: 12, length: 9)
        ])
    }

    func testRenderPlanPrimarySegmentsPreserveTableRowStyleFromSemanticBlock() {
        let markdown = "| A | B |\n"
        let tableRange = NSRange(location: 0, length: 9)
        let tableSpan = HighlightSpan(
            range: tableRange,
            font: EditorFontFactory.makeFont(family: .system, size: 14),
            color: nil,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: nil,
            strikethrough: false,
            paragraphStyle: NSParagraphStyle.default,
            tableRowStyle: .header
        )
        let document = EditorSemanticDocument.build(markdown: markdown, spans: [tableSpan])
        let plan = EditorRenderPlan(spans: [tableSpan])
        let segments = plan.primarySegments(
            for: document,
            defaultFont: EditorFontFactory.makeFont(family: .system, size: 14),
            defaultColor: platformLabelColor()
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].attributes[.quartzTableRowStyle] as? Int, QuartzTableRowStyle.header.rawValue)
    }

    func testSemanticDocumentBuildsInlineFormatsFromSemanticRoles() {
        let markdown = "Alpha **bold** `code` ~~gone~~"
        let spans = [
            makeSemanticSpan(range: NSRange(location: 6, length: 8), role: .bold),
            makeSemanticSpan(range: NSRange(location: 15, length: 6), role: .inlineCode),
            makeSemanticSpan(range: NSRange(location: 22, length: 8), role: .strikethrough),
            makeSemanticSpan(range: NSRange(location: 0, length: 5), role: .blockquote)
        ]

        let document = EditorSemanticDocument.build(markdown: markdown, spans: spans)

        XCTAssertEqual(document.inlineFormats.map(\.kind), [.bold, .inlineCode, .strikethrough])
        XCTAssertEqual(document.inlineFormatKinds(at: 9), Set([.bold]))
        XCTAssertEqual(document.inlineFormatKinds(at: 17), Set([.inlineCode]))
        XCTAssertEqual(document.inlineFormatKinds(at: 25), Set([.strikethrough]))
    }

    func testFormattingStateUsesSemanticInlineFormatsAndHeadingContext() {
        let markdown = "# **Bold** and `code`"
        let spans = [
            makeSemanticSpan(range: NSRange(location: 0, length: 21), role: .heading(level: 1)),
            makeSemanticSpan(range: NSRange(location: 2, length: 8), role: .bold),
            makeSemanticSpan(range: NSRange(location: 15, length: 6), role: .inlineCode)
        ]
        let document = EditorSemanticDocument.build(markdown: markdown, spans: spans)

        let boldState = FormattingState.detect(in: markdown, semanticDocument: document, at: 5)
        XCTAssertEqual(boldState.headingLevel, 1)
        XCTAssertTrue(boldState.isBold)
        XCTAssertFalse(boldState.isCode)

        let codeState = FormattingState.detect(in: markdown, semanticDocument: document, at: 17)
        XCTAssertEqual(codeState.headingLevel, 1)
        XCTAssertTrue(codeState.isCode)
        XCTAssertFalse(codeState.isItalic)
    }

    private func makeOverlaySpan(range: NSRange, revealRange: NSRange) -> HighlightSpan {
        HighlightSpan(
            range: range,
            font: EditorFontFactory.makeFont(family: .system, size: 14),
            color: nil,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: nil,
            strikethrough: false,
            isOverlay: true,
            overlayVisibilityBehavior: .concealWhenInactive(revealRange: revealRange)
        )
    }

    private func makeSemanticSpan(range: NSRange, role: HighlightSemanticRole) -> HighlightSpan {
        HighlightSpan(
            range: range,
            font: EditorFontFactory.makeFont(family: .system, size: 14),
            color: nil,
            traits: FontTraits(bold: role == .bold || role.isHeading, italic: role == .italic || role == .blockquote),
            backgroundColor: role == .inlineCode ? platformCodeBackgroundColor() : nil,
            strikethrough: role == .strikethrough,
            semanticRole: role
        )
    }

    private func platformLabelColor() -> PlatformColor {
        #if canImport(UIKit)
        return UIColor.label
        #elseif canImport(AppKit)
        return NSColor.labelColor
        #endif
    }

    private func platformCodeBackgroundColor() -> PlatformColor {
        #if canImport(UIKit)
        return UIColor.systemFill
        #elseif canImport(AppKit)
        return NSColor.quaternaryLabelColor.withAlphaComponent(0.15)
        #endif
    }
}

private extension HighlightSemanticRole {
    var isHeading: Bool {
        if case .heading = self {
            return true
        }
        return false
    }
}
