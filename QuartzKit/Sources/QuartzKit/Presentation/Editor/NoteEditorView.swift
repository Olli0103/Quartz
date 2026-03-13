import SwiftUI

/// WYSIWYG Markdown-Editor – clean, minimal, Apple-Notes-inspiriert.
/// Liquid Glass Statusbar + Formatting Toolbar.
public struct NoteEditorView: View {
    @Bindable var viewModel: NoteEditorViewModel
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    @Environment(\.featureGate) private var featureGate
    private let formatter = MarkdownFormatter()

    public init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Formatting Toolbar
            formattingBar
                .hidesInFocusMode()

            // Frontmatter (collapsible)
            if viewModel.note != nil {
                FrontmatterEditorView(
                    frontmatter: Binding(
                        get: { viewModel.note?.frontmatter ?? Frontmatter() },
                        set: { viewModel.updateFrontmatter($0) }
                    )
                )
                .hidesInFocusMode()
            }

            // Editor
            MarkdownTextViewRepresentable(
                text: $viewModel.content,
                editorFontScale: appearance.editorFontScale
            )

            // Status Bar
            statusBar
                .hidesInFocusMode()
        }
        .navigationTitle(viewModel.note?.displayName ?? "Note")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                editorToolbar
            }
        }
        .onTapGesture(count: 3) {
            if focusMode.isFocusModeActive {
                focusMode.toggleFocusMode()
            }
        }
    }

    // MARK: - Formatting Bar

    private var formattingBar: some View {
        FormattingToolbar { action in
            let (newText, _) = formatter.apply(
                action,
                to: viewModel.content,
                selectedRange: NSRange(location: viewModel.content.count, length: 0)
            )
            viewModel.content = newText
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(wordCount) words")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        if viewModel.isSaving { return .orange }
        if viewModel.isDirty { return .yellow }
        return .green
    }

    private var statusText: String {
        if viewModel.isSaving { return "Saving…" }
        if viewModel.isDirty { return "Edited" }
        return "Saved"
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            if featureGate.isEnabled(.focusMode) {
                Button {
                    focusMode.toggleFocusMode()
                } label: {
                    Image(systemName: focusMode.isFocusModeActive
                          ? "eye.slash.fill" : "eye.fill")
                        .symbolRenderingMode(.hierarchical)
                }
            }

            if viewModel.isDirty {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
    }

    private var wordCount: Int {
        viewModel.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}
