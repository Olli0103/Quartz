import Foundation
import Testing
@testable import QuartzKit

@Suite("In-note search state")
struct InNoteSearchStateTests {

    @Test("Empty query produces no matches")
    func emptyQueryProducesNoMatches() {
        let matches = InNoteSearchState.computeMatches(
            in: "Alpha Beta Gamma",
            query: "",
            isCaseSensitive: false
        )
        #expect(matches.isEmpty)
    }

    @Test("Match indexing is deterministic and case-insensitive by default")
    func deterministicMatchIndexing() {
        let text = "Alpha beta ALPHA alpha"
        let matches = InNoteSearchState.computeMatches(
            in: text,
            query: "alpha",
            isCaseSensitive: false
        )

        #expect(matches.count == 3)
        #expect(matches[0] == (text as NSString).range(of: "Alpha"))
        #expect(matches[1] == (text as NSString).range(of: "ALPHA"))
        #expect(matches[2] == (text as NSString).range(of: "alpha", options: [], range: NSRange(location: 12, length: (text as NSString).length - 12)))
    }

    @Test("Replace-all builder only mutates the provided current-note text")
    func replaceAllBuilderUsesOnlyCurrentText() {
        let text = "One fish, two fish, red fish, blue fish"
        let matches = InNoteSearchState.computeMatches(
            in: text,
            query: "fish",
            isCaseSensitive: false
        )

        let rebuilt = InNoteSearchState.replacingMatches(
            in: text,
            matches: matches,
            replacement: "bird"
        )

        #expect(rebuilt == "One bird, two bird, red bird, blue bird")
    }
}
