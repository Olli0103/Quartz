import SwiftUI

/// Spotlight-ähnliche Volltextsuche über den gesamten Vault.
/// Glasmorphismus-Design mit Live-Ergebnissen.
public struct SearchView: View {
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching: Bool = false
    @Environment(\.dismiss) private var dismiss

    let searchIndex: VaultSearchIndex
    let onSelect: (URL) -> Void

    public init(searchIndex: VaultSearchIndex, onSelect: @escaping (URL) -> Void) {
        self.searchIndex = searchIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if results.isEmpty && !query.isEmpty && !isSearching {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ForEach(results) { result in
                            Button {
                                onSelect(result.noteURL)
                                dismiss()
                            } label: {
                                SearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $query, isPresented: .constant(true), prompt: Text(String(localized: "Search all notes…")))
            .onChange(of: query) { _, newQuery in
                performSearch(newQuery)
            }
            .navigationTitle(String(localized: "Search"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func performSearch(_ query: String) {
        isSearching = true
        Task {
            let searchResults = await searchIndex.search(query: query)
            await MainActor.run {
                results = searchResults
                isSearching = false
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(QuartzColors.noteBlue)

                Text(result.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }

            if let context = result.context, !context.isEmpty {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !result.matchedTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(result.matchedTags, id: \.self) { tag in
                        QuartzTagBadge(text: tag)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
