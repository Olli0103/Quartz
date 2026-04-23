#if os(macOS)
import AppKit
import SwiftUI

/// Native macOS formatting toolbar hosted in the title bar.
///
/// SwiftUI's principal-toolbar composition can render correctly while dropping
/// child accessibility identifiers from the actionable title-bar controls.
/// This AppKit bridge keeps the visible product surface intact while ensuring
/// every toolbar control is represented by a real NSControl for XCTest.
struct MacEditorToolbar: View {
    let onFormatting: (FormattingAction) -> Void
    var formattingState: FormattingState = .empty
    var isComposing: Bool = false
    var hasSelection: Bool = false
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onAIAssist: (() -> Void)?

    var body: some View {
        MacEditorToolbarRepresentable(
            onFormatting: onFormatting,
            formattingState: formattingState,
            isComposing: isComposing,
            hasSelection: hasSelection,
            onUndo: onUndo,
            onRedo: onRedo,
            onAIAssist: onAIAssist
        )
        .frame(height: 32)
    }
}

@MainActor
private struct MacEditorToolbarRepresentable: NSViewRepresentable {
    let onFormatting: (FormattingAction) -> Void
    let formattingState: FormattingState
    let isComposing: Bool
    let hasSelection: Bool
    let onUndo: (() -> Void)?
    let onRedo: (() -> Void)?
    let onAIAssist: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFormatting: onFormatting,
            onUndo: onUndo,
            onRedo: onRedo,
            onAIAssist: onAIAssist
        )
    }

    func makeNSView(context: Context) -> MacEditorToolbarHostView {
        MacEditorToolbarHostView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: MacEditorToolbarHostView, context: Context) {
        context.coordinator.onFormatting = onFormatting
        context.coordinator.onUndo = onUndo
        context.coordinator.onRedo = onRedo
        context.coordinator.onAIAssist = onAIAssist
        nsView.update(
            formattingState: formattingState,
            isComposing: isComposing,
            hasSelection: hasSelection,
            showsUndoRedo: onUndo != nil && onRedo != nil,
            showsAIAssist: onAIAssist != nil,
            coordinator: context.coordinator
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onFormatting: (FormattingAction) -> Void
        var onUndo: (() -> Void)?
        var onRedo: (() -> Void)?
        var onAIAssist: (() -> Void)?

        init(
            onFormatting: @escaping (FormattingAction) -> Void,
            onUndo: (() -> Void)?,
            onRedo: (() -> Void)?,
            onAIAssist: (() -> Void)?
        ) {
            self.onFormatting = onFormatting
            self.onUndo = onUndo
            self.onRedo = onRedo
            self.onAIAssist = onAIAssist
        }

        @objc func triggerUndo(_ sender: NSControl) {
            QuartzFeedback.primaryAction()
            onUndo?()
        }

        @objc func triggerRedo(_ sender: NSControl) {
            QuartzFeedback.primaryAction()
            onRedo?()
        }

        @objc func triggerAIAssist(_ sender: NSControl) {
            QuartzFeedback.primaryAction()
            onAIAssist?()
        }

        @objc func triggerFormattingAction(_ sender: NSControl) {
            guard let identifier = sender.identifier?.rawValue else { return }
            let rawValue = identifier.replacingOccurrences(of: "editor-toolbar-", with: "")
            guard let action = FormattingAction(rawValue: rawValue) else { return }
            QuartzFeedback.primaryAction()
            onFormatting(action)
        }

        @objc func triggerFormattingMenuAction(_ sender: NSMenuItem) {
            guard let identifier = sender.identifier?.rawValue else { return }
            let rawValue = identifier.replacingOccurrences(of: "editor-toolbar-", with: "")
            guard let action = FormattingAction(rawValue: rawValue) else { return }
            QuartzFeedback.primaryAction()
            onFormatting(action)
        }

        @objc func showHeadingMenu(_ sender: NSButton) {
            guard let menu = sender.menu else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
        }

        @objc func showOverflowMenu(_ sender: NSButton) {
            guard let menu = sender.menu else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
        }
    }
}

@MainActor
private final class MacEditorToolbarHostView: NSView {
    private let stackView = NSStackView()
    private let undoButton = MacToolbarButton(icon: "arrow.uturn.backward")
    private let redoButton = MacToolbarButton(icon: "arrow.uturn.forward")
    private let boldButton = MacToolbarButton(icon: "bold")
    private let italicButton = MacToolbarButton(icon: "italic")
    private let strikethroughButton = MacToolbarButton(icon: "strikethrough")
    private let headingButton = MacToolbarButton(icon: "textformat.size.larger")
    private let bulletListButton = MacToolbarButton(icon: "list.bullet")
    private let numberedListButton = MacToolbarButton(icon: "list.number")
    private let checkboxButton = MacToolbarButton(icon: "checklist")
    private let codeButton = MacToolbarButton(icon: "chevron.left.forwardslash.chevron.right")
    private let linkButton = MacToolbarButton(icon: "link")
    private let overflowButton = MacToolbarButton(icon: "ellipsis.circle")
    private let aiButton = MacToolbarButton(icon: "sparkles")

