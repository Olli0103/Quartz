import Foundation

/// Chat session that reads live document context from `EditorSession` at send-time.
///
/// **Key design decisions:**
/// - Takes a live `EditorSession` reference (both are `@MainActor` — synchronous read)
/// - Reads `editorSession.currentText` at the moment the user taps Send, not at init time
/// - Streams tokens with 30fps (~33ms) batching to avoid overwhelming SwiftUI diffs
/// - Chat history clears on note switch (system prompt is document-specific)
///
/// **Ref:** Phase F3 Spec — DocumentChatSession
@Observable
@MainActor
public final class DocumentChatSession {

    // MARK: - Public State

    /// Completed messages in the conversation.
    public private(set) var messages: [ChatMessage] = []

    /// Partial AI response being streamed. Empty when idle.
    public private(set) var streamingContent: String = ""

    /// Current streaming lifecycle state.
    public private(set) var streamingState: StreamingState = .idle

    /// Error from the last send attempt.
    public var error: NoteChatError?

    public enum StreamingState: Sendable {
        case idle
        case waiting      // Request sent, no tokens yet
        case streaming    // Tokens arriving
        case complete     // Stream finished (transient — resets to idle)
    }

    // MARK: - Dependencies

    private let editorSession: EditorSession
    private let chatService: NoteChatService
    private var streamTask: Task<Void, Never>?

    /// 30fps batching interval — 33ms between SwiftUI state flushes.
    private static let batchInterval: UInt64 = 33_000_000 // nanoseconds

    // MARK: - Init

    public init(
        editorSession: EditorSession,
        chatService: NoteChatService = NoteChatService(providerRegistry: .shared)
    ) {
        self.editorSession = editorSession
        self.chatService = chatService
    }

    // MARK: - Public API

    /// Sends a user message and streams the AI response.
    ///
    /// Reads `editorSession.currentText` at call-time (live document snapshot).
    /// Tokens are batched at ~30fps to avoid SwiftUI performance issues.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Cancel any in-flight stream
        streamTask?.cancel()

        // Append user message
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Snapshot document context synchronously (@MainActor → @MainActor, no await)
        let noteText = editorSession.currentText
        let noteTitle = editorSession.note?.displayName ?? "Untitled"

        // Build chat history for the provider (AIMessage format)
        let history = messages.dropLast().compactMap { msg -> AIMessage? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            return AIMessage(role: msg.role, content: msg.content)
        }

        // Reset streaming state
        streamingContent = ""
        streamingState = .waiting
        error = nil

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                let tokenStream = try await self.chatService.streamMessage(
                    trimmed,
                    noteContent: noteText,
                    noteTitle: noteTitle,
                    chatHistory: Array(history)
                )

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

                // Promote streaming content to a completed message
                let finalContent = self.streamingContent
                if !finalContent.isEmpty {
                    let aiMessage = ChatMessage(role: .assistant, content: finalContent)
                    self.messages.append(aiMessage)
                }

                self.streamingContent = ""
                self.streamingState = .idle

            } catch is CancellationError {
                // Preserve partial content if cancelled mid-stream
                let partial = self.streamingContent
                if !partial.isEmpty {
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: partial + "\n\n*[interrupted]*",
                        isComplete: false
                    )
                    self.messages.append(partialMessage)
                }
                self.streamingContent = ""
                self.streamingState = .idle

            } catch let chatError as NoteChatError {
                self.error = chatError
                // Preserve partial content on error
                let partial = self.streamingContent
                if !partial.isEmpty {
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: partial + "\n\n*[error]*",
                        isComplete: false
                    )
                    self.messages.append(partialMessage)
                }
                self.streamingContent = ""
                self.streamingState = .idle

            } catch {
                self.error = .providerError(error.localizedDescription)
                let partial = self.streamingContent
                if !partial.isEmpty {
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: partial + "\n\n*[error]*",
                        isComplete: false
                    )
                    self.messages.append(partialMessage)
                }
                self.streamingContent = ""
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
        streamingState = .idle
        error = nil
    }

    /// Retries the last user message by removing the failed AI response and re-sending.
    public func retry() {
        // Remove the last AI message if it was incomplete
        if let last = messages.last, last.role == .assistant, !last.isComplete {
            messages.removeLast()
        }

        // Find and re-send the last user message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }
        // Remove the user message too — send() will re-add it
        if let idx = messages.lastIndex(where: { $0.id == lastUserMessage.id }) {
            messages.remove(at: idx)
        }
        send(lastUserMessage.content)
    }
}
