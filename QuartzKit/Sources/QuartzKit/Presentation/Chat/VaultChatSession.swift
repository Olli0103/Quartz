import Foundation

/// Observable chat session for vault-wide AI search.
@Observable
@MainActor
public final class VaultChatSession {
    public private(set) var messages: [VaultChatMessage] = []
    public private(set) var isLoading: Bool = false
    public var error: VaultChatError?

    private let chatService: VaultChatService
    private let noteResolver: @Sendable (UUID) -> String?

    public init(
        chatService: VaultChatService,
        noteResolver: @escaping @Sendable (UUID) -> String?
    ) {
        self.chatService = chatService
        self.noteResolver = noteResolver
    }

    public func ask(_ question: String) async {
        let userMsg = VaultChatMessage(role: .user, content: question, sources: [])
        messages.append(userMsg)
        isLoading = true
        error = nil

        do {
            let history = messages.dropLast().compactMap { msg -> AIMessage? in
                let role: AIMessage.Role = msg.role == .user ? .user : .assistant
                return AIMessage(role: role, content: msg.content)
            }

            let answer = try await chatService.ask(
                question,
                chatHistory: history,
                noteResolver: noteResolver
            )

            let assistantMsg = VaultChatMessage(
                role: .assistant,
                content: answer.answer,
                sources: answer.sources
            )
            messages.append(assistantMsg)
        } catch let chatError as VaultChatError {
            error = chatError
        } catch {
            self.error = .providerError(error.localizedDescription)
        }

        isLoading = false
    }

    public func clear() {
        messages.removeAll()
        error = nil
    }
}
