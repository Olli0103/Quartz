import XCTest
import SwiftUI
@testable import QuartzKit

#if canImport(AppKit)
import AppKit

@MainActor
final class EditorLiveMutationRegressionTests: XCTestCase {

    func testFormattingInvocationSourcesProduceMatchingResultsForSharedShortcutActions() async throws {
        let actions: [FormattingAction] = [
            .bold, .italic, .strikethrough, .heading2, .code, .codeBlock, .link, .blockquote
        ]
        let sources: [EditorSession.FormattingInvocationSource] = [
            .commandMenu, .hardwareKeyboard, .toolbar
        ]
        let initialText = "Alpha Beta"
        let staleSelection = NSRange(location: 0, length: 5)
        let liveSelection = NSRange(location: 6, length: 4)

        for action in actions {
            var canonicalText: String?
            var canonicalSelection: NSRange?
            var canonicalCanUndo: Bool?

            for source in sources {
                let harness = try await makeMountedHarness(text: initialText)
                let session = harness.session
                let textView = harness.textView

                if source == .toolbar {
                    textView.setSelectedRange(staleSelection)
                    session.selectionDidChange(staleSelection)
                }

                textView.setSelectedRange(liveSelection)
                session.selectionDidChange(liveSelection)

                session.handleFormattingAction(action, source: source)
                await pumpMountedHarness(harness)

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
                try await waitForSessionText(session, expected: initialText)
                XCTAssertEqual(session.currentText, initialText)

                session.redo()
                try await waitForSessionText(session, expected: formattedText)
                XCTAssertEqual(session.currentText, formattedText)
            }
        }
    }

    func testToolbarFormattingRestoresMacFirstResponderFromSelectionSnapshot() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        let window = harness.window
        let selection = NSRange(location: 6, length: 4)

        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.selectionOwnerWillResignFirstResponder(with: selection)
        window.makeFirstResponder(nil)

        session.handleFormattingAction(.bold, source: .toolbar)
        await pumpMountedHarness(harness)

