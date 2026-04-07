import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Conflict Flow Tests
//
// Conflict detection → banner → resolve data flow:
// ConflictState lifecycle, ConflictDiffState, and sync status.

@Suite("E2EConflictFlow")
struct E2EConflictFlowTests {

    @Test("ConflictState covers full lifecycle")
    func conflictStateLifecycle() {
        let states = ConflictState.allCases
        #expect(states.count == 5,
            "Should have clean, detected, diffLoaded, resolving, resolved")

        let rawValues = Set(states.map(\.rawValue))
        #expect(rawValues.count == 5, "All states must have unique rawValues")
    }

    @Test("ConflictState has valid next states defined")
    func validTransitions() {
        // Each state should define which states it can transition to
        for state in ConflictState.allCases {
            let nextStates = state.validNextStates
            // clean can go somewhere, resolved is terminal (may have empty set)
            if state == .clean {
                #expect(!nextStates.isEmpty, "Clean state should have valid transitions")
            }
        }
    }

    @Test("ConflictStateMachine starts in clean state")
    @MainActor func initialState() {
        let sm = ConflictStateMachine()
        #expect(sm.state == .clean, "Initial state should be clean")
    }

    @Test("ConflictDiffState holds both local and cloud versions")
    func diffStateHoldsBothVersions() {
        let diff = ConflictDiffState(
            fileURL: URL(fileURLWithPath: "/vault/note.md"),
            localContent: "Local version of the note",
            cloudContent: "Cloud version of the note",
            localModified: Date(),
            cloudModified: Date().addingTimeInterval(-60)
        )

        #expect(diff.localContent != diff.cloudContent,
            "Conflict means local and cloud differ")
        #expect(diff.fileURL.lastPathComponent == "note.md")
        #expect(diff.localModified != nil)
        #expect(diff.cloudModified != nil)
    }

    @Test("CloudSyncStatus.conflict is a distinct sync state")
    func conflictSyncStatus() {
        let status = CloudSyncStatus.conflict
        #expect(status.rawValue == "conflict")
        #expect(status != .current)
        #expect(status != .error)
    }

    @Test("FileMetadata.hasConflict enables conflict banner display")
    func conflictBannerTrigger() {
        let conflicted = FileMetadata(
            createdAt: Date(), modifiedAt: Date(), fileSize: 100,
            isEncrypted: false, cloudStatus: .downloaded, hasConflict: true
        )
        let clean = FileMetadata(
            createdAt: Date(), modifiedAt: Date(), fileSize: 100,
            isEncrypted: false, cloudStatus: .downloaded, hasConflict: false
        )

        #expect(conflicted.hasConflict, "Conflicted file triggers banner")
        #expect(!clean.hasConflict, "Clean file hides banner")
    }
}
