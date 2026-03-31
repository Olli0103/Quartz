import SwiftUI

// MARK: - Keyboard Shortcuts

/// Keyboard shortcuts for iPad and Mac.
///
/// Registers productivity-related key combinations:
/// - ⌘N: New note
/// - ⌘⇧N: New folder
/// - ⌘F: Search
/// - ⌘⇧F: Vault-wide search
/// - ⌘/: Toggle sidebar
/// - ⌘⇧D: Daily note
/// - Format menu: Bold, Italic, Headings, Code, etc.
public struct KeyboardShortcutCommands: Commands {
    let onNewNote: () -> Void
    let onNewFolder: () -> Void
    let onSearch: () -> Void
    let onGlobalSearch: () -> Void
    let onToggleSidebar: () -> Void
    let onDailyNote: () -> Void
    var onFormatAction: ((FormattingAction) -> Void)?
    var onOpenVault: (() -> Void)?
    var onCreateVault: (() -> Void)?

    public init(
        onNewNote: @escaping () -> Void,
        onNewFolder: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onGlobalSearch: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void,
        onDailyNote: @escaping () -> Void,
        onFormatAction: ((FormattingAction) -> Void)? = nil,
        onOpenVault: (() -> Void)? = nil,
        onCreateVault: (() -> Void)? = nil
    ) {
        self.onNewNote = onNewNote
        self.onNewFolder = onNewFolder
        self.onSearch = onSearch
        self.onGlobalSearch = onGlobalSearch
        self.onToggleSidebar = onToggleSidebar
        self.onDailyNote = onDailyNote
        self.onFormatAction = onFormatAction
        self.onOpenVault = onOpenVault
        self.onCreateVault = onCreateVault
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Note", bundle: .module)) { onNewNote() }
                .keyboardShortcut("n", modifiers: .command)

            Button(String(localized: "New Folder", bundle: .module)) { onNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Daily Note", bundle: .module)) { onDailyNote() }
                .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Open Vault…", bundle: .module)) { onOpenVault?() }
                .keyboardShortcut("o", modifiers: [.command, .shift])

            Button(String(localized: "Create New Vault…", bundle: .module)) { onCreateVault?() }
        }

        CommandGroup(after: .textEditing) {
            // Cmd+F: On iOS, UITextView provides native Find — only register on macOS
            #if os(macOS)
            Button(String(localized: "Find in Note", bundle: .module)) { onSearch() }
                .keyboardShortcut("f", modifiers: .command)
            #endif

            Button(String(localized: "Search All Notes", bundle: .module)) { onGlobalSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button(String(localized: "Toggle Sidebar", bundle: .module)) { onToggleSidebar() }
                .keyboardShortcut("/", modifiers: .command)
        }

        CommandMenu(String(localized: "Format", bundle: .module)) {
            Button(String(localized: "Bold", bundle: .module)) { onFormatAction?(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button(String(localized: "Italic", bundle: .module)) { onFormatAction?(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button(String(localized: "Strikethrough", bundle: .module)) { onFormatAction?(.strikethrough) }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Heading 1", bundle: .module)) { onFormatAction?(.heading1) }
                .keyboardShortcut("1", modifiers: .command)
            Button(String(localized: "Heading 2", bundle: .module)) { onFormatAction?(.heading2) }
                .keyboardShortcut("2", modifiers: .command)
            Button(String(localized: "Heading 3", bundle: .module)) { onFormatAction?(.heading3) }
                .keyboardShortcut("3", modifiers: .command)
            Button(String(localized: "Heading 4", bundle: .module)) { onFormatAction?(.heading4) }
                .keyboardShortcut("4", modifiers: .command)
            Button(String(localized: "Heading 5", bundle: .module)) { onFormatAction?(.heading5) }
                .keyboardShortcut("5", modifiers: .command)
            Button(String(localized: "Heading 6", bundle: .module)) { onFormatAction?(.heading6) }
                .keyboardShortcut("6", modifiers: .command)

            Divider()

            // Cmd+E: On iOS, UITextView uses this for "Use Selection for Find" — use Cmd+Shift+E instead
            #if os(macOS)
            Button(String(localized: "Inline Code", bundle: .module)) { onFormatAction?(.code) }
                .keyboardShortcut("e", modifiers: .command)
            #else
            Button(String(localized: "Inline Code", bundle: .module)) { onFormatAction?(.code) }
                .keyboardShortcut("e", modifiers: [.command, .option])
            #endif
            Button(String(localized: "Code Block", bundle: .module)) { onFormatAction?(.codeBlock) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button(String(localized: "Link", bundle: .module)) { onFormatAction?(.link) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button(String(localized: "Blockquote", bundle: .module)) { onFormatAction?(.blockquote) }
                .keyboardShortcut("q", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Bullet List", bundle: .module)) { onFormatAction?(.bulletList) }
            Button(String(localized: "Numbered List", bundle: .module)) { onFormatAction?(.numberedList) }
            Button(String(localized: "Checkbox", bundle: .module)) { onFormatAction?(.checkbox) }
            Button(String(localized: "Table", bundle: .module)) { onFormatAction?(.table) }
        }
    }
}
