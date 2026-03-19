import SwiftUI

/// Chat interface for asking questions across the entire vault using semantic search.
public struct VaultChatView: View {
    @State private var session: VaultChatSession
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let onNavigateToNote: ((UUID) -> Void)?

    public init(
        session: VaultChatSession,
        onNavigateToNote: ((UUID) -> Void)? = nil
    ) {
        _session = State(initialValue: session)
        self.onNavigateToNote = onNavigateToNote
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
            .navigationTitle(String(localized: "Vault Chat", bundle: .module))
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
        .frame(minWidth: 440, idealWidth: 520, minHeight: 480, idealHeight: 640)
        #endif
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if session.messages.isEmpty {
                        emptyState
                    }

                    ForEach(session.messages) { message in
                        VaultMessageBubble(
                            message: message,
                            onSourceTap: onNavigateToNote
                        )
                        .id(message.id)
                    }

                    if session.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "Searching vault…", bundle: .module))
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.quaternary)

            Text(String(localized: "Ask anything about your vault", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(localized: "Uses semantic search to find relevant notes and answer with AI.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                suggestionButton("What are my main topics?")
                suggestionButton("Summarize my recent ideas")
                suggestionButton("Find connections between notes")
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: VaultChatError) -> some View {
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
        .quartzMaterialBackground(cornerRadius: 10)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Suggestion Button

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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                String(localized: "Ask about your vault…", bundle: .module),
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

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await session.ask(text) }
    }
}

// MARK: - Vault Message Bubble

private struct VaultMessageBubble: View {
    let message: VaultChatMessage
    var onSourceTap: ((UUID) -> Void)?

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
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

                if message.role == .assistant, !message.sources.isEmpty {
                    sourcesView(message.sources)
                }
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    @Environment(\.layoutDirection) private var layoutDirection

    private func sourcesView(_ sources: [VaultSource]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Sources", bundle: .module))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 4, layoutDirection: layoutDirection) {
                ForEach(sources) { source in
                    sourceChip(source)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func sourceChip(_ source: VaultSource) -> some View {
        Button {
            onSourceTap?(source.noteID)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text(source.noteTitle)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(QuartzColors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(QuartzColors.accent.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

/// Simple horizontal wrapping layout for source chips. Supports RTL via layoutDirection.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var layoutDirection: LayoutDirection = .leftToRight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        let isRTL = layoutDirection == .rightToLeft
        for (index, subview) in subviews.enumerated() {
            guard index < result.origins.count else { continue }
            let size = subviews[index].sizeThatFits(.unspecified)
            let x: CGFloat
            if isRTL {
                x = bounds.maxX - result.origins[index].x - size.width
            } else {
                x = bounds.minX + result.origins[index].x
            }
            let origin = CGPoint(x: x, y: bounds.minY + result.origins[index].y)
            subview.place(at: origin, proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + rowHeight
        return (origins, CGSize(width: maxWidth, height: totalHeight))
    }
}
