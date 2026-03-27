import Foundation

/// Service for AI chat with a single note.
///
/// Context = current note content. The user can ask questions about the note
/// such as "Explain this note to me" or "Summarize the main points".
public actor NoteChatService {
    private let providerRegistry: AIProviderRegistry

    /// Maximum token length for the note context.
    private let maxContextLength = 100_000

    public init(providerRegistry: AIProviderRegistry) {
        self.providerRegistry = providerRegistry
    }

    /// Sends a message in the context of a note.
    ///
    /// - Parameters:
    ///   - userMessage: The user message
    ///   - noteContent: The Markdown content of the current note
    ///   - noteTitle: Title of the note
    ///   - chatHistory: Previous chat messages
    ///   - temperature: Creativity parameter (0.0-1.0)
    /// - Returns: The AI provider's response
    public func sendMessage(
        _ userMessage: String,
        noteContent: String,
        noteTitle: String,
        chatHistory: [AIMessage] = [],
        temperature: Double = 0.7
    ) async throws -> AIMessage {
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider else {
            throw NoteChatError.noProviderConfigured
        }

        let systemPrompt = buildSystemPrompt(noteTitle: noteTitle, noteContent: noteContent)

        var messages: [AIMessage] = [
            AIMessage(role: .system, content: systemPrompt)
        ]
        messages.append(contentsOf: chatHistory)
        messages.append(AIMessage(role: .user, content: userMessage))

        return try await provider.chat(
            messages: messages,
            model: modelID,
            temperature: temperature
        )
    }

    /// Streaming variant — returns an `AsyncThrowingStream` of content tokens.
    ///
    /// Uses the same system prompt construction and 100K truncation as `sendMessage`.
    /// Providers with real SSE support (OpenAI, OpenRouter) stream token-by-token;
    /// others fall back to yielding the full response at once.
    public func streamMessage(
        _ userMessage: String,
        noteContent: String,
        noteTitle: String,
        chatHistory: [AIMessage] = [],
        temperature: Double = 0.7
    ) async throws -> AsyncThrowingStream<String, Error> {
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider else {
            throw NoteChatError.noProviderConfigured
        }

        let systemPrompt = buildSystemPrompt(noteTitle: noteTitle, noteContent: noteContent)

        var messages: [AIMessage] = [
            AIMessage(role: .system, content: systemPrompt)
        ]
        messages.append(contentsOf: chatHistory)
        messages.append(AIMessage(role: .user, content: userMessage))

        return provider.streamChat(
            messages: messages,
            model: modelID,
            temperature: temperature
        )
    }

    // MARK: - Private

    private func buildSystemPrompt(noteTitle: String, noteContent: String) -> String {
        let truncatedContent: String
        if noteContent.count > maxContextLength {
            truncatedContent = String(noteContent.prefix(maxContextLength)) + "\n\n[... truncated]"
        } else {
            truncatedContent = noteContent
        }

        return """
        You are a helpful assistant integrated into a note-taking app called Quartz.
        The user is viewing a note and wants to discuss its contents.

        ## Current Note
        **Title:** \(noteTitle)

        **Content:**
        \(truncatedContent)

        ## Instructions
        - Answer questions about this note's content.
        - Help explain, summarize, or expand on the note's topics.
        - When referencing specific parts, quote them.
        - Respond in the same language the user writes in.
        - Keep responses concise and focused.
        - Use Markdown formatting in your responses.
        """
    }
}

// MARK: - Errors

public enum NoteChatError: LocalizedError, Sendable {
    case noProviderConfigured
    case providerError(String)
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .noProviderConfigured: String(localized: "No AI provider configured. Add an API key in Settings.", bundle: .module)
        case .providerError(let msg): String(localized: "AI error: \(msg)", bundle: .module)
        case .rateLimited: String(localized: "Too many requests. Please wait a moment.", bundle: .module)
        }
    }
}
