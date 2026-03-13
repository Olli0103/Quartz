import SwiftUI

/// WYSIWYG Markdown-Editor mit TextKit 2, Focus Mode und Typewriter Mode.
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
            // Formatting Toolbar (hidden in focus mode)
            FormattingToolbar { action in
                let (newText, _) = formatter.apply(
                    action,
                    to: viewModel.content,
                    selectedRange: NSRange(location: viewModel.content.count, length: 0)
                )
                viewModel.content = newText
            }
            .background(.bar)
            .hidesInFocusMode()

            // Frontmatter (hidden in focus mode)
            if viewModel.note != nil {
                FrontmatterEditorView(
                    frontmatter: Binding(
                        get: { viewModel.note?.frontmatter ?? Frontmatter() },
                        set: { viewModel.updateFrontmatter($0) }
                    )
                )
                .hidesInFocusMode()
            }

            // WYSIWYG Editor
            MarkdownTextViewRepresentable(
                text: $viewModel.content,
                editorFontScale: appearance.editorFontScale
            )

            // Status Bar (hidden in focus mode)
            HStack {
                if viewModel.isSaving {
                    Label("Saving...", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.isDirty {
                    Label("Unsaved changes", systemImage: "pencil.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Saved", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)
            .hidesInFocusMode()
        }
        .navigationTitle(viewModel.note?.displayName ?? "Note")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // Focus Mode Toggle
                    if featureGate.isEnabled(.focusMode) {
                        Button {
                            focusMode.toggleFocusMode()
                        } label: {
                            Image(systemName: focusMode.isFocusModeActive
                                  ? "eye.slash.fill" : "eye.fill")
                        }
                        .accessibilityLabel("Focus Mode")
                    }

                    // Typewriter Mode Toggle
                    if featureGate.isEnabled(.typewriterMode) {
                        Button {
                            focusMode.toggleTypewriterMode()
                        } label: {
                            Image(systemName: focusMode.isTypewriterModeActive
                                  ? "text.cursor" : "text.alignleft")
                        }
                        .accessibilityLabel("Typewriter Mode")
                    }

                    // Save Button
                    if viewModel.isDirty {
                        Button {
                            Task { await viewModel.save() }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
            }
        }
        // Tap to exit focus mode
        .onTapGesture(count: 3) {
            if focusMode.isFocusModeActive {
                focusMode.toggleFocusMode()
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
