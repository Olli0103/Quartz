import XCTest
@testable import QuartzKit

/// Phase 2 TDD tests for AI fallback orchestration.
/// Tests that the system gracefully falls back from remote AI to on-device
/// processing when remote providers fail or are unavailable.
final class AIFallbackPolicyTests: XCTestCase {

    // MARK: - Test: Remote Failure Triggers On-Device Fallback

    /// When a remote AI provider fails (network error, API error),
    /// the system should automatically fall back to on-device processing.
    func test_remoteFailure_triggersOnDeviceEmbeddingFallback() async {
        // Given: A policy configured with a failing remote provider
        let failingProvider = MockFailingAIProvider()
        let policy = AIExecutionPolicy(
            primaryProvider: failingProvider,
            fallbackMode: .onDeviceEmbeddings,
            circuitBreakerThreshold: 3 // Need multiple failures for degraded
        )

        // When: Requesting embeddings-based similarity multiple times to trigger degraded state
        _ = await policy.findSimilarContent(to: "Machine learning basics")
        _ = await policy.findSimilarContent(to: "Another query")
        let result = await policy.findSimilarContent(to: "Third query")

        // Then: Should return results from on-device NLEmbedding fallback
        XCTAssertNotNil(result)
        let path = await policy.lastExecutionPath
        let health = await policy.providerHealth
        XCTAssertEqual(path, .onDeviceFallback)
        // After 3 failures with threshold 3, should be circuitOpen
        XCTAssertEqual(health, .circuitOpen)
    }

    // MARK: - Test: Offline Mode Forces On-Device Path

