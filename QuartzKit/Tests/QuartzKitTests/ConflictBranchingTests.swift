import Testing
import Foundation
@testable import QuartzKit

// MARK: - Conflict Branching Tests

@Suite("ConflictBranching")
struct ConflictBranchingTests {

    @Test("ConflictDiffState captures both sides with metadata, ConflictState enum covers all cases")
    func diffStateAndEnumCoverage() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        let localDate = Date(timeIntervalSince1970: 1000)
        let cloudDate = Date(timeIntervalSince1970: 2000)

        let diff = ConflictDiffState(
            fileURL: url,
            localContent: "local version",
            cloudContent: "cloud version",
            localModified: localDate,
            cloudModified: cloudDate
        )

        #expect(diff.fileURL == url)
        #expect(diff.localContent == "local version")
        #expect(diff.cloudContent == "cloud version")
        #expect(diff.localModified == localDate)
        #expect(diff.cloudModified == cloudDate)

        // ConflictDiffState with nil dates (unknown modification times)
        let diffNil = ConflictDiffState(
            fileURL: url,
            localContent: "a",
            cloudContent: "b",
            localModified: nil,
            cloudModified: nil
        )
        #expect(diffNil.localModified == nil)
        #expect(diffNil.cloudModified == nil)

        // ConflictState enum exhaustive check
        let allStates = ConflictState.allCases
        #expect(allStates.count == 5)
        #expect(allStates.contains(.clean))
        #expect(allStates.contains(.detected))
        #expect(allStates.contains(.diffLoaded))
        #expect(allStates.contains(.resolving))
        #expect(allStates.contains(.resolved))
    }
}
