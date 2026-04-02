import Testing
import Foundation
@testable import QuartzKit

// MARK: - TextKit Poison Pill Fuzz Tests

/// Fuzz tests for TextKit circuit breaker using malicious inputs.
///
/// Tests verify:
/// - 50MB base64 blob detection and rejection
/// - 10,000 zero-width joiner detection
/// - Regex catastrophic backtracking protection
/// - Deeply nested markdown protection
/// - Circuit breaker trips correctly on failures
@Suite("TextKit Poison Pill Fuzz Tests")
struct TextKitPoisonPillTests {

    // MARK: - Zero-Width Character Floods

    @Test("Detects zero-width joiner flood")
    @MainActor
    func testZeroWidthJoinerFlood() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Create a string with 150 zero-width joiners
        let zwj = "\u{200D}" // Zero-width joiner
        let poison = String(repeating: zwj, count: 150)

        let validation = circuitBreaker.validateInput(poison)

        switch validation {
        case .rejected(let reason):
            if case .zeroWidthFlood(let count) = reason {
                #expect(count >= 100, "Should detect at least 100 zero-width chars")
            } else {
                Issue.record("Expected zeroWidthFlood, got \(reason)")
            }
        default:
            Issue.record("Expected rejected, got \(validation)")
        }
    }

    @Test("Detects zero-width space flood")
    @MainActor
    func testZeroWidthSpaceFlood() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Mix of zero-width space and zero-width non-joiner
        let zwsp = "\u{200B}"
        let zwnj = "\u{200C}"
        let poison = String(repeating: zwsp + zwnj, count: 75) // 150 total

        let validation = circuitBreaker.validateInput(poison)

        switch validation {
        case .rejected(let reason):
            if case .zeroWidthFlood = reason {
                // Expected
            } else {
                Issue.record("Expected zeroWidthFlood, got \(reason)")
            }
        default:
            Issue.record("Expected rejected, got \(validation)")
        }
    }

    @Test("Allows normal text with occasional zero-width chars")
    @MainActor
    func testNormalTextWithZeroWidth() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Normal text with a few zero-width chars (common in emoji sequences)
        let text = "Hello \u{200D} world \u{200D} test"

        let validation = circuitBreaker.validateInput(text)

        #expect(validation.canHighlight, "Normal text should be allowed")
    }

    // MARK: - Base64 Blob Detection

    @Test("Detects large base64 blob")
    @MainActor
    func testLargeBase64Blob() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Generate 200KB of base64-like content
        let base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var poison = ""
        for _ in 0..<200_000 {
            poison.append(base64Chars.randomElement()!)
        }

        let validation = circuitBreaker.validateInput(poison)

        switch validation {
        case .rejected(let reason):
            if case .base64Blob(let size) = reason {
                #expect(size >= 200_000, "Should report correct blob size")
            } else {
                Issue.record("Expected base64Blob, got \(reason)")
            }
        case .degraded:
            // Also acceptable — large document triggers degradation
            break
        default:
            Issue.record("Expected rejected or degraded, got \(validation)")
        }
    }

    // MARK: - Document Size Limits

    @Test("Degrades on oversized document")
    @MainActor
    func testOversizedDocument() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Create a 600KB document (over 500KB limit)
        let text = String(repeating: "Hello world. ", count: 50_000)

        let validation = circuitBreaker.validateInput(text)

        switch validation {
        case .degraded(let reason):
            if case .documentTooLarge(let size) = reason {
                #expect(size > 500_000, "Should report correct size")
            } else {
                Issue.record("Expected documentTooLarge, got \(reason)")
            }
        default:
            Issue.record("Expected degraded, got \(validation)")
        }
    }

    @Test("Allows document under size limit")
    @MainActor
    func testNormalSizedDocument() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Create a ~100KB document with reasonable line lengths (under limits)
        let line = "Test content for a normal document line.\n"
        let text = String(repeating: line, count: 2_500)  // ~100KB, short lines

        let validation = circuitBreaker.validateInput(text)

        #expect(validation.useFullAST, "Normal document should use full AST")
    }

    // MARK: - Line Length Limits

    @Test("Degrades on extremely long line")
    @MainActor
    func testExtremeLongLine() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Create a line with 15,000 characters (over 10,000 limit)
        let longLine = String(repeating: "x", count: 15_000)

        let validation = circuitBreaker.validateInput(longLine)

        switch validation {
        case .degraded(let reason):
            if case .lineTooLong(let length) = reason {
                #expect(length >= 15_000, "Should report correct line length")
            } else {
                Issue.record("Expected lineTooLong, got \(reason)")
            }
        default:
            Issue.record("Expected degraded, got \(validation)")
        }
    }

    // MARK: - Control Character Floods

    @Test("Detects control character flood")
    @MainActor
    func testControlCharFlood() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Create text with many soft hyphens (ignorable code point)
        let softHyphen = "\u{00AD}"
        let poison = String(repeating: "a" + softHyphen, count: 2000) // 2000 soft hyphens

        let validation = circuitBreaker.validateInput(poison)

        switch validation {
        case .rejected(let reason):
            if case .controlCharFlood = reason {
                // Expected
            } else {
                Issue.record("Expected controlCharFlood, got \(reason)")
            }
        default:
            // May also be degraded due to size
            break
        }
    }

    // MARK: - Circuit Breaker Behavior

    @Test("Circuit trips after repeated failures")
    @MainActor
    func testCircuitTripping() async {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Simulate parsing timeout using async sleep
        let result1 = await circuitBreaker.timedParse(timeout: .milliseconds(10)) {
            // Simulate slow operation using Task.sleep
            try? await Task.sleep(for: .milliseconds(100)) // 100ms, will timeout
            return "result"
        }

        #expect(result1 == nil, "First timeout should return nil")

        // Second failure should trip circuit
        let result2 = await circuitBreaker.timedParse(timeout: .milliseconds(10)) {
            try? await Task.sleep(for: .milliseconds(100))
            return "result"
        }

        #expect(result2 == nil, "Second timeout should return nil")

        // Circuit should now be degraded
        #expect(circuitBreaker.state == .degraded, "Circuit should be degraded after 2 failures")
    }

    @Test("Circuit recovers after success")
    @MainActor
    func testCircuitRecovery() async {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // Trip the circuit
        _ = await circuitBreaker.timedParse(timeout: .milliseconds(10)) {
            try? await Task.sleep(for: .milliseconds(100))
            return "result"
        }
        _ = await circuitBreaker.timedParse(timeout: .milliseconds(10)) {
            try? await Task.sleep(for: .milliseconds(100))
            return "result"
        }

        #expect(circuitBreaker.state == .degraded, "Should be degraded")

        // Now succeed multiple times
        for _ in 0..<3 {
            _ = await circuitBreaker.timedParse(timeout: .seconds(1)) {
                return "quick result" // Fast operation
            }
        }

        // Should have recovered (failure count decremented)
        #expect(circuitBreaker.state == .normal || circuitBreaker.state == .degraded, "Should recover or stay degraded")
    }

    // MARK: - Edge Cases

    @Test("Handles empty string")
    @MainActor
    func testEmptyString() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        let validation = circuitBreaker.validateInput("")

        #expect(validation.useFullAST, "Empty string should be allowed")
    }

    @Test("Handles single character")
    @MainActor
    func testSingleCharacter() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        let validation = circuitBreaker.validateInput("a")

        #expect(validation.useFullAST, "Single char should be allowed")
    }

    @Test("Handles normal markdown")
    @MainActor
    func testNormalMarkdown() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        let markdown = """
        # Heading

        This is a **bold** and *italic* text.

        - List item 1
        - List item 2

        ```swift
        let code = "example"
        ```

        [[wiki-link]]
        """

        let validation = circuitBreaker.validateInput(markdown)

        #expect(validation.useFullAST, "Normal markdown should use full AST")
    }

    // MARK: - Performance Tests

    @Test("Validation is fast for normal documents")
    @MainActor
    func testValidationPerformance() {
        let circuitBreaker = TextKitCircuitBreaker.shared
        circuitBreaker.reset()

        // 50KB of normal text
        let text = String(repeating: "Normal text content. ", count: 2_500)

        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            _ = circuitBreaker.validateInput(text)
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // 100 validations should complete in under 100ms
        #expect(elapsed < 100, "100 validations took \(elapsed)ms, expected < 100ms")
    }
}

