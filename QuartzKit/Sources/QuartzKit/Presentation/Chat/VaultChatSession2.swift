import Foundation

/// Streaming vault chat session with 30fps token batching and citation support.
///
/// **Key design decisions:**
/// - Uses `VaultChatService.streamAsk()` for retrieval + streaming
/// - Citations are known before streaming begins (built from search results)
/// - 30fps (~33ms) batched token consumption to avoid overwhelming SwiftUI diffs
/// - Messages use `VaultChatMessage2` (carries `[Citation]` arrays)
/// - Ephemeral: chat history is in-memory only, clears on session end
///
/// **Ref:** Phase F4 Spec — VaultChatSession2
@Observable
@MainActor
public final class VaultChatSession2 {

    // MARK: - Public State

    /// Completed messages in the conversation.
    public private(set) var messages: [VaultChatMessage2] = []

    /// Partial AI response being streamed. Empty when idle.
    public private(set) var streamingContent: String = ""

    /// Current streaming lifecycle state.
    public private(set) var streamingState: StreamingState = .idle

    /// Citations for the current streaming response (known before first token).
    public private(set) var currentCitations: [Citation] = []

    /// Error from the last send attempt.
    public var error: VaultChatError?

    public enum StreamingState: Sendable {
        case idle
        case waiting      // Request sent, no tokens yet
        case streaming    // Tokens arriving
    }

    // MARK: - Dependencies

    private let chatService: VaultChatService
    private let noteResolver: @Sendable (UUID) -> String?
    private var streamTask: Task<Void, Never>?

    /// 30fps batching interval — 33ms between SwiftUI state flushes.
    private static let batchInterval: UInt64 = 33_000_000 // nanoseconds

    // MARK: - Init

    /// Index stats for display in the chat empty state.
    public var indexedChunkCount: Int = 0
    public var indexedNoteCount: Int = 0

    public init(
        chatService: VaultChatService,
        noteResolver: @escaping @Sendable (UUID) -> String?,
        indexedChunkCount: Int = 0,
        indexedNoteCount: Int = 0
    ) {
        self.chatService = chatService
        self.noteResolver = noteResolver
        self.indexedChunkCount = indexedChunkCount
        self.indexedNoteCount = indexedNoteCount
    }

    // MARK: - Public API

    /// Sends a user question and streams the AI response with vault context.
    ///
    /// Flow: semantic search → build citations → construct system prompt → stream tokens at 30fps.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Cancel any in-flight stream
        streamTask?.cancel()

        // Append user message
        let userMessage = VaultChatMessage2(role: .user, content: trimmed)
        messages.append(userMessage)

        // Build chat history for the provider (AIMessage format)
        let history = messages.dropLast().compactMap { msg -> AIMessage? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            return AIMessage(role: msg.role, content: msg.content)
        }

        // Reset streaming state
        streamingContent = ""
        currentCitations = []
        streamingState = .waiting
        error = nil

        let resolver = noteResolver

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                let (citations, tokenStream) = try await self.chatService.streamAsk(
                    trimmed,
                    chatHistory: Array(history),
                    noteResolver: resolver
                )

                // Citations are known before streaming starts
                self.currentCitations = citations

                // 30fps batched consumption
                var buffer = ""
                var lastFlush = ContinuousClock.now

                for try await token in tokenStream {
                    guard !Task.isCancelled else { break }

                    buffer += token

                    let now = ContinuousClock.now
                    if now - lastFlush >= .nanoseconds(Self.batchInterval) {
                        self.streamingContent += buffer
                        if self.streamingState == .waiting {
                            self.streamingState = .streaming
                        }
                        buffer = ""
                        lastFlush = now
                    }
                }

                // Flush remainder
                if !buffer.isEmpty {
                    self.streamingContent += buffer
                }

                guard !Task.isCancelled else { return }

                // Promote streaming content to a completed message with citations
                let finalContent = self.streamingContent
                if !finalContent.isEmpty {
                    let aiMessage = VaultChatMessage2(
                        role: .assistant,
                        content: finalContent,
                        citations: citations
                    )
                    self.messages.append(aiMessage)
                }

                self.streamingContent = ""
                self.currentCitations = []
                self.streamingState = .idle

            } catch is CancellationError {
                let partial = self.streamingContent
                if !partial.isEmpty {
                    let partialMessage = VaultChatMessage2(
                        role: .assistant,
                        content: partial + "\n\n*[interrupted]*",
                        isComplete: false,
                        citations: self.currentCitations
                    )
                    self.messages.append(partialMessage)
                }
                self.streamingContent = ""
                self.currentCitations = []
                self.streamingState = .idle

            } catch let chatError as VaultChatError {
                self.error = chatError
                let partial = self.streamingContent
                if !partial.isEmpty {
                    let partialMessage = VaultChatMessage2(
                        role: .assistant,
                        content: partial + "\n\n*[error]*",
                        isComplete: false,
                        citations: self.currentCitations
                    )
                    self.messages.append(partialMessage)
                }
                self.streamingContent = ""
                self.currentCitations = []
                self.streamingState = .idle

            } catch {
                self.error = .providerError(error.localizedDescription)
                let partial = self.streamingContent
                if !partial.isEmpty {
                    let partialMessage = VaultChatMessage2(
                        role: .assistant,
                        content: partial + "\n\n*[error]*",
                        isComplete: false,
                        citations: self.currentCitations
                    )
                    self.messages.append(partialMessage)
                }
                self.streamingContent = ""
                self.currentCitations = []
                self.streamingState = .idle
            }
        }
    }

    /// Clears chat history and cancels any in-flight stream.
    public func clear() {
        streamTask?.cancel()
        streamTask = nil
        messages.removeAll()
        streamingContent = ""
        currentCitations = []
        streamingState = .idle
        error = nil
    }

    /// Retries the last user question by removing the failed AI response and re-sending.
    public func retry() {
        // Remove the last AI message if it was incomplete
        if let last = messages.last, last.role == .assistant, !last.isComplete {
            messages.removeLast()
        }

        // Find and re-send the last user message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }
        if let idx = messages.lastIndex(where: { $0.id == lastUserMessage.id }) {
            messages.remove(at: idx)
        }
        send(lastUserMessage.content)
    }
}
