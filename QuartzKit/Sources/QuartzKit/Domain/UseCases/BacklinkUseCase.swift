import Foundation

/// Use Case: Findet alle Backlinks zu einer Notiz.
///
/// Scannt alle Notizen im Vault nach `[[Note-Name]]` Links
/// die auf die gegebene Notiz verweisen.
public struct BacklinkUseCase: Sendable {
    private let vaultProvider: any VaultProviding
    private let linkExtractor: WikiLinkExtractor

    public init(vaultProvider: any VaultProviding, linkExtractor: WikiLinkExtractor = WikiLinkExtractor()) {
        self.vaultProvider = vaultProvider
        self.linkExtractor = linkExtractor
    }

    /// Findet alle Notizen die auf die gegebene Notiz verlinken.
    ///
    /// - Parameters:
    ///   - noteURL: URL der Ziel-Notiz
    ///   - vaultRoot: Root-URL des Vaults
    /// - Returns: Liste von Backlinks mit Quell-Notiz und Kontext
    public func findBacklinks(
        to noteURL: URL,
        in vaultRoot: URL
    ) async throws -> [Backlink] {
        // Use lowercased name for consistent case-insensitive matching
        let noteName = noteURL.deletingPathExtension().lastPathComponent.lowercased()
        let tree = try await vaultProvider.loadFileTree(at: vaultRoot)

        let backlinks = try await scanForBacklinks(
            in: tree,
            targetName: noteName
        )

        return backlinks.sorted { $0.sourceNoteName < $1.sourceNoteName }
    }

    private func scanForBacklinks(
        in nodes: [FileNode],
        targetName: String
    ) async throws -> [Backlink] {
        let noteNodes = collectNotes(from: nodes)

        return try await withThrowingTaskGroup(of: [Backlink].self) { group in
            for node in noteNodes {
                group.addTask {
                    let note = try await self.vaultProvider.readNote(at: node.url)
                    let links = self.linkExtractor.extractLinks(from: note.body)
                    return links
                        .filter { $0.target.lowercased() == targetName }
                        .map { link in
                            Backlink(
                                sourceNoteURL: node.url,
                                sourceNoteName: node.name.replacingOccurrences(of: ".md", with: ""),
                                context: self.extractContext(for: link, in: note.body)
                            )
                        }
                }
            }
            var all: [Backlink] = []
            for try await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    private func collectNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote { result.append(node) }
            if let children = node.children {
                result.append(contentsOf: collectNotes(from: children))
            }
        }
        return result
    }

    /// Extrahiert den umgebenden Text um einen Link herum.
    private func extractContext(for link: WikiLink, in body: String) -> String {
        let searchTerm = "[[\(link.raw)]]"
        guard let range = body.range(of: searchTerm) else { return "" }

        let lineRange = body.lineRange(for: range)
        return String(body[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Ein Backlink: Welche Notiz verlinkt hierher, mit Kontext.
public struct Backlink: Identifiable, Sendable {
    public let sourceNoteURL: URL
    public let sourceNoteName: String
    public let context: String
    public var id: URL { sourceNoteURL }

    public init(sourceNoteURL: URL, sourceNoteName: String, context: String) {
        self.sourceNoteURL = sourceNoteURL
        self.sourceNoteName = sourceNoteName
        self.context = context
    }
}
