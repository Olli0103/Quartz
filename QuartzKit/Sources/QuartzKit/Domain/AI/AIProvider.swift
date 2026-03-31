import Foundation
import Observation
import Security
import os

// MARK: - AI Provider Protocol

/// Last-known connectivity to the provider endpoint (distinct from having credentials / URL set).
public enum AIProviderReachability: Sendable, Equatable {
    /// No probe yet (e.g. Ollama not tested this session).
    case unknown
    case reachable
    case unreachable
}

/// Adapter pattern: each AI provider implements this protocol.
public protocol AIProvider: Sendable {
    /// Unique identifier for the provider.
    var id: String { get }
    /// Display name.
    var displayName: String { get }
    /// Whether credentials or endpoint settings are present (not whether the network responds).
    var isConfigured: Bool { get }
    /// Whether the remote endpoint was reachable at the last check. API-key providers default to `.reachable` when configured.
    var reachability: AIProviderReachability { get }
    /// Available models.
    var availableModels: [AIModel] { get }

    /// Chat completion with context.
    func chat(
        messages: [AIMessage],
        model: String?,
        temperature: Double
    ) async throws -> AIMessage

    /// Streaming chat completion — yields content tokens as they arrive.
    ///
    /// Default implementation falls back to the blocking `chat()` call
    /// and yields the entire response at once. Providers that support SSE
    /// (OpenAI, OpenRouter) override this for real token-by-token streaming.
    func streamChat(
        messages: [AIMessage],
        model: String?,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>

    /// Tests connectivity and configuration. Default implementation sends a minimal chat.
    func checkConnection() async -> Bool
}

public extension AIProvider {
    /// Default: treat key-based configuration as usable; network is not preflighted.
    var reachability: AIProviderReachability {
        isConfigured ? .reachable : .unreachable
    }

    /// Default streaming: falls back to blocking chat() and yields the full response.
    func streamChat(
        messages: [AIMessage],
        model: String?,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let capturedMessages = messages
            let capturedModel = model
            let capturedTemp = temperature
            Task {
                do {
                    let response = try await self.chat(
                        messages: capturedMessages,
                        model: capturedModel,
                        temperature: capturedTemp
                    )
                    continuation.yield(response.content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func checkConnection() async -> Bool {
        guard isConfigured else { return false }
        do {
            // Use a minimal request with short timeout to verify connectivity
            let model = availableModels.first?.id
            _ = try await chat(messages: [AIMessage(role: .user, content: "ping")], model: model, temperature: 0)
            return true
        } catch {
            return false
        }
    }
}

/// An AI model.
public struct AIModel: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let contextWindow: Int
    public let provider: String

    public init(id: String, name: String, contextWindow: Int, provider: String) {
        self.id = id
        self.name = name
        self.contextWindow = contextWindow
        self.provider = provider
    }
}

/// A chat message.
public struct AIMessage: Identifiable, Sendable, Codable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date

    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    public init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Provider Implementations

/// OpenAI Provider (GPT-4o, etc.)
public final class OpenAIProvider: AIProvider, Sendable {
    public let id = "openai"
    public let displayName = "OpenAI"
    private let keychain: KeychainHelper

    // Static well-known URL – constructed once at load time.
    private static let chatURL: URL = {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            preconditionFailure("Invalid static API URL for OpenAI")
        }
        return url
    }()

    public var isConfigured: Bool { keychain.hasKey(for: id) }

    public var availableModels: [AIModel] {
        [
            AIModel(id: "gpt-4o", name: "GPT-4o", contextWindow: 128_000, provider: id),
            AIModel(id: "gpt-4o-mini", name: "GPT-4o Mini", contextWindow: 128_000, provider: id),
        ]
    }

    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }

    public func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        try await withRetry {
            let apiKey = try await keychain.getKey(for: id)
            let modelID = model ?? "gpt-4o"

            let body = OpenAIChatBody(
                model: modelID,
                messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                temperature: temperature
            )

            var request = URLRequest(url: Self.chatURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (rawData, httpResponse) = try await Self.session.data(for: request)
            let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
            let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

            guard let content = response.choices.first?.message.content else {
                throw AIProviderError.emptyResponse
            }
            return AIMessage(role: .assistant, content: content)
        }
    }

    public func streamChat(
        messages: [AIMessage],
        model: String?,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let keychain = self.keychain
        let providerID = self.id
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await keychain.getKey(for: providerID)
                    let modelID = model ?? "gpt-4o"

                    var body = OpenAIChatBody(
                        model: modelID,
                        messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                        temperature: temperature
                    )
                    body.stream = true

                    var request = URLRequest(url: OpenAIProvider.chatURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (asyncBytes, httpResponse) = try await aiURLSession.bytes(for: request)

                    if let http = httpResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var errorData = Data()
                        for try await byte in asyncBytes { errorData.append(byte) }
                        _ = try validateHTTPResponse(errorData, httpResponse, provider: providerID)
                    }

                    for try await line in asyncBytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                              let content = chunk.choices?.first?.delta?.content,
                              !content.isEmpty else { continue }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Shared URLSession with robust timeouts for AI requests.
/// LLM responses can take 30-60+ seconds for complex queries.
/// nonisolated(unsafe) required for global stored property in Swift 6.
/// URLSession is thread-safe; the property is never mutated after initialization.
nonisolated(unsafe) private let aiURLSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60    // Time to receive first byte
    config.timeoutIntervalForResource = 300  // Total time for entire response (5 min for long streaming)
    config.waitsForConnectivity = true
    config.allowsConstrainedNetworkAccess = true
    config.allowsExpensiveNetworkAccess = true
    return URLSession(configuration: config)
}()

/// Retry configuration for AI requests.
private enum AIRetryConfig {
    static let maxRetries = 3
    static let baseDelay: TimeInterval = 1.0  // Exponential backoff: 1s, 2s, 4s

    /// Delays for each retry attempt.
    static func delay(for attempt: Int) -> TimeInterval {
        baseDelay * pow(2.0, Double(attempt))
    }

    /// Whether an error is retryable.
    static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost:
                return true
            default:
                return false
            }
        }
        if let aiError = error as? AIProviderError {
            switch aiError {
            case .rateLimited, .serverError:
                return true
            default:
                return false
            }
        }
        return false
    }
}

