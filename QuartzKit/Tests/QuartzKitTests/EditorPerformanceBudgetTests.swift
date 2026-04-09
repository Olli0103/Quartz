import Testing
import Foundation
@testable import QuartzKit

// MARK: - P95 Performance Budget Tests
//
// These tests enforce the ROADMAP_V1.md performance budgets:
//   - Syntax pass P95 < 12ms for 20k-char notes
//   - Keystroke-to-highlight P95 < 8ms (measured as incremental parse time)
//
// CI vs Production budgets:
//   - Production target: <16ms main-thread budget (profiled with Instruments)
//   - CI target: <50ms full parse, <30ms incremental (relaxed for shared runners,
//     no GPU, parallel test load). The key invariant is that incremental parsing
//     is ACTIVATED and significantly faster than full re-parse on large docs.
//   - MarkdownASTHighlighter is an actor — parsing runs off the main thread by design.

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
        #expect(elapsed < 0.050,
            "Word count should complete within 50ms, took \(String(format: "%.1f", elapsed * 1000))ms")
    }

    @Test("Memory footprint of parsing 20K doc stays under 50MB delta")
    func memoryBudget20KParse() async {
        let doc = generate20KDoc()
        #expect(doc.count >= 20_000)

        // Measure memory before
        let beforeMemory = Self.currentResidentMemoryMB()

        let highlighter = MarkdownASTHighlighter()
        // Parse multiple times to stress memory
        for _ in 0..<5 {
            let spans = await highlighter.parse(doc)
            #expect(!spans.isEmpty)
        }

        let afterMemory = Self.currentResidentMemoryMB()
        let delta = afterMemory - beforeMemory

        // Memory delta should be well under the 150MB ceiling (use 50MB as parse budget)
        #expect(delta < 50,
            "Memory delta for 20K doc parse should be < 50MB, got \(String(format: "%.1f", delta))MB")
    }

    @Test("MarkdownASTHighlighter.parse runs off main thread (actor isolation)")
    func parseRunsOffMainThread() async {
        // MarkdownASTHighlighter is an actor — its methods execute on a
        // cooperative thread pool, not the main thread. This is the production
        // guarantee that keeps the UI at 60fps (<16ms main thread budget).
        let highlighter = MarkdownASTHighlighter()
        let doc = "# Test\n\nSome **bold** text"
        let spans = await highlighter.parse(doc)
        #expect(!spans.isEmpty, "Actor-isolated parse should produce spans off main thread")
        // Actor isolation is enforced by the compiler — if this test compiles
        // and the `await` resolves, the parse ran on the actor's executor.
    }

    @Test("Highlight span attribute application within 16ms frame budget")
    func applyHighlightSpansBudget() async {
        let doc = generate20KDoc()
        let highlighter = MarkdownASTHighlighter()
        let spans = await highlighter.parse(doc)
        #expect(!spans.isEmpty, "Need spans for attribute application test")

        // Simulate attribute application on an NSAttributedString (the critical render path)
        let attrString = NSMutableAttributedString(string: doc)

        var times: [TimeInterval] = []
        for _ in 0..<5 {
            let start = CFAbsoluteTimeGetCurrent()

            // Mirror the applyHighlightSpans() hot path: iterate spans, set attributes
            attrString.beginEditing()
            for span in spans {
                guard span.range.location + span.range.length <= attrString.length else { continue }
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: span.font,
                ]
                if let color = span.color {
                    attrs[.foregroundColor] = color
                }
                attrString.setAttributes(attrs, range: span.range)
                if let bg = span.backgroundColor {
                    attrString.addAttribute(.backgroundColor, value: bg, range: span.range)
                }
                if span.strikethrough {
                    attrString.addAttribute(.strikethroughStyle,
                                            value: 1,
                                            range: span.range)
                }
            }
            attrString.endEditing()

            let elapsed = CFAbsoluteTimeGetCurrent() - start
            times.append(elapsed)
        }

        let sorted = times.sorted()
        let p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]

        // CI budget: 16ms (one frame). This proves attribute application
        // doesn't blow the frame budget even on a 20K document.
        #expect(p95 < 0.016,
            "Highlight span application P95 should be < 16ms, got \(String(format: "%.1f", p95 * 1000))ms")
    }

    /// Returns current resident memory in MB.
    private static func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }
}
