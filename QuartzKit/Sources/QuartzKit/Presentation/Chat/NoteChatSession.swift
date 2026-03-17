import Foundation

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
        chatService: NoteChatService = NoteChatService(providerRegistry: .shared)
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
