import Foundation

/// Service für den KI-Chat mit einer einzelnen Notiz.
///
/// Kontext = aktueller Notiz-Inhalt. Der User kann Fragen zur Notiz stellen
/// wie "Erkläre mir diese Notiz" oder "Fasse die Hauptpunkte zusammen".
public actor NoteChatService {
    private let providerRegistry: AIProviderRegistry

    /// Maximale Token-Länge für den Notiz-Kontext.
    private let maxContextLength = 100_000

    public init(providerRegistry: AIProviderRegistry = .shared) {
        self.providerRegistry = providerRegistry
    }

    /// Sendet eine Nachricht im Kontext einer Notiz.
    ///
    /// - Parameters:
    ///   - userMessage: Die Benutzernachricht
    ///   - noteContent: Der Markdown-Inhalt der aktuellen Notiz
    ///   - noteTitle: Titel der Notiz
    ///   - chatHistory: Bisherige Chat-Nachrichten
    ///   - temperature: Kreativitäts-Parameter (0.0-1.0)
    /// - Returns: Die Antwort des KI-Providers
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

// MARK: - Chat Session

/// Eine Chat-Session mit einer Notiz.
@Observable
@MainActor
public final class NoteChatSession {
    public private(set) var messages: [AIMessage] = []
    public private(set) var isLoading: Bool = false
    public var error: NoteChatError?

    private let chatService: NoteChatService
    private let noteContent: String
    private let noteTitle: String

    public init(
        noteContent: String,
        noteTitle: String,
        chatService: NoteChatService = NoteChatService()
    ) {
        self.noteContent = noteContent
        self.noteTitle = noteTitle
        self.chatService = chatService
    }

    /// Sendet eine Nachricht und wartet auf Antwort.
    public func send(_ message: String) async {
        let userMessage = AIMessage(role: .user, content: message)
        messages.append(userMessage)
        isLoading = true
        error = nil

        do {
            let response = try await chatService.sendMessage(
                message,
                noteContent: noteContent,
                noteTitle: noteTitle,
                chatHistory: messages.dropLast() // Ohne die gerade gesendete
                    .map { $0 }
            )
            messages.append(response)
        } catch let chatError as NoteChatError {
            error = chatError
        } catch {
            self.error = .providerError(error.localizedDescription)
        }

        isLoading = false
    }

    /// Löscht den Chat-Verlauf.
    public func clear() {
        messages.removeAll()
        error = nil
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
