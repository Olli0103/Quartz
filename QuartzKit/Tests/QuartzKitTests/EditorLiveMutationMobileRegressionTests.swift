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

    func testFormattingInvocationSourcesProduceMatchingResultsForSharedShortcutActions() async throws {
        try await assertFormattingInvocationSourcesProduceMatchingResults(for: .phone)
    }

    func testToolbarFormattingPrefersLiveSelectionOverStaleCursorSnapshot() async throws {
        try await assertToolbarFormattingPrefersLiveSelectionOverStaleCursorSnapshot(for: .phone)
    }

    func testToolbarFormattingUsesCollapsedSelectionAfterResponderCommitsCaretMove() async throws {
        try await assertToolbarFormattingUsesCollapsedSelectionAfterResponderCommitsCaretMove(for: .phone)
    }

    func testToolbarSelectionMatrixPreservesHeadingAcrossAllActions() async throws {
        try await assertToolbarSelectionMatrixPreservesHeadingAcrossAllActions(for: .phone)
    }

    func testToolbarCursorMatrixUsesCurrentInsertionPointAcrossBlockActions() async throws {
        try await assertToolbarCursorMatrixUsesCurrentInsertionPointAcrossBlockActions(for: .phone)
    }

    func testToolbarTableInsertionUsesCurrentCursorAndPreservesTableRendering() async throws {
        try await assertToolbarTableInsertionUsesCurrentCursorAndPreservesTableRendering(for: .phone)
    }

    func testMountedLinkFormattingSelectsURLPlaceholder() async throws {
        try await assertMountedLinkFormattingSelectsURLPlaceholder(for: .phone)
    }

    func testMountedLinkFormattingOnExistingMarkdownLinkKeepsTextAndSelectsURL() async throws {
        try await assertMountedLinkFormattingOnExistingMarkdownLinkKeepsTextAndSelectsURL(for: .phone)
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

    func testMountedTableTabSelectsNextCellWithoutMutatingMarkdown() async throws {
        try await assertMountedTableTabSelectsNextCellWithoutMutatingMarkdown(for: .phone)
    }

    func testMountedTableTabAtLastCellInsertsNewRow() async throws {
        try await assertMountedTableTabAtLastCellInsertsNewRow(for: .phone)
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

    func testFormattingInvocationSourcesProduceMatchingResultsForSharedShortcutActions() async throws {
        try await assertFormattingInvocationSourcesProduceMatchingResults(for: .pad)
    }

    func testToolbarFormattingPrefersLiveSelectionOverStaleCursorSnapshot() async throws {
        try await assertToolbarFormattingPrefersLiveSelectionOverStaleCursorSnapshot(for: .pad)
    }

    func testToolbarFormattingUsesCollapsedSelectionAfterResponderCommitsCaretMove() async throws {
        try await assertToolbarFormattingUsesCollapsedSelectionAfterResponderCommitsCaretMove(for: .pad)
    }

    func testToolbarSelectionMatrixPreservesHeadingAcrossAllActions() async throws {
        try await assertToolbarSelectionMatrixPreservesHeadingAcrossAllActions(for: .pad)
    }

    func testToolbarCursorMatrixUsesCurrentInsertionPointAcrossBlockActions() async throws {
        try await assertToolbarCursorMatrixUsesCurrentInsertionPointAcrossBlockActions(for: .pad)
    }

    func testToolbarTableInsertionUsesCurrentCursorAndPreservesTableRendering() async throws {
        try await assertToolbarTableInsertionUsesCurrentCursorAndPreservesTableRendering(for: .pad)
    }

    func testMountedLinkFormattingSelectsURLPlaceholder() async throws {
        try await assertMountedLinkFormattingSelectsURLPlaceholder(for: .pad)
    }

    func testMountedLinkFormattingOnExistingMarkdownLinkKeepsTextAndSelectsURL() async throws {
        try await assertMountedLinkFormattingOnExistingMarkdownLinkKeepsTextAndSelectsURL(for: .pad)
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

    func testMountedTableTabSelectsNextCellWithoutMutatingMarkdown() async throws {
        try await assertMountedTableTabSelectsNextCellWithoutMutatingMarkdown(for: .pad)
    }

    func testMountedTableTabAtLastCellInsertsNewRow() async throws {
        try await assertMountedTableTabAtLastCellInsertsNewRow(for: .pad)
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
private func assertFormattingInvocationSourcesProduceMatchingResults(
    for target: MobileEditorTargetDevice
) async throws {
    try requireMobileDevice(target)

    let actions: [FormattingAction] = [.bold, .italic, .strikethrough, .heading2, .code, .codeBlock, .link, .blockquote]
    let sources: [EditorSession.FormattingInvocationSource] = [.hardwareKeyboard, .toolbar]
    let initialText = "Alpha Beta"
    let staleSelection = NSRange(location: 0, length: 5)
    let liveSelection = NSRange(location: 6, length: 4)

    for action in actions {
        var canonicalText: String?
        var canonicalSelection: NSRange?
        var canonicalCanUndo: Bool?

        for source in sources {
            let harness = try await makeMountedMobileHarness(
                text: initialText,
                target: target,
                syntaxVisibilityMode: .hiddenUntilCaret
            )
            let session = harness.session
            let textView = harness.textView

            if source == .toolbar {
                textView.selectedRange = staleSelection
                session.selectionDidChange(staleSelection)
            }

            textView.selectedRange = liveSelection
            session.selectionDidChange(liveSelection)

            session.handleFormattingAction(action, source: source)
            await pumpMobileHarness(harness)

            let formattedText = session.currentText
            let formattedSelection = session.cursorPosition
            let canUndo = session.canUndo

            if let canonicalText, let canonicalSelection, let canonicalCanUndo {
                XCTAssertEqual(formattedText, canonicalText, "Action \(action.rawValue) must match for \(source.rawValue)")
                XCTAssertEqual(formattedSelection, canonicalSelection, "Selection for \(action.rawValue) must match for \(source.rawValue)")
                XCTAssertEqual(canUndo, canonicalCanUndo, "Undo availability for \(action.rawValue) must match for \(source.rawValue)")
            } else {
                canonicalText = formattedText
                canonicalSelection = formattedSelection
                canonicalCanUndo = canUndo
            }

            XCTAssertTrue(session.canUndo, "Formatting action \(action.rawValue) must register undo for \(source.rawValue)")

            session.undo()
            try await waitForMobileSessionText(session, expected: initialText)
            XCTAssertEqual(session.currentText, initialText)

            session.redo()
            try await waitForMobileSessionText(session, expected: formattedText)
            XCTAssertEqual(session.currentText, formattedText)
        }
    }
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
private func assertToolbarFormattingPrefersLiveSelectionOverStaleCursorSnapshot(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let text = "# Welcome to Quartz Notes\n\nHow are you?"
    let harness = try await makeMountedMobileHarness(
        text: text,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let staleSelection = (text as NSString).range(of: "Welcome")
    let liveSelection = (text as NSString).range(of: "How are you?")

    textView.selectedRange = staleSelection
    session.selectionDidChange(staleSelection)

    textView.selectedRange = liveSelection
    session.applyToolbarFormatting(.italic)
    await pumpMobileHarness(harness)

    let expectedText = "# Welcome to Quartz Notes\n\n*How are you?*"
    XCTAssertEqual(textView.text, expectedText)
    XCTAssertEqual(session.currentText, expectedText)
    XCTAssertTrue(session.formattingState.isItalic)

    let italicLocation = (expectedText as NSString).range(of: "How are you?").location
    let italicFont = try XCTUnwrap(
        textView.textStorage.attribute(.font, at: italicLocation, effectiveRange: nil) as? UIFont
    )
    XCTAssertTrue(isItalicFont(italicFont))
    assertVisibleTextUsesPrimaryColor(in: textView, substring: "Welcome to Quartz Notes")
}

@MainActor
private func assertToolbarFormattingUsesCollapsedSelectionAfterResponderCommitsCaretMove(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let text = "# Welcome to Quartz Notes\n\nHow are you?"
    let harness = try await makeMountedMobileHarness(
        text: text,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = (text as NSString).range(of: "How are you?")

    textView.selectedRange = selection
    session.selectionDidChange(selection)

    let collapsedSelection = NSRange(location: selection.location + selection.length, length: 0)
    textView.selectedRange = collapsedSelection
    textView.resignFirstResponder()

    session.applyToolbarFormatting(.bold)
    await pumpMobileHarness(harness)

    let expected = expectedMobileToolbarFormattingResult(
        action: .bold,
        text: text,
        selection: collapsedSelection
    )
    XCTAssertEqual(textView.text, expected.text)
    XCTAssertEqual(session.currentText, expected.text)
    XCTAssertEqual(textView.selectedRange, expected.newSelection)
    XCTAssertEqual(session.cursorPosition, expected.newSelection)
    XCTAssertTrue(textView.isFirstResponder)
    assertVisibleTextUsesPrimaryColor(in: textView, substring: "Welcome to Quartz Notes")
}

@MainActor
private func assertToolbarSelectionMatrixPreservesHeadingAcrossAllActions(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let text = "# Welcome to Quartz Notes\n\nHow are you?"
    let staleSelection = (text as NSString).range(of: "Welcome")
    let liveSelection = (text as NSString).range(of: "How are you?")

    for action in FormattingAction.allCases {
        let harness = try await makeMountedMobileHarness(
            text: text,
            target: target,
            syntaxVisibilityMode: .hiddenUntilCaret
        )
        let session = harness.session
        let textView = harness.textView

        textView.selectedRange = staleSelection
        session.selectionDidChange(staleSelection)

        textView.selectedRange = liveSelection
        let expected = expectedMobileToolbarFormattingResult(
            action: action,
            text: text,
            selection: liveSelection
        )

        session.applyToolbarFormatting(action)
        try await waitForMobileSessionText(session, expected: expected.text)
        await pumpMobileHarness(harness)

        XCTAssertEqual(textView.text, expected.text, "Action \(action.rawValue) must only format the live selection")
        XCTAssertEqual(session.currentText, expected.text, "Action \(action.rawValue) must keep session text in sync")
        XCTAssertEqual(textView.selectedRange, expected.newSelection, "Action \(action.rawValue) must restore the expected selection")
        XCTAssertEqual(session.cursorPosition, expected.newSelection, "Action \(action.rawValue) must keep the cursor snapshot aligned")

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes",
            context: action.rawValue
        )
        if action == .table {
            assertTableRowStylesRendered(in: textView)
        }
    }
}

@MainActor
private func assertToolbarCursorMatrixUsesCurrentInsertionPointAcrossBlockActions(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let text = "# Welcome to Quartz Notes\n\nHow are you?"
    let staleSelection = (text as NSString).range(of: "Welcome")
    let liveCursor = NSRange(location: (text as NSString).range(of: "How are you?").location + 2, length: 0)
    let actions: [FormattingAction] = [
        .heading, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
        .paragraph, .bulletList, .numberedList, .checkbox, .blockquote, .codeBlock, .mermaid
    ]

    for action in actions {
        let harness = try await makeMountedMobileHarness(
            text: text,
            target: target,
            syntaxVisibilityMode: .hiddenUntilCaret
        )
        let session = harness.session
        let textView = harness.textView

        textView.selectedRange = staleSelection
        session.selectionDidChange(staleSelection)

        textView.selectedRange = liveCursor
        textView.resignFirstResponder()
        let expected = expectedMobileToolbarFormattingResult(
            action: action,
            text: text,
            selection: liveCursor
        )

        session.applyToolbarFormatting(action)
        try await waitForMobileSessionText(session, expected: expected.text)
        await pumpMobileHarness(harness)

        XCTAssertEqual(textView.text, expected.text, "Action \(action.rawValue) must use the live cursor position")
        XCTAssertEqual(session.currentText, expected.text, "Action \(action.rawValue) must keep session text in sync")
        XCTAssertEqual(textView.selectedRange, expected.newSelection, "Action \(action.rawValue) must restore the expected cursor/selection")
        XCTAssertEqual(session.cursorPosition, expected.newSelection, "Action \(action.rawValue) must keep the cursor snapshot aligned")

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes",
            context: action.rawValue
        )
    }
}

@MainActor
private func assertToolbarTableInsertionUsesCurrentCursorAndPreservesTableRendering(for target: MobileEditorTargetDevice) async throws {
    try requireMobileDevice(target)

    let text = "# Welcome to Quartz Notes\n\nHow are you?"
    let harness = try await makeMountedMobileHarness(
        text: text,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let staleSelection = (text as NSString).range(of: "Welcome")
    let liveCursor = NSRange(location: (text as NSString).range(of: "How are you?").location + 2, length: 0)

    textView.selectedRange = staleSelection
    session.selectionDidChange(staleSelection)

    textView.selectedRange = liveCursor
    textView.resignFirstResponder()
    let expected = expectedMobileToolbarFormattingResult(
        action: .table,
        text: text,
        selection: liveCursor
    )

    session.applyToolbarFormatting(.table)
    try await waitForMobileSessionText(session, expected: expected.text)
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, expected.text)
    XCTAssertEqual(session.currentText, expected.text)
    XCTAssertEqual(textView.selectedRange, expected.newSelection)
    XCTAssertEqual(session.cursorPosition, expected.newSelection)

    assertVisibleTextUsesPrimaryColor(
        in: textView,
        substring: "Welcome to Quartz Notes",
        context: "table"
    )
    assertTableRowStylesRendered(in: textView)
}

@MainActor
private func assertMountedLinkFormattingSelectsURLPlaceholder(for target: MobileEditorTargetDevice) async throws {
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

    session.applyFormatting(.link)
    try await waitForMobileSessionText(session, expected: "Alpha [Beta](url)")
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, "Alpha [Beta](url)")
    XCTAssertEqual(session.currentText, "Alpha [Beta](url)")
    XCTAssertEqual(textView.selectedRange, NSRange(location: 13, length: 3))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 13, length: 3))
    XCTAssertEqual(session.currentTransaction?.origin, .formatting)
}

@MainActor
private func assertMountedLinkFormattingOnExistingMarkdownLinkKeepsTextAndSelectsURL(
    for target: MobileEditorTargetDevice
) async throws {
    try requireMobileDevice(target)

    let text = "Alpha [Beta](url) Gamma"
    let harness = try await makeMountedMobileHarness(
        text: text,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let selection = NSRange(location: 8, length: 0)
    textView.selectedRange = selection
    session.selectionDidChange(selection)

    session.applyFormatting(.link)
    await pumpMobileHarness(harness)

    XCTAssertEqual(textView.text, text)
    XCTAssertEqual(session.currentText, text)
    XCTAssertEqual(textView.selectedRange, NSRange(location: 13, length: 3))
    XCTAssertEqual(session.cursorPosition, NSRange(location: 13, length: 3))
    XCTAssertNil(session.currentTransaction)
    XCTAssertFalse(session.isDirty)
}

@MainActor
private func assertMountedTableTabSelectsNextCellWithoutMutatingMarkdown(
    for target: MobileEditorTargetDevice
) async throws {
    try requireMobileDevice(target)

    let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
    let harness = try await makeMountedMobileHarness(
        text: text,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let aLocation = (text as NSString).range(of: "A").location
    let delegate = try XCTUnwrap(textView.delegate)
    textView.selectedRange = NSRange(location: aLocation, length: 0)
    session.selectionDidChange(NSRange(location: aLocation, length: 0))

    let shouldChange = delegate.textView?(
        textView,
        shouldChangeTextIn: NSRange(location: aLocation, length: 0),
        replacementText: "\t"
    )
    await pumpMobileHarness(harness)

    XCTAssertEqual(shouldChange, false)
    XCTAssertEqual(textView.text, text)
    XCTAssertEqual(session.currentText, text)
    XCTAssertEqual(selectedString(in: textView), "B")
    XCTAssertNil(session.currentTransaction)
}

@MainActor
private func assertMountedTableTabAtLastCellInsertsNewRow(
    for target: MobileEditorTargetDevice
) async throws {
    try requireMobileDevice(target)

    let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
    let navigation = MarkdownTableNavigation()
    let lastCellLocation = (text as NSString).range(of: "2").location
    let expectedNavigation = try XCTUnwrap(
        navigation.handleTab(in: text, cursorPosition: lastCellLocation, isShiftTab: false)
    )
    let expectedInsertion = try XCTUnwrap(expectedNavigation.newRowInsertion)
    let expectedText = text + expectedInsertion.rowText

    let harness = try await makeMountedMobileHarness(
        text: text,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret
    )
    let session = harness.session
    let textView = harness.textView
    let delegate = try XCTUnwrap(textView.delegate)
    textView.selectedRange = NSRange(location: lastCellLocation, length: 0)
    session.selectionDidChange(NSRange(location: lastCellLocation, length: 0))

    let shouldChange = delegate.textView?(
        textView,
        shouldChangeTextIn: NSRange(location: lastCellLocation, length: 0),
        replacementText: "\t"
    )
    try await waitForMobileSessionText(session, expected: expectedText)
    await pumpMobileHarness(harness)

    XCTAssertEqual(shouldChange, false)
    XCTAssertEqual(textView.text, expectedText)
    XCTAssertEqual(session.currentText, expectedText)
    XCTAssertEqual(textView.selectedRange, expectedNavigation.selectionRange)
    XCTAssertEqual(session.cursorPosition, expectedNavigation.selectionRange)
    XCTAssertEqual(session.currentTransaction?.origin, .tableNavigation)
}

@MainActor
private func selectedString(in textView: UITextView) -> String {
    let range = textView.selectedRange
    guard range.length > 0 else { return "" }
    return ((textView.text ?? "") as NSString).substring(with: range)
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

private func isItalicFont(_ font: UIFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.traitItalic)
}

@MainActor
private func assertVisibleTextUsesPrimaryColor(
    in textView: UITextView,
    substring: String,
    context: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let nsText = (textView.text ?? "") as NSString
    let range = nsText.range(of: substring)
    XCTAssertNotEqual(range.location, NSNotFound, file: file, line: line)

    for offset in 0..<range.length {
        let location = range.location + offset
        let scalar = nsText.substring(with: NSRange(location: location, length: 1))
        if scalar == " " { continue }
        guard let color = textView.textStorage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor else {
            XCTFail("Expected foreground color at location \(location)", file: file, line: line)
            return
        }
        assertResolvedEqual(
            color,
            UIColor.label,
            message: "Visible heading text leaked styling in context \(context ?? "unknown") at character \(scalar)",
            file: file,
            line: line
        )
    }
}

private func expectedMobileToolbarFormattingResult(
    action: FormattingAction,
    text: String,
    selection: NSRange
) -> (text: String, newSelection: NSRange) {
    let spans = MarkdownASTHighlighter.parseImmediately(
        text,
        baseFontSize: expectedMobileBodyFontSize(),
        fontFamily: EditorTypography.defaultFontFamily,
        vaultRootURL: nil,
        noteURL: nil
    )
    let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: spans)
    let formatter = MarkdownFormatter()
    return formatter.apply(
        action,
        to: text,
        selectedRange: selection,
        semanticDocument: semanticDocument
    )
}

@MainActor
private func assertTableRowStylesRendered(in textView: UITextView) {
    var foundTableRowStyle = false
    for location in 0..<textView.textStorage.length {
        if textView.textStorage.attribute(.quartzTableRowStyle, at: location, effectiveRange: nil) != nil {
            foundTableRowStyle = true
            break
        }
    }

    XCTAssertTrue(foundTableRowStyle, "Inserted table must produce rendered table row styles")
}

private func expectedMobileBodyFontSize() -> CGFloat {
    UIFont.preferredFont(forTextStyle: .body).pointSize
}

private func assertResolvedEqual(
    _ color: UIColor,
    _ expected: UIColor,
    message: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let traitCollection = UITraitCollection(userInterfaceStyle: .light)
    let lhs = color.resolvedColor(with: traitCollection)
    let rhs = expected.resolvedColor(with: traitCollection)
    XCTAssertTrue(lhs.isEqual(rhs), message ?? "Expected \(lhs) to equal \(rhs)", file: file, line: line)
}
#endif
