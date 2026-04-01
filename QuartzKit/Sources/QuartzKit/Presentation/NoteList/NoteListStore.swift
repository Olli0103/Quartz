import SwiftUI

/// Drives the middle column note list.
///
/// Holds a filtered, sorted array of `NoteListItem` objects derived from the
/// `NotePreviewRepository` cache. Responds to `SourceSelection` changes from
/// the left sidebar, search text, and sort order.
///
/// **Data flow:** `NotePreviewRepository` (actor) → `allPreviews()` → filter → sort → `items`
/// **Reactivity:** Observes `.quartzPreviewCacheDidChange` and `.quartzFavoritesDidChange`
/// to refresh automatically when notes are saved, created, deleted, or favorited.
///
/// Owned by `ContentView` as `@State`, passed through `WorkspaceView` to `NoteListSidebar`.
@Observable
@MainActor
public final class NoteListStore {

    // MARK: - Published State

    /// Filtered, sorted note items for the current source selection.
    public private(set) var items: [NoteListItem] = []

    /// Time-bucketed sections for the list UI.
    /// Returns sections with headers when sorted by date, flat when sorted by title.
    public private(set) var sections: [NoteListSection] = []

    /// Whether the store is loading initial data.
    public private(set) var isLoading: Bool = true

    /// Search text for filtering within the current source.
    /// Debounced at 150ms to prevent excessive filtering during rapid typing.
    public var searchText: String = "" {
        didSet { scheduleSearchDebounce() }
    }

    /// Debounce task for search text changes.
    nonisolated(unsafe) private var searchDebounceTask: Task<Void, Never>?
    private static let searchDebounceDelay: Duration = .milliseconds(150)

