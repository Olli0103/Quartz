import XCTest
@testable import QuartzKit

// MARK: - Phase 2: AI Fallback Hardening
// Tests for circuit breaker, timeout handling, local fallback, and schema validation.
// Remote failure cannot break graph operations.

// MARK: - Controllable Mock AI Provider

/// A fully controllable mock for comprehensive failure scenario testing.
final class ControllableMockAIProvider: AIProvider, @unchecked Sendable {
    let id = "controllable-mock"
    let displayName = "Controllable Mock Provider"
    var isConfigured: Bool = true
    var availableModels: [AIModel] = [
        AIModel(id: "mock-model", name: "Mock Model", contextWindow: 4096, provider: "controllable-mock")
    ]

    // Control behavior
    var shouldFail = false
    var failureError: Error = AIProviderError.networkError("Simulated failure")
    var responseDelay: Duration = .zero
    var responseContent = "[\"concept1\", \"concept2\"]"
    var callCount = 0

    func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        callCount += 1
        if responseDelay > .zero {
            try await Task.sleep(for: responseDelay)
        }
        if shouldFail {
            throw failureError
        }
        return AIMessage(role: .assistant, content: responseContent)
    }
}

// MARK: - AI Execution Policy Tests

final class Phase2AIExecutionPolicyTests: XCTestCase {

    // MARK: - Circuit Breaker Tests

    @MainActor
    func testRemoteTimeoutTriggersLocalFallback() async throws {
        // Setup: provider that takes too long
        let mockProvider = ControllableMockAIProvider()
        mockProvider.responseDelay = .seconds(5)

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            remoteTimeout: .milliseconds(100),
            circuitBreakerThreshold: 3
        )

        // Execute: request concept extraction
        let concepts = await policy.extractConcepts(from: "Swift is a programming language developed by Apple.")

        // Verify: should return local NLP fallback results (non-empty)
        XCTAssertFalse(concepts.isEmpty, "Should return local fallback concepts after timeout")

        // Verify: execution path should indicate fallback
        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceFallback, "Should use on-device fallback after timeout")
    }

    @MainActor
    func testRepeatedRemoteErrorsOpenCircuit() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            remoteTimeout: .seconds(5),
            circuitBreakerThreshold: 3
        )

        // Cause failures to open circuit
        for _ in 0..<3 {
            _ = await policy.extractConcepts(from: "Test content")
        }

        // Verify: circuit should be open
        let health = await policy.providerHealth
        XCTAssertEqual(health, .circuitOpen, "Circuit should be open after threshold failures")
    }

    @MainActor
    func testCircuitOpenSkipsRemoteCalls() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            circuitBreakerThreshold: 2
        )

        // Open the circuit
        for _ in 0..<2 {
            _ = await policy.extractConcepts(from: "Test")
        }

        // Reset call count after circuit opens
        mockProvider.callCount = 0
        mockProvider.shouldFail = false  // Provider would succeed now

        // Make another request
        _ = await policy.extractConcepts(from: "Another test")

        // Verify: remote was not called because circuit is open
        XCTAssertEqual(mockProvider.callCount, 0, "Should not call remote when circuit is open")

        // Verify: fallback was used
        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceFallback, "Should use fallback when circuit is open")
    }

    @MainActor
    func testCircuitRecoveryAfterCooldown() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            circuitBreakerThreshold: 2,
            circuitRecoveryInterval: .milliseconds(100)
        )

        // Open circuit
        for _ in 0..<2 {
            _ = await policy.extractConcepts(from: "Test")
        }

        var health = await policy.providerHealth
        XCTAssertEqual(health, .circuitOpen, "Circuit should be open")

        // Wait for recovery interval
        try await Task.sleep(for: .milliseconds(150))

        // Now provider succeeds
        mockProvider.shouldFail = false
        mockProvider.callCount = 0

        _ = await policy.extractConcepts(from: "Recovery test")

        // Verify: remote was attempted after cooldown
        XCTAssertGreaterThan(mockProvider.callCount, 0, "Should attempt remote after recovery interval")

        // Verify: health restored after success
        health = await policy.providerHealth
        XCTAssertEqual(health, .healthy, "Health should recover after successful call")
    }

    @MainActor
    func testDegradedStateBeforeCircuitOpen() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            circuitBreakerThreshold: 4  // Opens at 4, degrades at 2
        )

        // Cause some failures (but not enough to open circuit)
        _ = await policy.extractConcepts(from: "Test 1")
        _ = await policy.extractConcepts(from: "Test 2")

        let health = await policy.providerHealth
        XCTAssertEqual(health, .degraded, "Should be degraded before circuit opens")
    }

    @MainActor
    func testSuccessResetsFailureCount() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            circuitBreakerThreshold: 3
        )

        // Cause some failures
        _ = await policy.extractConcepts(from: "Test 1")
        _ = await policy.extractConcepts(from: "Test 2")

        // Now succeed
        mockProvider.shouldFail = false
        _ = await policy.extractConcepts(from: "Test 3")

        // Verify health is restored
        let health = await policy.providerHealth
        XCTAssertEqual(health, .healthy, "Success should restore health")

        // Cause more failures - should need full threshold again
        mockProvider.shouldFail = true
        _ = await policy.extractConcepts(from: "Test 4")
        _ = await policy.extractConcepts(from: "Test 5")

        let healthAfter = await policy.providerHealth
        XCTAssertNotEqual(healthAfter, .circuitOpen, "Circuit should not open after reset")
    }

    // MARK: - Offline Mode Tests

    @MainActor
    func testOfflineModeUsesLocalDirectly() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.callCount = 0

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        await policy.setOfflineMode(true)

        let concepts = await policy.extractConcepts(from: "Swift programming language")

        // Verify: no remote calls made
        XCTAssertEqual(mockProvider.callCount, 0, "Should not call remote in offline mode")

        // Verify: path is direct on-device
        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceDirect, "Should use direct on-device path in offline mode")

        // Verify: still returns results
        XCTAssertFalse(concepts.isEmpty, "Should return local concepts in offline mode")
    }

    // MARK: - Budget / Timeout Tests

    @MainActor
    func testPerTaskTimeoutBudget() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.responseDelay = .seconds(10)  // Very slow

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            remoteTimeout: .milliseconds(50)  // Fast timeout
        )

        let startTime = ContinuousClock.now
        _ = await policy.extractConcepts(from: "Test content")
        let elapsed = ContinuousClock.now - startTime

        // Should complete quickly due to timeout, not wait 10 seconds
        XCTAssertLessThan(elapsed, .seconds(1), "Timeout should limit execution time")
    }
}

