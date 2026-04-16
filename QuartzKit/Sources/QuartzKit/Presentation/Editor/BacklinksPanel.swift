import SwiftUI

/// Panel that displays backlinks to the current note – Liquid Glass style.
struct BacklinksPanel: View {
    let backlinks: [Backlink]
    let isLoading: Bool
    let onNavigate: (URL) -> Void
    @State private var isExpanded: Bool = false

    init(
        backlinks: [Backlink],
        isLoading: Bool = false,
        onNavigate: @escaping (URL) -> Void
    ) {
        self.backlinks = backlinks
        self.isLoading = isLoading
        self.onNavigate = onNavigate
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(QuartzAnimation.standard) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: "link")
                        .font(.caption.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)

                    Text(String(localized: "Backlinks", bundle: .module))
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
                .padding(.vertical, 12)
                .quartzMaterialBackground(cornerRadius: 0)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor-backlinks-toggle")
            .accessibilityLabel(isExpanded ? String(localized: "Collapse backlinks", bundle: .module) : String(localized: "Expand backlinks", bundle: .module))

            // Content
            if isExpanded {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Loading backlinks…", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                } else if backlinks.isEmpty {
                    HStack {
                        Spacer()
                        Text(String(localized: "No other notes link here.", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 8) {
                        ForEach(backlinks) { backlink in
                            Button {
                                onNavigate(backlink.sourceNoteURL)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption.weight(.medium))
                                        .symbolRenderingMode(.hierarchical)
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
                                        .font(.caption2.weight(.medium))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.quaternary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.fill.quaternary)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Open \(backlink.sourceNoteName)", bundle: .module))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