/// Executes an async operation with retry logic.
private func withRetry<T>(
    maxAttempts: Int = AIRetryConfig.maxRetries,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            guard AIRetryConfig.isRetryable(error), attempt < maxAttempts - 1 else {
                throw error
            }
            let delay = AIRetryConfig.delay(for: attempt)
            try await Task.sleep(for: .seconds(delay))
        }
    }
    throw lastError ?? AIProviderError.networkError("Unknown error after retries")
}

private extension AIProvider {
    static var session: URLSession { aiURLSession }
}

/// Anthropic Provider (Claude)
public final class AnthropicProvider: AIProvider, Sendable {
    public let id = "anthropic"
    public let displayName = "Anthropic"
    private let keychain: KeychainHelper

    private static let messagesURL: URL = {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            preconditionFailure("Invalid static API URL for Anthropic")
        }
        return url
    }()

    public var isConfigured: Bool { keychain.hasKey(for: id) }

    public var availableModels: [AIModel] {
        [
            AIModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", contextWindow: 200_000, provider: id),
            AIModel(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", contextWindow: 200_000, provider: id),
            AIModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", contextWindow: 200_000, provider: id),
        ]
    }

    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }

    public func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        try await withRetry {
            let apiKey = try await keychain.getKey(for: id)
            let modelID = model ?? "claude-sonnet-4-6"

            let systemMsg = messages.first { $0.role == .system }?.content
            let chatMessages = messages
                .filter { $0.role != .system }
                .map { AnthropicMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content) }

            let body = AnthropicChatBody(
                model: modelID,
                max_tokens: 4096,
                system: systemMsg,
                messages: chatMessages,
                temperature: temperature
            )

            var request = URLRequest(url: Self.messagesURL)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (rawData, httpResponse) = try await Self.session.data(for: request)
            let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
            let response = try JSONDecoder().decode(AnthropicChatResponse.self, from: data)

            guard let content = response.content.first?.text else {
                throw AIProviderError.emptyResponse
            }
            return AIMessage(role: .assistant, content: content)
        }
    }
}