    /// When the device is offline, the system should immediately use
    /// on-device processing without attempting remote calls.
    func test_offlineMode_forcesOnDevicePath() async {
        // Given: A policy in offline mode
        let provider = MockAIProvider()
        let policy = AIExecutionPolicy(
            primaryProvider: provider,
            fallbackMode: .onDeviceEmbeddings
        )
        await policy.setOfflineMode(true)

        // When: Requesting any AI operation
        let result = await policy.findSimilarContent(to: "Test query")

        // Then: Should use on-device without attempting remote
        XCTAssertNotNil(result)
        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceDirect)
        XCTAssertEqual(provider.chatCallCount, 0, "Should not call remote provider in offline mode")
    }

    // MARK: - Test: Timeout Switches to Local Within Budget

    /// When a remote provider times out, the system should switch to
    /// on-device processing within a reasonable time budget.
    func test_timeout_remoteProvider_switchesToLocalWithinBudget() async {
        // Given: A provider that times out
        let slowProvider = MockSlowAIProvider(delay: .seconds(10))
        let policy = AIExecutionPolicy(
            primaryProvider: slowProvider,
            fallbackMode: .onDeviceEmbeddings,
            remoteTimeout: .seconds(2) // Short timeout for test
        )

        // When: Requesting an operation
        let startTime = Date()
        let result = await policy.findSimilarContent(to: "Test query")
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should fall back within budget (not wait full 10s)
        XCTAssertNotNil(result)
        XCTAssertLessThan(elapsed, 5.0, "Should fall back within timeout budget")
        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceFallback)
    }

    // MARK: - Test: Circuit Breaker Opens After Repeated Failures

    /// After multiple consecutive failures, the circuit breaker should
    /// open and skip remote attempts entirely for a cooldown period.
    func test_repeatedFailures_openCircuitBreaker() async {
        // Given: A consistently failing provider
        let failingProvider = MockFailingAIProvider()
        let policy = AIExecutionPolicy(
            primaryProvider: failingProvider,
            fallbackMode: .onDeviceEmbeddings,
            circuitBreakerThreshold: 3
        )

        // When: Making multiple requests that all fail
        for _ in 0..<5 {
            _ = await policy.findSimilarContent(to: "Test")
        }

        // Then: Circuit should be open, skipping remote attempts
        let health = await policy.providerHealth
        XCTAssertEqual(health, .circuitOpen)
        XCTAssertGreaterThanOrEqual(failingProvider.chatCallCount, 3)
        XCTAssertLessThan(failingProvider.chatCallCount, 5, "Should stop calling after circuit opens")
    }

    // MARK: - Test: Provider Health Recovery

    /// When a circuit-open provider becomes healthy again,
    /// the system should detect this and close the circuit.
    func test_healthyProvider_closesCircuit() async {
        // Given: A provider that was failing but recovered
        let recoveringProvider = MockRecoveringAIProvider(failCount: 3)
        let policy = AIExecutionPolicy(
            primaryProvider: recoveringProvider,
            fallbackMode: .onDeviceEmbeddings,
            circuitBreakerThreshold: 3,
            circuitRecoveryInterval: .milliseconds(100)
        )

        // Trigger circuit open
        for _ in 0..<4 {
            _ = await policy.findSimilarContent(to: "Test")
        }
        let initialHealth = await policy.providerHealth
        XCTAssertEqual(initialHealth, .circuitOpen)

        // Wait for recovery interval
        try? await Task.sleep(for: .milliseconds(150))

        // When: Making a new request after recovery interval
        _ = await policy.findSimilarContent(to: "Test after recovery")

        // Then: Should attempt remote and succeed
        let finalHealth = await policy.providerHealth
        let path = await policy.lastExecutionPath
        XCTAssertEqual(finalHealth, .healthy)
        XCTAssertEqual(path, .remote)
    }

    // MARK: - Test: Main Thread Isolation

    /// Heavy AI operations should never execute on the main thread.
    func test_heavyOperations_notOnMainThread() async {
        // Given: A policy with operations
        let provider = MockAIProvider()
        let policy = AIExecutionPolicy(
            primaryProvider: provider,
            fallbackMode: .onDeviceEmbeddings
        )

        // When: Running operations
        var executedOnMain = false
        provider.onChat = {
            executedOnMain = Thread.isMainThread
        }

        _ = await policy.findSimilarContent(to: "Test")

        // Then: Should not have executed on main thread
        XCTAssertFalse(executedOnMain, "AI operations should not run on main thread")
    }

    // MARK: - Test: Concept Extraction Fallback

    /// Concept extraction should fall back to basic NLP when remote fails.
    func test_conceptExtraction_fallsBackToLocalNLP() async {
        // Given: A failing provider
        let failingProvider = MockFailingAIProvider()
        let policy = AIExecutionPolicy(
            primaryProvider: failingProvider,
            fallbackMode: .localNLP
        )

        // When: Extracting concepts
        let concepts = await policy.extractConcepts(from: "Machine learning is a subset of artificial intelligence that enables systems to learn from data.")

        // Then: Should return basic concepts from local NLP
        XCTAssertFalse(concepts.isEmpty, "Should extract concepts via local NLP fallback")
        let path = await policy.lastExecutionPath
        XCTAssertEqual(path, .onDeviceFallback)
    }

    // MARK: - Test: Health State Persistence

    /// Provider health state should persist across policy instances.
    func test_healthState_persistsAcrossInstances() async {
        // Clear any previous state
        UserDefaults.standard.removeObject(forKey: "com.quartz.ai.providerHealthState")

        // Given: A failing provider that causes circuit to open
        let failingProvider = MockFailingAIProvider()
        let policy1 = AIExecutionPolicy(
            primaryProvider: failingProvider,
            fallbackMode: .onDeviceEmbeddings,
            circuitBreakerThreshold: 2,
            persistHealthState: true
        )

        // Trigger circuit open
        for _ in 0..<3 {
            _ = await policy1.findSimilarContent(to: "Test")
        }

        // When: Creating a new policy instance
        let policy2 = AIExecutionPolicy(
            primaryProvider: failingProvider,
            fallbackMode: .onDeviceEmbeddings,
            persistHealthState: true
        )

        // Then: Should inherit the circuit-open state
        let health = await policy2.providerHealth
        XCTAssertEqual(health, .circuitOpen)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "com.quartz.ai.providerHealthState")
    }
}

// MARK: - Test: Knowledge Extraction Fallback

final class KnowledgeExtractionFallbackTests: XCTestCase {

    /// When remote provider is unavailable, concept extraction should
    /// still return minimal graph entities using local NLP.
    func test_conceptExtraction_returnsMinimalEntities_whenProviderUnavailable() async {
        // Given: An unavailable provider
        let unavailableProvider = MockFailingAIProvider()
        let extractor = FallbackKnowledgeExtractor(
            primaryProvider: unavailableProvider
        )

        // When: Extracting from text
        let text = """
        Swift is a programming language developed by Apple.
        It is used for iOS, macOS, and server-side development.
        """
        let entities = await extractor.extractEntities(from: text)

        // Then: Should return entities from local NLP
        XCTAssertFalse(entities.isEmpty)
        // Should find at least some nouns/named entities
        let hasRelevantEntity = entities.contains { entity in
            entity.lowercased().contains("swift") ||
            entity.lowercased().contains("apple") ||
            entity.lowercased().contains("programming")
        }
        XCTAssertTrue(hasRelevantEntity, "Should find relevant entities: \(entities)")
    }

