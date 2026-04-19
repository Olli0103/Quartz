import SwiftUI

/// Panel that displays explicit outgoing links from the current note.
struct OutgoingLinksPanel: View {
    let outgoingLinks: [InspectorStore.OutgoingLinkItem]
    let onNavigate: (InspectorStore.OutgoingLinkItem) -> Void
    @State private var isExpanded: Bool = false

    init(
        outgoingLinks: [InspectorStore.OutgoingLinkItem],
        onNavigate: @escaping (InspectorStore.OutgoingLinkItem) -> Void
    ) {
        self.outgoingLinks = outgoingLinks
        self.onNavigate = onNavigate
    }

    var body: some View {
        VStack(spacing: 0) {
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

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)

                    Text(String(localized: "Outgoing Links", bundle: .module))
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Text("\(outgoingLinks.count)")
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
            .accessibilityIdentifier("editor-outgoing-links-toggle")
            .accessibilityLabel(
                isExpanded
                    ? String(localized: "Collapse outgoing links", bundle: .module)
                    : String(localized: "Expand outgoing links", bundle: .module)
            )

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(outgoingLinks) { outgoingLink in
                        Button {
                            onNavigate(outgoingLink)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.medium))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(QuartzColors.noteBlue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(outgoingLink.noteName)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)

                                    if outgoingLink.displayText.localizedCaseInsensitiveCompare(outgoingLink.noteName) != .orderedSame {
                                        Text(outgoingLink.displayText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    } else if !outgoingLink.context.isEmpty {
                                        Text(outgoingLink.context)
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
                        .accessibilityLabel(
                            String(localized: "Open linked note \(outgoingLink.noteName)", bundle: .module)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
