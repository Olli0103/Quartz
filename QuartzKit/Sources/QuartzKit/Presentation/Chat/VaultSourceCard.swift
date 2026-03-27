import SwiftUI

/// Compact card displaying a cited note in vault chat responses.
///
/// Shows a color-coded number badge, note icon, title, excerpt,
/// and a chevron for navigation. Tapping navigates to the cited note.
///
/// **Ref:** Phase F4 Spec — Source Cards
struct VaultSourceCard: View {
    let citation: Citation
    let onTap: ((UUID) -> Void)?

    @Environment(\.appearanceManager) private var appearance
    @ScaledMetric(relativeTo: .caption) private var cardPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 22

    /// Color cycling for citation sources.
    static func color(for index: Int) -> Color {
        switch index {
        case 1: return QuartzColors.accent
        case 2: return QuartzColors.noteBlue
        case 3: return QuartzColors.canvasPurple
        case 4: return QuartzColors.folderYellow
        default:
            let palette = QuartzColors.tagPalette
            return palette[(index - 5) % palette.count]
        }
    }

    var body: some View {
        Button {
            QuartzFeedback.selection()
            onTap?(citation.noteID)
        } label: {
            HStack(spacing: 10) {
                // Number badge
                Text("\(citation.id)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Self.color(for: citation.id))
                    .frame(width: badgeSize, height: badgeSize)
                    .background(
                        Circle()
                            .fill(Self.color(for: citation.id).opacity(0.15))
                    )

                // Note icon + title + excerpt
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                        Text(citation.noteTitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    if !citation.excerpt.isEmpty {
                        Text(citation.excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(cardPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.fill.quaternary)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "Source \(citation.id): \(citation.noteTitle)", bundle: .module)
        )
        .accessibilityHint(String(localized: "Double tap to open this note", bundle: .module))
    }
}
