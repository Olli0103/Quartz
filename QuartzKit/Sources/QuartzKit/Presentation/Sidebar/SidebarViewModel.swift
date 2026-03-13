import SwiftUI

/// ViewModel für die Sidebar: lädt den Dateibaum, filtert und sortiert.
@Observable
@MainActor
public final class SidebarViewModel {
    public var fileTree: [FileNode] = []
    public var searchText: String = ""
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let vaultProvider: any VaultProviding
    private var vaultRoot: URL?

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Lädt den Dateibaum für die gegebene Vault-Root-URL.
    public func loadTree(at root: URL) async {
        vaultRoot = root
        isLoading = true
        errorMessage = nil

        do {
            fileTree = try await vaultProvider.loadFileTree(at: root)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Lädt den Dateibaum neu.
    public func refresh() async {
        guard let root = vaultRoot else { return }
        await loadTree(at: root)
    }

    // MARK: - Folder Management

    /// Erstellt einen neuen Ordner.
    public func createFolder(named name: String, in parent: URL) async {
        do {
            _ = try await vaultProvider.createFolder(named: name, in: parent)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Erstellt eine neue Notiz.
    public func createNote(named name: String, in folder: URL) async {
        do {
            _ = try await vaultProvider.createNote(named: name, in: folder)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Benennt ein Element um.
    public func rename(at url: URL, to newName: String) async {
        do {
            _ = try await vaultProvider.rename(at: url, to: newName)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Löscht ein Element.
    public func delete(at url: URL) async {
        do {
            try await vaultProvider.deleteNote(at: url)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Gefilterte Nodes basierend auf Suchtext.
    public var filteredTree: [FileNode] {
        guard !searchText.isEmpty else { return fileTree }
        return fileTree.compactMap { filterNode($0, matching: searchText) }
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
}
