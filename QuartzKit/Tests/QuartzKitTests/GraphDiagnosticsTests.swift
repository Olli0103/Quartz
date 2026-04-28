import Testing
@testable import QuartzKit

@Suite("Graph diagnostics")
struct GraphDiagnosticsTests {
    @Test("focus mode with selected note reports true focus")
    func focusModeWithSelectedNoteReportsFocus() {
        let mode = GraphViewModel.diagnosticUsabilityMode(
            coverageMode: GraphCoverageMode.focus,
            largeGraph: true,
            focusNodeID: "note://selected",
            displayedNoteCount: 50,
            totalNoteCount: 900
        )

        #expect(mode == "focus")
    }

    @Test("focus mode without selected note reports overview")
    func focusModeWithoutSelectedNoteReportsOverview() {
        let capped = GraphViewModel.diagnosticUsabilityMode(
            coverageMode: GraphCoverageMode.focus,
            largeGraph: true,
            focusNodeID: nil,
            displayedNoteCount: 50,
            totalNoteCount: 900
        )
        let uncapped = GraphViewModel.diagnosticUsabilityMode(
            coverageMode: GraphCoverageMode.focus,
            largeGraph: false,
            focusNodeID: nil,
            displayedNoteCount: 20,
            totalNoteCount: 20
        )

        #expect(capped == "cappedOverview")
        #expect(uncapped == "focusOverview")
    }
}