        XCTAssertTrue(window.firstResponder === textView, "Toolbar formatting must restore the editor as first responder on macOS")
        XCTAssertEqual(textView.selectedRange(), session.cursorPosition, "Toolbar formatting must keep native selection and snapshot aligned")
        XCTAssertEqual(session.currentText, "Alpha **Beta**")
    }

    func testCommandMenuFormattingKeepsMacFirstResponderAndSelectionStable() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        let window = harness.window
        let selection = NSRange(location: 6, length: 4)

        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.handleFormattingAction(.bold, source: .commandMenu)
        await pumpMountedHarness(harness)

        XCTAssertTrue(window.firstResponder === textView, "Command formatting must leave the editor as first responder on macOS")
        XCTAssertEqual(textView.selectedRange(), session.cursorPosition, "Command formatting must keep native selection and snapshot aligned")
        XCTAssertEqual(session.currentText, "Alpha **Beta**")
    }

    func testNoteSwitchingRestoresSelectionForPreviouslyVisitedNote() async throws {
        let provider = MockVaultProvider()
        let noteAURL = URL(fileURLWithPath: "/tmp/editor-live-mutation-note-a-\(UUID().uuidString).md")
        let noteBURL = URL(fileURLWithPath: "/tmp/editor-live-mutation-note-b-\(UUID().uuidString).md")
        await provider.addNote(NoteDocument(
            fileURL: noteAURL,
            frontmatter: Frontmatter(title: "A"),
            body: "First note body",
            isDirty: false
        ))
        await provider.addNote(NoteDocument(
            fileURL: noteBURL,
            frontmatter: Frontmatter(title: "B"),
            body: "Second note body",
            isDirty: false
        ))

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        await session.loadNote(at: noteAURL)

        let harness = try await mountHarness(session: session, expectedText: "First note body")
        let textView = harness.textView
        let originalSelection = NSRange(location: 6, length: 4)

        textView.setSelectedRange(originalSelection)
        session.selectionDidChange(originalSelection)

        await session.loadNote(at: noteBURL)
        await pumpMountedHarness(harness)
        XCTAssertEqual(session.currentText, "Second note body")

        await session.loadNote(at: noteAURL)
        await pumpMountedHarness(harness)

        XCTAssertEqual(session.currentText, "First note body")
        XCTAssertEqual(textView.selectedRange(), originalSelection, "Switching back to a visited note must restore its previous selection")
        XCTAssertEqual(session.cursorPosition, originalSelection)
    }

    func testInNoteFindNavigationSelectsMatchesDeterministically() async throws {
        let text = "Alpha Beta Alpha"
        let harness = try await makeMountedHarness(text: text)
        let session = harness.session
        let textView = harness.textView

        session.presentInNoteSearch()
        session.setInNoteSearchQuery("Alpha")

        let first = (text as NSString).range(of: "Alpha")
        let second = (text as NSString).range(of: "Alpha", options: [], range: NSRange(location: 1, length: (text as NSString).length - 1))

        XCTAssertEqual(session.inNoteSearch.matchCount, 2)
        XCTAssertEqual(session.inNoteSearch.currentMatchDisplayIndex, 1)
        XCTAssertEqual(textView.selectedRange(), first)

        session.findNextInNote()
        XCTAssertEqual(session.inNoteSearch.currentMatchDisplayIndex, 2)
        XCTAssertEqual(textView.selectedRange(), second)

        session.findNextInNote()
        XCTAssertEqual(session.inNoteSearch.currentMatchDisplayIndex, 1)
        XCTAssertEqual(textView.selectedRange(), first)

        session.findPreviousInNote()
        XCTAssertEqual(session.inNoteSearch.currentMatchDisplayIndex, 2)
        XCTAssertEqual(textView.selectedRange(), second)
    }

    func testInNoteReplaceCurrentUndoRedoRoundTripsContent() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta Alpha")
        let session = harness.session
        let textView = harness.textView

        session.presentInNoteSearch()
        session.setInNoteSearchQuery("Alpha")
        session.setInNoteReplaceText("Omega")
        session.replaceCurrentInNote()

        try await waitForSessionText(session, expected: "Omega Beta Alpha")
        XCTAssertEqual(textView.string, "Omega Beta Alpha")
        XCTAssertEqual(session.inNoteSearch.matchCount, 1)
        XCTAssertEqual(session.inNoteSearch.currentMatchDisplayIndex, 1)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 5))

        session.undo()
        try await waitForSessionText(session, expected: "Alpha Beta Alpha")
        XCTAssertEqual(session.currentText, "Alpha Beta Alpha")

        session.redo()
        try await waitForSessionText(session, expected: "Omega Beta Alpha")
        XCTAssertEqual(session.currentText, "Omega Beta Alpha")
    }

    func testInNoteReplaceAllUndoRedoRoundTripsContent() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta Alpha")
        let session = harness.session

        session.presentInNoteSearch()
        session.setInNoteSearchQuery("Alpha")
        session.setInNoteReplaceText("Omega")
        session.replaceAllInNote()

        try await waitForSessionText(session, expected: "Omega Beta Omega")
        XCTAssertEqual(session.currentText, "Omega Beta Omega")
        XCTAssertEqual(session.inNoteSearch.matchCount, 0)

        session.undo()
        try await waitForSessionText(session, expected: "Alpha Beta Alpha")
        XCTAssertEqual(session.currentText, "Alpha Beta Alpha")

        session.redo()
        try await waitForSessionText(session, expected: "Omega Beta Omega")
        XCTAssertEqual(session.currentText, "Omega Beta Omega")
    }

    func testInNoteSearchStaysScopedToActiveNoteWhileOpen() async throws {
        let provider = MockVaultProvider()
        let noteAURL = URL(fileURLWithPath: "/tmp/editor-search-scope-note-a-\(UUID().uuidString).md")
        let noteBURL = URL(fileURLWithPath: "/tmp/editor-search-scope-note-b-\(UUID().uuidString).md")
        await provider.addNote(NoteDocument(
            fileURL: noteAURL,
            frontmatter: Frontmatter(title: "A"),
            body: "Alpha Beta Alpha",
            isDirty: false
        ))
        await provider.addNote(NoteDocument(
            fileURL: noteBURL,
            frontmatter: Frontmatter(title: "B"),
            body: "Gamma only",
            isDirty: false
        ))

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        await session.loadNote(at: noteAURL)

        let harness = try await mountHarness(session: session, expectedText: "Alpha Beta Alpha")
        session.presentInNoteSearch()
        session.setInNoteSearchQuery("Alpha")
        session.setInNoteReplaceText("Omega")
        session.replaceAllInNote()

        try await waitForSessionText(session, expected: "Omega Beta Omega")
        await session.loadNote(at: noteBURL)
        await pumpMountedHarness(harness)

        XCTAssertTrue(session.inNoteSearch.isPresented)
        XCTAssertEqual(session.currentText, "Gamma only")
        XCTAssertEqual(session.inNoteSearch.matchCount, 0)

        let noteB = try await provider.readNote(at: noteBURL)
        XCTAssertEqual(noteB.body, "Gamma only", "Find/replace must not mutate notes other than the currently loaded note")

        await session.loadNote(at: noteAURL)
        await pumpMountedHarness(harness)
        XCTAssertEqual(session.currentText, "Omega Beta Omega", "Active-note replace-all may persist the edited note, but it must stay scoped to that note only")
    }

    func testDismissingInNoteSearchRestoresMacEditorFirstResponder() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        let window = harness.window

        XCTAssertTrue(window.makeFirstResponder(textView))
        session.presentInNoteSearch()
        session.setInNoteSearchQuery("Beta")
        session.dismissInNoteSearch()

        XCTAssertTrue(window.firstResponder === textView)
        XCTAssertEqual(session.cursorPosition, textView.selectedRange())
    }

    func testInNoteReplaceNoOpsWhenQueryIsEmptyOrNoMatchesExist() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session

        session.presentInNoteSearch()
        session.setInNoteReplaceText("Omega")
        session.replaceCurrentInNote()
        XCTAssertEqual(session.currentText, "Alpha Beta")

        session.setInNoteSearchQuery("Missing")
        session.replaceCurrentInNote()
        session.replaceAllInNote()
        XCTAssertEqual(session.currentText, "Alpha Beta")
        XCTAssertEqual(session.inNoteSearch.matchCount, 0)
    }

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

    func testMountedItalicFormattingImmediatelyStylesSelectionWithoutHeadingDrift() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let selection = (text as NSString).range(of: "How are you?")
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.italic)

        XCTAssertEqual(textView.string, "# Welcome to Quartz Notes\n\n*How are you?*")
        XCTAssertEqual(session.currentText, "# Welcome to Quartz Notes\n\n*How are you?*")
        XCTAssertTrue(session.formattingState.isItalic)

        let italicLocation = ("# Welcome to Quartz Notes\n\n*How are you?*" as NSString).range(of: "How are you?").location
        let italicFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: italicLocation, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes",
            context: "italic"
        )
    }

    func testMountedBoldFormattingImmediatelyStylesSelectionWithoutHeadingDrift() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let selection = (text as NSString).range(of: "How are you?")
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.bold)

        XCTAssertEqual(textView.string, "# Welcome to Quartz Notes\n\n**How are you?**")
        XCTAssertEqual(session.currentText, "# Welcome to Quartz Notes\n\n**How are you?**")
        XCTAssertTrue(session.formattingState.isBold)

        let boldLocation = ("# Welcome to Quartz Notes\n\n**How are you?**" as NSString).range(of: "How are you?").location
        let boldFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: boldLocation, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes"
        )
    }

    func testMountedLinkFormattingSelectsURLPlaceholder() async throws {
        let harness = try await makeMountedHarness(text: "Alpha Beta")
        let session = harness.session
        let textView = harness.textView
        let selection = NSRange(location: 6, length: 4)
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.link)
        try await waitForSessionText(session, expected: "Alpha [Beta](url)")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "Alpha [Beta](url)")
        XCTAssertEqual(session.currentText, "Alpha [Beta](url)")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 13, length: 3))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 13, length: 3))
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)
    }

    func testMountedLinkFormattingOnExistingMarkdownLinkKeepsTextAndSelectsURL() async throws {
        let text = "Alpha [Beta](url) Gamma"
        let harness = try await makeMountedHarness(text: text)
        let session = harness.session
        let textView = harness.textView
        let selection = NSRange(location: 8, length: 0)
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.link)
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(session.currentText, text)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 13, length: 3))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 13, length: 3))
        XCTAssertNil(session.currentTransaction)
        XCTAssertFalse(session.isDirty)
    }

    func testMountedLinkFormattingImmediatelyStylesSelectionWithoutHeadingDrift() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let selection = (text as NSString).range(of: "How are you?")
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.link)

        let expectedText = "# Welcome to Quartz Notes\n\n[How are you?](url)"
        let expectedURLSelection = (expectedText as NSString).range(of: "url")
        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(session.currentText, expectedText)
        XCTAssertEqual(textView.selectedRange(), expectedURLSelection)
        XCTAssertEqual(session.cursorPosition, expectedURLSelection)

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes"
        )

        let linkLabelLocation = (expectedText as NSString).range(of: "How are you?").location
        let linkLabelColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: linkLabelLocation, effectiveRange: nil) as? NSColor
        )
        let normalizedLinkColor = try XCTUnwrap(normalizedColor(linkLabelColor))
        XCTAssertGreaterThan(normalizedLinkColor.blueComponent, 0.2)
    }

    func testToolbarFormattingPrefersLiveSelectionOverStaleCursorSnapshot() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let staleSelection = (text as NSString).range(of: "Welcome")
        let liveSelection = (text as NSString).range(of: "How are you?")

        textView.setSelectedRange(staleSelection)
        session.selectionDidChange(staleSelection)

        textView.setSelectedRange(liveSelection)
        session.applyToolbarFormatting(.italic)

        XCTAssertEqual(textView.string, "# Welcome to Quartz Notes\n\n*How are you?*")
        XCTAssertEqual(session.currentText, "# Welcome to Quartz Notes\n\n*How are you?*")
        XCTAssertTrue(session.formattingState.isItalic)

        let italicLocation = ("# Welcome to Quartz Notes\n\n*How are you?*" as NSString).range(of: "How are you?").location
        let italicFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: italicLocation, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes"
        )
    }

    func testToolbarFormattingUsesCollapsedSelectionAfterResponderCommitsCaretMove() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let selection = (text as NSString).range(of: "How are you?")

        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        let collapsedSelection = NSRange(location: selection.location + selection.length, length: 0)
        textView.setSelectedRange(collapsedSelection)
        harness.window.makeFirstResponder(nil)

        session.applyToolbarFormatting(.bold)

        let expected = expectedToolbarFormattingResult(
            action: .bold,
            text: text,
            selection: collapsedSelection
        )
        XCTAssertEqual(textView.string, expected.text)
        XCTAssertEqual(session.currentText, expected.text)
        XCTAssertEqual(textView.selectedRange(), expected.newSelection)
        XCTAssertEqual(session.cursorPosition, expected.newSelection)
        XCTAssertTrue(harness.window.firstResponder === textView)

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes"
        )
    }

    func testToolbarSelectionMatrixPreservesHeadingAcrossAllActions() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let staleSelection = (text as NSString).range(of: "Welcome")
        let liveSelection = (text as NSString).range(of: "How are you?")

        for action in FormattingAction.allCases {
            let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
            let session = harness.session
            let textView = harness.textView

            textView.setSelectedRange(staleSelection)
            session.selectionDidChange(staleSelection)

            textView.setSelectedRange(liveSelection)
            let expected = expectedToolbarFormattingResult(
                action: action,
                text: text,
                selection: liveSelection
            )

            session.applyToolbarFormatting(action)
            try await waitForSessionText(session, expected: expected.text)
            await pumpMountedHarness(harness)

            XCTAssertEqual(textView.string, expected.text, "Action \(action.rawValue) must only format the live selection")
            XCTAssertEqual(session.currentText, expected.text, "Action \(action.rawValue) must keep session text in sync")
            XCTAssertEqual(textView.selectedRange(), expected.newSelection, "Action \(action.rawValue) must restore the expected selection")
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

    func testToolbarCursorMatrixUsesCurrentInsertionPointAcrossBlockActions() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let staleSelection = (text as NSString).range(of: "Welcome")
        let liveCursor = NSRange(location: (text as NSString).range(of: "How are you?").location + 2, length: 0)
        let actions: [FormattingAction] = [
            .heading, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
            .paragraph, .bulletList, .numberedList, .checkbox, .blockquote, .codeBlock, .mermaid
        ]

        for action in actions {
            let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
            let session = harness.session
            let textView = harness.textView

            textView.setSelectedRange(staleSelection)
            session.selectionDidChange(staleSelection)

            textView.setSelectedRange(liveCursor)
            harness.window.makeFirstResponder(nil)
            let expected = expectedToolbarFormattingResult(
                action: action,
                text: text,
                selection: liveCursor
            )

            session.applyToolbarFormatting(action)
            try await waitForSessionText(session, expected: expected.text)
            await pumpMountedHarness(harness)

            XCTAssertEqual(textView.string, expected.text, "Action \(action.rawValue) must use the live cursor position")
            XCTAssertEqual(session.currentText, expected.text, "Action \(action.rawValue) must keep session text in sync")
            XCTAssertEqual(textView.selectedRange(), expected.newSelection, "Action \(action.rawValue) must restore the expected cursor/selection")
            XCTAssertEqual(session.cursorPosition, expected.newSelection, "Action \(action.rawValue) must keep the cursor snapshot aligned")

            assertVisibleTextUsesPrimaryColor(
                in: textView,
                substring: "Welcome to Quartz Notes",
                context: action.rawValue
            )
        }
    }

    func testToolbarTableInsertionUsesCurrentCursorAndPreservesTableRendering() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let staleSelection = (text as NSString).range(of: "Welcome")
        let liveCursor = NSRange(location: (text as NSString).range(of: "How are you?").location + 2, length: 0)

        textView.setSelectedRange(staleSelection)
        session.selectionDidChange(staleSelection)

        textView.setSelectedRange(liveCursor)
        harness.window.makeFirstResponder(nil)
        let expected = expectedToolbarFormattingResult(
            action: .table,
            text: text,
            selection: liveCursor
        )

        session.applyToolbarFormatting(.table)
        try await waitForSessionText(session, expected: expected.text)
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, expected.text)
        XCTAssertEqual(session.currentText, expected.text)
        XCTAssertEqual(textView.selectedRange(), expected.newSelection)
        XCTAssertEqual(session.cursorPosition, expected.newSelection)

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes",
            context: "table"
        )
        assertTableRowStylesRendered(in: textView)
    }

    func testToolbarMermaidInsertionPreservesParagraphBodyStyling() async throws {
        let text = "# Welcome to Quartz Notes\n\nHow are you?"
        let harness = try await makeMountedHarness(text: text, syntaxVisibilityMode: .hiddenUntilCaret)
        let session = harness.session
        let textView = harness.textView
        let staleSelection = (text as NSString).range(of: "Welcome")
        let liveCursor = NSRange(location: (text as NSString).range(of: "How are you?").location + 2, length: 0)
        let expectedText = "# Welcome to Quartz Notes\n\nHow are you?\n```mermaid\n\n```"
        let expectedSelection = NSRange(
            location: ((expectedText as NSString).range(of: "```mermaid\n").location + ("```mermaid\n" as NSString).length),
            length: 0
        )

        textView.setSelectedRange(staleSelection)
        session.selectionDidChange(staleSelection)

        textView.setSelectedRange(liveCursor)
        harness.window.makeFirstResponder(nil)

        session.applyToolbarFormatting(.mermaid)
        try await waitForSessionText(session, expected: expectedText)
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(session.currentText, expectedText)
        XCTAssertEqual(textView.selectedRange(), expectedSelection)
        XCTAssertEqual(session.cursorPosition, expectedSelection)

        assertVisibleTextUsesPrimaryColor(
            in: textView,
            substring: "Welcome to Quartz Notes",
            context: "mermaid-heading"
        )
        assertBodyTextStyling(
            in: textView,
            substring: "How are you?",
            context: "mermaid-body"
        )
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

    func testMountedBulletFormattingReplacesCheckboxSyntaxWithoutLayering() async throws {
        let harness = try await makeMountedHarness(text: "- [ ] Task")
        let session = harness.session
        let textView = harness.textView
        let insertionPoint = NSRange(location: 6, length: 0)
        textView.setSelectedRange(insertionPoint)
        session.selectionDidChange(insertionPoint)

        session.applyFormatting(.bulletList)
        try await waitForSessionText(session, expected: "- Task")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "- Task")
        XCTAssertEqual(session.currentText, "- Task")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 0))
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)
        XCTAssertTrue(session.formattingState.isBulletList)
        XCTAssertFalse(session.formattingState.isCheckbox)
    }

    func testMountedBlockquoteFormattingReplacesNumberedListSyntaxWithoutLayering() async throws {
        let harness = try await makeMountedHarness(text: "1. Task")
        let session = harness.session
        let textView = harness.textView
        let insertionPoint = NSRange(location: 3, length: 0)
        textView.setSelectedRange(insertionPoint)
        session.selectionDidChange(insertionPoint)

        session.applyFormatting(.blockquote)
        try await waitForSessionText(session, expected: "> Task")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "> Task")
        XCTAssertEqual(session.currentText, "> Task")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 0))
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)
        XCTAssertTrue(session.formattingState.isBlockquote)
        XCTAssertFalse(session.formattingState.isNumberedList)
    }

    func testMountedParagraphFormattingRemovesCodeFenceWithoutLeavingDelimitersBehind() async throws {
        let harness = try await makeMountedHarness(text: "```swift\nlet x = 1\n```")
        let session = harness.session
        let textView = harness.textView
        let insertionPoint = NSRange(location: 11, length: 0)
        textView.setSelectedRange(insertionPoint)
        session.selectionDidChange(insertionPoint)

        session.applyFormatting(.paragraph)
        try await waitForSessionText(session, expected: "let x = 1\n")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "let x = 1\n")
        XCTAssertEqual(session.currentText, "let x = 1\n")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 0))
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)
        XCTAssertFalse(session.formattingState.isCodeBlock)
    }

    func testMountedBulletFormattingTransformsEverySelectedLine() async throws {
        let harness = try await makeMountedHarness(text: "First\nSecond")
        let session = harness.session
        let textView = harness.textView
        let selection = NSRange(location: 0, length: textView.string.count)
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.bulletList)
        try await waitForSessionText(session, expected: "- First\n- Second")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "- First\n- Second")
        XCTAssertEqual(session.currentText, "- First\n- Second")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 14))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 2, length: 14))
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)
        XCTAssertTrue(session.formattingState.isBulletList)
    }

    func testMountedCodeBlockFormattingWrapsEntireSelectedLines() async throws {
        let harness = try await makeMountedHarness(text: "First\nSecond")
        let session = harness.session
        let textView = harness.textView
        let selection = NSRange(location: 1, length: 8)
        textView.setSelectedRange(selection)
        session.selectionDidChange(selection)

        session.applyFormatting(.codeBlock)
        try await waitForSessionText(session, expected: "```\nFirst\nSecond\n```")
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, "```\nFirst\nSecond\n```")
        XCTAssertEqual(session.currentText, "```\nFirst\nSecond\n```")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 12))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 4, length: 12))
        XCTAssertEqual(session.currentTransaction?.origin, .formatting)
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

    func testMountedTableTabSelectsNextCellWithoutMutatingMarkdown() async throws {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let harness = try await makeMountedHarness(text: text)
        let session = harness.session
        let textView = harness.textView
        let aLocation = (text as NSString).range(of: "A").location
        textView.setSelectedRange(NSRange(location: aLocation, length: 0))
        session.selectionDidChange(NSRange(location: aLocation, length: 0))

        textView.doCommand(by: #selector(NSTextView.insertTab(_:)))
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(session.currentText, text)
        XCTAssertEqual(selectedString(in: textView), "B")
        XCTAssertNil(session.currentTransaction)
    }

    func testMountedTableTabAtLastCellInsertsNewRow() async throws {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let navigation = MarkdownTableNavigation()
        let lastCellLocation = (text as NSString).range(of: "2").location
        let expectedNavigation = try XCTUnwrap(
            navigation.handleTab(in: text, cursorPosition: lastCellLocation, isShiftTab: false)
        )
        let expectedInsertion = try XCTUnwrap(expectedNavigation.newRowInsertion)
        let expectedText = text + expectedInsertion.rowText

        let harness = try await makeMountedHarness(text: text)
        let session = harness.session
        let textView = harness.textView
        textView.setSelectedRange(NSRange(location: lastCellLocation, length: 0))
        session.selectionDidChange(NSRange(location: lastCellLocation, length: 0))

        textView.doCommand(by: #selector(NSTextView.insertTab(_:)))
        try await waitForSessionText(session, expected: expectedText)
        await pumpMountedHarness(harness)

        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(session.currentText, expectedText)
        XCTAssertEqual(textView.selectedRange(), expectedNavigation.selectionRange)
        XCTAssertEqual(session.cursorPosition, expectedNavigation.selectionRange)
        XCTAssertEqual(session.currentTransaction?.origin, .tableNavigation)
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

    private func makeMountedHarness(
        text: String,
        syntaxVisibilityMode: SyntaxVisibilityMode = .full
    ) async throws -> EditorHarness {
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

        return try await mountHarness(
            session: session,
            expectedText: text,
            syntaxVisibilityMode: syntaxVisibilityMode
        )
    }

    private func mountHarness(
        session: EditorSession,
        expectedText: String,
        syntaxVisibilityMode: SyntaxVisibilityMode = .full
    ) async throws -> EditorHarness {
        let canvasSize = CGSize(width: 640, height: 320)
        let rootView = AnyView(
            ZStack {
            Color(nsColor: .textBackgroundColor)
            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: 1.0,
                editorFontFamily: EditorTypography.defaultFontFamily,
                editorLineSpacing: EditorTypography.defaultLineSpacingMultiplier,
                editorMaxWidth: EditorTypography.defaultMaxWidth,
                syntaxVisibilityMode: syntaxVisibilityMode
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
               textView.string == expectedText,
               textView.textStorage?.length == (expectedText as NSString).length {
                window.makeFirstResponder(textView)
                session.selectionDidChange(textView.selectedRange())
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

    private func selectedString(in textView: NSTextView) -> String {
        let range = textView.selectedRange()
        guard range.length > 0 else { return "" }
        return (textView.string as NSString).substring(with: range)
    }

    private func assertVisibleTextUsesPrimaryColor(in textView: NSTextView, substring: String, context: String? = nil) {
        let nsText = textView.string as NSString
        let range = nsText.range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound)

        let expected = normalizedColor(.labelColor)
        for offset in 0..<range.length {
            let location = range.location + offset
            let scalar = nsText.substring(with: NSRange(location: location, length: 1))
            if scalar == " " { continue }
            let color = try? XCTUnwrap(
                textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            )
            XCTAssertEqual(
                normalizedColor(color),
                expected,
                "Visible heading text leaked styling in context \(context ?? "unknown") at character \(scalar)"
            )
        }
    }

    private func assertBodyTextStyling(in textView: NSTextView, substring: String, context: String? = nil) {
        let nsText = textView.string as NSString
        let range = nsText.range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound)

        let codeFontName = EditorFontFactory.makeCodeFont(size: 14 * 0.9).fontName
        let expectedColor = normalizedColor(.labelColor)

        for offset in 0..<range.length {
            let location = range.location + offset
            let scalar = nsText.substring(with: NSRange(location: location, length: 1))
            if scalar == " " { continue }

            let font = try? XCTUnwrap(
                textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            )
            let color = try? XCTUnwrap(
                textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            )
            let background = textView.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor

            XCTAssertNotEqual(font?.fontName, codeFontName, "Body text leaked code font in context \(context ?? "unknown") at character \(scalar)")
            XCTAssertTrue(
                background == nil || isEffectivelyClear(background),
                "Body text leaked code background in context \(context ?? "unknown") at character \(scalar)"
            )
            XCTAssertEqual(normalizedColor(color), expectedColor, "Body text leaked color styling in context \(context ?? "unknown") at character \(scalar)")
        }
    }

    private func isEffectivelyClear(_ color: NSColor?) -> Bool {
        guard let color = normalizedColor(color) else { return true }
        return color.alphaComponent == 0
    }

    private func normalizedColor(_ color: NSColor?) -> NSColor? {
        color?.usingColorSpace(.deviceRGB)
    }

    private func expectedToolbarFormattingResult(
        action: FormattingAction,
        text: String,
        selection: NSRange
    ) -> (text: String, newSelection: NSRange) {
        let spans = MarkdownASTHighlighter.parseImmediately(
            text,
            baseFontSize: 14,
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

    private func assertTableRowStylesRendered(in textView: NSTextView) {
        let storage = textView.textStorage
        XCTAssertNotNil(storage)

        var foundTableRowStyle = false
        for location in 0..<(storage?.length ?? 0) {
            if storage?.attribute(.quartzTableRowStyle, at: location, effectiveRange: nil) != nil {
                foundTableRowStyle = true
                break
            }
        }

        XCTAssertTrue(foundTableRowStyle, "Inserted table must produce rendered table row styles")
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
