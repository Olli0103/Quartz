import SwiftUI

/// Einfacher Plaintext-Editor für Markdown-Dateien.
///
/// Nutzt SwiftUI `TextEditor` als Platzhalter bis der
/// TextKit 2 WYSIWYG-Editor in Phase 2 implementiert wird.
public struct NoteEditorView: View {
    @Bindable var viewModel: NoteEditorViewModel

    public init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Editor
            TextEditor(text: $viewModel.content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

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
