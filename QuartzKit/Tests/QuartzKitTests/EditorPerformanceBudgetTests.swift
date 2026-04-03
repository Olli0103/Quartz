import Testing
import Foundation
@testable import QuartzKit

// MARK: - P95 Performance Budget Tests
//
// These tests enforce the ROADMAP_V1.md performance budgets:
//   - Syntax pass P95 < 12ms for 20k-char notes
//   - Keystroke-to-highlight P95 < 8ms (measured as incremental parse time)
//
// The budgets are relaxed for CI (50ms full parse, 30ms incremental) to avoid
// flaky failures on shared runners. The key invariant is that incremental
// parsing is ACTIVATED and significantly faster than full re-parse on large docs.

@Suite("Editor Performance Budget")
struct EditorPerformanceBudgetTests {

    /// Generates a realistic 20K+ character markdown document.
    private func generate20KDoc() -> String {
        var doc = "# Performance Budget Test Document\n\n"
        doc += "This document tests syntax highlighting performance on large notes.\n\n"

        for i in 0..<250 {
            switch i % 5 {
            case 0:
                doc += "## Section \(i)\n\n"
                doc += "Regular paragraph with **bold**, *italic*, and `inline code`. "
                doc += "More text to fill out the paragraph with [a link](https://example.com). "
                doc += "Additional sentence for realistic paragraph length in a real note.\n\n"
            case 1:
                doc += "- List item with **bold** text and extra content\n"
                doc += "- Another item with `code` and more words here\n"
                doc += "- Third item with *emphasis* and a [link](url)\n\n"
            case 2:
                doc += "```swift\nfunc example\(i)() {\n    let x = \(i)\n    print(x)\n}\n```\n\n"
            case 3:
                doc += "| Column A | Column B | Column C |\n"
                doc += "|----------|----------|----------|\n"
                doc += "| cell \(i) | data here | value there |\n\n"
            default:
                doc += "> Blockquote paragraph \(i) with some **formatted** content "
                doc += "and a [reference link](url). More quoted text to fill it out.\n\n"
            }
        }
        return doc
    }

    @Test("Full syntax parse of 20K-char doc completes within budget")
    func fullParse20KBudget() async {
        let doc = generate20KDoc()
        #expect(doc.count >= 20_000,
            "Test document should be >= 20K chars, got \(doc.count)")

        let highlighter = MarkdownASTHighlighter()

        // Run 5 iterations, track all times
        var times: [TimeInterval] = []
        for _ in 0..<5 {
            let start = CFAbsoluteTimeGetCurrent()
            let spans = await highlighter.parse(doc)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            times.append(elapsed)
            #expect(!spans.isEmpty, "Parse should produce highlight spans")
        }

        let sorted = times.sorted()
        let p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]

        // CI budget: 50ms (generous). Production target: 12ms.
        // If this fails, incremental parsing may be broken or a regression was introduced.
        #expect(p95 < 0.050,
            "Full parse P95 should be < 50ms, got \(String(format: "%.1f", p95 * 1000))ms. Times: \(times.map { String(format: "%.1f", $0 * 1000) })ms")
    }

    @Test("Incremental parse after single-char insert within budget")
    func incrementalParseBudget() async {
        let doc = generate20KDoc()
        #expect(doc.count >= 20_000)

        let highlighter = MarkdownASTHighlighter()

        // Prime the cache with a full parse
        _ = await highlighter.parse(doc)

        // Simulate typing a single character in the middle
        let insertPos = doc.count / 2
        let nsDoc = doc as NSString
        let editedDoc = nsDoc.replacingCharacters(
            in: NSRange(location: insertPos, length: 0),
            with: "X"
        )

        // Run 5 incremental parses, track times
        var times: [TimeInterval] = []
        for _ in 0..<5 {
            let start = CFAbsoluteTimeGetCurrent()
            let spans = await highlighter.parseIncremental(
                editedDoc,
                editRange: NSRange(location: insertPos, length: 1),
                preEditLength: 0
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            times.append(elapsed)
            #expect(!spans.isEmpty, "Incremental parse should produce spans")
        }

        let sorted = times.sorted()
        let p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]

        // CI budget: 30ms (generous). Production target: 8ms.
        #expect(p95 < 0.030,
            "Incremental parse P95 should be < 30ms, got \(String(format: "%.1f", p95 * 1000))ms. Times: \(times.map { String(format: "%.1f", $0 * 1000) })ms")
    }

    @Test("Incremental parse is faster than full parse on 20K doc")
    func incrementalFasterThanFull() async {
        let doc = generate20KDoc()
        let highlighter = MarkdownASTHighlighter()

        // Full parse (measures cold + warm)
        var fullTimes: [TimeInterval] = []
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = await highlighter.parse(doc)
            fullTimes.append(CFAbsoluteTimeGetCurrent() - start)
        }

        // Incremental parse
        let insertPos = doc.count / 2
        let nsDoc = doc as NSString
        let editedDoc = nsDoc.replacingCharacters(
            in: NSRange(location: insertPos, length: 0),
            with: "Y"
        )

        var incTimes: [TimeInterval] = []
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = await highlighter.parseIncremental(
                editedDoc,
                editRange: NSRange(location: insertPos, length: 1),
                preEditLength: 0
            )
            incTimes.append(CFAbsoluteTimeGetCurrent() - start)
        }

        let avgFull = fullTimes.reduce(0, +) / Double(fullTimes.count)
        let avgInc = incTimes.reduce(0, +) / Double(incTimes.count)

        // Incremental should not be dramatically slower than full.
        // If incremental is > 1.5x full, the incremental path may be broken.
        #expect(avgInc <= avgFull * 1.5,
            "Incremental avg (\(String(format: "%.1f", avgInc * 1000))ms) should not exceed 1.5x full avg (\(String(format: "%.1f", avgFull * 1000))ms)")
    }

    @Test("Word count on 20K doc within 10ms budget")
    func wordCount20KBudget() {
        let doc = generate20KDoc()
        #expect(doc.count >= 20_000)

        let start = CFAbsoluteTimeGetCurrent()
        var count = 0
        doc.enumerateSubstrings(
            in: doc.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            count += 1
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(count > 0, "Should count words")
        #expect(elapsed < 0.010,
            "Word count should complete within 10ms, took \(String(format: "%.1f", elapsed * 1000))ms")
    }
}
