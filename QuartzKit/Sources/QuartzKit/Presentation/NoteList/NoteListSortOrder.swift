import Foundation

/// Sort order for the middle column note list.
///
/// Persisted in `UserDefaults` via `rawValue`.
public enum NoteListSortOrder: String, CaseIterable, Sendable {
    case dateModifiedNewest
    case dateModifiedOldest
    case titleAscending
    case titleDescending

    /// Localized display label for the sort menu.
    public var label: String {
        switch self {
        case .dateModifiedNewest: String(localized: "Newest First", bundle: .module)
        case .dateModifiedOldest: String(localized: "Oldest First", bundle: .module)
        case .titleAscending: String(localized: "Title (A–Z)", bundle: .module)
        case .titleDescending: String(localized: "Title (Z–A)", bundle: .module)
        }
    }

    /// SF Symbol for the sort menu row.
    public var icon: String {
        switch self {
        case .dateModifiedNewest: "arrow.down.circle"
        case .dateModifiedOldest: "arrow.up.circle"
        case .titleAscending: "textformat.abc"
        case .titleDescending: "textformat.abc"
        }
    }
}
