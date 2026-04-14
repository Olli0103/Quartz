import XCTest

#if canImport(UIKit) && !os(macOS)
import UIKit
@testable import QuartzKit

@MainActor
final class EditorLiveMutationRegressionTests_iOS: XCTestCase {

    func testOpenEditCloseReopenRoundTripsRenderedParagraphs() async throws {
        try await assertOpenEditCloseReopenRoundTrip(for: .phone)
    }

    func testMountedProgrammaticEditUndoRedoRoundTripsContentAndInsertionPoint() async throws {
        try await assertMountedProgrammaticUndoRedoRoundTrip(for: .phone)
    }

    func testMountedBoldFormattingPreservesSelectionAcrossForcedHighlight() async throws {
        try await assertMountedBoldFormattingPreservesSelectionAcrossForcedHighlight(for: .phone)
    }

    func testMountedHeadingRoundTripRestoresParagraphTypingAttributes() async throws {
        try await assertMountedHeadingRoundTripRestoresParagraphTypingAttributes(for: .phone)
    }

    func testMountedBulletFormattingReplacesCheckboxSyntaxWithoutLayering() async throws {
        try await assertMountedBulletFormattingReplacesCheckboxSyntaxWithoutLayering(for: .phone)
    }

    func testMountedBlockquoteFormattingReplacesNumberedListSyntaxWithoutLayering() async throws {
        try await assertMountedBlockquoteFormattingReplacesNumberedListSyntaxWithoutLayering(for: .phone)
    }

    func testMountedParagraphFormattingRemovesCodeFenceWithoutLeavingDelimitersBehind() async throws {
        try await assertMountedParagraphFormattingRemovesCodeFenceWithoutLeavingDelimitersBehind(for: .phone)
    }

    func testMountedBulletFormattingTransformsEverySelectedLine() async throws {
        try await assertMountedBulletFormattingTransformsEverySelectedLine(for: .phone)
    }

    func testMountedCodeBlockFormattingWrapsEntireSelectedLines() async throws {
        try await assertMountedCodeBlockFormattingWrapsEntireSelectedLines(for: .phone)
    }

    func testNativeReturnAfterHeadingDropsToParagraphTypingAttributes() async throws {
        try await assertNativeReturnAfterHeadingDropsToParagraphTypingAttributes(for: .phone)
    }

    func testSmartPasteNormalizesMultiParagraphPasteWithoutBreakingSelection() async throws {
        try await assertSmartPasteNormalizesMultiParagraphPasteWithoutBreakingSelection(for: .phone)
    }

    func testRawPastePreservesBytesAndCursorPlacement() async throws {
        try await assertRawPastePreservesBytesAndCursorPlacement(for: .phone)
    }
}

@MainActor
final class EditorLiveMutationRegressionTests_iPadOS: XCTestCase {

    func testOpenEditCloseReopenRoundTripsRenderedParagraphs() async throws {
        try await assertOpenEditCloseReopenRoundTrip(for: .pad)
    }

    func testMountedProgrammaticEditUndoRedoRoundTripsContentAndInsertionPoint() async throws {
        try await assertMountedProgrammaticUndoRedoRoundTrip(for: .pad)
    }

    func testMountedBoldFormattingPreservesSelectionAcrossForcedHighlight() async throws {
        try await assertMountedBoldFormattingPreservesSelectionAcrossForcedHighlight(for: .pad)
    }

    func testMountedHeadingRoundTripRestoresParagraphTypingAttributes() async throws {
        try await assertMountedHeadingRoundTripRestoresParagraphTypingAttributes(for: .pad)
    }

    func testMountedBulletFormattingReplacesCheckboxSyntaxWithoutLayering() async throws {
        try await assertMountedBulletFormattingReplacesCheckboxSyntaxWithoutLayering(for: .pad)
    }

    func testMountedBlockquoteFormattingReplacesNumberedListSyntaxWithoutLayering() async throws {
        try await assertMountedBlockquoteFormattingReplacesNumberedListSyntaxWithoutLayering(for: .pad)
    }

    func testMountedParagraphFormattingRemovesCodeFenceWithoutLeavingDelimitersBehind() async throws {
        try await assertMountedParagraphFormattingRemovesCodeFenceWithoutLeavingDelimitersBehind(for: .pad)
    }

    func testMountedBulletFormattingTransformsEverySelectedLine() async throws {
        try await assertMountedBulletFormattingTransformsEverySelectedLine(for: .pad)
    }

    func testMountedCodeBlockFormattingWrapsEntireSelectedLines() async throws {
        try await assertMountedCodeBlockFormattingWrapsEntireSelectedLines(for: .pad)
    }