    private let undoRedoDivider = MacToolbarDivider()
    private let emphasisDivider = MacToolbarDivider()
    private let listDivider = MacToolbarDivider()
    private let inlineDivider = MacToolbarDivider()
    private let overflowDivider = MacToolbarDivider()

    private lazy var headingMenu: NSMenu = makeHeadingMenu()
    private lazy var overflowMenu: NSMenu = makeOverflowMenu()

    init(coordinator: MacEditorToolbarRepresentable.Coordinator) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("editor-formatting-toolbar")
        setAccessibilityLabel("Formatting Toolbar")
        setupStackView()
        configureStaticMetadata(coordinator: coordinator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        stackView.fittingSize
    }

    func update(
        formattingState: FormattingState,
        isComposing: Bool,
        hasSelection: Bool,
        showsUndoRedo: Bool,
        showsAIAssist: Bool,
        coordinator: MacEditorToolbarRepresentable.Coordinator
    ) {
        configureTargets(with: coordinator)
        updateMenus(formattingState: formattingState, coordinator: coordinator)

        undoButton.isHidden = !showsUndoRedo
        redoButton.isHidden = !showsUndoRedo
        undoRedoDivider.isHidden = !showsUndoRedo

        aiButton.isHidden = !showsAIAssist
        overflowDivider.isHidden = !showsAIAssist

        let enabledButtons = topLevelButtons()
        for button in enabledButtons {
            button.isEnabled = !isComposing
        }

        aiButton.isEnabled = !isComposing && hasSelection

        boldButton.applyActiveAppearance(formattingState.isActive(.bold))
        italicButton.applyActiveAppearance(formattingState.isActive(.italic))
        strikethroughButton.applyActiveAppearance(formattingState.isActive(.strikethrough))
        headingButton.applyActiveAppearance(formattingState.hasActiveHeading)
        bulletListButton.applyActiveAppearance(formattingState.isActive(.bulletList))
        numberedListButton.applyActiveAppearance(formattingState.isActive(.numberedList))
        checkboxButton.applyActiveAppearance(formattingState.isActive(.checkbox))
        codeButton.applyActiveAppearance(formattingState.isActive(.code))
        linkButton.applyActiveAppearance(false)
        overflowButton.applyActiveAppearance(formattingState.hasActiveOverflowStyle)
        undoButton.applyActiveAppearance(false)
        redoButton.applyActiveAppearance(false)
        aiButton.applyActiveAppearance(false)

        aiButton.applyEnabledAppearance(isEnabled: aiButton.isEnabled, isComposing: isComposing)
        for button in enabledButtons where button !== aiButton {
            button.applyEnabledAppearance(isEnabled: button.isEnabled, isComposing: isComposing)
        }
    }

