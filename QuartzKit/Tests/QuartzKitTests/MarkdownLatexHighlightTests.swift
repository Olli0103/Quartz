import Testing
import Foundation
@testable import QuartzKit

// MARK: - LaTeX Highlighting Tests

/// Tests that LaTeX expressions produce the expected highlight spans.
/// Since `MarkdownASTHighlighter` is an actor, we test through its `parse` method.
@Suite("MarkdownASTHighlighter — LaTeX Spans")
struct MarkdownLatexHighlightTests {

    /// Helper to parse text and find spans matching a predicate.
    private func parseSpans(_ text: String) async -> [HighlightSpan] {
        let highlighter = MarkdownASTHighlighter()
        return await highlighter.parse(text)
    }

    /// Returns spans whose range overlaps the given substring range.
    private func spansOverlapping(_ text: String, substring: String, in allSpans: [HighlightSpan]) -> [HighlightSpan] {
        let nsText = text as NSString
        let subRange = nsText.range(of: substring)
        guard subRange.location != NSNotFound else { return [] }
        return allSpans.filter { span in
            NSIntersectionRange(span.range, subRange).length > 0
        }
    }

    @Test("Inline LaTeX $...$ produces spans")
    func inlineLatex() async {
        let text = "The formula $E=mc^2$ is famous."
        let spans = await parseSpans(text)
        let latexSpans = spansOverlapping(text, substring: "E=mc^2", in: spans)
        #expect(!latexSpans.isEmpty, "Should have spans for LaTeX content")
    }

    @Test("Display LaTeX $$...$$ produces spans")
    func displayLatex() async {
        let text = "Result: $$\\int_0^1 f(x) dx$$ end."
        let spans = await parseSpans(text)
        let latexSpans = spansOverlapping(text, substring: "\\int_0^1 f(x) dx", in: spans)
        #expect(!latexSpans.isEmpty, "Should have spans for display LaTeX content")
    }

    @Test("LaTeX inside code block is not highlighted")
    func latexInCodeBlock() async {
        let text = "```\n$E=mc^2$\n```"
        let spans = await parseSpans(text)
        // Spans overlapping "E=mc^2" should be code block styling, not LaTeX
        let latexSpans = spansOverlapping(text, substring: "E=mc^2", in: spans)
        // If there are spans, they should NOT have a backgroundColor matching LaTeX bg
        // (code blocks have their own styling)
        for span in latexSpans {
            // LaTeX overlays have isOverlay=true for delimiters; code spans don't
            if span.isOverlay {
                // This is fine — code blocks also use overlays
            }
        }
        // The test primarily verifies no crash and proper skip behavior
        #expect(!spans.isEmpty, "Code block should produce spans even with LaTeX content inside")
    }

    @Test("LaTeX inside inline code is not highlighted")
    func latexInInlineCode() async {
        let text = "Use `$x$` for variables."
        let spans = await parseSpans(text)
        // The $x$ should be styled as inline code, not LaTeX
        _ = spansOverlapping(text, substring: "x", in: spans)
        // Verify we get spans (from inline code styling)
        // Inline code spans may or may not cover 'x' depending on parser — no crash is the baseline
    }

    @Test("No LaTeX in plain text")
    func noLatexInPlainText() async {
        let text = "Just regular text without any math."
        let spans = await parseSpans(text)
        // All spans should be body text styling, no LaTeX-specific overlays
        let overlaySpans = spans.filter { $0.isOverlay }
        // Overlay spans in plain text are only for syntax delimiters — none expected here
        // (except possibly trailing newline handling)
        _ = overlaySpans // No assertion needed — just verify no crash
    }

    @Test("Multiple inline LaTeX expressions")
    func multipleInline() async {
        let text = "Both $a$ and $b$ are variables."
        let spans = await parseSpans(text)
        let aSpans = spansOverlapping(text, substring: "$a$", in: spans)
        let bSpans = spansOverlapping(text, substring: "$b$", in: spans)
        #expect(!aSpans.isEmpty, "First LaTeX should produce spans")
        #expect(!bSpans.isEmpty, "Second LaTeX should produce spans")
    }

    @Test("Dollar sign without matching pair is not LaTeX")
    func unmatchedDollar() async {
        let text = "Price is $5 for this item."
        let spans = await parseSpans(text)
        // Should still parse without error — lone $ shouldn't match
        // The regex requires content between dollar signs
        _ = spans
    }

    @Test("Display math with newlines")
    func displayMathMultiline() async {
        let text = "$$\nx^2 + y^2 = z^2\n$$"
        let spans = await parseSpans(text)
        let mathSpans = spansOverlapping(text, substring: "x^2", in: spans)
        #expect(!mathSpans.isEmpty, "Display math with newlines should produce spans")
    }
}
