import SwiftUI

/// Spotlight-like full-text search across the entire vault.
/// This is intentionally vault-wide, not an in-note find surface.
/// Glassmorphism design with live results.
public struct SearchView: View {
    static let isVaultWideSearchSheet = true
    static var navigationTitleText: String {
        String(localized: "Search Notes", bundle: .module)
    }
    static var promptText: String {
        String(localized: "Search all notes…", bundle: .module)
    }

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

    @State private var searchTask: Task<Void, Never>?

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
                .overlay {
                    if isSearching && results.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .searchable(text: $query, isPresented: .constant(true), prompt: Text(Self.promptText))
            .onChange(of: query) { _, newQuery in
                performSearch(newQuery)
            }
            .onDisappear { searchTask?.cancel() }
            .navigationTitle(Self.navigationTitleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
        }
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let searchResults = await searchIndex.search(query: query)
            guard !Task.isCancelled else { return }

            results = searchResults
            isSearching = false
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.title)
        .accessibilityHint(String(localized: "Double tap to open note", bundle: .module))
    }
}
