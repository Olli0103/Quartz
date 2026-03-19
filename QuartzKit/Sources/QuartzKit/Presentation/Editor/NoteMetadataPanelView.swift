#if os(macOS)
import SwiftUI

/// Right-hand metadata panel for the note editor: outline, folder path, tags (editable), export.
struct NoteMetadataPanelView: View {
    let note: NoteDocument
    let content: String
    let vaultRootURL: URL?
    var onUpdateFrontmatter: ((Frontmatter) -> Void)?
    let onExportPDF: () -> Void

    @Environment(\.appearanceManager) private var appearance
    @State private var newTagText = ""

    private let headingExtractor = HeadingExtractor()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "NOTE METADATA", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 12)

            // Created / modified – simplified (no user identity in app)
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(note.frontmatter.modifiedAt, style: .relative)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            // Folders (breadcrumb path)
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(breadcrumbPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.bottom, 12)

            // Tags (editable when onUpdateFrontmatter is provided)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.system(size: 12, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Tags", bundle: .module))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let onUpdate = onUpdateFrontmatter {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(note.frontmatter.tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                            .font(.caption)
                                            .foregroundStyle(appearance.accentColor)
                                        Button {
                                            var fm = note.frontmatter
                                            fm.tags.removeAll { $0 == tag }
                                            onUpdate(fm)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(appearance.accentColor.opacity(0.12)))
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            TextField(String(localized: "Add tag…", bundle: .module), text: $newTagText)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .frame(minWidth: 80)
                                .onSubmit { addTag(onUpdate: onUpdate) }
                            Button {
                                addTag(onUpdate: onUpdate)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(appearance.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !note.frontmatter.tags.isEmpty {
                    Text(note.frontmatter.tags.map { "#\($0)" }.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(appearance.accentColor)
                        .lineLimit(3)
                }
            }
            .padding(.bottom, 16)

            // Outline (hierarchical numbering: 1., 1.1., 2., 2.1.)
            let headings = headingExtractor.extractHeadings(from: content)
            if !headings.isEmpty {
                Text(String(localized: "OUTLINE", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if heading.level > 1 {
                                    Rectangle()
                                        .fill(appearance.accentColor.opacity(0.3))
                                        .frame(width: 2)
                                }
                                Text("\(hierarchicalNumber(for: heading, in: headings)). \(heading.text)")
                                    .font(.callout)
                                    .foregroundStyle(heading.level == 1 ? appearance.accentColor : .primary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, CGFloat(heading.level - 1) * 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            Button {
                onExportPDF()
            } label: {
                Text(String(localized: "Export Document", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(appearance.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
        .quartzMaterialBackground(cornerRadius: 12)
    }

    /// Hierarchical outline number: 1., 1.1., 2., 2.1. for h1, h2, h3...
    private func hierarchicalNumber(for heading: HeadingExtractor.Heading, in headings: [HeadingExtractor.Heading]) -> String {
        var counts = [0, 0, 0, 0, 0, 0]
        for h in headings {
            counts[h.level - 1] += 1
            for i in h.level..<6 {
                counts[i] = 0
            }
            if h.id == heading.id {
                break
            }
        }
        return (0..<heading.level).map { String(counts[$0]) }.joined(separator: ".")
    }

    private func addTag(onUpdate: (Frontmatter) -> Void) {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !tag.isEmpty, !note.frontmatter.tags.contains(tag) else {
            newTagText = ""
            return
        }
        var fm = note.frontmatter
        fm.tags.append(tag)
        onUpdate(fm)
        newTagText = ""
    }

    private var breadcrumbPath: String {
        let url = note.fileURL
        let parent = url.deletingLastPathComponent()
        guard let root = vaultRootURL else {
            return parent.pathComponents.suffix(2).joined(separator: " / ")
        }
        let rootPath = root.standardizedFileURL.path()
        let parentPath = parent.standardizedFileURL.path()
        guard parentPath.hasPrefix(rootPath) else {
            return parent.lastPathComponent
        }
        let relative = String(parentPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/")
        return components.isEmpty ? url.lastPathComponent : components.joined(separator: " / ")
    }
}
#endif
