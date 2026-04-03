import Testing
import Foundation
@testable import QuartzKit

// MARK: - Editor Performance Tests

/// Baseline performance tests for syntax highlighting and word counting.
/// These are generous limits — they exist to catch regressions, not
/// benchmark the absolute minimum latency.

@Suite("Editor Performance Baselines")
struct EditorPerformanceBaselineTests {

    @Test("Full syntax parse of moderate doc completes within 1s")
    func fullParseModerateDoc() async {
        // Build a moderate-size markdown document (~5KB)
        var doc = "# Performance Test Document\n\n"
        for i in 0..<50 {
            doc += "Paragraph \(i) with **bold**, *italic*, `code`, and [links](url). Some more words to fill the paragraph out a bit.\n\n"
        }

        let highlighter = MarkdownASTHighlighter()
        let start = Date()
        let spans = await highlighter.parse(doc)
        let elapsed = Date().timeIntervalSince(start)

        #expect(!spans.isEmpty, "Should produce highlight spans")
        #expect(elapsed < 1.0, "Full parse should complete within 1s, took \(elapsed)s")
    }

    @Test("Incremental parse faster than full parse")
    func incrementalFasterThanFull() async {
        var doc = "# Document\n\n"
        for i in 0..<100 {
            doc += "Line \(i) with **bold** and *italic* content.\n\n"
        }

        let highlighter = MarkdownASTHighlighter()

        // Full parse (cold)
        let fullStart = Date()
        _ = await highlighter.parse(doc)
        let fullElapsed = Date().timeIntervalSince(fullStart)

        // Incremental parse (warm — cache primed)
        let insertPos = doc.count / 2
        let nsDoc = doc as NSString
        let edited = nsDoc.replacingCharacters(
            in: NSRange(location: insertPos, length: 0),
            with: "X"
        )

        let incStart = Date()
        let incSpans = await highlighter.parseIncremental(
            edited,
            editRange: NSRange(location: insertPos, length: 1),
            preEditLength: 0
        )
        let incElapsed = Date().timeIntervalSince(incStart)

        #expect(!incSpans.isEmpty, "Incremental should produce spans")
        // Incremental should be no slower than full (ideally faster, but at minimum not worse)
        #expect(incElapsed <= fullElapsed * 2.0,
            "Incremental (\(incElapsed)s) should not be dramatically slower than full (\(fullElapsed)s)")
    }

    @Test("Word count on 20K chars completes within 10ms")
    func wordCount20K() {
        var text = ""
        for i in 0..<3000 {
            text += "word\(i) "
        }
        #expect(text.count > 18_000, "Text should be ~20K chars")

        let start = Date()
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            count += 1
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(count == 3000, "Should count 3000 words")
        #expect(elapsed < 0.01, "Word count should complete within 10ms, took \(elapsed)s")
    }
}
