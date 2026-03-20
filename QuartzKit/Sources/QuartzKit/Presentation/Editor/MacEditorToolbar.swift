#if os(macOS)
import SwiftUI

/// Native Mac editor toolbar – sits in the window frame via ToolbarItemGroup(placement: .principal).
/// Replaces the floating overlay with platform-appropriate toolbar placement.
struct MacEditorToolbar: View {
    let isPreviewMode: Bool
    let onPreviewToggle: () -> Void
    let onFormatting: (FormattingAction) -> Void
    let onImagePick: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onPreviewToggle()
            } label: {
                Image(systemName: isPreviewMode ? "pencil" : "doc.richtext")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isPreviewMode ? QuartzColors.accent : .primary)
                    .contentTransition(.interpolate)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.borderless)
            .help(isPreviewMode ? String(localized: "Switch to edit mode", bundle: .module) : String(localized: "Preview rendered markdown", bundle: .module))

            toolbarDivider

            HStack(spacing: 2) {
                formatButton(.bold, icon: "bold")
                formatButton(.italic, icon: "italic")
                formatButton(.link, icon: "link")
            }

            toolbarDivider

            HStack(spacing: 2) {
                formatButton(.bulletList, icon: "list.bullet")
                Button {
                    onImagePick()
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Insert Image", bundle: .module))
                formatButton(.code, icon: "chevron.left.forwardslash.chevron.right")
            }

            toolbarDivider

            Menu {
                ForEach([FormattingAction.table, .codeBlock, .blockquote, .checkbox, .numberedList, .heading, .strikethrough, .math, .mermaid], id: \.self) { action in
                    Button { onFormatting(action) } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .menuStyle(.borderlessButton)
            .help(String(localized: "More formatting options", bundle: .module))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }

    private func formatButton(_ action: FormattingAction, icon: String) -> some View {
        EditorFormatButton(action: action, icon: icon) {
            onFormatting(action)
        }
    }
}
#endif