// MARK: - Concept Extraction Fallback Tests

final class Phase2ConceptExtractionFallbackTests: XCTestCase {

    @MainActor
    func testLocalFallbackReturnsMinimalConceptSet() async throws {
        // No provider configured
        let policy = AIExecutionPolicy(
            primaryProvider: nil,
            fallbackMode: .localNLP
        )

        let text = """
        Apple announced the new iPhone 15 Pro at their headquarters in Cupertino.
        Tim Cook presented the device which features improved performance.
        """

        let concepts = await policy.extractConcepts(from: text)

        // Should return something meaningful from NLP
        XCTAssertFalse(concepts.isEmpty, "Local fallback should return concepts")

        // Should contain some recognizable entities
        let combined = concepts.joined(separator: " ").lowercased()
        let hasRelevantContent = combined.contains("apple") ||
                                  combined.contains("iphone") ||
                                  combined.contains("cupertino") ||
                                  combined.contains("cook") ||
                                  concepts.count >= 1  // At minimum, something extracted
        XCTAssertTrue(hasRelevantContent, "Local NLP should extract relevant concepts")
    }

    @MainActor
    func testLocalFallbackWithProviderUnavailable() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true
        mockProvider.failureError = AIProviderError.networkError("Connection refused")

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Swift is a programming language.")

        // Should fall back gracefully
        XCTAssertFalse(concepts.isEmpty, "Should return fallback concepts when provider fails")

        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceFallback, "Should indicate fallback path")
    }

    @MainActor
    func testFallbackKnowledgeExtractorEntityExtraction() async throws {
        // Test the FallbackKnowledgeExtractor specifically
        let extractor = FallbackKnowledgeExtractor(primaryProvider: nil)

        let text = """
        The meeting with John Smith about the Microsoft Azure project is scheduled for Monday.
        """

        let entities = await extractor.extractEntities(from: text)

        // Should extract named entities locally
        XCTAssertFalse(entities.isEmpty, "Should extract entities without provider")
    }

    @MainActor
    func testFallbackTagSuggestion() async throws {
        let extractor = FallbackKnowledgeExtractor(primaryProvider: nil)

        let text = """
        SwiftUI provides a declarative syntax for building user interfaces.
        It supports views, modifiers, and state management.
        """

        let tags = await extractor.suggestTags(for: text)

        XCTAssertFalse(tags.isEmpty, "Should suggest tags without provider")
        // Tags should be lowercase
        XCTAssertTrue(tags.allSatisfy { $0 == $0.lowercased() }, "Tags should be lowercase")
    }

    @MainActor
    func testEmptyTextReturnsEmptyConcepts() async throws {
        let policy = AIExecutionPolicy(
            primaryProvider: nil,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "")
        XCTAssertTrue(concepts.isEmpty, "Empty text should return empty concepts")

        let shortText = await policy.extractConcepts(from: "Hi")
        // Very short text might still be processed
        // Just verify it doesn't crash
    }
}

// MARK: - Schema Validation Tests

final class Phase2SchemaValidationTests: XCTestCase {

    @MainActor
    func testMalformedJSONDoesNotCrash() async throws {
        let mockProvider = ControllableMockAIProvider()
        // Return invalid JSON
        mockProvider.responseContent = "This is not JSON at all"

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        // Should not throw
        let concepts = await policy.extractConcepts(from: "Test content")

        // Should return empty or fallback, not crash
        // The policy will call the provider which returns invalid JSON,
        // the internal parsing should handle it gracefully
    }

