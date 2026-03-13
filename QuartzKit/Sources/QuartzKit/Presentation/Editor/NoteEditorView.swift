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
        .navigationTitle(viewModel.note?.displayName ?? String(localized: "Note"))
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
            let cursorPosition = viewModel.cursorPosition
            let (newText, newSelection) = formatter.apply(
                action,
                to: viewModel.content,
                selectedRange: cursorPosition
            )
            viewModel.content = newText
            viewModel.cursorPosition = newSelection
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
                    .scaleEffect(viewModel.isSaving ? 1.3 : 1.0)
                    .shadow(color: statusColor.opacity(viewModel.isSaving ? 0.6 : 0), radius: 4)
                    .animation(
                        viewModel.isSaving
                            ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.3),
                        value: viewModel.isSaving
                    )

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .animation(.easeInOut(duration: 0.2), value: statusText)

            Spacer()

            Text("\(viewModel.wordCount) \(String(localized: "words"))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .contentTransition(.numericText())
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
        if viewModel.isSaving { return String(localized: "Saving…") }
        if viewModel.isDirty { return String(localized: "Edited") }
        return String(localized: "Saved")
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
                .accessibilityLabel(focusMode.isFocusModeActive ? String(localized: "Exit focus mode") : String(localized: "Enter focus mode"))
            }

            if viewModel.isDirty {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "Save note"))
            }
        }
    }

}
