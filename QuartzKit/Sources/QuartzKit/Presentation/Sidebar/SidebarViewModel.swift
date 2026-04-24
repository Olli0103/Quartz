import SwiftUI

public extension Notification.Name {
    static let quartzFavoritesDidChange = Notification.Name("quartzFavoritesDidChange")
    static let quartzReindexRequested = Notification.Name("quartzReindexRequested")
    /// Posted with `object` set to the saved note’s file `URL` (Core Spotlight incremental index).
    static let quartzNoteSaved = Notification.Name("quartzNoteSaved")
    /// Posted when editor save health changes. `userInfo["state"]` is `failed` or `recovered`.
    static let quartzEditorSaveHealthChanged = Notification.Name("quartzEditorSaveHealthChanged")
    /// Posted after explicit wiki-link graph connections are updated.
    /// `object` is the canonical source note URL and `userInfo["targetURLs"]` contains canonical target URLs.
    static let quartzReferenceGraphDidChange = Notification.Name("quartzReferenceGraphDidChange")
    /// `userInfo["urls"]` is `[URL]` of markdown files removed from disk (Spotlight deletion).
    static let quartzSpotlightNotesRemoved = Notification.Name("quartzSpotlightNotesRemoved")
    /// `userInfo["old"]` and `["new"]` are file `URL`s after rename or move.
    static let quartzSpotlightNoteRelocated = Notification.Name("quartzSpotlightNoteRelocated")
    /// Posted after a note is renamed. `userInfo["oldURL"]` and `userInfo["newURL"]` contain the file URLs.
    static let quartzNoteRenamed = Notification.Name("quartzNoteRenamed")
    /// Posted when the preview cache changes (note save, reindex).
    static let quartzPreviewCacheDidChange = Notification.Name("quartzPreviewCacheDidChange")
    /// Posted when another device syncs a vault path via iCloud KVStore.
    static let quartzRemoteVaultDetected = Notification.Name("quartzRemoteVaultDetected")
}

public enum SidebarFilter: String, CaseIterable, Sendable {
    case all
    case favorites
    case recent
}

/// Sort order for sidebar folder contents.
public enum SidebarSortOrder: String, CaseIterable, Sendable {
    case nameAscending = "name"
    case dateModifiedNewest = "modified"
    case dateCreatedNewest = "created"

    public var label: String {
        switch self {
        case .nameAscending: String(localized: "Name (A–Z)", bundle: .module)
        case .dateModifiedNewest: String(localized: "Date modified (newest)", bundle: .module)
        case .dateCreatedNewest: String(localized: "Date created (newest)", bundle: .module)
        }
    }
}

/// ViewModel for the sidebar: loads the file tree, filters, and sorts. The column shell is a `List` in `SidebarView`.
@Observable
@MainActor
public final class SidebarViewModel {
    public var fileTree: [FileNode] = [] {
        didSet {
            invalidateFilterCache()
            invalidateTagCache()
            onFileTreeDidChange?(fileTree)
        }
    }
    public var searchText: String = "" {
        didSet { invalidateFilterCache() }
    }
    public var selectedTag: String? {
        didSet { invalidateFilterCache() }
    }
    public var activeFilter: SidebarFilter = .all {
        didSet { invalidateFilterCache() }
    }
    public private(set) var tagInfos: [TagInfo] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    /// Items in the vault's Recently Deleted (.quartzTrash) folder.
    public var trashedItems: [FileNode] = []

    private let trashService = VaultTrashService()
    /// Mirror of ContentViewModel's indexing progress. Set ONLY by ContentViewModel — do not mutate independently.
    public var indexingProgress: (current: Int, total: Int)?
    /// Mirror of ContentViewModel's cloud sync status. Set ONLY by ContentViewModel — do not mutate independently.
    public var cloudSyncStatus: CloudSyncStatus = .notApplicable

    /// Returns `true` if any note in the vault has an unresolved iCloud sync conflict.
    public var hasAnyConflicts: Bool {
        hasConflictsIn(fileTree)
    }

    /// Returns all notes with unresolved iCloud sync conflicts.
    public var conflictingNotes: [FileNode] {
        collectFlatNotes(from: fileTree).filter { $0.metadata.hasConflict }
    }