/// Ollama Provider (local models)
public final class OllamaProvider: AIProvider, @unchecked Sendable {
    public let id = "ollama"
    public let displayName = "Ollama (Local)"

    private static let urlDefaultsKey = "ollamaBaseURL"

    public static let defaultBaseURL: URL = {
        guard let url = URL(string: "http://localhost:11434") else {
            preconditionFailure("Invalid static URL for Ollama")
        }
        return url
    }()

    public var baseURL: URL {
        if let stored = UserDefaults.standard.string(forKey: Self.urlDefaultsKey),
           let url = URL(string: stored) {
            return url
        }
        return Self.defaultBaseURL
    }

    public static func setBaseURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: urlDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.reachabilityKey)
    }

    /// Returns the currently stored base URL string for UI display.
    public static func getStoredBaseURLString() -> String {
        UserDefaults.standard.string(forKey: urlDefaultsKey) ?? defaultBaseURL.absoluteString
    }

    private static let reachabilityKey = "ollamaReachabilityState"

    /// A base URL is configured (default localhost counts).
    public var isConfigured: Bool { true }

    public var reachability: AIProviderReachability {
        switch UserDefaults.standard.string(forKey: Self.reachabilityKey) {
        case "reachable": return .reachable
        case "unreachable": return .unreachable
        default: return .unknown
        }
    }

    private static func persistReachability(_ state: AIProviderReachability) {
        let raw: String
        switch state {
        case .unknown: raw = "unknown"
        case .reachable: raw = "reachable"
        case .unreachable: raw = "unreachable"
        }
        UserDefaults.standard.set(raw, forKey: Self.reachabilityKey)
    }

    public var availableModels: [AIModel] {
        [
            AIModel(id: "llama3.1", name: "Llama 3.1", contextWindow: 128_000, provider: id),
            AIModel(id: "mistral", name: "Mistral", contextWindow: 32_000, provider: id),
            AIModel(id: "gemma2", name: "Gemma 2", contextWindow: 8_000, provider: id),
        ]
    }

    public init() {}

    public func checkConnection() async -> Bool {
        let url = baseURL.appending(path: "api/tags")
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            Self.persistReachability(ok ? .reachable : .unreachable)
            return ok
        } catch {
            Self.persistReachability(.unreachable)
            return false
        }
    }

    public func fetchAvailableModels() async throws -> [AIModel] {
        let url = baseURL.appending(path: "api/tags")
        let (data, _) = try await URLSession.shared.data(from: url)
        struct OllamaModelsResponse: Codable {
            struct Model: Codable {
                let name: String
                let size: Int64?
                let modified_at: String?
            }
            let models: [Model]
        }
        let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return response.models.map { AIModel(id: $0.name, name: $0.name, contextWindow: 128_000, provider: "ollama") }
    }

    public func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        try await withRetry {
            let modelID = model ?? "llama3.1"

            let body = OllamaChatBody(
                model: modelID,
                messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                stream: false,
                options: .init(temperature: temperature)
            )

            var request = URLRequest(url: baseURL.appending(path: "api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (rawData, httpResponse) = try await Self.session.data(for: request)
            let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
            let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

            return AIMessage(role: .assistant, content: response.message.content)
        }
    }
}

/// Google Gemini Provider
public final class GeminiProvider: AIProvider, Sendable {
    public let id = "gemini"
    public let displayName = "Google Gemini"
    private let keychain: KeychainHelper

    public var isConfigured: Bool { keychain.hasKey(for: id) }

    public var availableModels: [AIModel] {
        [
            AIModel(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", contextWindow: 1_000_000, provider: id),
            AIModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", contextWindow: 1_000_000, provider: id),
            AIModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", contextWindow: 1_000_000, provider: id),
        ]
    }

    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }

