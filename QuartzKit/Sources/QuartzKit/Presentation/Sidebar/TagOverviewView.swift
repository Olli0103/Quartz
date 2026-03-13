import SwiftUI

/// Zeigt eine Übersicht aller Tags im Vault mit Filterfunktion.
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
                Text("No tags yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(tags) { tag in
                    Button {
                        if selectedTag == tag.name {
                            selectedTag = nil
                        } else {
                            selectedTag = tag.name
                        }
                    } label: {
                        HStack {
                            Image(systemName: "number")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tag.name)
                                .font(.callout)
                            Spacer()
                            Text("\(tag.count)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedTag == tag.name
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                    )
                }
            }
        } header: {
            HStack {
                Text("Tags")
                Spacer()
                if selectedTag != nil {
                    Button("Clear") {
                        selectedTag = nil
                    }
                    .font(.caption)
                }
            }
        }
    }
}

/// Info über einen Tag: Name und Anzahl der Notizen.
public struct TagInfo: Identifiable, Sendable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}