    func testNativeReturnAfterHeadingDropsToParagraphTypingAttributes() async throws {
        try await assertNativeReturnAfterHeadingDropsToParagraphTypingAttributes(for: .pad)
    }

    func testSmartPasteNormalizesMultiParagraphPasteWithoutBreakingSelection() async throws {
        try await assertSmartPasteNormalizesMultiParagraphPasteWithoutBreakingSelection(for: .pad)
    }

    func testRawPastePreservesBytesAndCursorPlacement() async throws {
        try await assertRawPastePreservesBytesAndCursorPlacement(for: .pad)
    }
}

@MainActor
private func assertOpenEditCloseReopenRoundTrip(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let provider = MockVaultProvider()
    let initialText = try EditorRealityFixture.headingParagraphDrift.load()
    let url = URL(fileURLWithPath: "/tmp/editor-mobile-roundtrip-\(target.platformSuffix)-\(UUID().uuidString).md")
    let session = try await makeLoadedMobileSession(
        text: initialText,
        title: "Roundtrip",
        url: url,
        provider: provider
    )
    let harness = try await mountMobileEditor(
        session: session,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )

    let insertionPoint = (initialText as NSString).length
    let appendedParagraph = "\n\nNoch ein Absatz."
    let expected = initialText + appendedParagraph
    let cursorAfter = NSRange(location: insertionPoint + (appendedParagraph as NSString).length, length: 0)

    harness.textView.selectedRange = NSRange(location: insertionPoint, length: 0)
    session.selectionDidChange(NSRange(location: insertionPoint, length: 0))
    session.applyExternalEdit(
        replacement: appendedParagraph,
        range: NSRange(location: insertionPoint, length: 0),
        cursorAfter: cursorAfter,
        origin: .pasteOrDrop
    )

    try await waitForMobileSessionText(session, expected: expected)
    await pumpMobileHarness(harness)
    await session.save()

    let reopenedSession = await makeLoadedExistingMobileSession(at: url, provider: provider)
    let reopenedHarness = try await mountMobileEditor(
        session: reopenedSession,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    try await waitForMobileSessionText(reopenedSession, expected: expected)
    await pumpMobileHarness(reopenedHarness)

    let paragraphLocation = (expected as NSString).range(of: "Noch ein Absatz.").location
    XCTAssertNotEqual(paragraphLocation, NSNotFound)

    reopenedHarness.textView.selectedRange = NSRange(location: paragraphLocation, length: 0)
    reopenedSession.selectionDidChange(NSRange(location: paragraphLocation, length: 0))

    XCTAssertEqual(reopenedHarness.textView.text, expected)
    XCTAssertEqual(reopenedSession.currentText, expected)

    let paragraphFont = try XCTUnwrap(
        reopenedHarness.textView.textStorage.attribute(
            .font,
            at: paragraphLocation,
            effectiveRange: nil
        ) as? UIFont
    )
    XCTAssertEqual(paragraphFont.pointSize, expectedMobileBodyFontSize(), accuracy: 0.01)
    XCTAssertFalse(isBoldFont(paragraphFont))
}

@MainActor
private func assertMountedProgrammaticUndoRedoRoundTrip(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "Alpha Beta",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = NSRange(location: 6, length: 4)
    textView.selectedRange = selection
    session.selectionDidChange(selection)

    session.applyExternalEdit(
        replacement: "**Beta**",
        range: selection,
        cursorAfter: NSRange(location: 10, length: 4),
        origin: .pasteOrDrop
    )

    XCTAssertTrue(session.canUndo)

    session.undo()
    try await waitForMobileSessionText(session, expected: "Alpha Beta")
    await pumpMobileHarness(harness)
    XCTAssertEqual(textView.text, "Alpha Beta")
    XCTAssertEqual(session.currentText, "Alpha Beta")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 6, length: 4))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 6, length: 4))

    XCTAssertTrue(session.canRedo)

    session.redo()
    try await waitForMobileSessionText(session, expected: "Alpha **Beta**")
    await pumpMobileHarness(harness)
    XCTAssertEqual(textView.text, "Alpha **Beta**")
    XCTAssertEqual(session.currentText, "Alpha **Beta**")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 10, length: 4))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 10, length: 4))
}

