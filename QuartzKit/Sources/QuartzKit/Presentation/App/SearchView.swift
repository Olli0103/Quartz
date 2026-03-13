import SwiftUI

/// Spotlight-ähnliche Volltextsuche über den gesamten Vault.
public struct SearchView: View {
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching: Bool = false

    let searchIndex: VaultSearchIndex
    let onSelect: (URL) -> Void

    public init(searchIndex: VaultSearchIndex, onSelect: @escaping (URL) -> Void) {
        self.searchIndex = searchIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { result in
                        Button {
                            onSelect(result.noteURL)
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, isPresented: .constant(true), prompt: "Search all notes")
            .onChange(of: query) { _, newQuery in
                performSearch(newQuery)
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.title)
                    .font(.callout.bold())
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
                        Text("#\(tag)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
