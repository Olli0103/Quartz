import Testing
import Foundation
@testable import QuartzKit

// MARK: - Conflict UI State Machine Tests

@Suite("ConflictUI")
struct ConflictUITests {

    @Test("EditorSession externalModificationDetected flag and conflict state machine integration")
    @MainActor func externalModificationAndConflictFlow() throws {
        let session = EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )

        // Initially no external modification
        #expect(session.externalModificationDetected == false)

        // Set external modification detected
        session.externalModificationDetected = true
        #expect(session.externalModificationDetected == true)

        // ConflictStateMachine: verify computed properties track state
        let sm = ConflictStateMachine()
        #expect(sm.hasActiveConflict == false)
        #expect(sm.canResolve == false)
        #expect(sm.isResolving == false)

        // Detect → hasActiveConflict true
        let url = URL(fileURLWithPath: "/test.md")
        try sm.detectConflict(at: url)
        #expect(sm.hasActiveConflict == true)
        #expect(sm.conflictURL == url)

        // Load diff → canResolve true
        let diff = ConflictDiffState(
            fileURL: url, localContent: "mine", cloudContent: "theirs",
            localModified: nil, cloudModified: nil
        )
        try sm.loadDiff(diff)
        #expect(sm.canResolve == true)
        #expect(sm.diffState != nil)
        #expect(sm.diffState?.localContent == "mine")
        #expect(sm.diffState?.cloudContent == "theirs")
    }
}
