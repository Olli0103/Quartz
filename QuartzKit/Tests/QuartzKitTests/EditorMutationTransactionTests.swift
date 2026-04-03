import Testing
import Foundation
@testable import QuartzKit

// MARK: - MutationOrigin Tests

@Suite("MutationOrigin")
struct MutationOriginTests {

    @Test("All origins have unique raw values")
    func uniqueRawValues() {
        let rawValues = MutationOrigin.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == MutationOrigin.allCases.count)
    }

    @Test("All origins are defined")
    func allCasesDefined() {
        #expect(MutationOrigin.allCases.count == 9)
        #expect(MutationOrigin.allCases.contains(.userTyping))
        #expect(MutationOrigin.allCases.contains(.listContinuation))
        #expect(MutationOrigin.allCases.contains(.formatting))
        #expect(MutationOrigin.allCases.contains(.aiInsert))
        #expect(MutationOrigin.allCases.contains(.syncMerge))
        #expect(MutationOrigin.allCases.contains(.pasteOrDrop))
        #expect(MutationOrigin.allCases.contains(.writingTools))
        #expect(MutationOrigin.allCases.contains(.taskToggle))
        #expect(MutationOrigin.allCases.contains(.tableNavigation))
    }
}

// MARK: - MutationTransaction Undo Policy Tests

@Suite("MutationTransaction Undo Policy")
struct MutationTransactionUndoPolicyTests {

    private func transaction(_ origin: MutationOrigin) -> MutationTransaction {
        MutationTransaction(
            origin: origin,
            editedRange: NSRange(location: 0, length: 5),
            replacementLength: 3
        )
    }

    // MARK: registersUndo

    @Test("userTyping registers undo")
    func userTypingRegistersUndo() {
        #expect(transaction(.userTyping).registersUndo == true)
    }

    @Test("listContinuation registers undo")
    func listContinuationRegistersUndo() {
        #expect(transaction(.listContinuation).registersUndo == true)
    }

    @Test("formatting registers undo")
    func formattingRegistersUndo() {
        #expect(transaction(.formatting).registersUndo == true)
    }

    @Test("aiInsert registers undo")
    func aiInsertRegistersUndo() {
        #expect(transaction(.aiInsert).registersUndo == true)
    }

    @Test("syncMerge does NOT register undo")
    func syncMergeNoUndo() {
        #expect(transaction(.syncMerge).registersUndo == false)
    }

    @Test("pasteOrDrop registers undo")
    func pasteOrDropRegistersUndo() {
        #expect(transaction(.pasteOrDrop).registersUndo == true)
    }

    @Test("writingTools does NOT register undo (system-managed)")
    func writingToolsNoUndo() {
        #expect(transaction(.writingTools).registersUndo == false)
    }

    @Test("taskToggle registers undo")
    func taskToggleRegistersUndo() {
        #expect(transaction(.taskToggle).registersUndo == true)
    }

    @Test("tableNavigation registers undo")
    func tableNavigationRegistersUndo() {
        #expect(transaction(.tableNavigation).registersUndo == true)
    }

    // MARK: clearsUndoStack

    @Test("Only syncMerge clears undo stack")
    func onlySyncMergeClearsStack() {
        for origin in MutationOrigin.allCases {
            let t = transaction(origin)
            if origin == .syncMerge {
                #expect(t.clearsUndoStack == true, "syncMerge should clear undo stack")
            } else {
                #expect(t.clearsUndoStack == false, "\(origin.rawValue) should NOT clear undo stack")
            }
        }
    }

    // MARK: groupsWithPrevious

    @Test("Only userTyping groups with previous")
    func onlyUserTypingGroups() {
        for origin in MutationOrigin.allCases {
            let t = transaction(origin)
            if origin == .userTyping {
                #expect(t.groupsWithPrevious == true, "userTyping should group with previous")
            } else {
                #expect(t.groupsWithPrevious == false, "\(origin.rawValue) should NOT group")
            }
        }
    }

    // MARK: needsExplicitUndoGroup

    @Test("Explicit undo group for surgical operations")
    func explicitUndoGroupForSurgical() {
        let needsGroup: Set<MutationOrigin> = [
            .listContinuation, .formatting, .aiInsert, .pasteOrDrop, .taskToggle, .tableNavigation
        ]
        for origin in MutationOrigin.allCases {
            let t = transaction(origin)
            if needsGroup.contains(origin) {
                #expect(t.needsExplicitUndoGroup == true, "\(origin.rawValue) should need explicit group")
            } else {
                #expect(t.needsExplicitUndoGroup == false, "\(origin.rawValue) should NOT need explicit group")
            }
        }
    }
}

// MARK: - MutationTransaction Highlight Policy Tests

@Suite("MutationTransaction Highlight Policy")
struct MutationTransactionHighlightPolicyTests {

    private func transaction(_ origin: MutationOrigin) -> MutationTransaction {
        MutationTransaction(
            origin: origin,
            editedRange: NSRange(location: 10, length: 3),
            replacementLength: 5
        )
    }

    @Test("Incremental highlight for typing and local operations")
    func incrementalForLocal() {
        let incremental: Set<MutationOrigin> = [
            .userTyping, .listContinuation, .pasteOrDrop, .taskToggle, .tableNavigation
        ]
        for origin in MutationOrigin.allCases {
            let t = transaction(origin)
            if incremental.contains(origin) {
                #expect(t.prefersIncrementalHighlight == true, "\(origin.rawValue) should prefer incremental")
            } else {
                #expect(t.prefersIncrementalHighlight == false, "\(origin.rawValue) should use full re-parse")
            }
        }
    }
}

// MARK: - MutationTransaction Properties Tests

@Suite("MutationTransaction Properties")
struct MutationTransactionPropertyTests {

    @Test("Transaction stores edit range and replacement length")
    func storesRangeAndLength() {
        let t = MutationTransaction(
            origin: .userTyping,
            editedRange: NSRange(location: 42, length: 3),
            replacementLength: 7
        )
        #expect(t.editedRange.location == 42)
        #expect(t.editedRange.length == 3)
        #expect(t.replacementLength == 7)
        #expect(t.origin == .userTyping)
    }

    @Test("Transaction has a timestamp")
    func hasTimestamp() {
        let before = Date()
        let t = MutationTransaction(
            origin: .formatting,
            editedRange: NSRange(location: 0, length: 0),
            replacementLength: 0
        )
        let after = Date()
        #expect(t.timestamp >= before)
        #expect(t.timestamp <= after)
    }

    @Test("Transaction is Sendable")
    func isSendable() {
        let t = MutationTransaction(
            origin: .aiInsert,
            editedRange: NSRange(location: 0, length: 0),
            replacementLength: 0
        )
        // Compiles = Sendable conformance holds
        let _: any Sendable = t
        _ = t
    }
}
