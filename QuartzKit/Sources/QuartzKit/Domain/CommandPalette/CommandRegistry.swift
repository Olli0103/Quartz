import Foundation

/// Builds the static list of app commands available in the command palette.
///
/// Commands are conditionally included based on context (vault open, platform).
/// Each command captures weak references to avoid retain cycles.
@MainActor
public struct CommandRegistry {

    /// Builds the command list for the current app context.
    ///
    /// - Parameters:
    ///   - vaultRoot: Root URL of the open vault (nil if no vault)
    ///   - onNewNote: Callback to present the new note dialog
    ///   - onNewFolder: Callback to present the new folder dialog
    ///   - onDailyNote: Callback to create/open a daily note
    ///   - onVaultChat: Callback to open vault chat
    ///   - onSettings: Callback to open settings
    ///   - onToggleFocus: Callback to toggle focus mode
    ///   - onToggleDarkMode: Callback to toggle dark/light mode
    ///   - onReindex: Callback to reindex the vault
    ///   - onExportBackup: Callback to export a backup
    ///   - onKnowledgeGraph: Callback to open the knowledge graph (macOS only)
    public static func build(
        vaultRoot: URL?,
        onNewNote: @escaping @MainActor @Sendable () -> Void,
        onNewFolder: @escaping @MainActor @Sendable () -> Void,
        onDailyNote: @escaping @MainActor @Sendable () -> Void,
        onVaultChat: @escaping @MainActor @Sendable () -> Void,
        onSettings: @escaping @MainActor @Sendable () -> Void,
        onToggleFocus: @escaping @MainActor @Sendable () -> Void,
        onToggleDarkMode: @escaping @MainActor @Sendable () -> Void,
        onReindex: @escaping @MainActor @Sendable () -> Void,
        onExportBackup: @escaping @MainActor @Sendable () -> Void,
        onExportPDF: (@MainActor @Sendable () -> Void)? = nil,
        onExportHTML: (@MainActor @Sendable () -> Void)? = nil,
        onOpenInNewWindow: (@MainActor @Sendable () -> Void)? = nil,
        onKnowledgeGraph: (@MainActor @Sendable () -> Void)? = nil
    ) -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        if vaultRoot != nil {
            commands.append(PaletteCommand(
                id: "new-note",
                title: "Create New Note",
                icon: "plus.circle.fill",
                shortcutLabel: "Cmd+N",
                keywords: ["new", "create", "add", "note"],
                action: onNewNote
            ))

            commands.append(PaletteCommand(
                id: "new-folder",
                title: "Create New Folder",
                icon: "folder.badge.plus",
                shortcutLabel: "Cmd+Shift+N",
                keywords: ["new", "create", "folder", "directory"],
                action: onNewFolder
            ))

            commands.append(PaletteCommand(
                id: "daily-note",
                title: "Open Daily Note",
                icon: "calendar",
                shortcutLabel: "Cmd+Shift+D",
                keywords: ["daily", "today", "journal", "diary"],
                action: onDailyNote
            ))

            commands.append(PaletteCommand(
                id: "vault-chat",
                title: "Open Vault Chat",
                icon: "bubble.left.and.bubble.right",
                shortcutLabel: "Cmd+Shift+J",
                keywords: ["chat", "ai", "ask", "question", "brain", "vault"],
                action: onVaultChat
            ))

            commands.append(PaletteCommand(
                id: "reindex",
                title: "Reindex Vault",
                icon: "arrow.triangle.2.circlepath",
                keywords: ["reindex", "rebuild", "refresh", "index", "embeddings"],
                action: onReindex
            ))

            commands.append(PaletteCommand(
                id: "export-backup",
                title: "Export Backup",
                icon: "square.and.arrow.up",
                keywords: ["backup", "export", "archive", "save", "zip"],
                action: onExportBackup
            ))

            if let onExportPDF {
                commands.append(PaletteCommand(
                    id: "export-pdf",
                    title: "Export as PDF",
                    icon: "doc.richtext",
                    shortcutLabel: "Cmd+Shift+E",
                    keywords: ["export", "pdf", "print", "document", "save"],
                    action: onExportPDF
                ))
            }

            if let onExportHTML {
                commands.append(PaletteCommand(
                    id: "export-html",
                    title: "Export as HTML",
                    icon: "doc.text.fill",
                    keywords: ["export", "html", "web", "page"],
                    action: onExportHTML
                ))
            }

            #if os(macOS)
            if let onKnowledgeGraph {
                commands.append(PaletteCommand(
                    id: "knowledge-graph",
                    title: "Knowledge Graph",
                    icon: "point.3.connected.trianglepath.dotted",
                    keywords: ["graph", "map", "connections", "links", "network"],
                    action: onKnowledgeGraph
                ))
            }

            if let onOpenInNewWindow {
                commands.append(PaletteCommand(
                    id: "open-new-window",
                    title: "Open Note in New Window",
                    icon: "macwindow.badge.plus",
                    shortcutLabel: "Cmd+Shift+O",
                    keywords: ["window", "new", "open", "detach", "separate"],
                    action: onOpenInNewWindow
                ))
            }
            #endif
        }

        // Always-available commands
        commands.append(PaletteCommand(
            id: "settings",
            title: "Open Settings",
            icon: "gear",
            shortcutLabel: "Cmd+,",
            keywords: ["settings", "preferences", "options", "config"],
            action: onSettings
        ))

        commands.append(PaletteCommand(
            id: "toggle-focus",
            title: "Toggle Focus Mode",
            icon: "arrow.up.left.and.arrow.down.right",
            keywords: ["focus", "zen", "distraction", "concentrate", "fullscreen"],
            action: onToggleFocus
        ))

        commands.append(PaletteCommand(
            id: "toggle-dark-mode",
            title: "Toggle Dark Mode",
            icon: "moon.fill",
            keywords: ["dark", "light", "theme", "mode", "appearance", "night"],
            action: onToggleDarkMode
        ))

        return commands
    }

    /// Commands shown in the empty-query state (pinned quick actions).
    public static let pinnedCommandIDs: Set<String> = [
        "new-note", "daily-note", "vault-chat"
    ]
}