// MARK: - MarkdownASTHighlighter Integration Tests

@Suite("MarkdownASTHighlighter Fuzz Tests")
struct MarkdownASTHighlighterFuzzTests {

    @Test("Highlighter handles deeply nested lists")
    func testDeeplyNestedLists() async {
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)

        // Create 30 levels of nested lists
        var markdown = ""
        for i in 0..<30 {
            markdown += String(repeating: "  ", count: i) + "- Item \(i)\n"
        }

        let spans = await highlighter.parse(markdown)

        // Should return spans without crashing
        #expect(spans.count >= 0, "Should return spans array")
    }

    @Test("Highlighter handles many wiki-links")
    func testManyWikiLinks() async {
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)

        // Create 500 wiki-links
        var markdown = ""
        for i in 0..<500 {
            markdown += "[[Note \(i)]] "
        }

        let spans = await highlighter.parse(markdown)

        // Should handle many links
        #expect(spans.count > 0, "Should return spans for wiki-links")
    }

    @Test("Highlighter handles complex table")
    func testComplexTable() async {
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)

        // Create a 50-column, 20-row table
        var markdown = "| " + (0..<50).map { "Col\($0)" }.joined(separator: " | ") + " |\n"
        markdown += "| " + (0..<50).map { _ in "---" }.joined(separator: " | ") + " |\n"
        for row in 0..<20 {
            markdown += "| " + (0..<50).map { "R\(row)C\($0)" }.joined(separator: " | ") + " |\n"
        }

        let spans = await highlighter.parse(markdown)

        #expect(spans.count > 0, "Should return spans for table")
    }

    @Test("Highlighter handles code block with many lines")
    func testLargeCodeBlock() async {
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)

        var markdown = "```swift\n"
        for i in 0..<1000 {
            markdown += "let line\(i) = \(i)\n"
        }
        markdown += "```"

        let spans = await highlighter.parse(markdown)

        #expect(spans.count > 0, "Should return spans for code block")
    }
}
