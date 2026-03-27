import SwiftUI

/// Individual row in the middle column note list.
///
/// Displays title, relative timestamp, 2-line snippet, and optional tags.
/// Follows Apple Notes / Bear visual density and typography hierarchy.
///
/// ## Typography (Agent 11 — ADA Judge)
/// - **Title**: `.body.weight(.semibold)`, `.primary` — matches Apple Notes density
/// - **Timestamp**: `.caption`, `.tertiary` — pushed to background
/// - **Snippet**: `.subheadline`, `.secondary` — clear separation from title
/// - **Tags**: `.caption2.weight(.medium)`, `QuartzColors.tagColor` — deterministic color variety
///
/// ## Spacing
/// - `6pt` vertical padding per row — Apple Notes density
/// - `4pt` internal VStack spacing — tight but readable
/// - `3pt` tag HStack spacing — compact chips
public struct NoteListRow: View {
    public let item: NoteListItem
    @Environment(\.appearanceManager) private var appearance

    public init(item: NoteListItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: Title + Timestamp
            HStack(alignment: .firstTextBaseline) {
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }

                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(Self.relativeTime(from: item.modifiedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Line 2-3: Snippet
            if !item.snippet.isEmpty {
                Text(item.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Line 4: Tags (if any, first 3 max)
            if !item.tags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(QuartzColors.tagColor(for: tag))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(item.isFavorite ? [.isSelected] : [])
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts = [item.title]
        parts.append(Self.relativeTime(from: item.modifiedAt))
        if !item.snippet.isEmpty {
            parts.append(item.snippet)
        }
        if item.isFavorite {
            parts.append(String(localized: "Favorite", bundle: .module))
        }
        if !item.tags.isEmpty {
            parts.append(item.tags.prefix(3).map { "#\($0)" }.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Date Formatting

    /// Stable relative timestamp ("2 min ago") — does NOT tick every second.
    /// Uses Foundation's `RelativeDateTimeFormatter` for performance.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.formattingContext = .standalone
        return f
    }()

    private static func relativeTime(from date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
