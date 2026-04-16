import XCTest
@testable import QuartzKit

#if canImport(AppKit)
import AppKit

@MainActor
final class EditorRenderingRegressionTests: XCTestCase {

    func testBlankParagraphAfterHeadingUsesBodyTypingAttributes() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = "### Test\n\n"
        let headingFont = NSFont.systemFont(ofSize: 17.5, weight: .bold)

        textView.string = text
        textView.textStorage?.setAttributes(
            [.font: headingFont, .foregroundColor: NSColor.tertiaryLabelColor],
            range: NSRange(location: 0, length: (text as NSString).length)
        )

        session.activeTextView = textView
        session.textDidChange(text)
        session.selectionDidChange(NSRange(location: (text as NSString).length, length: 0))

        let typingFont = textView.typingAttributes[.font] as? NSFont
        let typingColor = textView.typingAttributes[.foregroundColor] as? NSColor

        let resolvedTypingFont = try XCTUnwrap(typingFont)
        XCTAssertEqual(resolvedTypingFont.pointSize, CGFloat(14), accuracy: 0.01)
        XCTAssertEqual(typingColor, .labelColor)
        XCTAssertFalse(NSFontManager.shared.traits(of: resolvedTypingFont).contains(.boldFontMask))
    }

    func testHighlightPassRewritesMixedHeadingRangeBeyondLeadingCharacter() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = try EditorRealityFixture.headingParagraphDrift.load()

        textView.string = text
        session.activeTextView = textView
        session.textDidChange(text)

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter
        let spans = await highlighter.parse(text)

        let h2LineRange = NSRange(location: 11, length: 7) // "## Test"
        let h2ContentRange = NSRange(location: 14, length: 4) // "Test"
        let laterHeadingChar = h2ContentRange.location + 1    // "e" in "Test"
        session.applyHighlightSpansForTesting(spans)

        let expectedHeadingFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: laterHeadingChar, effectiveRange: nil) as? NSFont
        )

        let defaultFont = NSFont.systemFont(ofSize: 14)
        textView.textStorage?.setAttributes(
            [.font: defaultFont, .foregroundColor: NSColor.labelColor],
            range: h2LineRange
        )
        textView.textStorage?.setAttributes(
            [.font: expectedHeadingFont, .foregroundColor: NSColor.labelColor],
            range: NSRange(location: h2ContentRange.location, length: 1)
        )

        session.applyHighlightSpansForTesting(spans)

        let fixedHeadingFont = textView.textStorage?.attribute(.font, at: laterHeadingChar, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(fixedHeadingFont)
        XCTAssertEqual(fixedHeadingFont?.fontName, expectedHeadingFont.fontName)
        XCTAssertEqual(fixedHeadingFont?.pointSize ?? 0, expectedHeadingFont.pointSize, accuracy: 0.01)
    }

    func testHighlightPassRewritesPlainParagraphWhenSegmentStartsWithCleanNewline() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = try EditorRealityFixture.headingParagraphDrift.load()
        let nsText = text as NSString
        let paragraphStart = nsText.range(of: "Das ist ein Test...").location
        let staleRange = NSRange(location: paragraphStart, length: nsText.length - paragraphStart)

        textView.string = text
        session.activeTextView = textView
        session.textDidChange(text)

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter
        let spans = await highlighter.parse(text)

        let headingLikeFont = NSFont.systemFont(ofSize: 17.5, weight: .bold)
        textView.textStorage?.setAttributes(
            [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor],
            range: NSRange(location: paragraphStart - 1, length: 1)
        )
        textView.textStorage?.setAttributes(
            [.font: headingLikeFont, .foregroundColor: NSColor.tertiaryLabelColor],
            range: staleRange
        )

        session.applyHighlightSpansForTesting(spans)

        let paragraphFont = textView.textStorage?.attribute(.font, at: paragraphStart, effectiveRange: nil) as? NSFont
        let paragraphColor = textView.textStorage?.attribute(.foregroundColor, at: paragraphStart, effectiveRange: nil) as? NSColor

        let resolvedParagraphFont = try XCTUnwrap(paragraphFont)
        XCTAssertEqual(resolvedParagraphFont.pointSize, CGFloat(14), accuracy: 0.01)
        XCTAssertFalse(NSFontManager.shared.traits(of: resolvedParagraphFont).contains(.boldFontMask))
        XCTAssertEqual(paragraphColor, .labelColor)
    }

    func testHighlightPassRecomputesTypingAttributesForParagraphContext() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = try EditorRealityFixture.headingParagraphDrift.load()
        let paragraphEnd = (text as NSString).range(of: "Das ist ein Test...").upperBound

        textView.string = text
        textView.setSelectedRange(NSRange(location: paragraphEnd, length: 0))
        session.activeTextView = textView
        session.textDidChange(text)

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter
        let spans = await highlighter.parse(text)

        let staleHeadingFont = NSFont.systemFont(ofSize: 17.5, weight: .bold)
        textView.typingAttributes = [
            .font: staleHeadingFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        session.applyHighlightSpansForTesting(spans)

        let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? NSColor)

        XCTAssertEqual(typingFont.pointSize, CGFloat(14), accuracy: 0.01)
        XCTAssertEqual(typingColor, .labelColor)
        XCTAssertFalse(NSFontManager.shared.traits(of: typingFont).contains(.boldFontMask))
    }

    func testCloseAndReopenReappliesParagraphAttributesAfterStateDrift() async throws {
        let provider = MockVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/editor-rendering-regression.md")
        let text = try EditorRealityFixture.headingParagraphDrift.load()
        let paragraphStart = (text as NSString).range(of: "Das ist ein Test...").location
        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "Welcome"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        let textView = makeTextView()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.activeTextView = textView
        session.highlighter = highlighter

        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: paragraphStart)

        let expectedFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: paragraphStart, effectiveRange: nil) as? NSFont
        )
        let expectedColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: paragraphStart, effectiveRange: nil) as? NSColor
        )

        let staleHeadingFont = NSFont.systemFont(ofSize: 17.5, weight: .bold)
        textView.textStorage?.setAttributes(
            [.font: staleHeadingFont, .foregroundColor: NSColor.tertiaryLabelColor],
            range: NSRange(location: paragraphStart, length: (text as NSString).length - paragraphStart)
        )
        var staleTypingAttributes = textView.typingAttributes
        staleTypingAttributes[.font] = staleHeadingFont
        staleTypingAttributes[.foregroundColor] = NSColor.tertiaryLabelColor
        textView.typingAttributes = staleTypingAttributes

        session.closeNote()
        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: paragraphStart)

        let reopenedFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: paragraphStart, effectiveRange: nil) as? NSFont
        )
        let reopenedColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: paragraphStart, effectiveRange: nil) as? NSColor
        )

        XCTAssertEqual(reopenedFont.fontName, expectedFont.fontName)
        XCTAssertEqual(reopenedFont.pointSize, expectedFont.pointSize, accuracy: 0.01)
        XCTAssertEqual(reopenedColor, expectedColor)
    }

    func testStateRoundtripDoesNotLeakBackgroundColorOutsideInlineCode() async throws {
        let provider = MockVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/editor-rendering-roundtrip-background.md")
        let text = try EditorRealityFixture.editorStateRoundtrip.load()
        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "State Roundtrip"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        let textView = makeTextView()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.activeTextView = textView
        session.highlighter = highlighter

        await session.loadNote(at: url)
        let inlineCodeLocation = (text as NSString).range(of: "inline code").location
        try await waitForHighlightPass(on: textView, monitoredLocation: inlineCodeLocation)

        let allowedInlineCodeRange = (text as NSString).range(of: "`inline code`")
        XCTAssertNotEqual(allowedInlineCodeRange.location, NSNotFound)

        let leakedRanges = nonClearBackgroundRanges(in: textView).filter {
            NSIntersectionRange($0, allowedInlineCodeRange).length != $0.length
        }

        XCTAssertTrue(
            leakedRanges.isEmpty,
            "Unexpected background color ranges outside inline code: \(leakedRanges)"
        )
    }

    func testStateRoundtripHighlighterScopesBackgroundColorToInlineCode() async throws {
        let text = try EditorRealityFixture.editorStateRoundtrip.load()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        let spans = await highlighter.parse(text)
        let allowedInlineCodeRange = (text as NSString).range(of: "`inline code`")

        XCTAssertNotEqual(allowedInlineCodeRange.location, NSNotFound)

        let leakedRanges = spans.compactMap { span -> NSRange? in
            guard let backgroundColor = span.backgroundColor, !isEffectivelyClear(backgroundColor) else {
                return nil
            }
            return NSIntersectionRange(span.range, allowedInlineCodeRange).length == span.range.length
                ? nil
                : span.range
        }

        XCTAssertTrue(
            leakedRanges.isEmpty,
            "Highlighter emitted background spans outside inline code: \(leakedRanges)"
        )
    }

    func testRepeatedHighlightPassesKeepSemanticStylesScoped() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = "# Heading\n\nParagraph with [Link](url), `code`, and $x^2$."
        let nsText = text as NSString
        let headingLocation = nsText.range(of: "Heading").location
        let paragraphLocation = nsText.range(of: "Paragraph").location
        let linkLocation = nsText.range(of: "Link").location
        let codeRange = nsText.range(of: "`code`")
        let mathContentRange = nsText.range(of: "x^2")

        textView.string = text
        session.activeTextView = textView
        session.textDidChange(text)

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter

        for _ in 0..<4 {
            let spans = await highlighter.parse(text)
            session.applyHighlightSpansForTesting(spans)
        }

        let leakedRanges = nonClearBackgroundRanges(in: textView).filter { range in
            ![codeRange, mathContentRange].contains(where: { allowed in
                NSIntersectionRange(range, allowed).length == range.length
            })
        }

        XCTAssertTrue(leakedRanges.isEmpty, "Unexpected background leakage after repeated highlight cycles: \(leakedRanges)")

        let headingFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: headingLocation, effectiveRange: nil) as? NSFont
        )
        let paragraphFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: paragraphLocation, effectiveRange: nil) as? NSFont
        )
        let linkColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: linkLocation, effectiveRange: nil) as? NSColor
        )

        XCTAssertTrue(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))
        XCTAssertFalse(NSFontManager.shared.traits(of: paragraphFont).contains(.boldFontMask))
        XCTAssertGreaterThan(alphaComponent(of: linkColor), 0.001)
    }

    func testCloseAndReopenPreservesScopedSemanticRendering() async throws {
        let provider = MockVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/editor-rendering-semantic-roundtrip.md")
        let text = "# Heading\n\nParagraph with [Link](url), `code`, and $x^2$."
        let nsText = text as NSString
        let linkLocation = nsText.range(of: "Link").location
        let codeRange = nsText.range(of: "`code`")
        let mathContentRange = nsText.range(of: "x^2")

        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "Semantic Roundtrip"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        let textView = makeTextView()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.activeTextView = textView
        session.highlighter = highlighter

        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: linkLocation)
        session.closeNote()
        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: linkLocation)

        let leakedRanges = nonClearBackgroundRanges(in: textView).filter { range in
            ![codeRange, mathContentRange].contains(where: { allowed in
                NSIntersectionRange(range, allowed).length == range.length
            })
        }

        XCTAssertTrue(leakedRanges.isEmpty, "Unexpected background leakage after reopen: \(leakedRanges)")

        let linkColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: linkLocation, effectiveRange: nil) as? NSColor
        )
        XCTAssertGreaterThan(alphaComponent(of: linkColor), 0.001)
        XCTAssertEqual(session.currentText, text)
    }

    func testLongExistingNoteOpenReopenAndPostEditKeepHeadingContentUniform() async throws {
        let provider = MockVaultProvider()
        let seed = try EditorRealityFixture.existingLongHeadingRender.load()
        let text = makeLongExistingDocument(from: seed, minimumLength: 130_000)
        let url = URL(fileURLWithPath: "/tmp/editor-rendering-long-existing-heading.md")
        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "Existing Long Heading Render"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        let textView = makeTextView()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.activeTextView = textView
        session.highlighter = highlighter

        let monitoredLocation = try headingContentRange(
            matchingLine: "## Architecture Overview",
            in: text
        ).location
        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let initialH1 = try uniformHeadingContentSignature(
            matchingLine: "# Release Notes",
            in: text,
            textView: textView
        )
        let initialH2 = try uniformHeadingContentSignature(
            matchingLine: "## Architecture Overview",
            in: text,
            textView: textView
        )
        let initialH3 = try uniformHeadingContentSignature(
            matchingLine: "### Rendering Goals",
            in: text,
            textView: textView
        )

        session.closeNote()
        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let reopenedH1 = try uniformHeadingContentSignature(
            matchingLine: "# Release Notes",
            in: text,
            textView: textView
        )
        let reopenedH2 = try uniformHeadingContentSignature(
            matchingLine: "## Architecture Overview",
            in: text,
            textView: textView
        )
        let reopenedH3 = try uniformHeadingContentSignature(
            matchingLine: "### Rendering Goals",
            in: text,
            textView: textView
        )

        XCTAssertEqual(reopenedH1, initialH1)
        XCTAssertEqual(reopenedH2, initialH2)
        XCTAssertEqual(reopenedH3, initialH3)

        try await performHealingEdit(
            on: session,
            headingLine: "## Architecture Overview",
            expectedRestoredText: text,
            monitoredLocation: monitoredLocation,
            textView: textView
        )

        let postEditH1 = try uniformHeadingContentSignature(
            matchingLine: "# Release Notes",
            in: text,
            textView: textView
        )
        let postEditH2 = try uniformHeadingContentSignature(
            matchingLine: "## Architecture Overview",
            in: text,
            textView: textView
        )
        let postEditH3 = try uniformHeadingContentSignature(
            matchingLine: "### Rendering Goals",
            in: text,
            textView: textView
        )

        XCTAssertEqual(postEditH1, initialH1)
        XCTAssertEqual(postEditH2, initialH2)
        XCTAssertEqual(postEditH3, initialH3)

        session.closeNote()
        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let reopenedAfterEditH1 = try uniformHeadingContentSignature(
            matchingLine: "# Release Notes",
            in: text,
            textView: textView
        )
        let reopenedAfterEditH2 = try uniformHeadingContentSignature(
            matchingLine: "## Architecture Overview",
            in: text,
            textView: textView
        )
        let reopenedAfterEditH3 = try uniformHeadingContentSignature(
            matchingLine: "### Rendering Goals",
            in: text,
            textView: textView
        )

        XCTAssertEqual(reopenedAfterEditH1, initialH1)
        XCTAssertEqual(reopenedAfterEditH2, initialH2)
        XCTAssertEqual(reopenedAfterEditH3, initialH3)
    }

    func testTableToolbarInsertionKeepsLongExistingFormattingStableAboveInsertedTableAcrossReopen() async throws {
        let provider = MockVaultProvider()
        let seed = try EditorRealityFixture.existingLongHeadingRender.load()
        let text = makeLongExistingDocument(from: seed, minimumLength: 90_000)
        let url = URL(fileURLWithPath: "/tmp/editor-rendering-long-existing-table.md")
        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "Existing Long Table Insert"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        let textView = makeTextView()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.activeTextView = textView
        session.highlighter = highlighter

        let headingLine = "## Writing Workflow"
        let bodyLine = "This paragraph is deliberately long so the text system has to lay out a realistic amount of content before it reaches the next heading. The bug this fixture protects against was not about tiny synthetic notes. It showed up when a previously authored note reopened and only part of the heading line visually carried the correct font and color while the rest of the line looked like body text until the user touched it."
        let monitoredLocation = try headingContentRange(
            matchingLine: headingLine,
            in: text
        ).location

        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let initialHeading = try uniformHeadingContentSignature(
            matchingLine: headingLine,
            in: text,
            textView: textView
        )
        let initialBody = try uniformLineContentSignature(
            matchingLine: bodyLine,
            in: text,
            textView: textView
        )

        let insertionLocation = try lineContentRange(matchingLine: bodyLine, in: text).location + 24
        let insertionSelection = NSRange(location: insertionLocation, length: 0)
        textView.setSelectedRange(insertionSelection)
        session.selectionDidChange(insertionSelection)

        session.applyToolbarFormatting(.table)

        for _ in 0..<80 {
            if session.currentText.contains("| Column 1 | Column 2 | Column 3 |") {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(session.currentText.contains("| Column 1 | Column 2 | Column 3 |"))
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let postInsertHeading = try uniformHeadingContentSignature(
            matchingLine: headingLine,
            in: text,
            textView: textView
        )
        let postInsertBody = try uniformLineContentSignature(
            matchingLine: bodyLine,
            in: text,
            textView: textView
        )

        XCTAssertEqual(postInsertHeading, initialHeading)
        XCTAssertEqual(postInsertBody, initialBody)

        await session.manualSave()
        session.closeNote()
        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let reopenedHeading = try uniformHeadingContentSignature(
            matchingLine: headingLine,
            in: text,
            textView: textView
        )
        let reopenedBody = try uniformLineContentSignature(
            matchingLine: bodyLine,
            in: text,
            textView: textView
        )

        XCTAssertEqual(reopenedHeading, initialHeading)
        XCTAssertEqual(reopenedBody, initialBody)
        XCTAssertTrue(session.currentText.contains("| Column 1 | Column 2 | Column 3 |"))
    }

    func testTableToolbarInsertionImmediatelyKeepsLongExistingFormattingStableAboveInsertion() async throws {
        let provider = MockVaultProvider()
        let seed = try EditorRealityFixture.existingLongHeadingRender.load()
        let text = makeLongExistingDocument(from: seed, minimumLength: 90_000)
        let url = URL(fileURLWithPath: "/tmp/editor-rendering-long-existing-table-immediate.md")
        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "Existing Long Table Insert Immediate"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        let textView = makeTextView()
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.activeTextView = textView
        session.highlighter = highlighter

        let headingLine = "## Writing Workflow"
        let bodyLine = "This paragraph is deliberately long so the text system has to lay out a realistic amount of content before it reaches the next heading. The bug this fixture protects against was not about tiny synthetic notes. It showed up when a previously authored note reopened and only part of the heading line visually carried the correct font and color while the rest of the line looked like body text until the user touched it."
        let monitoredLocation = try headingContentRange(
            matchingLine: headingLine,
            in: text
        ).location

        await session.loadNote(at: url)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)

        let initialHeading = try uniformHeadingContentSignature(
            matchingLine: headingLine,
            in: text,
            textView: textView
        )
        let initialBody = try uniformLineContentSignature(
            matchingLine: bodyLine,
            in: text,
            textView: textView
        )

        let insertionLocation = try lineContentRange(matchingLine: bodyLine, in: text).location + 24
        let insertionSelection = NSRange(location: insertionLocation, length: 0)
        textView.setSelectedRange(insertionSelection)
        session.selectionDidChange(insertionSelection)

        session.applyToolbarFormatting(.table)

        XCTAssertTrue(session.currentText.contains("| Column 1 | Column 2 | Column 3 |"))
        XCTAssertTrue(hasRenderedTableRowStyles(in: textView), "Table formatting must rebuild table row styles immediately for long notes")

        let immediateHeading = try uniformHeadingContentSignature(
            matchingLine: headingLine,
            in: text,
            textView: textView
        )
        let immediateBody = try uniformLineContentSignature(
            matchingLine: bodyLine,
            in: text,
            textView: textView
        )

        XCTAssertEqual(immediateHeading, initialHeading)
        XCTAssertEqual(immediateBody, initialBody)
    }

    func testHiddenUntilCaretHidesOverlayWhenCaretIsOnDifferentLine() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = try EditorRealityFixture.concealmentBoundaries.load()
        let nsText = text as NSString
        let delimiterLocation = nsText.range(of: "**").location
        let secondLineLocation = nsText.range(of: "Second line plain.").location

        XCTAssertNotEqual(delimiterLocation, NSNotFound)
        XCTAssertNotEqual(secondLineLocation, NSNotFound)

        textView.string = text
        textView.setSelectedRange(NSRange(location: secondLineLocation, length: 0))
        session.activeTextView = textView
        session.textDidChange(text)
        session.syntaxVisibilityMode = .hiddenUntilCaret
        session.selectionDidChange(NSRange(location: secondLineLocation, length: 0))

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter
        let spans = await highlighter.parse(text)
        session.applyHighlightSpansForTesting(spans)

        let overlayColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: delimiterLocation, effectiveRange: nil) as? NSColor
        )
        XCTAssertLessThanOrEqual(alphaComponent(of: overlayColor), 0.001)
    }

    func testHiddenUntilCaretRevealsOverlayWhenCaretReturnsToSameLine() async throws {
        let session = makeSession()
        let textView = makeTextView()
        let text = try EditorRealityFixture.concealmentBoundaries.load()
        let nsText = text as NSString
        let delimiterLocation = nsText.range(of: "**").location
        let boldLocation = nsText.range(of: "bold").location
        let secondLineLocation = nsText.range(of: "Second line plain.").location

        XCTAssertNotEqual(delimiterLocation, NSNotFound)
        XCTAssertNotEqual(boldLocation, NSNotFound)
        XCTAssertNotEqual(secondLineLocation, NSNotFound)

        textView.string = text
        textView.setSelectedRange(NSRange(location: secondLineLocation, length: 0))
        session.activeTextView = textView
        session.textDidChange(text)
        session.syntaxVisibilityMode = .hiddenUntilCaret
        session.selectionDidChange(NSRange(location: secondLineLocation, length: 0))

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter
        let spans = await highlighter.parse(text)
        session.applyHighlightSpansForTesting(spans)

        var hiddenColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: delimiterLocation, effectiveRange: nil) as? NSColor
        )
        XCTAssertLessThanOrEqual(alphaComponent(of: hiddenColor), 0.001)

        textView.setSelectedRange(NSRange(location: boldLocation, length: 0))
        session.selectionDidChange(NSRange(location: boldLocation, length: 0))

        hiddenColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: delimiterLocation, effectiveRange: nil) as? NSColor
        )
        XCTAssertGreaterThan(alphaComponent(of: hiddenColor), 0.001)
    }

    func testHiddenUntilCaretKeepsInlineSyntaxHiddenWhenCaretIsInPlainTextOnSameLine() async throws {
        let text = try EditorRealityFixture.concealmentBoundaries.load()
        let nsText = text as NSString
        let plainTextLocation = nsText.range(of: "Paragraph").location
        let boldDelimiterLocation = nsText.range(of: "**").location
        let italicDelimiterLocation = nsText.range(of: "*italic*").location
        let codeDelimiterLocation = nsText.range(of: "`code`").location

        XCTAssertNotEqual(plainTextLocation, NSNotFound)
        XCTAssertNotEqual(boldDelimiterLocation, NSNotFound)
        XCTAssertNotEqual(italicDelimiterLocation, NSNotFound)
        XCTAssertNotEqual(codeDelimiterLocation, NSNotFound)

        let textView = try await makeHiddenUntilCaretTextView(
            text: text,
            selection: NSRange(location: plainTextLocation, length: 0)
        )

        XCTAssertTrue(isVisuallyHidden(at: boldDelimiterLocation, in: textView))
        XCTAssertTrue(isVisuallyHidden(at: italicDelimiterLocation, in: textView))
        XCTAssertTrue(isVisuallyHidden(at: codeDelimiterLocation, in: textView))
    }

    func testHiddenUntilCaretRevealsOnlyActiveInlineTokenOnSharedLine() async throws {
        let text = try EditorRealityFixture.concealmentBoundaries.load()
        let nsText = text as NSString
        let boldContentLocation = nsText.range(of: "bold").location
        let boldDelimiterLocation = nsText.range(of: "**").location
        let italicDelimiterLocation = nsText.range(of: "*italic*").location
        let codeDelimiterLocation = nsText.range(of: "`code`").location

        XCTAssertNotEqual(boldContentLocation, NSNotFound)
        XCTAssertNotEqual(boldDelimiterLocation, NSNotFound)
        XCTAssertNotEqual(italicDelimiterLocation, NSNotFound)
        XCTAssertNotEqual(codeDelimiterLocation, NSNotFound)

        let textView = try await makeHiddenUntilCaretTextView(
            text: text,
            selection: NSRange(location: boldContentLocation, length: 0)
        )

        XCTAssertFalse(isVisuallyHidden(at: boldDelimiterLocation, in: textView))
        XCTAssertTrue(isVisuallyHidden(at: italicDelimiterLocation, in: textView))
        XCTAssertTrue(isVisuallyHidden(at: codeDelimiterLocation, in: textView))
    }

    func testHiddenUntilCaretKeepsWikiLinkTextVisibleWhileHidingItsBrackets() async throws {
        let text = "Paragraph with [[Linked Note]] and plain text.\nSecond line plain."
        let nsText = text as NSString
        let secondLineLocation = nsText.range(of: "Second line plain.").location
        let bracketLocation = nsText.range(of: "[[").location
        let linkTextLocation = nsText.range(of: "Linked Note").location

        XCTAssertNotEqual(secondLineLocation, NSNotFound)
        XCTAssertNotEqual(bracketLocation, NSNotFound)
        XCTAssertNotEqual(linkTextLocation, NSNotFound)

        let textView = try await makeHiddenUntilCaretTextView(
            text: text,
            selection: NSRange(location: secondLineLocation, length: 0)
        )

        XCTAssertTrue(isVisuallyHidden(at: bracketLocation, in: textView))
        XCTAssertFalse(isVisuallyHidden(at: linkTextLocation, in: textView))

        let linkColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: linkTextLocation, effectiveRange: nil) as? NSColor
        )
        XCTAssertGreaterThan(alphaComponent(of: linkColor), 0.001)
    }

    func testHiddenUntilCaretKeepsMarkdownLinkLabelVisibleWhileHidingSyntaxAndURL() async throws {
        let text = "Paragraph with [Linked Note](url) and plain text.\nSecond line plain."
        let nsText = text as NSString
        let secondLineLocation = nsText.range(of: "Second line plain.").location
        let openBracketLocation = nsText.range(of: "[").location
        let linkTextLocation = nsText.range(of: "Linked Note").location
        let destinationLocation = nsText.range(of: "url").location

        XCTAssertNotEqual(secondLineLocation, NSNotFound)
        XCTAssertNotEqual(openBracketLocation, NSNotFound)
        XCTAssertNotEqual(linkTextLocation, NSNotFound)
        XCTAssertNotEqual(destinationLocation, NSNotFound)

        let textView = try await makeHiddenUntilCaretTextView(
            text: text,
            selection: NSRange(location: secondLineLocation, length: 0)
        )

        XCTAssertTrue(isVisuallyHidden(at: openBracketLocation, in: textView))
        XCTAssertFalse(isVisuallyHidden(at: linkTextLocation, in: textView))
        XCTAssertTrue(isVisuallyHidden(at: destinationLocation, in: textView))

        let linkColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: linkTextLocation, effectiveRange: nil) as? NSColor
        )
        XCTAssertGreaterThan(alphaComponent(of: linkColor), 0.001)
    }

    private func makeSession() -> EditorSession {
        EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
    }

    private func makeTextView() -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.isRichText = false
        textView.allowsUndo = false
        return textView
    }

    private func waitForHighlightPass(on textView: NSTextView, monitoredLocation: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)

        while clock.now < deadline {
            if textView.alphaValue == 1,
               let textStorage = textView.textStorage,
               monitoredLocation < textStorage.length,
               textStorage.attribute(.font, at: monitoredLocation, effectiveRange: nil) != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        struct HighlightPassTimeout: Error {}
        XCTFail("Timed out waiting for highlight pass to complete")
        throw HighlightPassTimeout()
    }

    private func makeHiddenUntilCaretTextView(
        text: String,
        selection: NSRange
    ) async throws -> NSTextView {
        let session = makeSession()
        let textView = makeTextView()

        textView.string = text
        textView.setSelectedRange(selection)
        session.activeTextView = textView
        session.textDidChange(text)
        session.syntaxVisibilityMode = .hiddenUntilCaret
        session.selectionDidChange(selection)

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighter = highlighter
        let spans = await highlighter.parse(text)
        session.applyHighlightSpansForTesting(spans)

        return textView
    }

    private func isVisuallyHidden(at location: Int, in textView: NSTextView) -> Bool {
        guard let color = textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor else {
            return false
        }
        return alphaComponent(of: color) <= 0.001
    }

    private func alphaComponent(of color: NSColor) -> CGFloat {
        color.usingColorSpace(.deviceRGB)?.alphaComponent ?? color.alphaComponent
    }

    private func nonClearBackgroundRanges(in textView: NSTextView) -> [NSRange] {
        guard let storage = textView.textStorage else { return [] }

        var ranges: [NSRange] = []
        var location = 0
        while location < storage.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let background = storage.attribute(.backgroundColor, at: location, effectiveRange: &effectiveRange) as? NSColor
            if let background, !isEffectivelyClear(background) {
                ranges.append(effectiveRange)
            }
            location = NSMaxRange(effectiveRange)
        }
        return ranges
    }

    private func isEffectivelyClear(_ color: NSColor) -> Bool {
        alphaComponent(of: color) <= 0.001
    }

    private struct HeadingContentSignature: Equatable {
        let fontName: String
        let pointSize: CGFloat
        let color: NSColor
        let paragraphStyleDescription: String
    }

    private func makeLongExistingDocument(from seed: String, minimumLength: Int) -> String {
        var sections: [String] = []
        var counter = 1
        while sections.joined(separator: "\n\n").count < minimumLength {
            sections.append(
                seed.replacingOccurrences(
                    of: "Release Notes",
                    with: "Release Notes \(counter)"
                )
            )
            counter += 1
        }
        return sections.joined(separator: "\n\n")
    }

    private func headingContentRange(
        matchingLine line: String,
        in text: String
    ) throws -> NSRange {
        let nsText = text as NSString
        let lineRange = nsText.range(of: line)
        XCTAssertNotEqual(lineRange.location, NSNotFound, "Fixture must contain heading line '\(line)'")
        let lineText = nsText.substring(with: lineRange)
        let contentPrefixLength = lineText.prefix { $0 == "#" || $0 == " " || $0 == "\t" }.count
        return NSRange(
            location: lineRange.location + contentPrefixLength,
            length: lineRange.length - contentPrefixLength
        )
    }

    private func lineContentRange(
        matchingLine line: String,
        in text: String
    ) throws -> NSRange {
        let nsText = text as NSString
        let lineRange = nsText.range(of: line)
        XCTAssertNotEqual(lineRange.location, NSNotFound, "Fixture must contain line '\(line)'")
        return lineRange
    }

    private func uniformHeadingContentSignature(
        matchingLine line: String,
        in text: String,
        textView: NSTextView
    ) throws -> HeadingContentSignature {
        let contentRange = try headingContentRange(matchingLine: line, in: text)
        let storage = try XCTUnwrap(textView.textStorage)
        let expectedFont = try XCTUnwrap(
            storage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont
        )
        let expectedColor = try XCTUnwrap(
            storage.attribute(.foregroundColor, at: contentRange.location, effectiveRange: nil) as? NSColor
        )
        let expectedParagraphStyle = storage.attribute(.paragraphStyle, at: contentRange.location, effectiveRange: nil) as? NSParagraphStyle

        var location = contentRange.location
        while location < NSMaxRange(contentRange) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = try XCTUnwrap(
                storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont
            )
            let color = try XCTUnwrap(
                storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            )
            let paragraphStyle = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle

            XCTAssertEqual(font.fontName, expectedFont.fontName, "Heading line '\(line)' should use one consistent font across the content run")
            XCTAssertEqual(font.pointSize, expectedFont.pointSize, accuracy: 0.01, "Heading line '\(line)' should use one consistent point size across the content run")
            XCTAssertEqual(color, expectedColor, "Heading line '\(line)' should use one consistent color across the content run")
            XCTAssertEqual(paragraphStyle?.debugDescription, expectedParagraphStyle?.debugDescription, "Heading line '\(line)' should keep one paragraph style across the content run")

            location = min(NSMaxRange(effectiveRange), NSMaxRange(contentRange))
        }

        XCTAssertTrue(NSFontManager.shared.traits(of: expectedFont).contains(.boldFontMask))
        XCTAssertGreaterThan(expectedFont.pointSize, CGFloat(14))

        return HeadingContentSignature(
            fontName: expectedFont.fontName,
            pointSize: expectedFont.pointSize,
            color: expectedColor,
            paragraphStyleDescription: expectedParagraphStyle?.debugDescription ?? ""
        )
    }

    private func uniformLineContentSignature(
        matchingLine line: String,
        in text: String,
        textView: NSTextView
    ) throws -> HeadingContentSignature {
        let contentRange = try lineContentRange(matchingLine: line, in: text)
        let storage = try XCTUnwrap(textView.textStorage)
        let expectedFont = try XCTUnwrap(
            storage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont
        )
        let expectedColor = try XCTUnwrap(
            storage.attribute(.foregroundColor, at: contentRange.location, effectiveRange: nil) as? NSColor
        )
        let expectedParagraphStyle = storage.attribute(.paragraphStyle, at: contentRange.location, effectiveRange: nil) as? NSParagraphStyle

        var location = contentRange.location
        while location < NSMaxRange(contentRange) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = try XCTUnwrap(
                storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont
            )
            let color = try XCTUnwrap(
                storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            )
            let paragraphStyle = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle

            XCTAssertEqual(font.fontName, expectedFont.fontName, "Line '\(line)' should use one consistent font across the content run")
            XCTAssertEqual(font.pointSize, expectedFont.pointSize, accuracy: 0.01, "Line '\(line)' should use one consistent point size across the content run")
            XCTAssertEqual(color, expectedColor, "Line '\(line)' should use one consistent color across the content run")
            XCTAssertEqual(paragraphStyle?.debugDescription, expectedParagraphStyle?.debugDescription, "Line '\(line)' should keep one paragraph style across the content run")

            location = min(NSMaxRange(effectiveRange), NSMaxRange(contentRange))
        }

        return HeadingContentSignature(
            fontName: expectedFont.fontName,
            pointSize: expectedFont.pointSize,
            color: expectedColor,
            paragraphStyleDescription: expectedParagraphStyle?.debugDescription ?? ""
        )
    }

    private func performHealingEdit(
        on session: EditorSession,
        headingLine: String,
        expectedRestoredText: String,
        monitoredLocation: Int,
        textView: NSTextView
    ) async throws {
        let nsText = expectedRestoredText as NSString
        let headingRange = nsText.range(of: headingLine)
        XCTAssertNotEqual(headingRange.location, NSNotFound, "Fixture must contain heading line '\(headingLine)'")

        let insertionLocation = NSMaxRange(headingRange)
        let insertedText = nsText.replacingCharacters(in: NSRange(location: insertionLocation, length: 0), with: " ")

        session.applyExternalEdit(
            replacement: " ",
            range: NSRange(location: insertionLocation, length: 0),
            cursorAfter: NSRange(location: insertionLocation + 1, length: 0),
            origin: .formatting
        )
        try await waitForSessionText(session, expected: insertedText)

        session.applyExternalEdit(
            replacement: "",
            range: NSRange(location: insertionLocation, length: 1),
            cursorAfter: NSRange(location: insertionLocation, length: 0),
            origin: .formatting
        )
        try await waitForSessionText(session, expected: expectedRestoredText)
        try await waitForHighlightPass(on: textView, monitoredLocation: monitoredLocation)
    }

    private func waitForSessionText(_ session: EditorSession, expected: String) async throws {
        for _ in 0..<80 {
            if session.currentText == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for session text to become expected content")
    }

    private func hasRenderedTableRowStyles(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        for location in 0..<storage.length {
            if storage.attribute(.quartzTableRowStyle, at: location, effectiveRange: nil) != nil {
                return true
            }
        }
        return false
    }
}
#endif
