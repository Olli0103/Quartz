import SwiftUI

/// Displays the YAML frontmatter block as an editable key-value list.
/// Collapsible with Liquid Glass design.
public struct FrontmatterEditorView: View {
    @Binding var frontmatter: Frontmatter
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.appearanceManager) private var appearance
    @State private var isExpanded: Bool = false
    @State private var newTag: String = ""
    @State private var newCustomKey: String = ""
    @State private var newCustomValue: String = ""
    @FocusState private var focusedField: FrontmatterField?

    enum FrontmatterField: Hashable {
        case title, newTag, customKey, customValue
    }

    public init(frontmatter: Binding<Frontmatter>) {
        self._frontmatter = frontmatter
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toggle Header
            Button {
                withAnimation(QuartzAnimation.standard) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: "doc.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(String(localized: "Frontmatter", bundle: .module))
                        .font(.caption.weight(.semibold))

                    Spacer()

                    if !isExpanded {
                        Text(summaryText)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .quartzMaterialBackground(cornerRadius: 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? String(localized: "Collapse frontmatter", bundle: .module) : String(localized: "Expand frontmatter", bundle: .module))

            // Expanded Content
            if isExpanded {
                VStack(spacing: 14) {
                    // Title
                    LabeledField(label: String(localized: "Title", bundle: .module)) {
                        TextField(String(localized: "Note title", bundle: .module), text: Binding(
                            get: { frontmatter.title ?? "" },
                            set: { frontmatter.title = $0.isEmpty ? nil : $0 }
                        ))
                        .focused($focusedField, equals: .title)
                        .onSubmit { focusedField = .newTag }
                        .textFieldStyle(.roundedBorder)
                    }

                    // Tags
                    LabeledField(label: String(localized: "Tags", bundle: .module)) {
                        FlowLayout(spacing: 6, layoutDirection: layoutDirection) {
                            ForEach(frontmatter.tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    QuartzTagBadge(text: tag)
                                    Button {
                                        frontmatter.tags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(localized: "Remove tag \(tag)", bundle: .module))
                                }
                            }

                            HStack(spacing: 4) {
                                TextField(String(localized: "Add tag", bundle: .module), text: $newTag)
                                    .focused($focusedField, equals: .newTag)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 100)
                                    .onSubmit { addTag() }

                                Button { addTag() } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(appearance.accentColor)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                #if os(iOS)
                                .hoverEffect(.highlight)
                                #endif
                                .disabled(newTag.isEmpty)
                                .accessibilityLabel(String(localized: "Add tag", bundle: .module))
                            }
                        }
                    }

                    // Dates
                    HStack(spacing: 16) {
                        LabeledField(label: String(localized: "Created", bundle: .module)) {
                            Text(frontmatter.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LabeledField(label: String(localized: "Modified", bundle: .module)) {
                            Text(frontmatter.modifiedAt, style: .relative)
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
                        TextField(String(localized: "Key", bundle: .module), text: $newCustomKey)
                            .focused($focusedField, equals: .customKey)
                            .onSubmit { focusedField = .customValue }
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        TextField(String(localized: "Value", bundle: .module), text: $newCustomValue)
                            .focused($focusedField, equals: .customValue)
                            .onSubmit { addCustomField(); focusedField = .customKey }
                            .textFieldStyle(.roundedBorder)
                        Button { addCustomField() } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(QuartzColors.accent)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #if os(iOS)
                        .hoverEffect(.highlight)
                        #endif
                        .disabled(newCustomKey.isEmpty)
                        .accessibilityLabel(String(localized: "Add custom field", bundle: .module))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.background.secondary)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Helpers

    private var summaryText: String {
        var parts: [String] = []
        if let title = frontmatter.title { parts.append(title) }
        if !frontmatter.tags.isEmpty { parts.append(String(localized: "^[\(frontmatter.tags.count) tag](inflect: true)", bundle: .module)) }
        return parts.joined(separator: " · ")
    }

    private func addTag() {
        let tag = newTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !tag.isEmpty, tag.count <= 50, !frontmatter.tags.contains(tag) else { return }
        frontmatter.tags.append(tag)
        newTag = ""
    }

    private func addCustomField() {
        let key = newCustomKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
        guard !key.isEmpty, key.count <= 50 else { return }
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }
}

/// Simple flow layout for tags – supports both LTR and RTL layout directions.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var layoutDirection: LayoutDirection = .leftToRight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        let isRTL = layoutDirection == .rightToLeft
        for (index, position) in result.positions.enumerated() {
            let size = subviews[index].sizeThatFits(.unspecified)
            let x: CGFloat
            if isRTL {
                x = bounds.maxX - position.x - size.width
            } else {
                x = bounds.minX + position.x
            }
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        let size: CGSize
        let positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
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

        return ArrangeResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions
        )
    }
}
