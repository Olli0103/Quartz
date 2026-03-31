import SwiftUI

/// Floating pill toolbar for iOS/iPadOS — formatting + save.
///
/// Design spec (Agent 13 / Agent 11):
/// - No preview toggle (live TextKit 2 surface)
/// - Uniform `.body.weight(.medium)` + `.imageScale(.large)` on every button
/// - Active state: subtle `accentColor.opacity(0.15)` rounded background, icon stays `.primary`
/// - Groups separated by `Divider().frame(height: 16)`
/// - Capsule: `.regularMaterial` + separator stroke + soft shadow
/// - Save button: accent circle on trailing edge
struct IosEditorToolbar: View {
    let onFormatting: (FormattingAction) -> Void
    let onSave: () -> Void
    var formattingState: FormattingState = .empty
    var isComposing: Bool = false
    var hasSelection: Bool = false
    var onAIAssist: (() -> Void)?
    var onInsertImage: (() -> Void)?

    @Environment(\.appearanceManager) private var appearance

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // — Font styles —
                    formatButton("bold", action: .bold, active: formattingState.isBold)
                    formatButton("italic", action: .italic, active: formattingState.isItalic)
                    formatButton("strikethrough", action: .strikethrough, active: formattingState.isStrikethrough)

                    groupDivider

                    // — Structure —
                    headingMenu
                    formatButton("list.bullet", action: .bulletList)
                    formatButton("checklist", action: .checkbox)

                    groupDivider

                    // — Code & links —
                    formatButton("chevron.left.forwardslash.chevron.right", action: .code, active: formattingState.isCode)
                    formatButton("link", action: .link)

                    groupDivider

                    // — Overflow —
                    overflowMenu

                    if onAIAssist != nil {
                        groupDivider

                        Button {
                            QuartzFeedback.primaryAction()
                            onAIAssist?()
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.body.weight(.medium))
                                .imageScale(.large)
                                .foregroundStyle(.primary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasSelection)
                        .opacity(hasSelection ? 1.0 : 0.35)
                        .accessibilityLabel(String(localized: "AI Assistant", bundle: .module))
                    }

                    if onInsertImage != nil {
                        groupDivider

                        Button {
                            QuartzFeedback.primaryAction()
                            onInsertImage?()
                        } label: {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.body.weight(.medium))
                                .imageScale(.large)
                                .foregroundStyle(.primary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Insert Image", bundle: .module))
                    }
                }
                .disabled(isComposing)
                .opacity(isComposing ? 0.4 : 1.0)
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Button {
                QuartzFeedback.primaryAction()
                onSave()
            } label: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(appearance.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Save note", bundle: .module))
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .quartzFloatingPill()
    }

    // MARK: - Format Button (with active state)

    private func formatButton(_ icon: String, action: FormattingAction, active: Bool = false) -> some View {
        Button {
            QuartzFeedback.primaryAction()
            onFormatting(action)
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? appearance.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Heading Menu

    private var headingMenu: some View {
        Menu {
            Button { onFormatting(.paragraph) } label: {
                Label(FormattingAction.paragraph.label, systemImage: FormattingAction.paragraph.icon)
            }
            Divider()
            ForEach(1...6, id: \.self) { level in
                let action = [FormattingAction.heading1, .heading2, .heading3, .heading4, .heading5, .heading6][level - 1]
                Button { onFormatting(action) } label: {
                    Label(action.label, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "textformat.size.larger")
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "Heading level", bundle: .module))
    }

    // MARK: - Overflow Menu

    private var overflowMenu: some View {
        Menu {
            ForEach([FormattingAction.numberedList, .codeBlock, .blockquote, .table, .image, .math, .mermaid], id: \.self) { action in
                Button { onFormatting(action) } label: {
                    Label(action.label, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "More formatting options", bundle: .module))
    }

    // MARK: - Divider

    private var groupDivider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 2)
    }
}
