import Foundation
import NaturalLanguage
import os

// MARK: - Execution Path

/// The path taken to execute an AI operation.
public enum AIExecutionPath: Equatable, Sendable {
    /// Successfully used the remote AI provider.
    case remote
    /// Used on-device processing directly (e.g., offline mode).
    case onDeviceDirect
    /// Fell back to on-device after remote failure.
    case onDeviceFallback
}

// MARK: - Provider Health State

/// Health state of an AI provider.
public enum AIProviderHealthState: Equatable, Sendable, Codable {
    /// Provider is working normally.
    case healthy
    /// Provider has had some failures but is still usable.
    case degraded
    /// Provider is completely unavailable.
    case unavailable
    /// Circuit breaker is open; provider is being skipped.
    case circuitOpen
}

// MARK: - Fallback Mode

/// Fallback modes for when remote AI fails.
public enum AIFallbackMode: Sendable {
    /// Fall back to on-device NLEmbedding for similarity.
    case onDeviceEmbeddings
    /// Fall back to local NLP (NLTagger) for entity extraction.
    case localNLP
    /// No fallback; fail immediately.
    case none
}

// MARK: - AI Execution Policy

/// Orchestrates AI execution with automatic fallback and circuit breaker protection.
///
/// Features:
/// - Automatic fallback from remote to on-device processing
/// - Circuit breaker to prevent hammering failing providers
/// - Health state tracking and persistence
/// - Offline mode support
/// - Timeout management
///
/// Thread Safety: All operations are actor-isolated.
public actor AIExecutionPolicy {
    private let primaryProvider: (any AIProvider)?
    private let fallbackMode: AIFallbackMode
    private let remoteTimeout: Duration
    private let circuitBreakerThreshold: Int
    private let circuitRecoveryInterval: Duration
    private let persistHealthState: Bool
    private let logger = Logger(subsystem: "com.quartz", category: "AIExecutionPolicy")

    // State
    public private(set) var providerHealth: AIProviderHealthState = .healthy
    public private(set) var lastExecutionPath: AIExecutionPath = .remote
    private var isOffline = false
    private var consecutiveFailures = 0
    private var circuitOpenedAt: Date?

    // Persistence key
    private static let healthStateKey = "com.quartz.ai.providerHealthState"

    public init(
        primaryProvider: (any AIProvider)?,
        fallbackMode: AIFallbackMode,
        remoteTimeout: Duration = .seconds(30),
        circuitBreakerThreshold: Int = 5,
        circuitRecoveryInterval: Duration = .seconds(60),
        persistHealthState: Bool = false
    ) {
        self.primaryProvider = primaryProvider
        self.fallbackMode = fallbackMode
        self.remoteTimeout = remoteTimeout
        self.circuitBreakerThreshold = circuitBreakerThreshold
        self.circuitRecoveryInterval = circuitRecoveryInterval
        self.persistHealthState = persistHealthState

        // Load persisted state if enabled
        if persistHealthState {
            self.providerHealth = Self.loadPersistedHealth() ?? .healthy
            if self.providerHealth == .circuitOpen {
                self.circuitOpenedAt = Date()
            }
        }
    }

    // MARK: - Offline Mode

    /// Sets offline mode, forcing all operations to use on-device processing.
    public func setOfflineMode(_ offline: Bool) {
        isOffline = offline
        if offline {
            lastExecutionPath = .onDeviceDirect
        }
    }

    // MARK: - Similarity Search

    /// Finds content similar to the query using AI or on-device fallback.
    public func findSimilarContent(to query: String) async -> [String]? {
        // Offline mode: go straight to on-device
        if isOffline {
            lastExecutionPath = .onDeviceDirect
            return await onDeviceSimilarity(for: query)
        }

        // Circuit open: check if recovery interval has passed
        if providerHealth == .circuitOpen {
            if shouldAttemptRecovery() {
                logger.info("Circuit recovery interval passed, attempting remote")
            } else {
                lastExecutionPath = .onDeviceFallback
                return await onDeviceSimilarity(for: query)
            }
        }

        // Try remote with timeout
        if let provider = primaryProvider, provider.isConfigured {
            do {
                let result = try await withTimeout(remoteTimeout) {
                    try await self.remoteSemanticSearch(query: query, provider: provider)
                }
                recordSuccess()
                lastExecutionPath = .remote
                return result
            } catch {
                recordFailure(error)
                logger.warning("Remote similarity failed: \(error.localizedDescription), falling back")
            }
        }

        // Fallback
        lastExecutionPath = .onDeviceFallback
        return await onDeviceSimilarity(for: query)
    }

    // MARK: - Concept Extraction

    /// Extracts concepts from text using AI or local NLP fallback.
    public func extractConcepts(from text: String) async -> [String] {
        return await extractConcepts(from: text, model: nil)
    }

    /// Extracts concepts from text using AI or local NLP fallback.
    ///
    /// - Parameters:
    ///   - text: The text to extract concepts from
    ///   - model: Optional model ID override
    ///   - systemPrompt: Optional custom system prompt for concept extraction
    /// - Returns: Array of extracted concept strings
    public func extractConcepts(
        from text: String,
        model: String?,
        systemPrompt: String? = nil
    ) async -> [String] {
        // Offline mode: go straight to on-device
        if isOffline {
            lastExecutionPath = .onDeviceDirect
            return localNLPExtractConcepts(from: text)
        }

        // Circuit open: check if recovery interval has passed
        if providerHealth == .circuitOpen {
            if shouldAttemptRecovery() {
                logger.info("Circuit recovery interval passed, attempting remote for concept extraction")
            } else {
                lastExecutionPath = .onDeviceFallback
                return localNLPExtractConcepts(from: text)
            }
        }

        // Try remote
        if let provider = primaryProvider, provider.isConfigured {
            do {
                let result = try await withTimeout(remoteTimeout) {
                    try await self.remoteConcepts(from: text, provider: provider, model: model, systemPrompt: systemPrompt)
                }
                recordSuccess()
                lastExecutionPath = .remote
                return result
            } catch {
                recordFailure(error)
                logger.warning("Remote concept extraction failed: \(error.localizedDescription)")
            }
        }

        // Fallback to local NLP
        lastExecutionPath = .onDeviceFallback
        return localNLPExtractConcepts(from: text)
    }

    // MARK: - Remote Operations

    private func remoteSemanticSearch(query: String, provider: any AIProvider) async throws -> [String] {
        let messages = [
            AIMessage(role: .system, content: "Return a JSON array of 5 related topics for the given query. Only output the JSON array, nothing else."),
            AIMessage(role: .user, content: query)
        ]
        let response = try await provider.chat(messages: messages, model: nil, temperature: 0.3)
        // Parse JSON array from response
        if let data = response.content.data(using: .utf8),
           let topics = try? JSONDecoder().decode([String].self, from: data) {
            return topics
        }
        return [response.content]
    }

    private func remoteConcepts(
        from text: String,
        provider: any AIProvider,
        model: String? = nil,
        systemPrompt: String? = nil
    ) async throws -> [String] {
        let prompt = systemPrompt ?? "Extract key concepts from the text. Return a JSON array of concept strings. Only output the JSON array."
        let messages = [
            AIMessage(role: .system, content: prompt),
            AIMessage(role: .user, content: text)
        ]
        let response = try await provider.chat(messages: messages, model: model, temperature: 0.1)
        return parseConceptsFromResponse(response.content)
    }

    /// Parses concept array from AI response, handling code fences and malformed output.
    private func parseConceptsFromResponse(_ response: String) -> [String] {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find JSON array bounds
        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else {
            return []
        }

        // Parse JSON
        guard let data = String(text[startIdx...endIdx]).data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        // Filter and normalize concepts
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 50 }
            .map { $0.lowercased() }
    }

    // MARK: - On-Device Operations

    private func onDeviceSimilarity(for query: String) async -> [String]? {
        // Use NLTagger to extract key nouns as "similar" concepts
        // This is a simple fallback when NLEmbedding isn't available
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = query

        var nouns: [String] = []
        tagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag, tag == .noun {
                let word = String(query[range])
                if word.count > 2 {
                    nouns.append(word)
                }
            }
            return true
        }

        // Try to use word embeddings if available
        if let embedding = NLEmbedding.wordEmbedding(for: .english) {
            var results: [String] = []
            for noun in nouns {
                let neighbors = embedding.neighbors(for: noun, maximumCount: 3)
                results.append(contentsOf: neighbors.map(\.0))
            }
            if !results.isEmpty {
                return Array(Set(results)).prefix(10).map { $0 }
            }
        }

        // Fallback: just return the nouns we found
        return nouns.isEmpty ? ["general", "topic", "content"] : nouns
    }

    private func localNLPExtractConcepts(from text: String) -> [String] {
        var concepts: [String] = []

        // Use NLTagger for named entity recognition and noun extraction
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text

        // Extract named entities
        let entityTypes: [NLTag] = [.personalName, .placeName, .organizationName]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if let tag, entityTypes.contains(tag) {
                let entity = String(text[range])
                if entity.count > 2 {
                    concepts.append(entity)
                }
            }
            return true
        }

        // Extract significant nouns
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag == .noun {
                let word = String(text[range])
                if word.count > 3 && !concepts.contains(word) {
                    concepts.append(word)
                }
            }
            return true
        }

        return Array(Set(concepts)).prefix(20).map { $0 }
    }

    // MARK: - Circuit Breaker

    private func recordSuccess() {
        consecutiveFailures = 0
        if providerHealth == .degraded || providerHealth == .circuitOpen {
            providerHealth = .healthy
            circuitOpenedAt = nil
            persistHealth()
            logger.info("Provider recovered to healthy state")
        }
    }

    private func recordFailure(_ error: Error) {
        consecutiveFailures += 1

        if consecutiveFailures >= circuitBreakerThreshold {
            providerHealth = .circuitOpen
            circuitOpenedAt = Date()
            persistHealth()
            logger.warning("Circuit breaker opened after \(self.consecutiveFailures) failures")
        } else if consecutiveFailures >= circuitBreakerThreshold / 2 {
            providerHealth = .degraded
            persistHealth()
        }
    }

    private func shouldAttemptRecovery() -> Bool {
        guard let openedAt = circuitOpenedAt else { return true }
        let elapsed = Date().timeIntervalSince(openedAt)
        return elapsed >= circuitRecoveryInterval.asTimeInterval
    }

    // MARK: - Persistence

    private func persistHealth() {
        guard persistHealthState else { return }
        UserDefaults.standard.set(providerHealth.rawValue, forKey: Self.healthStateKey)
    }

    private static func loadPersistedHealth() -> AIProviderHealthState? {
        guard let rawValue = UserDefaults.standard.string(forKey: healthStateKey) else {
            return nil
        }
        return AIProviderHealthState(rawValue: rawValue)
    }

    // MARK: - Timeout Helper

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw AIExecutionPolicyError.timeout
            }

            guard let result = try await group.next() else {
                throw AIExecutionPolicyError.timeout
            }

            group.cancelAll()
            return result
        }
    }
}

