import SwiftUI

/// Floating pill-shaped toolbar for iPhone: B, I, bullet, link, table, image, code, More, save.
/// Extracted from NoteEditorView for modularity and maintainability.
struct IosEditorToolbar: View {
    let isPreviewMode: Bool
    let onPreviewToggle: () -> Void
    let onFormatting: (FormattingAction) -> Void
    let onImagePick: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button {
                        onPreviewToggle()
                    } label: {
                        Image(systemName: isPreviewMode ? "pencil" : "doc.richtext")
                            .font(.system(size: 14, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isPreviewMode ? QuartzColors.accent : .primary)
                            .contentTransition(.interpolate)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPreviewMode ? String(localized: "Edit mode", bundle: .module) : String(localized: "Preview", bundle: .module))
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1, height: 24)
                    formatButton(.bold, icon: "bold")
                    formatButton(.italic, icon: "italic")
                    HeadingDropdown { action in
                        onFormatting(action)
                    }
                    formatButton(.bulletList, icon: "list.bullet")
                    formatButton(.link, icon: "link")
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1, height: 24)
                        .padding(.horizontal, 8)
                    formatButton(.table, icon: "tablecells")
                    Button {
                        onImagePick()
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 14, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.primary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Insert Image", bundle: .module))
                    formatButton(.code, icon: "chevron.left.forwardslash.chevron.right")
                    Menu {
                        ForEach([FormattingAction.codeBlock, .blockquote, .checkbox, .numberedList, .strikethrough, .math, .mermaid], id: \.self) { action in
                            Button { onFormatting(action) } label: {
                                Label(action.label, systemImage: action.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "More formatting options", bundle: .module))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: 300)

            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 24)
                .padding(.horizontal, 8)

            Button {
                onSave()
            } label: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Circle().fill(appearance.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Save note", bundle: .module))
            .padding(.leading, 12)
            .padding(.trailing, 12)
        }
        .quartzMaterialBackground(cornerRadius: 20, shadowRadius: 16, layer: .floating)
    }

    @Environment(\.appearanceManager) private var appearance

    private func formatButton(_ action: FormattingAction, icon: String) -> some View {
        EditorFormatButton(action: action, icon: icon) {
            onFormatting(action)
        }
    }
}