@MainActor
private func assertMountedBoldFormattingPreservesSelectionAcrossForcedHighlight(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "Alpha Beta",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = NSRange(location: 6, length: 4)
    textView.selectedRange = selection
    session.selectionDidChange(selection)

    let formatter = MarkdownFormatter()
    let edit = try XCTUnwrap(
        formatter.surgicalEdit(.bold, in: session.currentText, selectedRange: selection)
    )
    let expectedText = ("Alpha Beta" as NSString).replacingCharacters(in: edit.range, with: edit.replacement)

    session.applyFormatting(.bold)
    try await waitForMobileSessionText(session, expected: expectedText)
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "Alpha **Beta**")
    XCTAssertEqual(session.currentText, "Alpha **Beta**")
    XCTAssertEqual(textView.selectedRange, edit.cursorAfter)
    XCTAssertEqual(session.cursorPosition, edit.cursorAfter)
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)

    let attributeLocation = validAttributeLocation(edit.cursorAfter.location, storageLength: textView.textStorage.length)
    let boldFont = try XCTUnwrap(
        textView.textStorage.attribute(.font, at: attributeLocation, effectiveRange: nil) as? UIFont
    )
    XCTAssertTrue(isBoldFont(boldFont))
}

@MainActor
private func assertMountedHeadingRoundTripRestoresParagraphTypingAttributes(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "Title",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let insertionPoint = NSRange(location: (textView.text ?? "").count, length: 0)
    textView.selectedRange = insertionPoint
    session.selectionDidChange(insertionPoint)

    session.applyFormatting(.heading2)
    try await waitForMobileSessionText(session, expected: "## Title")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "## Title")
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)

    session.applyFormatting(.paragraph)
    try await waitForMobileSessionText(session, expected: "Title")
    await pumpMobileHarness(harness)

    let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
    let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? UIColor)

    XCTAssertEqual(textView.text, "Title")
    XCTAssertEqual(session.currentText, "Title")
    XCTAssertEqual(session.cursorPosition, textView.selectedRange)
    XCTAssertEqual(typingFont.pointSize, expectedMobileBodyFontSize(), accuracy: 0.01)
    XCTAssertFalse(isBoldFont(typingFont))
    assertResolvedEqual(typingColor, UIColor.label)
}

@MainActor
private func assertMountedBulletFormattingReplacesCheckboxSyntaxWithoutLayering(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "- [ ] Task",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let insertionPoint = NSRange(location: 6, length: 0)
    textView.selectedRange = insertionPoint
    session.selectionDidChange(insertionPoint)

    session.applyFormatting(.bulletList)
    try await waitForMobileSessionText(session, expected: "- Task")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "- Task")
    XCTAssertEqual(session.currentText, "- Task")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 0))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 0))
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)
    XCTAssertTrue(session.formattingState.isBulletList)
    XCTAssertFalse(session.formattingState.isCheckbox)
}

@MainActor
private func assertMountedBlockquoteFormattingReplacesNumberedListSyntaxWithoutLayering(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "1. Task",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let insertionPoint = NSRange(location: 3, length: 0)
    textView.selectedRange = insertionPoint
    session.selectionDidChange(insertionPoint)

    session.applyFormatting(.blockquote)
    try await waitForMobileSessionText(session, expected: "> Task")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "> Task")
    XCTAssertEqual(session.currentText, "> Task")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 0))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 0))
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)
    XCTAssertTrue(session.formattingState.isBlockquote)
    XCTAssertFalse(session.formattingState.isNumberedList)
}

@MainActor
private func assertMountedParagraphFormattingRemovesCodeFenceWithoutLeavingDelimitersBehind(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "```swift\nlet x = 1\n```",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let insertionPoint = NSRange(location: 11, length: 0)
    textView.selectedRange = insertionPoint
    session.selectionDidChange(insertionPoint)

    session.applyFormatting(.paragraph)
    try await waitForMobileSessionText(session, expected: "let x = 1\n")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "let x = 1\n")
    XCTAssertEqual(session.currentText, "let x = 1\n")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 0))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 0))
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)
    XCTAssertFalse(session.formattingState.isCodeBlock)
}

@MainActor
private func assertMountedBulletFormattingTransformsEverySelectedLine(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "First\nSecond",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = NSRange(location: 0, length: (textView.text ?? "").count)
    textView.selectedRange = selection
    session.selectionDidChange(selection)

    session.applyFormatting(.bulletList)
    try await waitForMobileSessionText(session, expected: "- First\n- Second")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "- First\n- Second")
    XCTAssertEqual(session.currentText, "- First\n- Second")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 14))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 14))
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)
    XCTAssertTrue(session.formattingState.isBulletList)
}

