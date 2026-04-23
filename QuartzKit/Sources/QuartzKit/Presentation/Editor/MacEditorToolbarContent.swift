#if os(macOS)
import SwiftUI

struct MacEditorToolbarContent: ToolbarContent {
    let onFormatting: (FormattingAction) -> Void
    var formattingState: FormattingState = .empty
    var isComposing: Bool = false
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onOverflowToggle: (() -> Void)?
    var isOverflowPresented: Bool = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if let onUndo, let onRedo {
                toolbarButton(
                    identifier: "editor-toolbar-undo",
                    systemImage: "arrow.uturn.backward",
                    label: "Undo",
                    help: "Undo (⌘Z)",
                    isEnabled: !isComposing,
                    action: onUndo
                )
                toolbarButton(
                    identifier: "editor-toolbar-redo",
                    systemImage: "arrow.uturn.forward",
                    label: "Redo",
                    help: "Redo (⌘⇧Z)",
                    isEnabled: !isComposing,
                    action: onRedo
                )
            }

            formattingButton(.bold)
            formattingButton(.italic)
            formattingButton(.strikethrough)
            headingMenu
            formattingButton(.bulletList)
            formattingButton(.numberedList)
            formattingButton(.checkbox)
            formattingButton(.code)
            formattingButton(.link)
            overflowButton
        }
    }

    @ViewBuilder
    private func formattingButton(_ action: FormattingAction) -> some View {
        toolbarButton(
            identifier: "editor-toolbar-\(action.rawValue)",
            systemImage: action.icon,
            label: action.label,
            help: action.shortcut.map { "\(action.label) (\($0))" } ?? action.label,
            isEnabled: !isComposing,
            isActive: formattingState.isActive(action),
            action: { onFormatting(action) }
        )
    }

    private var headingMenu: some View {
        Menu {
            menuAction(.paragraph)
            Divider()
            menuAction(.heading1)
            menuAction(.heading2)
            menuAction(.heading3)
            menuAction(.heading4)
            menuAction(.heading5)
            menuAction(.heading6)
        } label: {
            Image(systemName: FormattingAction.heading.icon)
        }
        .menuStyle(.borderlessButton)
        .disabled(isComposing)
        .tint(formattingState.hasActiveHeading ? .accentColor : .primary)
        .accessibilityIdentifier("editor-toolbar-heading-menu")
        .accessibilityLabel(String(localized: "Heading level", bundle: .module))
        .help(String(localized: "Change heading level (⌘1-6)", bundle: .module))
    }

    private var overflowButton: some View {
        toolbarButton(
            identifier: "editor-toolbar-overflow-menu",
            systemImage: "ellipsis.circle",
            label: "More formatting options",
            help: "More formatting options",
            isEnabled: !isComposing,
            isActive: isOverflowPresented,
            action: { onOverflowToggle?() }
        )
    }

    @ViewBuilder
    private func menuAction(_ action: FormattingAction) -> some View {
        Button {
            onFormatting(action)
        } label: {
            Label(action.label, systemImage: action.icon)
        }
        .accessibilityIdentifier("editor-toolbar-\(action.rawValue)")
    }

    @ViewBuilder
    private func toolbarButton(
        identifier: String,
        systemImage: String,
        label: String,
        help: String,
        isEnabled: Bool,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .tint(isActive ? .accentColor : .primary)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(label))
        .help(help)
    }
}
#endif
