#if os(macOS)
import SwiftUI

/// Native macOS formatting toolbar — clean buttons in the window title bar.
///
/// All buttons use `.buttonStyle(.plain)` to prevent AppKit accent color tinting.
/// The entire HStack has `.tint(.primary)` as a nuclear override.
struct MacEditorToolbar: View {
    let onFormatting: (FormattingAction) -> Void
    var formattingState: FormattingState = .empty
    var isComposing: Bool = false
    var hasSelection: Bool = false
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onAIAssist: (() -> Void)?

    @Environment(\.appearanceManager) private var appearance

    var body: some View {
        HStack(spacing: 8) {
            if let onUndo, let onRedo {
                iconButton("arrow.uturn.backward", label: "Undo", help: "Undo (⌘Z)") { onUndo() }
                iconButton("arrow.uturn.forward", label: "Redo", help: "Redo (⌘⇧Z)") { onRedo() }
                groupDivider
            }

            formatButton("bold", action: .bold, active: formattingState.isActive(.bold))
            formatButton("italic", action: .italic, active: formattingState.isActive(.italic))
            formatButton("strikethrough", action: .strikethrough, active: formattingState.isActive(.strikethrough))

            groupDivider

            headingMenu
            formatButton("list.bullet", action: .bulletList, active: formattingState.isActive(.bulletList))
            formatButton("list.number", action: .numberedList, active: formattingState.isActive(.numberedList))
            formatButton("checklist", action: .checkbox, active: formattingState.isActive(.checkbox))

            groupDivider

            formatButton("chevron.left.forwardslash.chevron.right", action: .code, active: formattingState.isActive(.code))
            formatButton("link", action: .link)

            groupDivider

            overflowMenu

            if onAIAssist != nil {
                groupDivider

                Button {
                    QuartzFeedback.primaryAction()
                    onAIAssist?()
                } label: {
                    iconLabel("sparkles")
                }
                .buttonStyle(.plain)
                .disabled(!hasSelection)
                .opacity(hasSelection ? 1.0 : 0.35)
                .accessibilityLabel(String(localized: "AI Assistant", bundle: .module))
                .help(String(localized: "Rewrite selected text with AI", bundle: .module))
            }
        }
        .tint(.primary)
        .disabled(isComposing)
        .opacity(isComposing ? 0.4 : 1.0)
    }

    // MARK: - Format Button

    private func formatButton(_ icon: String, action: FormattingAction, active: Bool = false) -> some View {
        Button {
            QuartzFeedback.primaryAction()
            onFormatting(action)
        } label: {
            iconLabel(icon)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(active ? appearance.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .help(action.shortcut.map { "\(action.label) (\($0))" } ?? action.label)
    }

    // MARK: - Icon Button

    private func iconButton(_ icon: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            iconLabel(icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: .init(stringLiteral: label), bundle: .module))
        .help(String(localized: .init(stringLiteral: help), bundle: .module))
    }

    // MARK: - Shared Icon Label

    private func iconLabel(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.body.weight(.medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(.primary)
            .frame(width: 28, height: 28)
    }

    // MARK: - Heading Menu

    private var headingMenu: some View {
        Menu {
            Button { onFormatting(.paragraph) } label: {
                menuItemLabel(for: .paragraph)
            }
            Divider()
            ForEach(1...6, id: \.self) { level in
                let action = [FormattingAction.heading1, .heading2, .heading3, .heading4, .heading5, .heading6][level - 1]
                Button { onFormatting(action) } label: {
                    menuItemLabel(for: action)
                }
            }
        } label: {
            iconLabel("textformat.size.larger")
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(formattingState.hasActiveHeading ? appearance.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(String(localized: "Heading level", bundle: .module))
        .help(String(localized: "Change heading level (⌘1-6)", bundle: .module))
    }

    // MARK: - Overflow Menu

    private var overflowMenu: some View {
        Menu {
            ForEach([FormattingAction.codeBlock, .blockquote, .table, .image, .math, .mermaid], id: \.self) { action in
                Button { onFormatting(action) } label: {
                    menuItemLabel(for: action)
                }
            }
        } label: {
            iconLabel("ellipsis.circle")
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(formattingState.hasActiveOverflowStyle ? appearance.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(String(localized: "More formatting options", bundle: .module))
        .help(String(localized: "More formatting options", bundle: .module))
    }

    // MARK: - Divider

    private var groupDivider: some View {
        Divider()
            .frame(height: 12)
    }

    @ViewBuilder
    private func menuItemLabel(for action: FormattingAction) -> some View {
        HStack {
            Label(action.label, systemImage: action.icon)
            Spacer(minLength: 12)
            if formattingState.isActive(action) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
