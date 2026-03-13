import SwiftUI

/// Panel das Backlinks zur aktuellen Notiz anzeigt – Liquid Glass Stil.
public struct BacklinksPanel: View {
    let backlinks: [Backlink]
    let onNavigate: (URL) -> Void
    @State private var isExpanded: Bool = false

    public init(backlinks: [Backlink], onNavigate: @escaping (URL) -> Void) {
        self.backlinks = backlinks
        self.onNavigate = onNavigate
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Backlinks")
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Text("\(backlinks.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.fill.tertiary))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                if backlinks.isEmpty {
                    HStack {
                        Spacer()
                        Text("No other notes link here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 6) {
                        ForEach(backlinks) { backlink in
                            Button {
                                onNavigate(backlink.sourceNoteURL)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption)
                                        .foregroundStyle(QuartzColors.noteBlue)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(backlink.sourceNoteName)
                                            .font(.callout.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !backlink.context.isEmpty {
                                            Text(backlink.context)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.quaternary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.fill.quaternary)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
