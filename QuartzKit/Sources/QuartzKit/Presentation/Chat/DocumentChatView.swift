import SwiftUI

/// Premium chat interface for document-context Q&A.
///
/// Presents a scrollable conversation with streaming AI responses,
/// suggestion pills, and an input bar. Reads live document context
/// from `EditorSession` at send-time via `DocumentChatSession`.
///
/// **Ref:** Phase F3 Spec — DocumentChatView
public struct DocumentChatView: View {
    let session: DocumentChatSession

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .callout) private var bubblePadding: CGFloat = 12
    @ScaledMetric(relativeTo: .callout) private var bubbleSpacer: CGFloat = 60

    public init(session: DocumentChatSession) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = session.error {
                    errorBanner(error)
                }
                messageList
                Divider()
                inputBar
            }
            .navigationTitle(String(localized: "Chat", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close", bundle: .module)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        QuartzFeedback.destructive()
                        session.clear()
                    } label: {
                        Image(systemName: "trash")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(session.messages.isEmpty && session.streamingState == .idle)
                    .accessibilityLabel(String(localized: "Clear chat history", bundle: .module))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 400, idealHeight: 600)
        .onAppear { isInputFocused = true }
        #endif
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if session.messages.isEmpty && session.streamingState == .idle {
                        emptyState
                    }

                    ForEach(session.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }

                    // Streaming states
                    if session.streamingState == .waiting {
                        waitingIndicator
                            .id("streaming-indicator")
                    } else if session.streamingState == .streaming {
                        streamingBubble
                            .id("streaming-indicator")
                    }

                    // Invisible anchor for scroll-to-bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                }
                .padding(.vertical, 16)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session.streamingContent) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session.streamingState) { _, newState in
                if newState == .waiting || newState == .streaming {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        } else {
            withAnimation(QuartzAnimation.soft) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(for message: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: min(bubbleSpacer, 100))
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // AI identity marker
                if message.role == .assistant {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }

                // Message content
                Group {
                    if message.role == .assistant {
                        renderedMarkdown(message.content)
                    } else {
                        Text(message.content)
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(bubblePadding)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.role == .user
                              ? AnyShapeStyle(appearance.accentColor.opacity(0.12))
                              : AnyShapeStyle(Color.secondary.opacity(0.1)))
                )

                // Incomplete indicator
                if !message.isComplete {
                    Text(String(localized: "Incomplete response", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if message.role != .user {
                Spacer(minLength: min(bubbleSpacer, 100))
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            message.role == .user
                ? String(localized: "You said: \(message.content)", bundle: .module)
                : String(localized: "AI response: \(message.content)", bundle: .module)
        )
    }

    /// Renders markdown content using AttributedString for inline formatting.
    @ViewBuilder
    private func renderedMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    // MARK: - Streaming States

    private var waitingIndicator: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Thinking…", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(bubblePadding)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            Spacer(minLength: min(bubbleSpacer, 100))
        }
        .padding(.horizontal, 16)
        .accessibilityLabel(String(localized: "AI is thinking", bundle: .module))
    }

    private var streamingBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)

                HStack(spacing: 0) {
                    renderedMarkdown(session.streamingContent)
                        .font(.callout)

                    // Blinking cursor
                    if reduceMotion {
                        Text("…")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("|")
                            .font(.callout.weight(.light))
                            .foregroundStyle(.secondary)
                            .opacity(1)
                            .animation(
                                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                value: session.streamingState
                            )
                    }
                }
                .textSelection(.enabled)
                .padding(bubblePadding)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            Spacer(minLength: min(bubbleSpacer, 100))
        }
        .padding(.horizontal, 16)
        .accessibilityLabel(String(localized: "AI is responding", bundle: .module))
        .accessibilityValue(session.streamingContent)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.quaternary)

            Text(String(localized: "Ask anything about this note", bundle: .module))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(String(localized: "AI-powered Q&A on your document.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                suggestionPill(String(localized: "Summarize this note", bundle: .module))
                suggestionPill(String(localized: "What are the key points?", bundle: .module))
                suggestionPill(String(localized: "Suggest improvements", bundle: .module))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func suggestionPill(_ text: String) -> some View {
        Button {
            QuartzFeedback.selection()
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .foregroundStyle(appearance.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(appearance.accentColor.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Suggestion: \(text)", bundle: .module))
        .accessibilityHint(String(localized: "Double tap to ask this question", bundle: .module))
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: NoteChatError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)
            Text(error.errorDescription ?? String(localized: "An error occurred.", bundle: .module))
                .font(.callout)
                .lineLimit(3)
            Spacer()

            Button {
                QuartzFeedback.selection()
                session.retry()
            } label: {
                Text(String(localized: "Retry", bundle: .module))
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                session.error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss error", bundle: .module))
        }
        .padding(10)
        .quartzMaterialBackground(cornerRadius: 10)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(QuartzAnimation.status, value: session.error != nil)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                String(localized: "Ask about this note…", bundle: .module),
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .focused($isInputFocused)
            .onSubmit { sendMessage() }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.fill.tertiary)
            )
            #if os(iOS)
            .submitLabel(.send)
            #endif

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSendDisabled ? Color.secondary.opacity(0.3) : appearance.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
            .accessibilityLabel(String(localized: "Send message", bundle: .module))
            .accessibilityHint(String(localized: "Sends your question to the AI", bundle: .module))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var isSendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || session.streamingState != .idle
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        QuartzFeedback.primaryAction()
        inputText = ""
        session.send(text)
    }
}