    public func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        try await withRetry {
            let apiKey = try await keychain.getKey(for: id)
            let modelID = model ?? "gemini-2.5-flash"

            let systemMsg = messages.first { $0.role == .system }?.content
            let chatMessages = messages
                .filter { $0.role != .system }
                .map { GeminiContent(role: $0.role == .user ? "user" : "model", parts: [.init(text: $0.content)]) }

            let body = GeminiChatBody(
                contents: chatMessages,
                systemInstruction: systemMsg.map { GeminiContent(role: "user", parts: [.init(text: $0)]) },
                generationConfig: GeminiGenerationConfig(temperature: temperature, maxOutputTokens: 8192)
            )

            guard let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                throw AIProviderError.networkError("Invalid model ID: \(modelID)")
            }
            let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModelID):generateContent"
            guard let url = URL(string: urlString) else {
                throw AIProviderError.networkError("Invalid model ID: \(modelID)")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try JSONEncoder().encode(body)

            let (rawData, httpResponse) = try await Self.session.data(for: request)
            let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
            let response = try JSONDecoder().decode(GeminiChatResponse.self, from: data)

            guard let text = response.candidates?.first?.content.parts.first?.text else {
                throw AIProviderError.emptyResponse
            }
            return AIMessage(role: .assistant, content: text)
        }
    }
}

/// OpenRouter Provider – access to hundreds of models via a single API.
public final class OpenRouterProvider: AIProvider, Sendable {
    public let id = "openrouter"
    public let displayName = "OpenRouter"
    private let keychain: KeychainHelper