@MainActor
private func assertMountedCodeBlockFormattingWrapsEntireSelectedLines(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "First\nSecond",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = NSRange(location: 1, length: 8)
    textView.selectedRange = selection
    session.selectionDidChange(selection)

    session.applyFormatting(.codeBlock)
    try await waitForMobileSessionText(session, expected: "```\nFirst\nSecond\n```")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "```\nFirst\nSecond\n```")
    XCTAssertEqual(session.currentText, "```\nFirst\nSecond\n```")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 4, length: 12))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 4, length: 12))
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)
}

@MainActor
private func assertNativeReturnAfterHeadingDropsToParagraphTypingAttributes(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "## Heading",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let insertionPoint = (textView.text ?? "").count
    textView.selectedRange = NSRange(location: insertionPoint, length: 0)
    session.selectionDidChange(NSRange(location: insertionPoint, length: 0))

    textView.insertText("\n")
    try await waitForMobileSessionText(session, expected: "## Heading\n")
    await pumpMobileHarness(harness)

    let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
    let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? UIColor)

    XCTAssertEqual(session.currentText, "## Heading\n")
    XCTAssertEqual(session.cursorPosition, NSRange(location: "## Heading\n".count, length: 0))
    XCTAssertEqual(typingFont.pointSize, expectedMobileBodyFontSize(), accuracy: 0.01)
    XCTAssertFalse(isBoldFont(typingFont))
    assertResolvedEqual(typingColor, UIColor.label)
}

@MainActor
private func assertSmartPasteNormalizesMultiParagraphPasteWithoutBreakingSelection(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "Lead\n\nTail",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = NSRange(location: 6, length: 4)
    let pasted = "## Pasted Heading\r\n\r\n\tBody paragraph"
    let expectedReplacement = "## Pasted Heading\n\n    Body paragraph"
    let expectedText = "Lead\n\n\(expectedReplacement)"
    let expectedSelection = NSRange(location: 6 + (expectedReplacement as NSString).length, length: 0)

    textView.selectedRange = selection
    session.selectionDidChange(selection)
    session.applyPastedText(pasted, mode: .smart)

    try await waitForMobileSessionText(session, expected: expectedText)
    await pumpMobileHarness(harness)

    let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
    let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? UIColor)

    XCTAssertEqual(textView.text, expectedText)
    XCTAssertEqual(session.currentText, expectedText)
    XCTAssertEqual(textView.selectedRange, expectedSelection)
    XCTAssertEqual(session.cursorPosition, expectedSelection)
    XCTAssertTrue(expectedText.contains("## Pasted Heading"))
    XCTAssertEqual(session.currentTransaction?.origin, .pasteOrDrop)
    XCTAssertEqual(typingFont.pointSize, expectedMobileBodyFontSize(), accuracy: 0.01)
    XCTAssertFalse(isBoldFont(typingFont))
    assertResolvedEqual(typingColor, UIColor.label)
}

@MainActor
private func assertRawPastePreservesBytesAndCursorPlacement(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let harness = try await makeMountedMobileHarness(
        text: "Lead ",
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let insertion = "\t**Raw**\u{00A0}Copy"
    let expectedText = "Lead \(insertion)"
    let expectedSelection = NSRange(location: (expectedText as NSString).length, length: 0)

    textView.selectedRange = NSRange(location: 5, length: 0)
    session.selectionDidChange(NSRange(location: 5, length: 0))
    session.applyPastedText(insertion, mode: .raw)

    try await waitForMobileSessionText(session, expected: expectedText)
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, expectedText)
    XCTAssertEqual(session.currentText, expectedText)
    XCTAssertEqual(textView.selectedRange, expectedSelection)
    XCTAssertEqual(session.cursorPosition, expectedSelection)
    XCTAssertTrue(expectedText.contains("\t**Raw**\u{00A0}Copy"))
    XCTAssertEqual(session.currentTransaction?.origin, .pasteOrDrop)
}

private func validAttributeLocation(_ preferred: Int, storageLength: Int) -> Int {
    guard storageLength > 0 else { return 0 }
    return min(max(preferred, 0), storageLength - 1)
}

private func expectedMobileBodyFontSize() -> CGFloat {
    UIFont.preferredFont(forTextStyle: .body).pointSize
}

private func assertResolvedEqual(
    _ color: UIColor,
    _ expected: UIColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let traitCollection = UITraitCollection(userInterfaceStyle: .light)
    let lhs = color.resolvedColor(with: traitCollection)
    let rhs = expected.resolvedColor(with: traitCollection)
    XCTAssertTrue(lhs.isEqual(rhs), "Expected \(lhs) to equal \(rhs)", file: file, line: line)
}
#endif
