import SwiftUI

/// WYSIWYG Markdown-Editor mit TextKit 2.
///
/// Rendert Markdown live: Headlines, Bold, Italic, Code, Listen, Checkboxen.
/// Fallback auf einfachen TextEditor wenn nötig.
public struct NoteEditorView: View {
    @Bindable var viewModel: NoteEditorViewModel
    @Environment(\.appearanceManager) private var appearance
    private let formatter = MarkdownFormatter()

    public init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Formatting Toolbar
            FormattingToolbar { action in
                let (newText, _) = formatter.apply(
                    action,
                    to: viewModel.content,
                    selectedRange: NSRange(location: viewModel.content.count, length: 0)
                )
                viewModel.content = newText
            }
            .background(.bar)

            // WYSIWYG Editor
            MarkdownTextViewRepresentable(
                text: $viewModel.content,
                editorFontScale: appearance.editorFontScale
            )

            // Status Bar
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
        }
        .navigationTitle(viewModel.note?.displayName ?? "Note")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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

    private var wordCount: Int {
        viewModel.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}
