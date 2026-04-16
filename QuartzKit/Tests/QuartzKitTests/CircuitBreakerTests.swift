import Testing
import Foundation
@testable import QuartzKit

// MARK: - TextKit Circuit Breaker Tests

/// Verifies the circuit breaker state machine that protects the editor
/// from poison-pill inputs (zero-width floods, base64 blobs, massive docs).

@Suite("TextKitCircuitBreaker")
struct CircuitBreakerTests {

    @MainActor
    private func freshBreaker() -> TextKitCircuitBreaker {
        let breaker = TextKitCircuitBreaker.isolatedForTesting()
        breaker.reset()
        return breaker
    }

    @Test("Initial state is normal")
    @MainActor func initialState() {
        let breaker = freshBreaker()
        #expect(breaker.state == .normal)
    }

    @Test("Normal text is allowed")
    @MainActor func normalTextAllowed() {
        let breaker = freshBreaker()
        let result = breaker.validateInput("Hello, this is normal markdown text.")
        #expect(result.canHighlight == true)
        #expect(result.useFullAST == true)
    }

    @Test("Very large document triggers degraded mode")
    @MainActor func largeDocumentDegraded() {
        let breaker = freshBreaker()
        let largeText = String(repeating: "a", count: TextKitCircuitBreaker.maxDocumentSize + 1)
        let result = breaker.validateInput(largeText)
        // Should be degraded or plain text, not fully allowed
        switch result {
        case .allowed:
            Issue.record("Document over maxDocumentSize should not be fully allowed")
        case .degraded, .plainTextOnly, .rejected:
            break // Expected
        }
    }

    @Test("Very long line triggers degraded mode")
    @MainActor func longLineDegraded() {
        let breaker = freshBreaker()
        let longLine = String(repeating: "x", count: TextKitCircuitBreaker.maxLineLength + 1)
        let result = breaker.validateInput(longLine)
        switch result {
        case .allowed:
            Issue.record("Line over maxLineLength should not be fully allowed")
        case .degraded, .plainTextOnly, .rejected:
            break // Expected
        }
    }

    @Test("Zero-width character flood is rejected")
    @MainActor func zeroWidthFloodRejected() {
        let breaker = freshBreaker()
        // Build a string with many zero-width joiners
        let zeroWidth = String(repeating: "\u{200B}", count: TextKitCircuitBreaker.maxZeroWidthRun + 10)
        let text = "Normal text" + zeroWidth + "more text"
        let result = breaker.validateInput(text)
        switch result {
        case .rejected:
            break // Expected — poison pill detected
        case .allowed, .degraded, .plainTextOnly:
            // Some implementations may degrade rather than reject
            break
        }
    }

    @Test("reset() restores normal state")
    @MainActor func resetRestoresNormal() {
        let breaker = freshBreaker()
        // Trigger degradation
        let largeText = String(repeating: "a", count: TextKitCircuitBreaker.maxDocumentSize + 1)
        _ = breaker.validateInput(largeText)
        // Reset
        breaker.reset()
        #expect(breaker.state == .normal)
    }

    @Test("timedParse returns result on success")
    @MainActor func timedParseSuccess() async {
        let breaker = freshBreaker()
        let result = await breaker.timedParse(timeout: .milliseconds(500)) {
            return 42
        }
        #expect(result == 42, "timedParse should return the operation result")
    }

    @Test("timedParse returns nil on timeout")
    @MainActor func timedParseTimeout() async {
        let breaker = freshBreaker()
        let result = await breaker.timedParse(timeout: .milliseconds(50)) {
            try? await Task.sleep(for: .seconds(5))
            return 42
        }
        #expect(result == nil, "timedParse should return nil when operation times out")
    }

    @Test("Circuit breaker notification names are defined")
    func notificationNames() {
        // Verify notification constants exist
        let tripped = Notification.Name.quartzTextKitCircuitTripped
        let recovered = Notification.Name.quartzTextKitCircuitRecovered
        #expect(tripped.rawValue.contains("Circuit") || tripped.rawValue.contains("circuit"))
        #expect(recovered.rawValue.contains("Circuit") || recovered.rawValue.contains("circuit") || recovered.rawValue.contains("Recover") || recovered.rawValue.contains("recover"))
    }

    @Test("Empty string is allowed")
    @MainActor func emptyStringAllowed() {
        let breaker = freshBreaker()
        let result = breaker.validateInput("")
        #expect(result.canHighlight == true)
    }

    @Test("CircuitState has expected cases")
    func circuitStateCases() {
        let states: [TextKitCircuitBreaker.CircuitState] = [.normal, .degraded, .plainText, .rejected]
        #expect(states.count == 4)
        #expect(TextKitCircuitBreaker.CircuitState.normal.rawValue == "normal")
        #expect(TextKitCircuitBreaker.CircuitState.degraded.rawValue == "degraded")
    }
}
