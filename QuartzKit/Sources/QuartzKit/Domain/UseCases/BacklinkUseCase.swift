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
        let noteName = noteURL.deletingPathExtension().lastPathComponent
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
        var backlinks: [Backlink] = []

        for node in nodes {
            if node.isNote {
                let note = try await vaultProvider.readNote(at: node.url)
                let links = linkExtractor.extractLinks(from: note.body)

                for link in links where link.target.caseInsensitiveCompare(targetName) == .orderedSame {
                    let context = extractContext(for: link, in: note.body)
                    backlinks.append(Backlink(
                        sourceNoteURL: node.url,
                        sourceNoteName: node.name.replacingOccurrences(of: ".md", with: ""),
                        context: context
                    ))
                }
            }
            if let children = node.children {
                backlinks += try await scanForBacklinks(in: children, targetName: targetName)
            }
        }

        return backlinks
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
