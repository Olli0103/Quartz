import SwiftUI

/// Chat interface for discussing a note with AI.
public struct NoteChatView: View {
    @State private var session: NoteChatSession
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(noteContent: String, noteTitle: String) {
        _session = State(initialValue: NoteChatSession(
            noteContent: noteContent,
            noteTitle: noteTitle
        ))
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
                    Button(String(localized: "Close", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        session.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(session.messages.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 480, minHeight: 400, idealHeight: 600)
        #endif
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if session.messages.isEmpty {
                        emptyState
                    }

                    ForEach(session.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if session.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "Thinking…", bundle: .module))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .id("loading")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: session.messages.count) { _, _ in
                withAnimation {
                    if let last = session.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.quaternary)

            Text(String(localized: "Ask anything about this note", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(localized: "Requires an AI provider with API key configured in Settings.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                suggestionButton("Summarize this note")
                suggestionButton("What are the key points?")
                suggestionButton("Suggest improvements")
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ error: NoteChatError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error.errorDescription ?? "An error occurred.")
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button {
                session.error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .foregroundStyle(QuartzColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(QuartzColors.accent.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

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

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary.opacity(0.3)
                        : QuartzColors.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await session.send(text) }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(message.role == .user
                                  ? AnyShapeStyle(QuartzColors.accent.opacity(0.12))
                                  : AnyShapeStyle(.tertiary.opacity(0.15)))
                    )
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}
