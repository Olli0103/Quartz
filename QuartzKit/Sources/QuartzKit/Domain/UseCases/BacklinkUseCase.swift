import Foundation

/// Use case: Finds all backlinks to a note.
///
/// Scans all notes in the vault for `[[Note-Name]]` links
/// that point to the given note.
public struct BacklinkUseCase: Sendable {
    private let vaultProvider: any VaultProviding
    private let linkExtractor: WikiLinkExtractor
    private let graphEdgeStore: GraphEdgeStore?

    public init(
        vaultProvider: any VaultProviding,
        linkExtractor: WikiLinkExtractor = WikiLinkExtractor(),
        graphEdgeStore: GraphEdgeStore? = nil
    ) {
        self.vaultProvider = vaultProvider
        self.linkExtractor = linkExtractor
        self.graphEdgeStore = graphEdgeStore
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
        let canonicalTargetNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        let tree = try await vaultProvider.loadFileTree(at: vaultRoot)
        let catalog = NoteReferenceCatalog(allNotes: tree)
        let noteNodes = collectNotes(from: tree)

        let scannedBacklinks = try await scanForBacklinks(
            in: noteNodes,
            targetNoteURL: canonicalTargetNoteURL,
            catalog: catalog
        )
        let graphBacklinks = try await liveGraphBacklinks(
            from: noteNodes,
            targetNoteURL: canonicalTargetNoteURL,
            catalog: catalog
        )

        var mergedBySource: [URL: Backlink] = [:]
        for backlink in scannedBacklinks + graphBacklinks {
            let sourceURL = CanonicalNoteIdentity.canonicalFileURL(for: backlink.sourceNoteURL)
            if let existing = mergedBySource[sourceURL] {
                let existingStrength = backlinkStrength(existing)
                let candidateStrength = backlinkStrength(backlink)
                if existingStrength >= candidateStrength {
                    continue
                }
            }
            mergedBySource[sourceURL] = backlink
        }

        return mergedBySource.values.sorted { $0.sourceNoteName < $1.sourceNoteName }
    }

    /// Maximum concurrent file reads to avoid exceeding file descriptor limits.
    private static let maxConcurrentReads = 20

    private func scanForBacklinks(
        in noteNodes: [FileNode],
        targetNoteURL: URL,
        catalog: NoteReferenceCatalog
    ) async throws -> [Backlink] {
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
                    let links = await catalog.resolvedExplicitReferences(
                        in: note.body,
                        graphEdgeStore: self.graphEdgeStore,
                        using: self.linkExtractor
                    )
                    var backlinks: [Backlink] = []
                    for reference in links where reference.noteURL == targetNoteURL {
                        backlinks.append(
                            Backlink(
                                sourceNoteURL: CanonicalNoteIdentity.canonicalFileURL(for: node.url),
                                sourceNoteName: node.name.replacingOccurrences(of: ".md", with: ""),
                                context: reference.context,
                                referenceDisplayText: reference.displayText,
                                referenceRange: reference.matchRange
                            )
                        )
                    }
                    return backlinks
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

    private func liveGraphBacklinks(
        from noteNodes: [FileNode],
        targetNoteURL: URL,
        catalog: NoteReferenceCatalog
    ) async throws -> [Backlink] {
        guard let graphEdgeStore else { return [] }

        let liveSourceURLs = await graphEdgeStore.backlinks(for: targetNoteURL)
            .map(CanonicalNoteIdentity.canonicalFileURL(for:))
        guard !liveSourceURLs.isEmpty else { return [] }

        let nodesByURL = Dictionary(uniqueKeysWithValues: noteNodes.map {
            (CanonicalNoteIdentity.canonicalFileURL(for: $0.url), $0)
        })

        var backlinks: [Backlink] = []
        for sourceURL in liveSourceURLs {
            guard let node = nodesByURL[sourceURL] else { continue }
            let note = try await vaultProvider.readNote(at: sourceURL)
            let context = await liveBacklinkContext(in: note.body, targetNoteURL: targetNoteURL, catalog: catalog)

            backlinks.append(
                Backlink(
                    sourceNoteURL: sourceURL,
                    sourceNoteName: node.name.replacingOccurrences(of: ".md", with: ""),
                    context: context.context,
                    referenceDisplayText: context.displayText,
                    referenceRange: context.range
                )
            )
        }

        return backlinks
    }

    private func liveBacklinkContext(
        in body: String,
        targetNoteURL: URL,
        catalog: NoteReferenceCatalog
    ) async -> (context: String, displayText: String, range: NSRange?) {
        let references = await catalog.resolvedExplicitReferences(
            in: body,
            graphEdgeStore: graphEdgeStore,
            using: linkExtractor
        )

        if let reference = references.first(where: { $0.noteURL == targetNoteURL }) {
            return (reference.context, reference.displayText, reference.matchRange)
        }

        return ("", "", nil)
    }

    private func backlinkStrength(_ backlink: Backlink) -> Int {
        var score = 0
        if backlink.referenceRange != nil { score += 2 }
        if !backlink.context.isEmpty { score += 1 }
        return score
    }
}

/// A backlink: which note links here, with context.
public struct Backlink: Identifiable, Sendable {
    public let sourceNoteURL: URL
    public let sourceNoteName: String
    public let context: String
    public let referenceDisplayText: String
    public let referenceRange: NSRange?
    public var id: String { "\(sourceNoteURL.absoluteString)#\(referenceRange?.location ?? -1)" }

    public init(
        sourceNoteURL: URL,
        sourceNoteName: String,
        context: String,
        referenceDisplayText: String = "",
        referenceRange: NSRange? = nil
    ) {
        self.sourceNoteURL = sourceNoteURL
        self.sourceNoteName = sourceNoteName
        self.context = context
        self.referenceDisplayText = referenceDisplayText
        self.referenceRange = referenceRange
    }
}