    private func setupStackView() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        [
            undoButton,
            redoButton,
            undoRedoDivider,
            boldButton,
            italicButton,
            strikethroughButton,
            emphasisDivider,
            headingButton,
            bulletListButton,
            numberedListButton,
            checkboxButton,
            listDivider,
            codeButton,
            linkButton,
            inlineDivider,
            overflowButton,
            overflowDivider,
            aiButton
        ].forEach { stackView.addArrangedSubview($0) }
    }

    private func configureStaticMetadata(coordinator: MacEditorToolbarRepresentable.Coordinator) {
        configureButton(
            undoButton,
            identifier: "editor-toolbar-undo",
            label: "Undo",
            help: "Undo (⌘Z)"
        )
        configureButton(
            redoButton,
            identifier: "editor-toolbar-redo",
            label: "Redo",
            help: "Redo (⌘⇧Z)"
        )

        configureFormattingButton(boldButton, action: .bold)
        configureFormattingButton(italicButton, action: .italic)
        configureFormattingButton(strikethroughButton, action: .strikethrough)
        configureFormattingButton(bulletListButton, action: .bulletList)
        configureFormattingButton(numberedListButton, action: .numberedList)
        configureFormattingButton(checkboxButton, action: .checkbox)
        configureFormattingButton(codeButton, action: .code)
        configureFormattingButton(linkButton, action: .link)

        configureButton(
            headingButton,
            identifier: "editor-toolbar-heading-menu",
            label: "Heading level",
            help: "Change heading level (⌘1-6)"
        )
        headingButton.setAccessibilityRole(.menuButton)
        configureButton(
            overflowButton,
            identifier: "editor-toolbar-overflow-menu",
            label: "More formatting options",
            help: "More formatting options"
        )
        overflowButton.setAccessibilityRole(.menuButton)
        configureButton(
            aiButton,
            identifier: "editor-toolbar-ai-assistant",
            label: "AI Assistant",
            help: "Rewrite selected text with AI"
        )

        headingButton.menu = headingMenu
        overflowButton.menu = overflowMenu

        configureTargets(with: coordinator)
        updateMenus(formattingState: .empty, coordinator: coordinator)
    }

    private func configureTargets(with coordinator: MacEditorToolbarRepresentable.Coordinator) {
        undoButton.target = coordinator
        undoButton.action = #selector(MacEditorToolbarRepresentable.Coordinator.triggerUndo(_:))

        redoButton.target = coordinator
        redoButton.action = #selector(MacEditorToolbarRepresentable.Coordinator.triggerRedo(_:))

        [boldButton, italicButton, strikethroughButton, bulletListButton, numberedListButton,
         checkboxButton, codeButton, linkButton].forEach { button in
            button.target = coordinator
            button.action = #selector(MacEditorToolbarRepresentable.Coordinator.triggerFormattingAction(_:))
        }

        headingButton.target = coordinator
        headingButton.action = #selector(MacEditorToolbarRepresentable.Coordinator.showHeadingMenu(_:))

        overflowButton.target = coordinator
        overflowButton.action = #selector(MacEditorToolbarRepresentable.Coordinator.showOverflowMenu(_:))

        aiButton.target = coordinator
        aiButton.action = #selector(MacEditorToolbarRepresentable.Coordinator.triggerAIAssist(_:))
    }

    private func configureFormattingButton(_ button: MacToolbarButton, action: FormattingAction) {
        configureButton(
            button,
            identifier: "editor-toolbar-\(action.rawValue)",
            label: action.label,
            help: action.shortcut.map { "\(action.label) (\($0))" } ?? action.label
        )
    }

    private func configureButton(
        _ button: MacToolbarButton,
        identifier: String,
        label: String,
        help: String
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.toolTip = help
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(label)
    }

    private func updateMenus(
        formattingState: FormattingState,
        coordinator: MacEditorToolbarRepresentable.Coordinator
    ) {
        for item in headingMenu.items {
            item.target = coordinator
            item.action = #selector(MacEditorToolbarRepresentable.Coordinator.triggerFormattingMenuAction(_:))
            if let identifier = item.identifier?.rawValue,
               let action = formattingAction(for: identifier) {
                item.state = formattingState.isActive(action) ? .on : .off
            } else {
                item.state = .off
            }
        }

        for item in overflowMenu.items {
            item.target = coordinator
            item.action = #selector(MacEditorToolbarRepresentable.Coordinator.triggerFormattingMenuAction(_:))
            if let identifier = item.identifier?.rawValue,
               let action = formattingAction(for: identifier) {
                item.state = formattingState.isActive(action) ? .on : .off
            } else {
                item.state = .off
            }
        }
    }

    private func makeHeadingMenu() -> NSMenu {
        let menu = NSMenu(title: "Heading")
        menu.autoenablesItems = false
        menu.addItem(makeMenuItem(title: FormattingAction.paragraph.label, action: .paragraph))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: FormattingAction.heading1.label, action: .heading1))
        menu.addItem(makeMenuItem(title: FormattingAction.heading2.label, action: .heading2))
        menu.addItem(makeMenuItem(title: FormattingAction.heading3.label, action: .heading3))
        menu.addItem(makeMenuItem(title: FormattingAction.heading4.label, action: .heading4))
        menu.addItem(makeMenuItem(title: FormattingAction.heading5.label, action: .heading5))
        menu.addItem(makeMenuItem(title: FormattingAction.heading6.label, action: .heading6))
        return menu
    }

    private func makeOverflowMenu() -> NSMenu {
        let menu = NSMenu(title: "More Formatting")
        menu.autoenablesItems = false
        [
            FormattingAction.codeBlock,
            .blockquote,
            .table,
            .image,
            .math,
            .mermaid
        ].forEach { action in
            menu.addItem(makeMenuItem(title: action.label, action: action))
        }
        return menu
    }

    private func makeMenuItem(title: String, action: FormattingAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("editor-toolbar-\(action.rawValue)")
        item.image = NSImage(
            systemSymbolName: action.icon,
            accessibilityDescription: title
        )
        return item
    }

    private func formattingAction(for identifier: String) -> FormattingAction? {
        let rawValue = identifier.replacingOccurrences(of: "editor-toolbar-", with: "")
        return FormattingAction(rawValue: rawValue)
    }

    private func topLevelButtons() -> [MacToolbarButton] {
        [
            undoButton,
            redoButton,
            boldButton,
            italicButton,
            strikethroughButton,
            headingButton,
            bulletListButton,
            numberedListButton,
            checkboxButton,
            codeButton,
            linkButton,
            overflowButton,
            aiButton
        ]
    }
}

@MainActor
private final class MacToolbarButton: NSButton {
    init(icon: String) {
        super.init(frame: .zero)
        bezelStyle = .texturedRounded
        isBordered = false
        image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        imagePosition = .imageOnly
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = 5
        contentTintColor = .labelColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyActiveAppearance(_ isActive: Bool) {
        layer?.backgroundColor = isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
    }

    func applyEnabledAppearance(isEnabled: Bool, isComposing: Bool) {
        alphaValue = isComposing ? 0.4 : (isEnabled ? 1.0 : 0.35)
    }
}

@MainActor
private final class MacToolbarDivider: NSBox {
    init() {
        super.init(frame: .zero)
        boxType = .separator
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 1),
            heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