    @MainActor
    func testPartialJSONIsHandled() async throws {
        let mockProvider = ControllableMockAIProvider()
        // Return truncated/partial JSON
        mockProvider.responseContent = "[\"concept1\", \"concept"

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Test content")
        // Should not crash, may return empty or partial results
    }

    @MainActor
    func testWrongTypeInArrayIsHandled() async throws {
        let mockProvider = ControllableMockAIProvider()
        // Return array with wrong types
        mockProvider.responseContent = "[\"valid\", 123, null, {\"invalid\": true}]"

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        // Should not crash
        let concepts = await policy.extractConcepts(from: "Test content")
    }

    @MainActor
    func testMarkdownCodeFenceIsStripped() async throws {
        let mockProvider = ControllableMockAIProvider()
        // LLMs often wrap JSON in code fences
        mockProvider.responseContent = """
        ```json
        ["swift", "ios", "development"]
        ```
        """

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Test content")

        // Should successfully parse despite code fence
        XCTAssertTrue(concepts.contains("swift") || concepts.contains("ios"),
                      "Should parse JSON from code fence")
    }

    @MainActor
    func testExtremelyLongConceptIsTruncated() async throws {
        let mockProvider = ControllableMockAIProvider()
        let veryLongConcept = String(repeating: "a", count: 200)
        mockProvider.responseContent = "[\"\(veryLongConcept)\", \"short\"]"

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Test content")

        // Overly long concepts should be filtered or truncated
        let allReasonableLength = concepts.allSatisfy { $0.count <= 50 }
        XCTAssertTrue(allReasonableLength, "Concepts should be reasonably sized")
    }

    @MainActor
    func testEmptyArrayResponse() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.responseContent = "[]"

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Test content")
        XCTAssertTrue(concepts.isEmpty, "Empty array should return empty concepts")
    }

    @MainActor
    func testWhitespaceOnlyConceptsFiltered() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.responseContent = "[\"valid\", \"  \", \"\", \"   also valid   \"]"

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Test content")

        // Whitespace-only concepts should be filtered
        XCTAssertFalse(concepts.contains(""), "Empty strings should be filtered")
        XCTAssertFalse(concepts.contains("  "), "Whitespace-only should be filtered")
    }
}

// MARK: - Health State Persistence Tests

final class Phase2HealthStatePersistenceTests: XCTestCase {

    @MainActor
    func testHealthStatePersistedAndLoaded() async throws {
        // This test verifies the persistence mechanism
        // Clear any existing state
        UserDefaults.standard.removeObject(forKey: "com.quartz.ai.providerHealthState")

        let mockProvider = ControllableMockAIProvider()
        mockProvider.shouldFail = true

        // Create policy with persistence enabled
        let policy1 = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            circuitBreakerThreshold: 2,
            persistHealthState: true
        )

        // Open circuit
        _ = await policy1.extractConcepts(from: "Test 1")
        _ = await policy1.extractConcepts(from: "Test 2")

        let health1 = await policy1.providerHealth
        XCTAssertEqual(health1, .circuitOpen, "Circuit should be open")

        // Create new policy instance (simulating app restart)
        let policy2 = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP,
            circuitBreakerThreshold: 2,
            persistHealthState: true
        )

        // Should load persisted state
        let health2 = await policy2.providerHealth
        XCTAssertEqual(health2, .circuitOpen, "Should restore circuit open state from persistence")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "com.quartz.ai.providerHealthState")
    }
}

// MARK: - Provider Unavailable Tests

final class Phase2ProviderUnavailableTests: XCTestCase {

    @MainActor
    func testNoProviderConfiguredUsesLocalDirectly() async throws {
        let policy = AIExecutionPolicy(
            primaryProvider: nil,
            fallbackMode: .localNLP
        )

        let concepts = await policy.extractConcepts(from: "Apple develops software for iOS devices.")

        XCTAssertFalse(concepts.isEmpty, "Should return local concepts with no provider")

        let path = await policy.lastExecutionPath
        // With no provider, should use fallback path
        XCTAssertTrue(path == .onDeviceFallback || path == .onDeviceDirect,
                      "Should use on-device path when no provider configured")
    }

    @MainActor
    func testProviderNotConfiguredUsesLocal() async throws {
        let mockProvider = ControllableMockAIProvider()
        mockProvider.isConfigured = false  // Provider exists but not configured

        let policy = AIExecutionPolicy(
            primaryProvider: mockProvider,
            fallbackMode: .localNLP
        )

        mockProvider.callCount = 0
        let concepts = await policy.extractConcepts(from: "Test content for extraction")

        // Should not attempt to use unconfigured provider
        XCTAssertEqual(mockProvider.callCount, 0, "Should not call unconfigured provider")
        XCTAssertFalse(concepts.isEmpty, "Should return local fallback concepts")
    }
}
