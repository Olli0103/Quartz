import SwiftUI

/// Overview of all tags in the vault – pill style with color palette.
public struct TagOverviewView: View {
    let tags: [TagInfo]
    @Binding var selectedTag: String?

    public init(tags: [TagInfo], selectedTag: Binding<String?>) {
        self.tags = tags
        self._selectedTag = selectedTag
    }

    public var body: some View {
        Section {
            if tags.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                        Text(String(localized: "No tags yet", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(tags) { tag in
                    Button {
                        QuartzFeedback.selection()
                        withAnimation(QuartzAnimation.standard) {
                            if selectedTag == tag.name {
                                selectedTag = nil
                            } else {
                                selectedTag = tag.name
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(QuartzColors.tagColor(for: tag.name))
                                .frame(width: 8, height: 8)

                            Text(tag.name)
                                .font(.callout)

                            Spacer()

                            Text("\(tag.count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(.fill.tertiary)
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tag.name)
                    .accessibilityHint(selectedTag == tag.name
                        ? String(localized: "Double tap to deselect", bundle: .module)
                        : String(localized: "Double tap to filter by this tag", bundle: .module))
                    .accessibilityAddTraits(selectedTag == tag.name ? .isSelected : [])
                    .listRowBackground(
                        selectedTag == tag.name
                        ? QuartzColors.tagColor(for: tag.name).opacity(0.1)
                        : Color.clear
                    )
                }
            }
        } header: {
            HStack {
                QuartzSectionHeader(String(localized: "Tags", bundle: .module), icon: "tag")
                Spacer()
                if selectedTag != nil {
                    Button(String(localized: "Clear", bundle: .module)) {
                        QuartzFeedback.selection()
                        withAnimation { selectedTag = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Info about a tag: name and number of notes.
public struct TagInfo: Identifiable, Sendable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}
