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

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Lädt den Dateibaum für die gegebene Vault-Root-URL.
    public func loadTree(at root: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            fileTree = try await vaultProvider.loadFileTree(at: root)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
