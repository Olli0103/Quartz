import Testing
import Foundation
@testable import QuartzKit

// MARK: - Conflict Banner View Model Tests

@Suite("ConflictBannerView")
struct ConflictBannerViewTests {

    @Test("ConflictStateMachine error message and transition history after resolution failure")
    @MainActor func errorMessageAndHistory() throws {
        let sm = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/banner-test.md")

        // Drive to resolving state
        try sm.detectConflict(at: url)
        try sm.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "local", cloudContent: "cloud",
            localModified: nil, cloudModified: nil
        ))
        try sm.beginResolving()
        #expect(sm.isResolving == true)

        // Resolution failure sets error message and goes to diffLoaded
        try sm.resolutionFailed(error: "Merge conflict unresolvable")
        #expect(sm.state == .diffLoaded)
        #expect(sm.errorMessage == "Merge conflict unresolvable")

        // History contains all transitions
        let states = sm.transitionHistory.map(\.to)
        #expect(states.contains(.detected))
        #expect(states.contains(.diffLoaded))
        #expect(states.contains(.resolving))
        // Final transition back to diffLoaded also recorded
        #expect(states.last == .diffLoaded)
    }
}