    private func hasConflictsIn(_ nodes: [FileNode]) -> Bool {
        for node in nodes {
            if node.metadata.hasConflict { return true }
            if let children = node.children, hasConflictsIn(children) { return true }
        }
        return false
    }

    private static let sortOrderKey = "quartz.sidebarSortOrder"
    private var cachedSortOrder: SidebarSortOrder?

    public var sortOrder: SidebarSortOrder {
        get {
            if let cached = cachedSortOrder { return cached }
            guard let raw = UserDefaults.standard.string(forKey: Self.sortOrderKey),
                  let order = SidebarSortOrder(rawValue: raw) else {
                cachedSortOrder = .nameAscending
                return .nameAscending
            }
            cachedSortOrder = order
            return order
        }
        set {
            cachedSortOrder = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.sortOrderKey)
            invalidateFilterCache()
        }
    }

    private let vaultProvider: any VaultProviding
    private var vaultRoot: URL?
    private var cachedFilteredTree: [FileNode]?
    private var cachedFlatNotes: [FileNode]?
    private var _favoriteURLs: Set<String>?
    private var tagCacheValid: Bool = false

    /// Hook for consumers that need immediate access to the authoritative catalog
    /// after sidebar file mutations. KG3 uses this to keep relationship resolution
    /// aligned without depending on view-layer `.onChange` fan-out.
    public var onFileTreeDidChange: (([FileNode]) -> Void)?

    /// Public access to the vault root URL.
    public var vaultRootURL: URL? { vaultRoot }

    // MARK: - Favorites

    public var favoriteURLs: Set<String> {
        if let cached = _favoriteURLs { return cached }
        let set = FavoriteNoteStorage.readStoredKeys()
        _favoriteURLs = set
        return set
    }

    public func isFavorite(_ url: URL) -> Bool {
        FavoriteNoteStorage.isFavorite(
            fileURL: url,
            vaultRoot: vaultRoot,
            storedKeys: favoriteURLs,
            fileTree: fileTree
        )
    }

    public func toggleFavorite(_ url: URL) {
        _ = FavoriteNoteStorage.toggleFavorite(fileURL: url, vaultRoot: vaultRoot, fileTree: fileTree)
        _favoriteURLs = nil
        invalidateFilterCache()
    }

    /// Stored notification tokens removed during teardown.
    /// Swift 6 runs `deinit` nonisolated, and removing NotificationCenter observers is
    /// safe there without forcing a MainActor precondition.
    nonisolated(unsafe) private var favoritesObserver: Any?
    nonisolated(unsafe) private var renameObserver: Any?

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
        favoritesObserver = NotificationCenter.default.addObserver(
            forName: .quartzFavoritesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.invalidateFavorites()
            }
        }

        renameObserver = NotificationCenter.default.addObserver(
            forName: .quartzNoteRenamed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    deinit {
        if let observer = favoritesObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = renameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func invalidateFavorites() {
        _favoriteURLs = nil
        invalidateFilterCache()
    }

    /// Loads the file tree for the given vault root URL.
    public func loadTree(at root: URL) async {
        vaultRoot = root
        isLoading = true
        errorMessage = nil

        do {
            fileTree = try await vaultProvider.loadFileTree(at: root)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }

        refreshTrash()
        isLoading = false
    }

    /// Reloads the file tree.
    public func refresh() async {
        guard let root = vaultRoot else { return }
        await loadTree(at: root)
    }

    // MARK: - Folder Management

    /// Creates a new folder.
    public func createFolder(named name: String, in parent: URL) async {
        do {
            _ = try await vaultProvider.createFolder(named: name, in: parent)
            await refresh()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Creates a new note and returns its URL. Inserts the node locally for instant feedback.
    @discardableResult
    public func createNote(named name: String, in folder: URL) async -> URL? {
        do {
            let note = try await vaultProvider.createNote(named: name, in: folder)
            // Insert the new node locally for instant feedback (avoid full refresh)
            insertNoteNode(for: note, in: folder)
            return note.fileURL
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    /// Creates a new note with initial content (e.g. from voice transcription). Returns the note URL.
    public func createNote(named name: String, in folder: URL, initialContent: String) async -> URL? {
        do {
            let note = try await vaultProvider.createNote(named: name, in: folder, initialContent: initialContent)
            // Insert the new node locally for instant feedback
            insertNoteNode(for: note, in: folder)
            return note.fileURL
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    /// Creates a new note from a template.
    @discardableResult
    public func createNoteFromTemplate(_ template: NoteTemplate, named name: String, in folder: URL) async -> URL? {
        do {
            let templateService = VaultTemplateService()
            let fileURL = try await templateService.createFromTemplate(template, named: name, in: folder)
            // Insert the new node locally for instant feedback
            insertNoteNode(at: fileURL, in: folder)
            return fileURL
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    /// Inserts a newly created note into the file tree without a full refresh.
    private func insertNoteNode(for note: NoteDocument, in folder: URL) {
        let newNode = FileNode(
            name: note.fileURL.lastPathComponent,
            url: note.fileURL,
            nodeType: .note,
            children: nil,
            metadata: FileMetadata(
                createdAt: note.frontmatter.createdAt,
                modifiedAt: note.frontmatter.modifiedAt,
                fileSize: 0,
                isEncrypted: note.frontmatter.isEncrypted,
                cloudStatus: .local
            ),
            frontmatter: note.frontmatter
        )
        insertNodeIntoTree(newNode, parentURL: folder)
    }

    /// Inserts a newly created note (by URL) into the file tree without a full refresh.
    private func insertNoteNode(at url: URL, in folder: URL) {
        let newNode = FileNode(
            name: url.lastPathComponent,
            url: url,
            nodeType: .note,
            children: nil,
            metadata: FileMetadata(
                createdAt: .now,
                modifiedAt: .now,
                fileSize: 0,
                isEncrypted: false,
                cloudStatus: .local
            ),
            frontmatter: nil
        )
        insertNodeIntoTree(newNode, parentURL: folder)
    }

    /// Common tree insertion logic.
    private func insertNodeIntoTree(_ node: FileNode, parentURL: URL) {
        // Find and update the parent folder in the tree
        fileTree = insertNode(node, into: fileTree, parentURL: parentURL)
        invalidateFilterCache()
    }

    /// Recursively inserts a node into the appropriate parent folder.
    private func insertNode(_ node: FileNode, into tree: [FileNode], parentURL: URL) -> [FileNode] {
        var result = tree
        let standardizedParent = parentURL.standardizedFileURL

        for i in result.indices {
            if result[i].url.standardizedFileURL == standardizedParent && result[i].isFolder {
                // Found the parent folder - insert the new node
                var children = result[i].children ?? []
                children.append(node)
                // Sort children: folders first, then alphabetically
                children.sort { lhs, rhs in
                    if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                result[i].children = children
                return result
            } else if let children = result[i].children {
                // Recurse into subfolders
                result[i].children = insertNode(node, into: children, parentURL: parentURL)
            }
        }

        // If parentURL is the vault root, insert at top level
        if let root = vaultRoot, standardizedParent == root.standardizedFileURL {
            result.append(node)
            result.sort { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        return result
    }

    /// Renames an item.
    public func rename(at url: URL, to newName: String) async {
        do {
            let proposedName: String
            if url.pathExtension.lowercased() == "md" {
                proposedName = newName.hasSuffix(".md") ? newName : "\(newName).md"
            } else {
                proposedName = newName
            }
            let relocatedNotes = relocatedMarkdownFileURLs(
                from: url,
                to: url.deletingLastPathComponent().appending(path: proposedName)
            )
            let newURL = try await vaultProvider.rename(at: url, to: newName)
            await refresh()
            if newURL != url {
                for relocation in relocatedNotesResolved(from: relocatedNotes, newRootURL: newURL, oldRootURL: url) {
                    await DomainEventBus.shared.publish(.noteRelocated(from: relocation.oldURL, to: relocation.newURL))
                }
                NotificationCenter.default.post(
                    name: .quartzSpotlightNoteRelocated,
                    object: nil,
                    userInfo: ["old": url, "new": newURL]
                )
                NotificationCenter.default.post(
                    name: .quartzNoteRenamed,
                    object: nil,
                    userInfo: ["oldURL": url, "newURL": newURL]
                )
            }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Moves an item to a new parent folder.
    /// - Returns: `true` if the move succeeded, `false` if it failed.
    @discardableResult
    public func move(at sourceURL: URL, to destinationFolder: URL) async -> Bool {
        print("[SidebarViewModel] move called: \(sourceURL.lastPathComponent) -> \(destinationFolder.lastPathComponent)")
        do {
            let relocatedNotes = relocatedMarkdownFileURLs(
                from: sourceURL,
                to: destinationFolder.appending(path: sourceURL.lastPathComponent, directoryHint: sourceURL.hasDirectoryPath ? .isDirectory : .notDirectory)
            )
            let folderUseCase = FolderManagementUseCase(vaultProvider: vaultProvider)
            let newURL = try await folderUseCase.move(at: sourceURL, to: destinationFolder)
            print("[SidebarViewModel] move succeeded: \(newURL.path)")
            await refresh()
            if newURL != sourceURL {
                for relocation in relocatedNotesResolved(from: relocatedNotes, newRootURL: newURL, oldRootURL: sourceURL) {
                    await DomainEventBus.shared.publish(.noteRelocated(from: relocation.oldURL, to: relocation.newURL))
                }
                NotificationCenter.default.post(
                    name: .quartzSpotlightNoteRelocated,
                    object: nil,
                    userInfo: ["old": sourceURL, "new": newURL]
                )
            }
            return true
        } catch {
            print("[SidebarViewModel] move failed: \(error)")
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    /// Deletes an item.
    public func delete(at url: URL) async {
        do {
            let removed = markdownFileURLsUnder(url)
            try await vaultProvider.deleteNote(at: url)
            await refresh()
            refreshTrash()
            if !removed.isEmpty {
                for removedURL in removed {
                    await DomainEventBus.shared.publish(.noteDeleted(url: removedURL))
                }
                NotificationCenter.default.post(
                    name: .quartzSpotlightNotesRemoved,
                    object: nil,
                    userInfo: ["urls": removed]
                )
            }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    // MARK: - Recently Deleted

    /// Refreshes the list of trashed items from the .quartzTrash folder.
    public func refreshTrash() {
        guard let root = vaultRootURL else {
            trashedItems = []
            return
        }
        trashedItems = trashService.trashedItems(in: root)
    }

    /// Restores a trashed note back to the vault root.
    public func restoreFromTrash(at url: URL) async {
        guard let root = vaultRootURL else { return }
        do {
            _ = try trashService.restoreItem(url, to: root)
            refreshTrash()
            await refresh()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Permanently deletes a single trashed note.
    public func permanentlyDelete(at url: URL) async {
        do {
            try trashService.permanentlyDelete(url)
            refreshTrash()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Permanently deletes all items in the trash.
    public func emptyTrash() async {
        guard let root = vaultRootURL else { return }
        do {
            try trashService.emptyTrash(in: root)
            refreshTrash()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Checks if a URL is inside the vault's trash folder.
    public func isInTrash(_ url: URL) -> Bool {
        guard let root = vaultRootURL else { return false }
        return trashService.isInTrash(url, vaultRoot: root)
    }

    /// Markdown files affected by deleting `url` (single note or folder), before the delete runs.
    private func markdownFileURLsUnder(_ url: URL) -> [URL] {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        if let node = Self.findNode(at: canonicalURL, in: fileTree) {
            return Self.collectMarkdownNoteURLs(in: node)
        }
        return Self.markdownFileURLsOnDisk(under: canonicalURL)
    }

    private func relocatedMarkdownFileURLs(from oldRootURL: URL, to proposedNewRootURL: URL) -> [(oldURL: URL, newURL: URL)] {
        let canonicalOldRootURL = CanonicalNoteIdentity.canonicalFileURL(for: oldRootURL)
        let canonicalNewRootURL = CanonicalNoteIdentity.canonicalFileURL(for: proposedNewRootURL)
        let oldNoteURLs = markdownFileURLsUnder(canonicalOldRootURL)

        return oldNoteURLs.map { oldNoteURL in
            let canonicalOldNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: oldNoteURL)
            if canonicalOldNoteURL == canonicalOldRootURL {
                return (oldURL: canonicalOldNoteURL, newURL: canonicalNewRootURL)
            }

            let oldRootPath = canonicalOldRootURL.path(percentEncoded: false)
            let oldNotePath = canonicalOldNoteURL.path(percentEncoded: false)
            let relativePath: String
            if oldNotePath.hasPrefix(oldRootPath + "/") {
                relativePath = String(oldNotePath.dropFirst(oldRootPath.count + 1))
            } else {
                relativePath = canonicalOldNoteURL.lastPathComponent
            }

            return (
                oldURL: canonicalOldNoteURL,
                newURL: CanonicalNoteIdentity.canonicalFileURL(
                    for: canonicalNewRootURL.appending(path: relativePath)
                )
            )
        }
    }

    private func relocatedNotesResolved(
        from proposedRelocations: [(oldURL: URL, newURL: URL)],
        newRootURL: URL,
        oldRootURL: URL
    ) -> [(oldURL: URL, newURL: URL)] {
        let canonicalOldRootURL = CanonicalNoteIdentity.canonicalFileURL(for: oldRootURL)
        let canonicalNewRootURL = CanonicalNoteIdentity.canonicalFileURL(for: newRootURL)

        return proposedRelocations.map { relocation in
            guard relocation.oldURL != canonicalOldRootURL else {
                return (
                    oldURL: CanonicalNoteIdentity.canonicalFileURL(for: relocation.oldURL),
                    newURL: canonicalNewRootURL
                )
            }

            let oldRootPath = canonicalOldRootURL.path(percentEncoded: false)
            let oldNotePath = CanonicalNoteIdentity.canonicalFileURL(for: relocation.oldURL).path(percentEncoded: false)
            let relativePath: String
            if oldNotePath.hasPrefix(oldRootPath + "/") {
                relativePath = String(oldNotePath.dropFirst(oldRootPath.count + 1))
            } else {
                relativePath = relocation.oldURL.lastPathComponent
            }

            return (
                oldURL: CanonicalNoteIdentity.canonicalFileURL(for: relocation.oldURL),
                newURL: CanonicalNoteIdentity.canonicalFileURL(for: canonicalNewRootURL.appending(path: relativePath))
            )
        }
    }

    private static func findNode(at url: URL, in nodes: [FileNode]) -> FileNode? {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        for node in nodes {
            if CanonicalNoteIdentity.canonicalFileURL(for: node.url) == canonicalURL {
                return node
            }
            if let children = node.children,
               let match = findNode(at: canonicalURL, in: children) {
                return match
            }
        }
        return nil
    }

    private static func collectMarkdownNoteURLs(in node: FileNode) -> [URL] {
        if node.isNote {
            return node.url.pathExtension.lowercased() == "md" ? [CanonicalNoteIdentity.canonicalFileURL(for: node.url)] : []
        }

        return (node.children ?? []).flatMap { child in
            collectMarkdownNoteURLs(in: child)
        }
    }

    private static func markdownFileURLsOnDisk(under url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else {
            return []
        }
        if !isDir.boolValue {
            return url.pathExtension.lowercased() == "md" ? [CanonicalNoteIdentity.canonicalFileURL(for: url)] : []
        }
        var urls: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "md" {
                    urls.append(CanonicalNoteIdentity.canonicalFileURL(for: fileURL))
                }
            }
        }
        return urls
    }

    /// Collects tags from the file tree. Uses caching to avoid redundant traversals.
    public func collectTags() {
        guard !tagCacheValid else { return }

        var tagCounts: [String: Int] = [:]
        collectTagsFromNodes(fileTree, into: &tagCounts)
        tagInfos = tagCounts
            .map { TagInfo(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        tagCacheValid = true
    }

    /// Invalidates the tag cache, forcing recollection on next access.
    private func invalidateTagCache() {
        tagCacheValid = false
        tagInfos = []
    }

    private func collectTagsFromNodes(_ nodes: [FileNode], into counts: inout [String: Int]) {
        for node in nodes {
            if let tags = node.frontmatter?.tags {
                for tag in tags {
                    counts[tag, default: 0] += 1
                }
            }
            if let children = node.children {
                collectTagsFromNodes(children, into: &counts)
            }
        }
    }

    /// Filtered nodes based on search text, selected tag, and active filter.
    public var filteredTree: [FileNode] {
        if let cached = cachedFilteredTree {
            return cached
        }

        var result = fileTree

        if let tag = selectedTag {
            result = result.compactMap { filterByTag($0, tag: tag) }
        }

        if !searchText.isEmpty {
            result = result.compactMap { filterNode($0, matching: searchText) }
        }

        switch activeFilter {
        case .all:
            break
        case .favorites:
            let favs = favoriteURLs
            result = result.compactMap { filterByFavorite($0, favorites: favs) }
        case .recent:
            let allNotes = collectFlatNotes(from: result)
            let recent = allNotes
                .sorted { $0.metadata.modifiedAt > $1.metadata.modifiedAt }
                .prefix(20)
            result = Array(recent)
        }

        result = sortNodes(result, by: sortOrder)
        cachedFilteredTree = result
        return result
    }

    private func sortNodes(_ nodes: [FileNode], by order: SidebarSortOrder) -> [FileNode] {
        let sorted = nodes.map { node in
            guard var children = node.children else { return node }
            children = sortNodes(children, by: order)
            var copy = node
            copy.children = children
            return copy
        }
        return sorted.sorted { a, b in
            // Folders first, then sort by selected order
            if a.isFolder != b.isFolder { return a.isFolder }
            switch order {
            case .nameAscending:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dateModifiedNewest:
                return a.metadata.modifiedAt > b.metadata.modifiedAt
            case .dateCreatedNewest:
                return a.metadata.createdAt > b.metadata.createdAt
            }
        }
    }

    private func filterByFavorite(_ node: FileNode, favorites: Set<String>) -> FileNode? {
        if node.isNote {
            guard let root = vaultRoot else { return nil }
            return FavoriteNoteStorage.isFavorite(
                fileURL: node.url,
                vaultRoot: root,
                storedKeys: favorites,
                fileTree: fileTree
            ) ? node : nil
        }
        if node.isFolder, let children = node.children {
            let filtered = children.compactMap { filterByFavorite($0, favorites: favorites) }
            if !filtered.isEmpty {
                var copy = node
                copy.children = filtered
                return copy
            }
        }
        return nil
    }

    /// Flattened list of all note nodes from the filtered tree (cached).
    public var flatNotes: [FileNode] {
        if let cached = cachedFlatNotes { return cached }
        let result = collectFlatNotes(from: filteredTree)
        cachedFlatNotes = result
        return result
    }

    /// Recent notes sorted by modification date (from full tree, not filtered).
    public func recentNotes(limit: Int = 10) -> [FileNode] {
        let all = collectFlatNotes(from: fileTree)
        return Array(all.sorted { $0.metadata.modifiedAt > $1.metadata.modifiedAt }.prefix(limit))
    }

    private func collectFlatNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote { result.append(node) }
            if let children = node.children {
                result.append(contentsOf: collectFlatNotes(from: children))
            }
        }
        return result
    }

    private func invalidateFilterCache() {
        cachedFilteredTree = nil
        cachedFlatNotes = nil
    }

    private func filterNode(_ node: FileNode, matching query: String) -> FileNode? {
        let nameMatches = node.name.localizedCaseInsensitiveContains(query)

        if node.isFolder, let children = node.children {
            let filteredChildren = children.compactMap { filterNode($0, matching: query) }
            if nameMatches || !filteredChildren.isEmpty {
                var filtered = node
                filtered.children = filteredChildren
                return filtered
            }
            return nil
        }

        return nameMatches ? node : nil
    }

    private func filterByTag(_ node: FileNode, tag: String) -> FileNode? {
        let hasTag = node.frontmatter?.tags.contains(tag) ?? false

        if node.isFolder, let children = node.children {
            let filtered = children.compactMap { filterByTag($0, tag: tag) }
            if !filtered.isEmpty {
                var copy = node
                copy.children = filtered
                return copy
            }
            return nil
        }

        return hasTag ? node : nil
    }

    private func userFacingMessage(for error: Error) -> String {
        if let fsError = error as? FileSystemError {
            return fsError.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }
}
