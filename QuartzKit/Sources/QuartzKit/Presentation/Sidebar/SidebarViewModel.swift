import SwiftUI

/// ViewModel for the sidebar: loads the file tree, filters, and sorts.
@Observable
@MainActor
public final class SidebarViewModel {
    public var fileTree: [FileNode] = [] {
        didSet { invalidateFilterCache() }
    }
    public var searchText: String = "" {
        didSet { invalidateFilterCache() }
    }
    public var selectedTag: String? {
        didSet { invalidateFilterCache() }
    }
    public var tagInfos: [TagInfo] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let vaultProvider: any VaultProviding
    private var vaultRoot: URL?
    private var cachedFilteredTree: [FileNode]?
    private var cachedFlatNotes: [FileNode]?

    /// Public access to the vault root URL.
    public var vaultRootURL: URL? { vaultRoot }

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
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

    /// Creates a new note.
    public func createNote(named name: String, in folder: URL) async {
        do {
            _ = try await vaultProvider.createNote(named: name, in: folder)
            await refresh()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Renames an item.
    public func rename(at url: URL, to newName: String) async {
        do {
            _ = try await vaultProvider.rename(at: url, to: newName)
            await refresh()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Deletes an item.
    public func delete(at url: URL) async {
        do {
            try await vaultProvider.deleteNote(at: url)
            await refresh()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    /// Collects tags from the file tree.
    public func collectTags() {
        var tagCounts: [String: Int] = [:]
        collectTagsFromNodes(fileTree, into: &tagCounts)
        tagInfos = tagCounts
            .map { TagInfo(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
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

    /// Filtered nodes based on search text and selected tag.
    /// Result is cached until fileTree, searchText, or selectedTag change.
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

        cachedFilteredTree = result
        return result
    }

    /// Flattened list of all note nodes from the filtered tree (cached).
    public var flatNotes: [FileNode] {
        if let cached = cachedFlatNotes { return cached }
        let result = collectFlatNotes(from: filteredTree)
        cachedFlatNotes = result
        return result
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
            return fsError.errorDescription ?? String(localized: "An unexpected error occurred.", bundle: .module)
        }
        return String(localized: "An unexpected error occurred. Please try again.", bundle: .module)
    }
}
