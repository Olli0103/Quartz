import SwiftUI

/// Zeigt den YAML-Frontmatter-Block als editierbare Key-Value-Liste.
///
/// Standard: Eingeklappt. Per Toggle sichtbar. Änderungen werden
/// direkt im ViewModel reflektiert.
public struct FrontmatterEditorView: View {
    @Binding var frontmatter: Frontmatter
    @State private var isExpanded: Bool = false
    @State private var newTag: String = ""
    @State private var newCustomKey: String = ""
    @State private var newCustomValue: String = ""

    public init(frontmatter: Binding<Frontmatter>) {
        self._frontmatter = frontmatter
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toggle-Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Frontmatter")
                        .font(.caption.bold())
                    Spacer()
                    if !isExpanded {
                        Text(summaryText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .buttonStyle(.plain)

            // Expandierter Inhalt
            if isExpanded {
                VStack(spacing: 12) {
                    // Title
                    LabeledField(label: "Title") {
                        TextField("Note title", text: Binding(
                            get: { frontmatter.title ?? "" },
                            set: { frontmatter.title = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    // Tags
                    LabeledField(label: "Tags") {
                        FlowLayout(spacing: 6) {
                            ForEach(frontmatter.tags, id: \.self) { tag in
                                TagChip(text: tag) {
                                    frontmatter.tags.removeAll { $0 == tag }
                                }
                            }

                            HStack(spacing: 4) {
                                TextField("Add tag", text: $newTag)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .onSubmit {
                                        addTag()
                                    }
                                Button {
                                    addTag()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(newTag.isEmpty)
                            }
                        }
                    }

                    // Aliases
                    LabeledField(label: "Aliases") {
                        Text(frontmatter.aliases.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Dates
                    LabeledField(label: "Created") {
                        Text(frontmatter.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledField(label: "Modified") {
                        Text(frontmatter.modifiedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Template
                    if let template = frontmatter.template {
                        LabeledField(label: "Template") {
                            Text(template)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Custom Fields
                    if !frontmatter.customFields.isEmpty {
                        ForEach(
                            frontmatter.customFields.sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { key, value in
                            LabeledField(label: key) {
                                TextField(key, text: Binding(
                                    get: { value },
                                    set: { frontmatter.customFields[key] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    // Add Custom Field
                    HStack(spacing: 8) {
                        TextField("Key", text: $newCustomKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        TextField("Value", text: $newCustomValue)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            addCustomField()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(newCustomKey.isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.background.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var summaryText: String {
        var parts: [String] = []
        if let title = frontmatter.title { parts.append(title) }
        if !frontmatter.tags.isEmpty { parts.append("\(frontmatter.tags.count) tags") }
        return parts.joined(separator: " · ")
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !frontmatter.tags.contains(tag) else { return }
        frontmatter.tags.append(tag)
        newTag = ""
    }

    private func addCustomField() {
        let key = newCustomKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        frontmatter.customFields[key] = newCustomValue
        newCustomKey = ""
        newCustomValue = ""
    }
}

// MARK: - Supporting Views

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

private struct TagChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.tertiary)
        .clipShape(Capsule())
    }
}

/// Einfaches FlowLayout für Tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
