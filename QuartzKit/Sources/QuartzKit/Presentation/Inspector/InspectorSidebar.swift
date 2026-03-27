import SwiftUI

/// Right-hand inspector panel: Table of Contents, document stats, tags, metadata.
///
/// On macOS, attached via `.inspector(isPresented:)`.
/// On iOS/iPadOS, presented as a `.sheet` with detents.
public struct InspectorSidebar: View {
    let store: InspectorStore
    let note: NoteDocument?
    let vaultRootURL: URL?
    var onScrollToHeading: ((HeadingItem) -> Void)?

    @Environment(\.appearanceManager) private var appearance

    public init(
        store: InspectorStore,
        note: NoteDocument?,
        vaultRootURL: URL?,
        onScrollToHeading: ((HeadingItem) -> Void)? = nil
    ) {
        self.store = store
        self.note = note
        self.vaultRootURL = vaultRootURL
        self.onScrollToHeading = onScrollToHeading
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statsSection
                    .padding(.bottom, 16)

                if !store.headings.isEmpty {
                    tocSection
                        .padding(.bottom, 16)
                }

                if let note, !note.frontmatter.tags.isEmpty {
                    tagsSection(tags: note.frontmatter.tags)
                        .padding(.bottom, 16)
                }

                if let note {
                    metadataSection(note: note)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DOCUMENT STATS", icon: "chart.bar")

            HStack(spacing: 4) {
                Text("\(store.stats.wordCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(store.stats.wordCount == 1 ? "word" : "words")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(store.stats.characterCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("chars")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text("~\(store.stats.readingTimeMinutes) min read")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Table of Contents

    private var tocSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("TABLE OF CONTENTS", icon: "list.bullet")

            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.headings) { heading in
                    Button {
                        QuartzFeedback.selection()
                        onScrollToHeading?(heading)
                    } label: {
                        HStack(spacing: 6) {
                            if heading.level > 1 {
                                Rectangle()
                                    .fill(store.activeHeadingID == heading.id
                                          ? appearance.accentColor
                                          : appearance.accentColor.opacity(0.2))
                                    .frame(width: 2)
                            }

                            Text(heading.text)
                                .font(heading.level == 1
                                      ? .callout.weight(.semibold)
                                      : .callout)
                                .foregroundStyle(store.activeHeadingID == heading.id
                                                 ? appearance.accentColor
                                                 : .primary)
                                .lineLimit(1)
                        }
                        .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(store.activeHeadingID == heading.id
                                      ? appearance.accentColor.opacity(0.08)
                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Heading level \(heading.level): \(heading.text)")
                }
            }
        }
    }

    // MARK: - Tags Section

    private func tagsSection(tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("TAGS", icon: "tag")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(QuartzColors.tagColor(for: tag))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(QuartzColors.tagColor(for: tag).opacity(0.12))
                            )
                    }
                }
            }
        }
    }

    // MARK: - Metadata Section

    private func metadataSection(note: NoteDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("METADATA", icon: "info.circle")

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text(note.frontmatter.modifiedAt, style: .relative)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text(breadcrumbPath(for: note))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private func breadcrumbPath(for note: NoteDocument) -> String {
        let parent = note.fileURL.deletingLastPathComponent()
        guard let root = vaultRootURL else {
            return parent.lastPathComponent
        }
        let rootPath = root.standardizedFileURL.path()
        let parentPath = parent.standardizedFileURL.path()
        guard parentPath.hasPrefix(rootPath) else {
            return parent.lastPathComponent
        }
        let relative = String(parentPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/")
        return components.isEmpty ? note.fileURL.lastPathComponent : components.joined(separator: " / ")
    }
}
