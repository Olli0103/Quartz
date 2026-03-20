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
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    onPreviewToggle()
                } label: {
                    Image(systemName: isPreviewMode ? "pencil" : "doc.richtext")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPreviewMode ? QuartzColors.accent : .primary)
                        .contentTransition(.interpolate)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .help(isPreviewMode ? String(localized: "Switch to edit mode", bundle: .module) : String(localized: "Preview rendered markdown", bundle: .module))
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 4)
                formatButton(.bold, icon: "bold")
                formatButton(.italic, icon: "italic")
                formatButton(.link, icon: "link")
            }
            .padding(.leading, 16)
            .padding(.vertical, 8)

            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                formatButton(.bulletList, icon: "list.bullet")
                Button {
                    onImagePick()
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                formatButton(.code, icon: "chevron.left.forwardslash.chevron.right")
            }

            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 8)

            Menu {
                ForEach([FormattingAction.table, .codeBlock, .blockquote, .checkbox, .numberedList, .heading, .strikethrough, .math, .mermaid], id: \.self) { action in
                    Button { onFormatting(action) } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .menuStyle(.borderlessButton)
            .padding(.trailing, 16)
        }
    }

    private func formatButton(_ action: FormattingAction, icon: String) -> some View {
        EditorFormatButton(action: action, icon: icon) {
            onFormatting(action)
        }
    }
}
#endif
