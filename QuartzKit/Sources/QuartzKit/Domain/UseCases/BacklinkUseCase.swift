import Foundation

/// Use case: Finds all backlinks to a note.
///
/// Scans all notes in the vault for explicit wiki-links that point to the given note,
/// then overlays any newer in-memory explicit references from the live graph store.
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

        let scannedReferences = try await scanForBacklinkReferences(
            in: noteNodes,
            targetNoteURL: canonicalTargetNoteURL,
            catalog: catalog
        )
        let liveReferences = await liveBacklinkReferences(targetNoteURL: canonicalTargetNoteURL)

        let nodesByURL = Dictionary(uniqueKeysWithValues: noteNodes.map {
            (CanonicalNoteIdentity.canonicalFileURL(for: $0.url), $0)
        })

        var mergedBySource: [URL: ExplicitNoteReference] = [:]
        for reference in scannedReferences + liveReferences {
            let sourceURL = reference.sourceNoteURL
            if let existing = mergedBySource[sourceURL],
               explicitReferenceStrength(existing) >= explicitReferenceStrength(reference) {
                continue
            }
            mergedBySource[sourceURL] = reference
        }

        let backlinks = mergedBySource.values.compactMap { reference -> Backlink? in
            let sourceURL = reference.sourceNoteURL
            let sourceNoteName = nodesByURL[sourceURL]?.name.replacingOccurrences(of: ".md", with: "")
                ?? catalog.noteReference(for: sourceURL)?.noteName
                ?? sourceURL.deletingPathExtension().lastPathComponent
            return Backlink(reference: reference, sourceNoteName: sourceNoteName)
        }

        return backlinks.sorted { $0.sourceNoteName < $1.sourceNoteName }
    }

    /// Maximum concurrent file reads to avoid exceeding file descriptor limits.
    private static let maxConcurrentReads = 20

    private func scanForBacklinkReferences(
        in noteNodes: [FileNode],
        targetNoteURL: URL,
        catalog: NoteReferenceCatalog
    ) async throws -> [ExplicitNoteReference] {
        return try await withThrowingTaskGroup(of: [ExplicitNoteReference].self) { group in
            var submitted = 0
            var all: [ExplicitNoteReference] = []

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
                        sourceNoteURL: node.url,
                        graphEdgeStore: self.graphEdgeStore,
                        using: self.linkExtractor
                    )
                    return links.filter { $0.targetNoteURL == targetNoteURL }
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

    private func liveBacklinkReferences(
        targetNoteURL: URL
    ) async -> [ExplicitNoteReference] {
        guard let graphEdgeStore else { return [] }
        let liveReferences = await graphEdgeStore.explicitBacklinks(to: targetNoteURL)
        return liveReferences
    }

    private func explicitReferenceStrength(_ reference: ExplicitNoteReference) -> Int {
        var score = 0
        if reference.matchRange != nil { score += 2 }
        if !reference.context.isEmpty { score += 1 }
        if !reference.displayText.isEmpty { score += 1 }
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
    public let headingFragment: String?
    public var id: String { "\(sourceNoteURL.absoluteString)#\(referenceRange?.location ?? -1)" }

    public init(
        sourceNoteURL: URL,
        sourceNoteName: String,
        context: String,
        referenceDisplayText: String = "",
        referenceRange: NSRange? = nil,
        headingFragment: String? = nil
    ) {
        self.sourceNoteURL = sourceNoteURL
        self.sourceNoteName = sourceNoteName
        self.context = context
        self.referenceDisplayText = referenceDisplayText
        self.referenceRange = referenceRange
        self.headingFragment = headingFragment
    }

    public init(reference: ExplicitNoteReference, sourceNoteName: String) {
        self.init(
            sourceNoteURL: reference.sourceNoteURL,
            sourceNoteName: sourceNoteName,
            context: reference.context,
            referenceDisplayText: reference.displayText,
            referenceRange: reference.matchRange,
            headingFragment: reference.headingFragment
        )
    }
}