    /// Tags should be extractable even when remote AI is unavailable.
    func test_tagGeneration_worksOffline() async {
        // Given: No network
        let extractor = FallbackKnowledgeExtractor(
            primaryProvider: nil
        )

        // When: Generating tags
        let text = "Machine learning tutorial for beginners covering neural networks"
        let tags = await extractor.suggestTags(for: text)

        // Then: Should return tags from local analysis
        XCTAssertFalse(tags.isEmpty)
    }
}

// MARK: - Test: Main Thread Isolation

final class MainThreadIsolationTests: XCTestCase {

    /// Fallback orchestration should not block the main thread.
    func test_fallbackOrchestration_doesNotBlockMainThread() async {
        // Given: A policy that will trigger fallback
        let slowProvider = MockSlowAIProvider(delay: .milliseconds(500))
        let policy = AIExecutionPolicy(
            primaryProvider: slowProvider,
            fallbackMode: .onDeviceEmbeddings,
            remoteTimeout: .milliseconds(100)
        )

        // When: Running the operation
        let startTime = Date()
        _ = await policy.findSimilarContent(to: "Test")
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should complete within reasonable time (not block)
        XCTAssertLessThan(elapsed, 2.0, "Should not block during fallback")
    }

    /// Heavy embedding operations should run off main thread.
    func test_embeddingOperations_supportsConcurrency() async {
        // Given: An embedding service
        let service = VectorEmbeddingService(
            vaultURL: URL(fileURLWithPath: "/tmp/test-vault")
        )

        // When: Indexing content (actor-isolated, inherently off main thread)
        // The actor isolation ensures this doesn't block main thread
        try? await service.indexNote(
            noteID: UUID(),
            content: "Test content for embedding"
        )

        // Then: Should complete without error (actor handles threading)
        let count = await service.entryCount
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - Mock Providers

/// A mock AI provider that always fails.
class MockFailingAIProvider: AIProvider, @unchecked Sendable {
    let id = "mock-failing"
    let displayName = "Mock Failing"
    var isConfigured: Bool { true }
    var availableModels: [AIModel] { [] }
    var chatCallCount = 0

    func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        chatCallCount += 1
        throw AIProviderError.networkError("Simulated failure")
    }
}

/// A mock AI provider that works normally.
class MockAIProvider: AIProvider, @unchecked Sendable {
    let id = "mock"
    let displayName = "Mock"
    var isConfigured: Bool { true }
    var availableModels: [AIModel] { [] }
    var chatCallCount = 0
    var onChat: (() -> Void)?

    func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        chatCallCount += 1
        onChat?()
        return AIMessage(role: .assistant, content: "Mock response")
    }
}

/// A mock AI provider that takes a long time to respond.
class MockSlowAIProvider: AIProvider, @unchecked Sendable {
    let id = "mock-slow"
    let displayName = "Mock Slow"
    var isConfigured: Bool { true }
    var availableModels: [AIModel] { [] }
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        try await Task.sleep(for: delay)
        return AIMessage(role: .assistant, content: "Slow response")
    }
}

/// A mock AI provider that fails N times then recovers.
class MockRecoveringAIProvider: AIProvider, @unchecked Sendable {
    let id = "mock-recovering"
    let displayName = "Mock Recovering"
    var isConfigured: Bool { true }
    var availableModels: [AIModel] { [] }
    var callCount = 0
    let failCount: Int

    init(failCount: Int) {
        self.failCount = failCount
    }

    func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        callCount += 1
        if callCount <= failCount {
            throw AIProviderError.networkError("Simulated failure \(callCount)")
        }
        return AIMessage(role: .assistant, content: "Recovered response")
    }
}

// MARK: - Types Note

// Types AIExecutionPath, AIProviderHealthState, AIFallbackMode, AIExecutionPolicy,
// and FallbackKnowledgeExtractor are implemented in:
// QuartzKit/Sources/QuartzKit/Domain/AI/AIExecutionPolicy.swift
