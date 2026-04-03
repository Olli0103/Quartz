import Testing
import Foundation
@testable import QuartzKit

// MARK: - Undo Bundle Policy Tests

/// Verifies that the undo policy decisions encoded in MutationTransaction
/// correctly map to the expected undo manager behavior for each origin.
///
/// The actual undo manager integration is tested via UI tests (requires active text view).
/// These tests verify the policy model that drives the undo bundles in EditorSession.applyExternalEdit.

@Suite("Deterministic Undo Bundles — Policy Verification")
struct DeterministicUndoBundleTests {

    private func tx(_ origin: MutationOrigin) -> MutationTransaction {
        MutationTransaction(origin: origin, editedRange: NSRange(location: 0, length: 5), replacementLength: 3)
    }

    // MARK: - Undo Registration Policy

    @Test("User typing registers undo natively (no explicit group)")
    func userTypingNative() {
        let t = tx(.userTyping)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == false)
        #expect(t.groupsWithPrevious == true)
    }

    @Test("List continuation wraps in explicit undo group")
    func listContinuationExplicitGroup() {
        let t = tx(.listContinuation)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == true)
        #expect(t.groupsWithPrevious == false)
    }

    @Test("Formatting wraps in explicit undo group")
    func formattingExplicitGroup() {
        let t = tx(.formatting)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == true)
        #expect(t.groupsWithPrevious == false)
    }

    @Test("AI insert wraps in explicit undo group")
    func aiInsertExplicitGroup() {
        let t = tx(.aiInsert)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == true)
        #expect(t.groupsWithPrevious == false)
    }

    @Test("Sync merge disables undo and clears stack")
    func syncMergeNoUndo() {
        let t = tx(.syncMerge)
        #expect(t.registersUndo == false)
        #expect(t.clearsUndoStack == true)
        #expect(t.needsExplicitUndoGroup == false)
    }

    @Test("Paste/drop wraps in explicit undo group")
    func pasteDropExplicitGroup() {
        let t = tx(.pasteOrDrop)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == true)
        #expect(t.groupsWithPrevious == false)
    }

    @Test("Writing Tools bypasses undo (system-managed)")
    func writingToolsBypass() {
        let t = tx(.writingTools)
        #expect(t.registersUndo == false)
        #expect(t.needsExplicitUndoGroup == false)
        #expect(t.clearsUndoStack == false)
    }

    @Test("Task toggle wraps in explicit undo group")
    func taskToggleExplicitGroup() {
        let t = tx(.taskToggle)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == true)
    }

    @Test("Table navigation wraps in explicit undo group")
    func tableNavigationExplicitGroup() {
        let t = tx(.tableNavigation)
        #expect(t.registersUndo == true)
        #expect(t.needsExplicitUndoGroup == true)
    }

    // MARK: - Comprehensive Policy Matrix

    @Test("Every origin has consistent undo policy")
    func consistentPolicy() {
        for origin in MutationOrigin.allCases {
            let t = tx(origin)

            // If it doesn't register undo, it shouldn't need explicit grouping
            if !t.registersUndo {
                #expect(t.needsExplicitUndoGroup == false,
                    "\(origin.rawValue): non-registering edits shouldn't need explicit groups")
            }

            // If it groups with previous, it shouldn't also use explicit grouping
            if t.groupsWithPrevious {
                #expect(t.needsExplicitUndoGroup == false,
                    "\(origin.rawValue): native grouping and explicit grouping are mutually exclusive")
            }

            // Only syncMerge should clear the undo stack
            if origin != .syncMerge {
                #expect(t.clearsUndoStack == false,
                    "\(origin.rawValue): only syncMerge should clear undo stack")
            }
        }
    }
}