    private static let chatURL: URL = {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            preconditionFailure("Invalid static API URL for OpenRouter")
        }
        return url
    }()

    private static let modelsURL: URL = {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            preconditionFailure("Invalid static models URL for OpenRouter")
        }
        return url
    }()

    public var isConfigured: Bool { keychain.hasKey(for: id) }

    public func checkConnection() async -> Bool {
        guard isConfigured else { return false }
        do {
            let apiKey = try await keychain.getKey(for: id)
            var request = URLRequest(url: Self.modelsURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (_, httpResponse) = try await Self.session.data(for: request)
            guard let response = httpResponse as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(response.statusCode)
        } catch {
            return false
        }
    }

    public var availableModels: [AIModel] {
        [
            AIModel(id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4", contextWindow: 200_000, provider: id),
            AIModel(id: "openai/gpt-4o", name: "GPT-4o", contextWindow: 128_000, provider: id),
            AIModel(id: "google/gemini-2.5-pro-preview", name: "Gemini 2.5 Pro", contextWindow: 1_000_000, provider: id),
            AIModel(id: "meta-llama/llama-4-maverick", name: "Llama 4 Maverick", contextWindow: 1_000_000, provider: id),
            AIModel(id: "deepseek/deepseek-r1", name: "DeepSeek R1", contextWindow: 64_000, provider: id),
            AIModel(id: "mistralai/mistral-large-2", name: "Mistral Large 2", contextWindow: 128_000, provider: id),
        ]
    }

    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }

    public func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
        try await withRetry {
            let apiKey = try await keychain.getKey(for: id)
            let modelID = model ?? "anthropic/claude-sonnet-4"

            // OpenRouter uses the OpenAI-compatible format
            let body = OpenAIChatBody(
                model: modelID,
                messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                temperature: temperature
            )

            var request = URLRequest(url: Self.chatURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Quartz Notes", forHTTPHeaderField: "X-Title")
            request.httpBody = try JSONEncoder().encode(body)

            let (rawData, httpResponse) = try await Self.session.data(for: request)
            let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
            let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

            guard let content = response.choices.first?.message.content else {
                throw AIProviderError.emptyResponse
            }
            return AIMessage(role: .assistant, content: content)
        }
    }

    public func streamChat(
        messages: [AIMessage],
        model: String?,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let keychain = self.keychain
        let providerID = self.id
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await keychain.getKey(for: providerID)
                    let modelID = model ?? "anthropic/claude-sonnet-4"

                    var body = OpenAIChatBody(
                        model: modelID,
                        messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                        temperature: temperature
                    )
                    body.stream = true

                    var request = URLRequest(url: OpenRouterProvider.chatURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Quartz Notes", forHTTPHeaderField: "X-Title")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (asyncBytes, httpResponse) = try await aiURLSession.bytes(for: request)

                    if let http = httpResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var errorData = Data()
                        for try await byte in asyncBytes { errorData.append(byte) }
                        _ = try validateHTTPResponse(errorData, httpResponse, provider: providerID)
                    }

                    for try await line in asyncBytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                              let content = chunk.choices?.first?.delta?.content,
                              !content.isEmpty else { continue }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Provider Registry

/// Registry of all available AI providers.
/// @unchecked Sendable: all mutable state is protected by @MainActor isolation.
/// Safe to share references across actor boundaries (e.g. chat service actors).
@Observable
@MainActor
public final class AIProviderRegistry: @unchecked Sendable {
    public private(set) var providers: [any AIProvider]
    public var selectedProviderID: String {
        didSet { persistSelection() }
    }
    public var selectedModelID: String? {
        didSet { persistSelection() }
    }

    public static let shared = AIProviderRegistry()

    private let customModelStore = CustomModelStore()

    private static let providerKey = "quartz.ai.selectedProviderID"
    private static let modelKey = "quartz.ai.selectedModelID"

    public init() {
        let providers: [any AIProvider] = [
            OpenAIProvider(),
            AnthropicProvider(),
            GeminiProvider(),
            OpenRouterProvider(),
            OllamaProvider(),
        ]
        self.providers = providers
        self.selectedProviderID = UserDefaults.standard.string(forKey: Self.providerKey) ?? "ollama"
        self.selectedModelID = UserDefaults.standard.string(forKey: Self.modelKey)
    }

    private func persistSelection() {
        UserDefaults.standard.set(selectedProviderID, forKey: Self.providerKey)
        if let model = selectedModelID {
            UserDefaults.standard.set(model, forKey: Self.modelKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.modelKey)
        }
    }

    public var selectedProvider: (any AIProvider)? {
        providers.first { $0.id == selectedProviderID }
    }

    public var configuredProviders: [any AIProvider] {
        providers.filter(\.isConfigured)
    }

    /// Providers with settings in place and not known to be offline (Ollama server must be reachable when last probed).
    public var providersReadyForUse: [any AIProvider] {
        providers.filter { $0.isConfigured && $0.reachability != .unreachable }
    }

    /// All models for a provider: built-in + user-defined.
    public func allModels(for providerID: String) async -> [AIModel] {
        let builtIn = providers.first { $0.id == providerID }?.availableModels ?? []
        let custom = await customModelStore.customModels(for: providerID)
        return builtIn + custom
    }

    /// Add a custom model.
    public func addCustomModel(id modelID: String, name: String? = nil, contextWindow: Int = 128_000, forProvider providerID: String) async {
        let model = AIModel(
            id: modelID,
            name: name ?? modelID,
            contextWindow: contextWindow,
            provider: providerID
        )
        await customModelStore.add(model, for: providerID)
    }

    /// Remove a custom model.
    public func removeCustomModel(id modelID: String, forProvider providerID: String) async {
        await customModelStore.remove(modelID: modelID, for: providerID)
    }

    /// All user-defined models for a provider.
    public func customModels(for providerID: String) async -> [AIModel] {
        await customModelStore.customModels(for: providerID)
    }
}

// MARK: - Custom Model Store

/// Persists user-defined models in UserDefaults.
/// Actor isolation guarantees atomic read/write access.
public actor CustomModelStore {
    private let defaults = UserDefaults.standard
    private let storageKey = "com.quartz.customModels"
    private let logger = Logger(subsystem: "com.quartz", category: "CustomModelStore")

    public init() {}

    public func customModels(for providerID: String) -> [AIModel] {
        loadAll()[providerID] ?? []
    }

    public func add(_ model: AIModel, for providerID: String) {
        var all = loadAll()
        var models = all[providerID] ?? []
        // Avoid duplicates
        models.removeAll { $0.id == model.id }
        models.append(model)
        all[providerID] = models
        save(all)
    }

    public func remove(modelID: String, for providerID: String) {
        var all = loadAll()
        all[providerID]?.removeAll { $0.id == modelID }
        save(all)
    }

    private func loadAll() -> [String: [AIModel]] {
        guard let data = defaults.data(forKey: storageKey) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: [AIModel]].self, from: data)
        } catch {
            logger.error("Failed to decode custom models: \(error.localizedDescription)")
            return [:]
        }
    }

    private func save(_ models: [String: [AIModel]]) {
        do {
            let data = try JSONEncoder().encode(models)
            defaults.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to encode custom models: \(error.localizedDescription)")
        }
    }
}

// MARK: - Keychain Helper

