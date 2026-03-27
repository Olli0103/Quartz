import Foundation

/// Time proximity bucket for grouping notes by modification date.
public enum TimeBucket: String, CaseIterable, Sendable {
    case today
    case previous7Days
    case previous30Days
    case older

    public var title: String {
        switch self {
        case .today: String(localized: "Today", bundle: .module)
        case .previous7Days: String(localized: "Previous 7 Days", bundle: .module)
        case .previous30Days: String(localized: "Previous 30 Days", bundle: .module)
        case .older: String(localized: "Older", bundle: .module)
        }
    }

    /// Determines which bucket a date falls into relative to now.
    public static func bucket(for date: Date) -> TimeBucket {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return .today
        }
        let now = Date()
        if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now),
           date >= sevenDaysAgo {
            return .previous7Days
        }
        if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now),
           date >= thirtyDaysAgo {
            return .previous30Days
        }
        return .older
    }
}

/// A section of notes grouped by time proximity or displayed flat.
///
/// When the sort order is date-based, notes are grouped into time buckets
/// (Today, Previous 7 Days, etc.). When sorted by title, a single flat section
/// with an empty title is used.
public struct NoteListSection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [NoteListItem]

    public init(id: String, title: String, items: [NoteListItem]) {
        self.id = id
        self.title = title
        self.items = items
    }

    /// Builds time-bucketed sections from a pre-sorted array of items.
    /// Empty buckets are omitted.
    public static func timeSections(from items: [NoteListItem]) -> [NoteListSection] {
        var buckets: [TimeBucket: [NoteListItem]] = [:]
        for item in items {
            let bucket = TimeBucket.bucket(for: item.modifiedAt)
            buckets[bucket, default: []].append(item)
        }
        // Return in chronological bucket order, omitting empty ones
        return TimeBucket.allCases.compactMap { bucket in
            guard let items = buckets[bucket], !items.isEmpty else { return nil }
            return NoteListSection(id: bucket.rawValue, title: bucket.title, items: items)
        }
    }

    /// Wraps items in a single flat section (no header).
    public static func flat(from items: [NoteListItem]) -> [NoteListSection] {
        guard !items.isEmpty else { return [] }
        return [NoteListSection(id: "all", title: "", items: items)]
    }
}
