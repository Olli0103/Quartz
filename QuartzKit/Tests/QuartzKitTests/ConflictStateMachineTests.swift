import Testing
import Foundation
@testable import QuartzKit

// MARK: - Conflict State Machine Tests

@Suite("ConflictStateMachineP2")
struct ConflictStateMachineP2Tests {

    @Test("Initial state, valid full cycle, and history tracking")
    @MainActor func fullCycleAndHistory() throws {
        let sm = ConflictStateMachine()

        // Initial state
        #expect(sm.state == .clean)
        #expect(sm.hasActiveConflict == false)
        #expect(sm.canResolve == false)
        #expect(sm.isResolving == false)
        #expect(sm.transitionHistory.isEmpty)

        // Full cycle: clean → detected → diffLoaded → resolving → resolved → clean
        let url = URL(fileURLWithPath: "/test.md")
        try sm.detectConflict(at: url)
        #expect(sm.state == .detected)
        #expect(sm.hasActiveConflict == true)
        #expect(sm.conflictURL == url)

        let diff = ConflictDiffState(
            fileURL: url,
            localContent: "local",
            cloudContent: "cloud",
            localModified: Date(),
            cloudModified: Date()
        )
        try sm.loadDiff(diff)
        #expect(sm.state == .diffLoaded)
        #expect(sm.canResolve == true)

        try sm.beginResolving()
        #expect(sm.state == .resolving)
        #expect(sm.isResolving == true)

        try sm.resolutionSucceeded()
        #expect(sm.state == .clean)
        #expect(sm.hasActiveConflict == false)

        // History should record all transitions
        #expect(sm.transitionHistory.count >= 5)
    }

    @Test("Invalid transitions are rejected")
    @MainActor func invalidTransitions() {
        let sm = ConflictStateMachine()

        // Can't go from clean to diffLoaded directly
        #expect(throws: ConflictStateMachineError.self) {
            try sm.loadDiff(ConflictDiffState(
                fileURL: URL(fileURLWithPath: "/x.md"),
                localContent: "", cloudContent: "",
                localModified: nil, cloudModified: nil
            ))
        }

        // Can't begin resolving from clean
        #expect(throws: ConflictStateMachineError.self) {
            try sm.beginResolving()
        }
    }

    @Test("Reset from any state, cancel restrictions, resolution failure retry")
    @MainActor func resetCancelAndRetry() throws {
        let sm = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/test.md")

        // Reset from detected
        try sm.detectConflict(at: url)
        sm.reset()
        #expect(sm.state == .clean)
        #expect(sm.conflictURL == nil)

        // Cancel from detected works
        try sm.detectConflict(at: url)
        try sm.cancel()
        #expect(sm.state == .clean)

        // Cannot cancel while resolving
        try sm.detectConflict(at: url)
        try sm.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "a", cloudContent: "b",
            localModified: nil, cloudModified: nil
        ))
        try sm.beginResolving()
        #expect(throws: ConflictStateMachineError.self) {
            try sm.cancel()
        }

        // Resolution failure goes back to diffLoaded for retry
        try sm.resolutionFailed(error: "Network error")
        #expect(sm.state == .diffLoaded)
        #expect(sm.errorMessage == "Network error")

        // ConflictState enum
        #expect(ConflictState.allCases.count == 5)
    }
}
