import Foundation
import Observation
import Security

// MARK: - AI Provider Protocol

/// Adapter-Pattern: Jeder KI-Provider implementiert dieses Protokoll.
public protocol AIProvider: Sendable {
    /// Eindeutiger Identifier des Providers.
    var id: String { get }
    /// Anzeigename.
    var displayName: String { get }
    /// Ob ein API-Key konfiguriert ist.
    var isConfigured: Bool { get }
    /// Unterstützte Modelle.
    var availableModels: [AIModel] { get }

    /// Chat-Completion mit Kontext.
    func chat(
        messages: [AIMessage],
        model: String?,
        temperature: Double
    ) async throws -> AIMessage
}

/// Ein KI-Modell.
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

/// Eine Chat-Nachricht.
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
        let apiKey = try keychain.getKey(for: id)
        let modelID = model ?? "gpt-4o"

        let body = OpenAIChatBody(
            model: modelID,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: temperature
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (rawData, httpResponse) = try await URLSession.shared.data(for: request)
        let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

        guard let content = response.choices.first?.message.content else {
            throw AIProviderError.emptyResponse
        }
        return AIMessage(role: .assistant, content: content)
    }
}

/// Anthropic Provider (Claude)
public final class AnthropicProvider: AIProvider, Sendable {
    public let id = "anthropic"
    public let displayName = "Anthropic"
    private let keychain: KeychainHelper

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
        let apiKey = try keychain.getKey(for: id)
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

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (rawData, httpResponse) = try await URLSession.shared.data(for: request)
        let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
        let response = try JSONDecoder().decode(AnthropicChatResponse.self, from: data)

        guard let content = response.content.first?.text else {
            throw AIProviderError.emptyResponse
        }
        return AIMessage(role: .assistant, content: content)
    }
}

/// Ollama Provider (lokale Modelle)
public final class OllamaProvider: AIProvider, Sendable {
    public let id = "ollama"
    public let displayName = "Ollama (Local)"
    private let baseURL: URL

    public var isConfigured: Bool { true } // Kein API-Key nötig

    public var availableModels: [AIModel] {
        [
            AIModel(id: "llama3.1", name: "Llama 3.1", contextWindow: 128_000, provider: id),
            AIModel(id: "mistral", name: "Mistral", contextWindow: 32_000, provider: id),
            AIModel(id: "gemma2", name: "Gemma 2", contextWindow: 8_000, provider: id),
        ]
    }

    public init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    public func chat(messages: [AIMessage], model: String?, temperature: Double) async throws -> AIMessage {
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

        let (rawData, httpResponse) = try await URLSession.shared.data(for: request)
        let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

        return AIMessage(role: .assistant, content: response.message.content)
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
        let apiKey = try keychain.getKey(for: id)
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

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (rawData, httpResponse) = try await URLSession.shared.data(for: request)
        let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
        let response = try JSONDecoder().decode(GeminiChatResponse.self, from: data)

        guard let text = response.candidates?.first?.content.parts.first?.text else {
            throw AIProviderError.emptyResponse
        }
        return AIMessage(role: .assistant, content: text)
    }
}

/// OpenRouter Provider – Zugang zu hunderten Modellen über eine API.
public final class OpenRouterProvider: AIProvider, Sendable {
    public let id = "openrouter"
    public let displayName = "OpenRouter"
    private let keychain: KeychainHelper

    public var isConfigured: Bool { keychain.hasKey(for: id) }

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
        let apiKey = try keychain.getKey(for: id)
        let modelID = model ?? "anthropic/claude-sonnet-4"

        // OpenRouter nutzt das OpenAI-kompatible Format
        let body = OpenAIChatBody(
            model: modelID,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: temperature
        )

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Quartz Notes", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body)

        let (rawData, httpResponse) = try await URLSession.shared.data(for: request)
        let data = try validateHTTPResponse(rawData, httpResponse, provider: id)
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

        guard let content = response.choices.first?.message.content else {
            throw AIProviderError.emptyResponse
        }
        return AIMessage(role: .assistant, content: content)
    }
}

// MARK: - Provider Registry

/// Registry für alle verfügbaren KI-Provider.
@Observable
@MainActor
public final class AIProviderRegistry {
    public private(set) var providers: [any AIProvider]
    public var selectedProviderID: String
    public var selectedModelID: String?

    public static let shared = AIProviderRegistry()

    private let customModelStore = CustomModelStore()

    public init() {
        let providers: [any AIProvider] = [
            OpenAIProvider(),
            AnthropicProvider(),
            GeminiProvider(),
            OpenRouterProvider(),
            OllamaProvider(),
        ]
        self.providers = providers
        self.selectedProviderID = "anthropic"
        self.selectedModelID = nil
    }

    public var selectedProvider: (any AIProvider)? {
        providers.first { $0.id == selectedProviderID }
    }

    public var configuredProviders: [any AIProvider] {
        providers.filter(\.isConfigured)
    }

    /// Alle Modelle eines Providers: Built-in + benutzerdefinierte.
    public func allModels(for providerID: String) async -> [AIModel] {
        let builtIn = providers.first { $0.id == providerID }?.availableModels ?? []
        let custom = await customModelStore.customModels(for: providerID)
        return builtIn + custom
    }

    /// Benutzerdefiniertes Modell hinzufügen.
    public func addCustomModel(id modelID: String, name: String? = nil, contextWindow: Int = 128_000, forProvider providerID: String) async {
        let model = AIModel(
            id: modelID,
            name: name ?? modelID,
            contextWindow: contextWindow,
            provider: providerID
        )
        await customModelStore.add(model, for: providerID)
    }

    /// Benutzerdefiniertes Modell entfernen.
    public func removeCustomModel(id modelID: String, forProvider providerID: String) async {
        await customModelStore.remove(modelID: modelID, for: providerID)
    }

    /// Alle benutzerdefinierten Modelle eines Providers.
    public func customModels(for providerID: String) async -> [AIModel] {
        await customModelStore.customModels(for: providerID)
    }
}

// MARK: - Custom Model Store

/// Persistiert benutzerdefinierte Modelle in UserDefaults.
/// Actor-Isolation garantiert atomare Lese-/Schreibzugriffe.
public actor CustomModelStore {
    private let defaults = UserDefaults.standard
    private let storageKey = "com.quartz.customModels"

    public init() {}

    public func customModels(for providerID: String) -> [AIModel] {
        loadAll()[providerID] ?? []
    }

    public func add(_ model: AIModel, for providerID: String) {
        var all = loadAll()
        var models = all[providerID] ?? []
        // Duplikat vermeiden
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
        guard let data = defaults.data(forKey: storageKey),
              let all = try? JSONDecoder().decode([String: [AIModel]].self, from: data) else {
            return [:]
        }
        return all
    }

    private func save(_ models: [String: [AIModel]]) {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Keychain Helper

/// Sichere Speicherung von API-Keys in der Keychain.
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

struct OpenAIChatBody: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
}

struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIChatMessage
}

struct AnthropicChatBody: Codable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let temperature: Double
}

struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

struct AnthropicChatResponse: Codable {
    let content: [AnthropicContentBlock]
}

struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
}

struct OllamaChatBody: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaOptions
}

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaOptions: Codable {
    let temperature: Double
}

struct OllamaChatResponse: Codable {
    let message: OllamaChatMessage
}

// Gemini DTOs

struct GeminiChatBody: Codable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GeminiGenerationConfig
}

struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String
}

struct GeminiGenerationConfig: Codable {
    let temperature: Double
    let maxOutputTokens: Int
}

struct GeminiChatResponse: Codable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent
}
