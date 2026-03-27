import Foundation

/// A static app command that can be executed from the command palette.
public struct PaletteCommand: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String            // SF Symbol name
    public let shortcutLabel: String?  // e.g. "Cmd+N"
    public let keywords: [String]      // extra terms for fuzzy matching
    /// The action to execute. Captured at registry build time.
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String,
        title: String,
        icon: String,
        shortcutLabel: String? = nil,
        keywords: [String] = [],
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutLabel = shortcutLabel
        self.keywords = keywords
        self.action = action
    }
}

/// A note search result from the palette.
public struct NoteResult: Sendable {
    public let url: URL
    public let title: String
    public let folderPath: String   // e.g. "Projects/" or "/"
    public let modifiedAt: Date
    public let snippet: String?
    public let matchScore: Int

    public init(url: URL, title: String, folderPath: String, modifiedAt: Date, snippet: String? = nil, matchScore: Int = 0) {
        self.url = url
        self.title = title
        self.folderPath = folderPath
        self.modifiedAt = modifiedAt
        self.snippet = snippet
        self.matchScore = matchScore
    }
}

/// A unified row in the command palette — either a note or a command.
public enum PaletteItem: Identifiable {
    case note(NoteResult)
    case command(PaletteCommand)

    public var id: String {
        switch self {
        case .note(let n): "note:\(n.url.absoluteString)"
        case .command(let c): "cmd:\(c.id)"
        }
    }

    /// Sort score — higher is better.
    public var score: Int {
        switch self {
        case .note(let n): n.matchScore
        case .command: 0 // commands use their own scoring in the engine
        }
    }

    public var title: String {
        switch self {
        case .note(let n): n.title
        case .command(let c): c.title
        }
    }
}
