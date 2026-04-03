import Testing
import Foundation
@testable import QuartzKit

// MARK: - Live Table Rendering Tests

/// Verifies the markdown table parsing pipeline: row detection,
/// QuartzTableRowStyle attribute assignment, and span consistency.

@Suite("Live Table Rendering")
struct LiveTableRenderingTests {

    @Test("Table markdown produces table row style spans")
    func tableRowDetection() async {
        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(table)

        let tableSpans = spans.filter { $0.tableRowStyle != nil }
        #expect(!tableSpans.isEmpty,
            "Table markdown should produce spans with tableRowStyle attribute")
    }

    @Test("Table has header, divider, and body row styles")
    func tableRowStyles() async {
        let table = "| H1 | H2 |\n|---|---|\n| A | B |\n| C | D |"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(table)

        let styles = Set(spans.compactMap { $0.tableRowStyle })
        #expect(styles.contains(.header), "Should have header row style")
        #expect(styles.contains(.divider), "Should have divider row style")
        // Body rows alternate even/odd
        let hasBody = styles.contains(.bodyEven) || styles.contains(.bodyOdd)
        #expect(hasBody, "Should have body row styles")
    }

    @Test("QuartzTableRowStyle rawValue mapping is stable")
    func tableRowStyleRawValues() {
        #expect(QuartzTableRowStyle.header.rawValue == 0)
        #expect(QuartzTableRowStyle.divider.rawValue == 1)
        #expect(QuartzTableRowStyle.bodyEven.rawValue == 2)
        #expect(QuartzTableRowStyle.bodyOdd.rawValue == 3)
    }

    @Test("Table spans cover all table lines")
    func tableSpansCoverage() async {
        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(table)

        let tableSpans = spans.filter { $0.tableRowStyle != nil }
        // Each line should have at least one table span
        let lines = table.components(separatedBy: "\n")
        #expect(tableSpans.count >= lines.count,
            "Should have at least one table span per line (got \(tableSpans.count) for \(lines.count) lines)")
    }

    @Test("Non-table text has no table row style")
    func nonTableNoStyle() async {
        let text = "# Heading\n\nJust a paragraph with **bold** text."
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(text)

        let tableSpans = spans.filter { $0.tableRowStyle != nil }
        #expect(tableSpans.isEmpty, "Non-table text should not have table row styles")
    }
}
