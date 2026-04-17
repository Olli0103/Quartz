import SwiftUI

/// Editor-local wiki-link suggestion surface shown while typing `[[`.
///
/// The query remains in the editor buffer. This view only renders suggestions
/// and routes actions back into the active `EditorSession`.
struct NoteLinkPicker: View {
    let session: EditorSession
    @Environment(\.appearanceManager) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(appearance.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Link Note", bundle: .module))
                        .font(.caption.weight(.semibold))
                    if session.linkInsertion.query.isEmpty {
                        Text(String(localized: "Type to filter notes", bundle: .module))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(session.linkInsertion.query)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(session.linkInsertion.suggestions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Button {
                    _ = session.dismissLinkInsertion()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("editor-link-picker-close")
                .accessibilityLabel(String(localized: "Close note link suggestions", bundle: .module))
            }

            if session.linkInsertion.suggestions.isEmpty {
                Text(String(localized: "No matching notes", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("editor-link-picker-empty")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.linkInsertion.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            session.insertWikiLinkSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(QuartzColors.noteBlue)

                                Text(suggestion.noteName)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        index == session.linkInsertion.selectedIndex
                                            ? appearance.accentColor.opacity(0.10)
                                            : Color.clear
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("editor-link-suggestion-\(index)")
                        .accessibilityLabel(String(localized: "Insert link to \(suggestion.noteName)", bundle: .module))
                    }
                }
            }

            Text(String(localized: "Use ↑ ↓ and Return to insert, Esc to close", bundle: .module))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .quartzMaterialBackground(cornerRadius: 12, shadowRadius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-link-picker")
    }
}