/// Secure storage of API keys in the Keychain.
public actor KeychainHelper {
    public static let shared = KeychainHelper()

    private let servicePrefix = "com.quartz.ai-provider."

    public init() {}

    public func saveKey(_ key: String, for providerID: String) throws {
        let service = servicePrefix + providerID
        let data = Data(key.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw AIProviderError.keychainError(status)
        }
    }

    public func getKey(for providerID: String) throws -> String {
        let service = servicePrefix + providerID

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw AIProviderError.noAPIKey(providerID)
        }
        return key
    }

    public nonisolated func hasKey(for providerID: String) -> Bool {
        let service = servicePrefix + providerID
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func deleteKey(for providerID: String) {
        let service = servicePrefix + providerID
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum AIProviderError: LocalizedError, Sendable {
    case noAPIKey(String)
    case emptyResponse
    case keychainError(OSStatus)
    case networkError(String)
    case unauthorized(String)
    case rateLimited
    case serverError(Int)
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider): String(localized: "No API key configured for \(provider).", bundle: .module)
        case .emptyResponse: String(localized: "AI provider returned an empty response.", bundle: .module)
        case .keychainError(let status): String(localized: "Keychain error: \(status)", bundle: .module)
        case .networkError(let msg): String(localized: "Network error: \(msg)", bundle: .module)
        case .unauthorized(let provider): String(localized: "Invalid API key for \(provider). Check Settings.", bundle: .module)
        case .rateLimited: String(localized: "Too many requests. Please wait a moment.", bundle: .module)
        case .serverError(let code): String(localized: "Server error (\(code)). Try again later.", bundle: .module)
        case .httpError(let code, _): String(localized: "Request failed with status \(code).", bundle: .module)
        }
    }
}

// MARK: - HTTP Validation

private func validateHTTPResponse(_ data: Data, _ response: URLResponse, provider: String) throws -> Data {
    guard let http = response as? HTTPURLResponse else { return data }
    switch http.statusCode {
    case 200..<300:
        return data
    case 401:
        throw AIProviderError.unauthorized(provider)
    case 429:
        throw AIProviderError.rateLimited
    case 500..<600:
        throw AIProviderError.serverError(http.statusCode)
    default:
        let body = String(data: data, encoding: .utf8) ?? ""
        throw AIProviderError.httpError(http.statusCode, body)
    }
}

// MARK: - API DTOs

struct OpenAIChatBody: Codable, Sendable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
    var stream: Bool?
}

struct OpenAIChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct OpenAIChatResponse: Codable, Sendable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable, Sendable {
    let message: OpenAIChatMessage
}

struct AnthropicChatBody: Codable, Sendable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let temperature: Double
}

struct AnthropicMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct AnthropicChatResponse: Codable, Sendable {
    let content: [AnthropicContentBlock]
}

struct AnthropicContentBlock: Codable, Sendable {
    let type: String
    let text: String?
}

struct OllamaChatBody: Codable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaOptions
}

struct OllamaChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct OllamaOptions: Codable, Sendable {
    let temperature: Double
}

struct OllamaChatResponse: Codable, Sendable {
    let message: OllamaChatMessage
}

// Gemini DTOs

struct GeminiChatBody: Codable, Sendable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GeminiGenerationConfig
}

struct GeminiContent: Codable, Sendable {
    let role: String
    let parts: [GeminiPart]
}

struct GeminiPart: Codable, Sendable {
    let text: String
}

struct GeminiGenerationConfig: Codable, Sendable {
    let temperature: Double
    let maxOutputTokens: Int
}

struct GeminiChatResponse: Codable, Sendable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Codable, Sendable {
    let content: GeminiContent
}

// MARK: - SSE Streaming DTOs (OpenAI-compatible format, used by OpenAI + OpenRouter)

/// A single SSE chunk from an OpenAI-compatible streaming response.
/// `data: {"id":"...","choices":[{"delta":{"content":"token"}}]}`
struct OpenAIStreamChunk: Codable, Sendable {
    let choices: [OpenAIStreamChoice]?
}

struct OpenAIStreamChoice: Codable, Sendable {
    let delta: OpenAIStreamDelta?
    let finish_reason: String?
}

struct OpenAIStreamDelta: Codable, Sendable {
    let content: String?
}
