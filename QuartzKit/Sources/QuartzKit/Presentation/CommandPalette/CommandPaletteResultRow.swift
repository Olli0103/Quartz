import SwiftUI

/// A single row in the command palette — renders either a note or a command.
///
/// When `isSelected`, shows accent background with white text.
/// Otherwise, transparent background with standard text colors.
struct CommandPaletteResultRow: View {
    let item: PaletteItem
    let isSelected: Bool

    @Environment(\.appearanceManager) private var appearance

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.body.weight(.medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Trailing: shortcut label for commands, date for notes
            if let trailing = trailingText {
                Text(trailing)
                    .font(.caption.monospaced())
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? appearance.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch item {
        case .note: "doc.text.fill"
        case .command(let c): c.icon
        }
    }

    private var subtitle: String? {
        switch item {
        case .note(let n): n.folderPath
        case .command(let c): c.shortcutLabel.map { _ in "" } // no subtitle for commands with shortcuts
        }
    }

    private var trailingText: String? {
        switch item {
        case .note(let n):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: n.modifiedAt, relativeTo: Date())
        case .command(let c):
            return c.shortcutLabel
        }
    }

    private var accessibilityText: String {
        switch item {
        case .note(let n):
            "Note: \(n.title), in \(n.folderPath)"
        case .command(let c):
            "Command: \(c.title)\(c.shortcutLabel.map { ", \($0)" } ?? "")"
        }
    }
}