// MARK: - Errors

public enum AIExecutionPolicyError: LocalizedError {
    case timeout
    case noProvider
    case fallbackFailed

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "The operation timed out"
        case .noProvider:
            return "No AI provider configured"
        case .fallbackFailed:
            return "Both remote and fallback operations failed"
        }
    }
}

// MARK: - Duration Extension

private extension Duration {
    var asTimeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1_000_000_000_000_000_000
    }
}

// MARK: - Health State Codable

extension AIProviderHealthState: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .healthy: return "healthy"
        case .degraded: return "degraded"
        case .unavailable: return "unavailable"
        case .circuitOpen: return "circuitOpen"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "healthy": self = .healthy
        case "degraded": self = .degraded
        case "unavailable": self = .unavailable
        case "circuitOpen": self = .circuitOpen
        default: return nil
        }
    }
}

// MARK: - Fallback Knowledge Extractor

/// Knowledge extractor that falls back to local NLP when remote AI is unavailable.
public actor FallbackKnowledgeExtractor {
    private let primaryProvider: (any AIProvider)?
    private let logger = Logger(subsystem: "com.quartz", category: "KnowledgeExtractor")

    public init(primaryProvider: (any AIProvider)?) {
        self.primaryProvider = primaryProvider
    }

    /// Extracts named entities from text, falling back to local NLP.
    public func extractEntities(from text: String) async -> [String] {
        // Try remote if available
        if let provider = primaryProvider, provider.isConfigured {
            do {
                let messages = [
                    AIMessage(role: .system, content: "Extract named entities (people, places, organizations, concepts) from the text. Return a JSON array of strings."),
                    AIMessage(role: .user, content: text)
                ]
                let response = try await provider.chat(messages: messages, model: nil, temperature: 0.1)
                if let data = response.content.data(using: .utf8),
                   let entities = try? JSONDecoder().decode([String].self, from: data) {
                    return entities
                }
            } catch {
                logger.warning("Remote entity extraction failed: \(error.localizedDescription)")
            }
        }

        // Local NLP fallback
        return localExtractEntities(from: text)
    }

    /// Suggests tags for text, falling back to local analysis.
    public func suggestTags(for text: String) async -> [String] {
        // Try remote if available
        if let provider = primaryProvider, provider.isConfigured {
            do {
                let messages = [
                    AIMessage(role: .system, content: "Suggest 3-5 tags for categorizing this text. Return a JSON array of lowercase tag strings."),
                    AIMessage(role: .user, content: text)
                ]
                let response = try await provider.chat(messages: messages, model: nil, temperature: 0.3)
                if let data = response.content.data(using: .utf8),
                   let tags = try? JSONDecoder().decode([String].self, from: data) {
                    return tags
                }
            } catch {
                logger.warning("Remote tag suggestion failed: \(error.localizedDescription)")
            }
        }

        // Local analysis fallback
        return localSuggestTags(for: text)
    }

    // MARK: - Local NLP

    private func localExtractEntities(from text: String) -> [String] {
        var entities: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text

        // Named entities
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                let entity = String(text[range])
                if entity.count > 1 && !entity.allSatisfy({ $0.isWhitespace }) {
                    entities.append(entity)
                }
            }
            return true
        }

        // Capitalized nouns (potential proper nouns)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag == .noun {
                let word = String(text[range])
                if word.first?.isUppercase == true && word.count > 2 && !entities.contains(word) {
                    entities.append(word)
                }
            }
            return true
        }

        return Array(Set(entities))
    }

    private func localSuggestTags(for text: String) -> [String] {
        var tagCandidates: [String: Int] = [:]

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text.lowercased()

        // Count significant nouns
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag == .noun {
                let word = String(text[range]).lowercased()
                if word.count > 3 {
                    tagCandidates[word, default: 0] += 1
                }
            }
            return true
        }

        // Return top tags by frequency
        return tagCandidates
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
    }
}
