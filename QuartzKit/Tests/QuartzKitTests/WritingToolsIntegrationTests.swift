import Testing
import Foundation
@testable import QuartzKit

// MARK: - Writing Tools Integration Tests

/// Verifies that the Writing Tools mutation origin has correct undo policy
/// and that the on-device writing tools service can be instantiated.

@Suite("Writing Tools Integration")
struct WritingToolsIntegrationTests {

    @Test("writingTools origin does not register undo")
    func writingToolsNoUndo() {
        let tx = MutationTransaction(
            origin: .writingTools,
            editedRange: NSRange(location: 0, length: 10),
            replacementLength: 8
        )
        #expect(tx.registersUndo == false,
            "Writing Tools edits are system-managed, should not register undo")
        #expect(tx.needsExplicitUndoGroup == false)
        #expect(tx.clearsUndoStack == false)
    }

    @Test("writingTools is in MutationOrigin.allCases")
    func writingToolsInAllCases() {
        #expect(MutationOrigin.allCases.contains(.writingTools))
    }

    @Test("OnDeviceWritingToolsService can be instantiated")
    func serviceInstantiation() async {
        let service = OnDeviceWritingToolsService()
        // Actor instantiation should not crash
        _ = service
    }

    @Test("writingTools prefers full re-parse (not incremental)")
    func writingToolsFullReparse() {
        let tx = MutationTransaction(
            origin: .writingTools,
            editedRange: NSRange(location: 0, length: 50),
            replacementLength: 40
        )
        #expect(tx.prefersIncrementalHighlight == false,
            "Writing Tools replacements should trigger full re-parse")
    }
}
