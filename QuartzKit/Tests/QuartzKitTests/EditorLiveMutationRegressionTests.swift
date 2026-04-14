import XCTest
import SwiftUI
@testable import QuartzKit

#if canImport(AppKit)
import AppKit

@MainActor
final class EditorLiveMutationRegressionTests: XCTestCase {

    func testApplyExternalEditSynchronizesCursorSnapshotImmediately() async throws {
        let harness = try await makeMountedHarness(text: "Hello")
        let session = harness.session
        let textView = harness.textView
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        session.selectionDidChange(NSRange(location: 5, length: 0))

        session.applyExternalEdit(
            replacement: " world",
            range: NSRange(location: 5, length: 0),
            cursorAfter: NSRange(location: 11, length: 0),
            origin: .pasteOrDrop
        )

        XCTAssertEqual(textView.string, "Hello world")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 0))
        XCTAssertEqual(session.currentText, "Hello world")
        XCTAssertEqual(session.cursorPosition, NSRange(location: 11, length: 0))
        XCTAssertEqual(session.currentTransaction?.origin, .pasteOrDrop)
    }

    func testListContinuationPreservesSelectionAcrossLiveHighlighting() async throws {
        let harness = try await makeMountedHarness(text: "- item")
        let session = harness.session
        let textView = harness.textView
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        session.selectionDidChange(NSRange(location: 6, length: 0))

        let engine = MarkdownListContinuation()
        let result = try XCTUnwrap(
            engine.handleNewline(in: textView.string, cursorPosition: 6)
        )

        session.applyExternalEdit(
            replacement: result.insertionText,
            range: result.replacementRange,
            cursorAfter: NSRange(location: result.newCursorPosition, length: 0),
            origin: .listContinuation
        )

        XCTAssertEqual(textView.string, "- item\n- ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertEqual(session.currentText, "- item\n- ")
        XCTAssertEqual(session.cursorPosition, NSRange(location: 9, length: 0))
        XCTAssertEqual(session.currentTransaction?.origin, .listContinuation)

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        let spans = await highlighter.parse(textView.string)
        let selectionBeforeHighlight = textView.selectedRange()
        session.applyHighlightSpansForTesting(spans)

        XCTAssertEqual(textView.selectedRange(), selectionBeforeHighlight)
        XCTAssertEqual(session.cursorPosition, selectionBeforeHighlight)
    }

    func testProgrammaticEditKeepsMutationOriginThroughDelegateEcho() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        textView.setSelectedRange(NSRange(location: 6, length: 4))
        session.selectionDidChange(NSRange(location: 6, length: 4))

        session.applyExternalEdit(
            replacement: "**Beta**",
            range: NSRange(location: 6, length: 4),
            cursorAfter: NSRange(location: 10, length: 4),
            origin: .pasteOrDrop
        )

        XCTAssertEqual(textView.string, "Alpha **Beta**")
        XCTAssertEqual(session.currentText, "Alpha **Beta**")
        XCTAssertEqual(session.cursorPosition, NSRange(location: 10, length: 4))
        XCTAssertEqual(session.currentTransaction?.origin, .pasteOrDrop)
    }

    func testMountedProgrammaticEditUndoRedoRoundTripsContentAndInsertionPoint() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        textView.setSelectedRange(NSRange(location: 6, length: 4))
        session.selectionDidChange(NSRange(location: 6, length: 4))

        session.applyExternalEdit(
            replacement: "**Beta**",
            range: NSRange(location: 6, length: 4),
            cursorAfter: NSRange(location: 10, length: 4),
            origin: .pasteOrDrop
        )

        XCTAssertTrue(session.canUndo)

        session.undo()
        try await waitForSessionText(session, expected: "Alpha Beta")
        XCTAssertEqual(textView.string, "Alpha Beta")
        XCTAssertEqual(session.currentText, "Alpha Beta")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 10, length: 0))

        XCTAssertTrue(session.canRedo)

        session.redo()
        try await waitForSessionText(session, expected: "Alpha **Beta**")
        XCTAssertEqual(textView.string, "Alpha **Beta**")
        XCTAssertEqual(session.currentText, "Alpha **Beta**")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 14, length: 0))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 14, length: 0))
    }

    func testMountedBoldFormattingPreservesSelectionAcrossForcedHighlight() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        let selection = NSRange(location: 6, length: 4)
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        let formatter = MarkdownFormatter()
        let edit = try XCTUnwrap(
            formatter.surgicalEdit(.bold, in: session.currentText, selectedRange: selection)
        )
        let expectedText = ("Alpha Beta" as NSString).replacingCharacters(in: edit.range, with: edit.replacement)

        session.applyFormatting(.bold)
        try await waitForSessionText(session, expected: expectedText)
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "Alpha **Beta**")
        XCTAssertEqual(session.currentText, "Alpha **Beta**")
        XCTAssertEqual(textView.selectedRange(), edit.cursorAfter)
        XCTAssertEqual(session.cursorPosition, edit.cursorAfter)
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)

        let boldFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: edit.cursorAfter.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
    }

    func testMountedHeadingRoundTripRestoresParagraphTypingAttributes() async throws {
        let harness = try await makeMountedHarness(text: "Title")
        let session = harness.session
        let textView = harness.textView
        let insertionPoint = NSRange(location: textView.string.count, length: 0)
        textView.setSelectedRange(insertionPoint)
        session.selectionDidChange(insertionPoint)

        session.applyFormatting(.heading2)
        try await waitForSessionText(session, expected: "## Title")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "## Title")
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)

        session.applyFormatting(.paragraph)
        try await waitForSessionText(session, expected: "Title")
        await pumpMountedHarness(harness)

        let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? NSColor)

        XCTAssertEqual(textView.string, "Title")
        XCTAssertEqual(session.currentText, "Title")
        XCTAssertEqual(session.cursorPosition, textView.selectedRange())
        XCTAssertEqual(typingFont.pointSize, CGFloat(14), accuracy: 0.01)
        XCTAssertFalse(NSFontManager.shared.traits(of: typingFont).contains(.boldFontMask))
        XCTAssertEqual(typingColor, .labelColor)
    }

    func testNativeReturnAfterHeadingDropsToParagraphTypingAttributes() async throws {
        let harness = try await makeMountedHarness(text: "## Heading")
        let session = harness.session
        let textView = harness.textView
        let insertionPoint = textView.string.count
        textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
        session.selectionDidChange(NSRange(location: insertionPoint, length: 0))

        textView.insertNewline(nil)
        try await waitForSessionText(session, expected: "## Heading\n")

        let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? NSColor)

        XCTAssertEqual(session.currentText, "## Heading\n")
        XCTAssertEqual(session.cursorPosition, NSRange(location: "## Heading\n".count, length: 0))
        XCTAssertEqual(typingFont.pointSize, CGFloat(14), accuracy: 0.01)
        XCTAssertFalse(NSFontManager.shared.traits(of: typingFont).contains(.boldFontMask))
        XCTAssertEqual(typingColor, .labelColor)
    }

    func testMultiParagraphPastePreservesSelectionAndBodyTypingAfterHighlight() async throws {
        let harness = try await makeMountedHarness(text: "Lead\n\nTail")
        let session = harness.session
        let textView = harness.textView
        let selection = NSRange(location: 6, length: 4)
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        let replacement = "## Pasted Heading\n\nBody paragraph"
        let endSelection = NSRange(location: 6 + replacement.count, length: 0)

        session.applyExternalEdit(
            replacement: replacement,
            range: selection,
            cursorAfter: endSelection,
            origin: .pasteOrDrop
        )

        try await waitForSessionText(session, expected: "Lead\n\n## Pasted Heading\n\nBody paragraph")

        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        let spans = await highlighter.parse(textView.string)
        session.applyHighlightSpansForTesting(spans)

        let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? NSColor)

        XCTAssertEqual(textView.selectedRange(), endSelection)
        XCTAssertEqual(session.cursorPosition, endSelection)
        XCTAssertEqual(session.currentTransaction?.origin, .pasteOrDrop)
        XCTAssertEqual(typingFont.pointSize, CGFloat(14), accuracy: 0.01)
        XCTAssertFalse(NSFontManager.shared.traits(of: typingFont).contains(.boldFontMask))
        XCTAssertEqual(typingColor, .labelColor)
    }

    private func makeMountedHarness(text: String) async throws -> EditorHarness {
        let provider = MockVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/editor-live-mutation-regression-\(UUID().uuidString).md")
        let note = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: "Editor Regression"),
            body: text,
            isDirty: false
        )
        await provider.addNote(note)

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        await session.loadNote(at: url)

        let canvasSize = CGSize(width: 640, height: 320)
        let rootView = AnyView(
            ZStack {
            Color(nsColor: .textBackgroundColor)
            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: 1.0,
                editorFontFamily: .system,
                editorLineSpacing: 1.5,
                editorMaxWidth: 560,
                syntaxVisibilityMode: .full
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        )

        let hostingView = NSHostingView(rootView: rootView)
        let container = NSView(frame: NSRect(origin: .zero, size: canvasSize))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        window.contentView = container

        for _ in 0..<80 {
            window.displayIfNeeded()
            container.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()

            if let textView = session.activeTextView,
               textView.alphaValue == 1,
               textView.string == text,
               textView.textStorage?.length == (text as NSString).length {
                return EditorHarness(
                    session: session,
                    textView: textView,
                    window: window,
                    container: container,
                    hostingView: hostingView
                )
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for mounted editor harness to become ready")
        throw CancellationError()
    }

    private func waitForSessionText(
        _ session: EditorSession,
        expected: String
    ) async throws {
        for _ in 0..<80 {
            if session.currentText == expected,
               session.activeTextView?.string == expected {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for editor text to become \(expected.debugDescription)")
    }

    private func pumpMountedHarness(_ harness: EditorHarness, iterations: Int = 12) async {
        for _ in 0..<iterations {
            harness.window.displayIfNeeded()
            harness.container.layoutSubtreeIfNeeded()
            harness.hostingView.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct EditorHarness {
    let session: EditorSession
    let textView: NSTextView
    let window: NSWindow
    let container: NSView
    let hostingView: NSHostingView<AnyView>
}
#endif
