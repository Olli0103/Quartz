import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Edit Existing Note Tests
//
// Edit → undo → save data flow contracts: MutationTransaction,
// FormattingState detection, EditorSession dirty tracking.

@Suite("E2EEditExistingNote")
struct E2EEditExistingNoteTests {

    @Test("MutationTransaction records edit metadata")
    func mutationTransactionMetadata() {
        let tx = MutationTransaction(
            origin: .userTyping,
            editedRange: NSRange(location: 10, length: 5),
            replacementLength: 3
        )

        #expect(tx.origin == .userTyping)
        #expect(tx.editedRange.location == 10)
        #expect(tx.editedRange.length == 5)
        #expect(tx.replacementLength == 3)
        #expect(tx.timestamp <= Date())
    }

    @Test("MutationOrigin.userTyping groups with previous for undo")
    func userTypingGroups() {
        let tx = MutationTransaction(origin: .userTyping, editedRange: NSRange(location: 0, length: 1), replacementLength: 1)
        #expect(tx.groupsWithPrevious, "User typing should group consecutive edits in one undo step")
        #expect(tx.registersUndo, "User typing should be undoable")
    }

    @Test("MutationOrigin.syncMerge does not register undo")
    func syncMergeNoUndo() {
        let tx = MutationTransaction(origin: .syncMerge, editedRange: NSRange(location: 0, length: 10), replacementLength: 10)
        #expect(!tx.registersUndo, "Sync merge should not be undoable")
        #expect(tx.clearsUndoStack, "Sync merge should clear undo stack")
    }

    @Test("FormattingState detects bold at cursor position")
    func formattingDetection() {
        let state = FormattingState.detect(in: "Some **bold** text", at: 8)
        #expect(state.isBold, "Cursor inside **markers** should detect bold")

        let plain = FormattingState.detect(in: "Some **bold** text", at: 2)
        #expect(!plain.isBold, "Cursor outside markers should not detect bold")
    }

    @Test("FormattingState.empty has no active formatting")
    func emptyFormattingState() {
        let empty = FormattingState.empty
        #expect(!empty.isBold)
        #expect(!empty.isItalic)
        #expect(!empty.isStrikethrough)
        #expect(!empty.isCode)
        #expect(!empty.isBulletList)
        #expect(!empty.isNumberedList)
        #expect(!empty.isCheckbox)
        #expect(!empty.isBlockquote)
        #expect(!empty.isCodeBlock)
        #expect(empty.headingLevel == 0)
    }

    @Test("NoteDocument body can be modified for editing")
    func noteDocumentEditable() {
        var doc = NoteDocument(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/vault/note.md"),
            frontmatter: Frontmatter(),
            body: "Original content"
        )

        doc.body = "Modified content"
        #expect(doc.body == "Modified content")
        #expect(doc.displayName.count > 0, "Display name should always be non-empty")
    }
}
