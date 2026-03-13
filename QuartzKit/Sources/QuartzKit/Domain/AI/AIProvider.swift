import Foundation
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
public final class OpenAIProvider: AIProvider, @unchecked Sendable {
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

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

        guard let content = response.choices.first?.message.content else {
            throw AIProviderError.emptyResponse
        }
        return AIMessage(role: .assistant, content: content)
    }
}

/// Anthropic Provider (Claude)
public final class AnthropicProvider: AIProvider, @unchecked Sendable {
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

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AnthropicChatResponse.self, from: data)

        guard let content = response.content.first?.text else {
            throw AIProviderError.emptyResponse
        }
        return AIMessage(role: .assistant, content: content)
    }
}

/// Ollama Provider (lokale Modelle)
public final class OllamaProvider: AIProvider, @unchecked Sendable {
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

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

        return AIMessage(role: .assistant, content: response.message.content)
    }
}

// MARK: - Provider Registry

/// Registry für alle verfügbaren KI-Provider.
public final class AIProviderRegistry: ObservableObject, @unchecked Sendable {
    @Published public private(set) var providers: [any AIProvider]
    @Published public var selectedProviderID: String
    @Published public var selectedModelID: String?

    public static let shared = AIProviderRegistry()

    public init() {
        let providers: [any AIProvider] = [
            OpenAIProvider(),
            AnthropicProvider(),
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
}

// MARK: - Keychain Helper

/// Sichere Speicherung von API-Keys in der Keychain.
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()

    private let servicePrefix = "com.quartz.ai-provider."

    public init() {}

    public func saveKey(_ key: String, for providerID: String) throws {
        let service = servicePrefix + providerID
        let data = Data(key.utf8)

        // Bestehenden löschen
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Neuen speichern
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
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

    public func hasKey(for providerID: String) -> Bool {
        (try? getKey(for: providerID)) != nil
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

    public var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider): "No API key configured for \(provider)."
        case .emptyResponse: "AI provider returned an empty response."
        case .keychainError(let status): "Keychain error: \(status)"
        case .networkError(let msg): "Network error: \(msg)"
        }
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
