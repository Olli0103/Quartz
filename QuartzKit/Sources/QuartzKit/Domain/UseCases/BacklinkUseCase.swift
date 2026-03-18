import Foundation

/// Use case: Finds all backlinks to a note.
///
/// Scans all notes in the vault for `[[Note-Name]]` links
/// that point to the given note.
public struct BacklinkUseCase: Sendable {
    private let vaultProvider: any VaultProviding
    private let linkExtractor: WikiLinkExtractor

    public init(vaultProvider: any VaultProviding, linkExtractor: WikiLinkExtractor = WikiLinkExtractor()) {
        self.vaultProvider = vaultProvider
        self.linkExtractor = linkExtractor
    }

    /// Finds all notes that link to the given note.
    ///
    /// - Parameters:
    ///   - noteURL: URL of the target note
    ///   - vaultRoot: Root URL of the vault
    /// - Returns: List of backlinks with source note and context
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

    /// Maximum concurrent file reads to avoid exceeding file descriptor limits.
    private static let maxConcurrentReads = 20

    private func scanForBacklinks(
        in nodes: [FileNode],
        targetName: String
    ) async throws -> [Backlink] {
        let noteNodes = collectNotes(from: nodes)

        return try await withThrowingTaskGroup(of: [Backlink].self) { group in
            var submitted = 0
            var all: [Backlink] = []

            for node in noteNodes {
                // Throttle: wait for a result before adding more tasks
                if submitted >= Self.maxConcurrentReads {
                    if let batch = try await group.next() {
                        all.append(contentsOf: batch)
                    }
                    submitted -= 1
                }
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
                submitted += 1
            }
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

    /// Extracts the surrounding text around a link.
    private func extractContext(for link: WikiLink, in body: String) -> String {
        let searchTerm = "[[\(link.raw)]]"
        guard let range = body.range(of: searchTerm) else { return "" }

        let lineRange = body.lineRange(for: range)
        return String(body[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A backlink: which note links here, with context.
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