    /// Current sort order. Persisted in UserDefaults.
    public var sortOrder: NoteListSortOrder {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
            rebuildItems()
        }
    }

    // MARK: - Internal State

    /// Current source selection driving the filter.
    private var currentSource: SourceSelection = .allNotes

    /// All previews from the repository (unfiltered snapshot).
    private var allItems: [NoteListItem] = []

    /// Repository reference for data loading.
    private var repository: NotePreviewRepository?

    /// Vault root for favorites resolution and folder filtering.
    public private(set) var vaultRoot: URL?

    /// Notification observer tokens for cleanup.
    nonisolated(unsafe) private var observerTokens: [Any] = []

    private static let sortOrderKey = "quartz.noteListSortOrder"
    private static let recentLimit = 20

    // MARK: - Init

    public init() {
        let saved = UserDefaults.standard.string(forKey: Self.sortOrderKey)
        self.sortOrder = saved.flatMap(NoteListSortOrder.init(rawValue:)) ?? .dateModifiedNewest
    }

    deinit {
        searchDebounceTask?.cancel()
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Configuration

    /// Wires the repository and vault root. Called once when a vault loads.
    /// Also starts observing change notifications for real-time updates.
    public func configure(repository: NotePreviewRepository, vaultRoot: URL) {
        self.repository = repository
        self.vaultRoot = vaultRoot
        startObserving()
    }

    // MARK: - Notification Observers

    private func startObserving() {
        // Remove previous observers if reconfiguring
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()

        // Preview cache updated (note saved, created, deleted, renamed)
        let cacheToken = NotificationCenter.default.addObserver(
            forName: .quartzPreviewCacheDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedURL = notification.object as? URL
            Task { @MainActor in
                if let url = changedURL {
                    // Targeted update: only refresh the single changed note
                    await self.refreshSingleItem(at: url)
                } else {
                    // Bulk change (delete, rename, reindex): full refresh
                    await self.refresh()
                }
            }
        }
        observerTokens.append(cacheToken)

        // Favorites toggled
        let favToken = NotificationCenter.default.addObserver(
            forName: .quartzFavoritesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        observerTokens.append(favToken)
    }

    // MARK: - Search Debounce

    /// Schedules a debounced search/filter rebuild.
    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounceDelay)
            guard !Task.isCancelled, let self else { return }
            self.rebuildItems()
        }
    }

    // MARK: - Data Loading

    /// Loads all items from the repository and applies the current filter.
    /// Call after `configure()` and after preview indexing completes.
    public func loadItems(for source: SourceSelection) async {
        currentSource = source
        guard let repository, let vaultRoot else {
            items = []
            sections = []
            isLoading = false
            return
        }

        isLoading = true
        let previews = await repository.allPreviews()
        let favoriteKeys = FavoriteNoteStorage.readStoredKeys()

        // Filter to only include notes that are within the current vault root
        let vaultRootPath = vaultRoot.path(percentEncoded: false)
        let filteredPreviews = previews.filter { preview in
            preview.url.path(percentEncoded: false).hasPrefix(vaultRootPath)
        }

        allItems = filteredPreviews.map { preview in
            NoteListItem(
                url: preview.url,
                title: preview.title,
                modifiedAt: preview.modifiedAt,
                fileSize: preview.fileSize,
                snippet: preview.snippet,
                tags: preview.tags,
                isFavorite: FavoriteNoteStorage.isFavorite(
                    fileURL: preview.url,
                    vaultRoot: vaultRoot,
                    storedKeys: favoriteKeys,
                    fileTree: nil
                )
            )
        }

        rebuildItems()
        isLoading = false
    }

    /// Refreshes items from the repository without changing source.
    /// Call after bulk changes (delete, rename, reindex).
    public func refresh() async {
        await loadItems(for: currentSource)
    }

    /// Targeted refresh for a single note URL.
    /// Fetches only the changed preview and updates it in-place, avoiding a full list flicker.
    public func refreshSingleItem(at url: URL) async {
        guard let repository else { return }

        // Fetch the updated preview from the cache
        let allPreviews = await repository.allPreviews()
        let favoriteKeys = FavoriteNoteStorage.readStoredKeys()

        guard let updatedPreview = allPreviews.first(where: { $0.url == url }) else {
            // Note was removed from cache — do a full refresh
            await refresh()
            return
        }

        let updatedItem = NoteListItem(
            url: updatedPreview.url,
            title: updatedPreview.title,
            modifiedAt: updatedPreview.modifiedAt,
            fileSize: updatedPreview.fileSize,
            snippet: updatedPreview.snippet,
            tags: updatedPreview.tags,
            isFavorite: FavoriteNoteStorage.isFavorite(
                fileURL: updatedPreview.url,
                vaultRoot: vaultRoot,
                storedKeys: favoriteKeys,
                fileTree: nil
            )
        )

        // Update in-place in allItems
        if let index = allItems.firstIndex(where: { $0.url == url }) {
            allItems[index] = updatedItem
        } else {
            // New note not in our list yet — add it
            allItems.append(updatedItem)
        }

        rebuildItems()
    }

    /// Updates the source filter and rebuilds the list.
    public func changeSource(to source: SourceSelection) async {
        currentSource = source
        searchText = ""
        rebuildItems()
    }

    // MARK: - Navigation Title

    /// Display title for the navigation bar, derived from current source.
    public var navigationTitle: String {
        switch currentSource {
        case .allNotes: String(localized: "All Notes", bundle: .module)
        case .favorites: String(localized: "Favorites", bundle: .module)
        case .recent: String(localized: "Recent", bundle: .module)
        case .folder(let url): url.lastPathComponent
        case .tag(let tag): "#\(tag)"
        }
    }

    // MARK: - Filter / Sort Pipeline

    /// Runs the full filter → sort → assign → section pipeline.
    private func rebuildItems() {
        var filtered = filterBySource(allItems)
        filtered = filterBySearch(filtered)
        filtered = sort(filtered)

        // For .recent, limit to top N after sorting by date
        if case .recent = currentSource {
            filtered = Array(filtered.prefix(Self.recentLimit))
        }

        // Debug: check for duplicates by URL path (not URL object identity)
        let paths = filtered.map { $0.url.path(percentEncoded: false) }
        let uniquePaths = Set(paths)
        if paths.count != uniquePaths.count {
            print("[NoteListStore] WARNING: \(paths.count - uniquePaths.count) duplicate paths detected in filtered items!")
            let duplicates = Dictionary(grouping: paths, by: { $0 }).filter { $1.count > 1 }
            for (path, occurrences) in duplicates.prefix(5) {
                print("  - \(path) appears \(occurrences.count) times")
            }
        }

        // Also check allItems
        let allPaths = allItems.map { $0.url.path(percentEncoded: false) }
        let uniqueAllPaths = Set(allPaths)
        if allPaths.count != uniqueAllPaths.count {
            print("[NoteListStore] WARNING: \(allPaths.count - uniqueAllPaths.count) duplicate paths in allItems!")
        }

        items = filtered

        // Build sections: time-bucketed for date sorts, flat for title sorts
        let isDateSort = (sortOrder == .dateModifiedNewest || sortOrder == .dateModifiedOldest)
        if isDateSort && !filtered.isEmpty {
            sections = NoteListSection.timeSections(from: filtered)
        } else {
            sections = NoteListSection.flat(from: filtered)
        }
    }

    private func filterBySource(_ items: [NoteListItem]) -> [NoteListItem] {
        switch currentSource {
        case .allNotes:
            return items

        case .favorites:
            return items.filter { $0.isFavorite }

        case .recent:
            // Sort by date (newest first) regardless of sortOrder for the recent view
            return items.sorted { $0.modifiedAt > $1.modifiedAt }

        case .folder(let folderURL):
            let folderPath = folderURL.path(percentEncoded: false)
            return items.filter { item in
                let itemDir = item.url.deletingLastPathComponent().path(percentEncoded: false)
                return itemDir == folderPath
            }

        case .tag(let tag):
            let tagLower = tag.lowercased()
            return items.filter { item in
                item.tags.contains { $0.lowercased() == tagLower }
            }
        }
    }

    private func filterBySearch(_ items: [NoteListItem]) -> [NoteListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }

        return items.filter { item in
            item.title.lowercased().contains(query) ||
            item.snippet.lowercased().contains(query) ||
            item.tags.contains { $0.lowercased().contains(query) }
        }
    }

    private func sort(_ items: [NoteListItem]) -> [NoteListItem] {
        // Recent source has its own sort logic (always newest first)
        if case .recent = currentSource { return items }

        switch sortOrder {
        case .dateModifiedNewest:
            return items.sorted { $0.modifiedAt > $1.modifiedAt }
        case .dateModifiedOldest:
            return items.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAscending:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDescending:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }
}
