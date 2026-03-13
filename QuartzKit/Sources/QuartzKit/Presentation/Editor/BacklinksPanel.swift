import SwiftUI

/// Panel das Backlinks zur aktuellen Notiz anzeigt ("Wer verlinkt hierher?").
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
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Backlinks")
                        .font(.caption.bold())
                    Spacer()
                    Text("\(backlinks.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if backlinks.isEmpty {
                    Text("No other notes link here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(backlinks) { backlink in
                            Button {
                                onNavigate(backlink.sourceNoteURL)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backlink.sourceNoteName)
                                        .font(.callout.bold())
                                        .foregroundStyle(.primary)
                                    if !backlink.context.isEmpty {
                                        Text(backlink.context)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.fill.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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
