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

    private func platformLabelColor() -> PlatformColor {
        #if canImport(UIKit)
        return UIColor.label
        #elseif canImport(AppKit)
        return NSColor.labelColor
        #endif
    }
}
