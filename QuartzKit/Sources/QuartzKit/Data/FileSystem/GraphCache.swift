import Foundation
import CoreGraphics
import CryptoKit

/// Persisted cache for the knowledge graph. Avoids rebuilding on every open.
///
/// Cache is stored at `{vault}/.quartz/graph-cache.json`.
/// Invalidated when any note's modification date changes.
public struct GraphCache: Sendable {
    static let currentSchemaVersion = 5
    private let cacheURL: URL

    public init(vaultRoot: URL) {
        cacheURL = vaultRoot
            .appending(path: ".quartz")
            .appending(path: "graph-cache.json")
    }

    /// Cached graph data.
    public struct CachedGraph: Codable, Sendable {
        public let schemaVersion: Int
        /// Authoritative explicit note-to-note relationship snapshot written by
        /// the live relationship owner, not by graph view.
        public let explicitRelationshipSnapshot: CachedExplicitRelationshipSnapshot?
        /// Authoritative note-to-note related-note similarity snapshot written by
        /// the live relationship owner, not by graph view.
        public let semanticRelationshipSnapshot: CachedSemanticRelationshipSnapshot?
        /// Graph-view-only snapshot: layout plus non-explicit edges used for
        /// graph rendering. This does not author persisted explicit or semantic truth.
        public let graphViewSnapshot: CachedGraphViewSnapshot?

        public init(
            schemaVersion: Int = 5,
            explicitRelationshipSnapshot: CachedExplicitRelationshipSnapshot? = nil,
            semanticRelationshipSnapshot: CachedSemanticRelationshipSnapshot? = nil,
            graphViewSnapshot: CachedGraphViewSnapshot? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.explicitRelationshipSnapshot = explicitRelationshipSnapshot
            self.semanticRelationshipSnapshot = semanticRelationshipSnapshot
            self.graphViewSnapshot = graphViewSnapshot
        }

        public struct CachedExplicitRelationshipSnapshot: Codable, Sendable {
            public let fingerprint: String
            public let references: [ExplicitNoteReference]

            public init(fingerprint: String, references: [ExplicitNoteReference]) {
                self.fingerprint = fingerprint
                self.references = references
            }
        }

        public struct CachedSemanticRelationshipSnapshot: Codable, Sendable {
            public struct CachedSemanticRelation: Codable, Sendable {
                public let sourceURL: URL
                public let targetURLs: [URL]

                public init(sourceURL: URL, targetURLs: [URL]) {
                    self.sourceURL = sourceURL
                    self.targetURLs = targetURLs
                }
            }

            public let fingerprint: String
            public let relations: [CachedSemanticRelation]

            public init(fingerprint: String, relations: [CachedSemanticRelation]) {
                self.fingerprint = fingerprint
                self.relations = relations
            }
        }

        public struct CachedGraphViewSnapshot: Codable, Sendable {
            public let fingerprint: String
            public let nodes: [CachedNode]
            /// Legacy graph-view-only semantic edge cache kept only for backward compatibility.
            /// KG6 no longer uses graph-view-local relationship edges as graph truth.
            public let semanticEdges: [CachedEdge]
            /// Legacy graph-view-only concept edge cache kept only for backward compatibility.
            /// KG6 no longer uses graph-view-local relationship edges as graph truth.
            public let conceptEdges: [CachedEdge]

            public init(
                fingerprint: String,
                nodes: [CachedNode],
                semanticEdges: [CachedEdge],
                conceptEdges: [CachedEdge]
            ) {
                self.fingerprint = fingerprint
                self.nodes = nodes
                self.semanticEdges = semanticEdges.filter { $0.kind == .semanticSimilarity }
                self.conceptEdges = conceptEdges.filter { $0.kind == .aiConcept }
            }

            private enum CodingKeys: String, CodingKey {
                case fingerprint
                case nodes
                case semanticEdges
                case conceptEdges
                case legacyEdges = "edges"
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                fingerprint = try container.decode(String.self, forKey: .fingerprint)
                nodes = try container.decode([CachedNode].self, forKey: .nodes)

                if container.contains(.semanticEdges) || container.contains(.conceptEdges) {
                    semanticEdges = (try container.decodeIfPresent([CachedEdge].self, forKey: .semanticEdges) ?? [])
                        .filter { $0.kind == .semanticSimilarity }
                    conceptEdges = (try container.decodeIfPresent([CachedEdge].self, forKey: .conceptEdges) ?? [])
                        .filter { $0.kind == .aiConcept }
                    return
                }

                let legacyEdges = try container.decodeIfPresent([CachedEdge].self, forKey: .legacyEdges) ?? []
                semanticEdges = legacyEdges.filter { $0.kind == .semanticSimilarity }
                conceptEdges = legacyEdges.filter { $0.kind == .aiConcept }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(fingerprint, forKey: .fingerprint)
                try container.encode(nodes, forKey: .nodes)
                try container.encode(semanticEdges, forKey: .semanticEdges)
                try container.encode(conceptEdges, forKey: .conceptEdges)
            }
        }

        public struct CachedNode: Codable, Sendable {
            public let id: String
            public let title: String
            public let url: URL
            public let x: CGFloat
            public let y: CGFloat
            public let connectionCount: Int
            public let tags: [String]?
        }

        public struct CachedEdge: Codable, Sendable {
            public let from: String
            public let to: String
            public let kind: EdgeKind

            public init(from: String, to: String, kind: EdgeKind) {
                self.from = from
                self.to = to
                self.kind = kind
            }
        }

        public enum EdgeKind: String, Codable, Sendable {
            case semanticSimilarity
            case aiConcept
        }

        private struct LegacyCachedEdge: Codable, Sendable {
            let from: String
            let to: String
            let isSemantic: Bool
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case explicitRelationshipSnapshot
            case semanticRelationshipSnapshot
            case graphViewSnapshot
            case legacyNodes = "nodes"
            case legacyEdges = "edges"
            case legacyFingerprint = "fingerprint"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let explicitRelationshipSnapshot = try container.decodeIfPresent(
                CachedExplicitRelationshipSnapshot.self,
                forKey: .explicitRelationshipSnapshot
            )
            let semanticRelationshipSnapshot = try container.decodeIfPresent(
                CachedSemanticRelationshipSnapshot.self,
                forKey: .semanticRelationshipSnapshot
            )
            let graphViewSnapshot = try container.decodeIfPresent(
                CachedGraphViewSnapshot.self,
                forKey: .graphViewSnapshot
            )

            if explicitRelationshipSnapshot != nil || semanticRelationshipSnapshot != nil || graphViewSnapshot != nil {
                self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                    ?? GraphCache.currentSchemaVersion
                self.explicitRelationshipSnapshot = explicitRelationshipSnapshot
                self.semanticRelationshipSnapshot = semanticRelationshipSnapshot
                self.graphViewSnapshot = graphViewSnapshot
                return
            }

            let legacyNodes = try container.decodeIfPresent([CachedNode].self, forKey: .legacyNodes) ?? []
            let legacyEdges = try container.decodeIfPresent([LegacyCachedEdge].self, forKey: .legacyEdges) ?? []
            let legacyFingerprint = try container.decodeIfPresent(String.self, forKey: .legacyFingerprint)

            self.schemaVersion = GraphCache.currentSchemaVersion
            self.explicitRelationshipSnapshot = nil
            self.semanticRelationshipSnapshot = nil

            if let legacyFingerprint, !legacyNodes.isEmpty || !legacyEdges.isEmpty {
                self.graphViewSnapshot = CachedGraphViewSnapshot(
                    fingerprint: legacyFingerprint,
                    nodes: legacyNodes,
                    semanticEdges: legacyEdges.compactMap { edge in
                        guard edge.isSemantic else { return nil }
                        return CachedEdge(from: edge.from, to: edge.to, kind: .semanticSimilarity)
                    },
                    conceptEdges: []
                )
            } else {
                self.graphViewSnapshot = nil
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encodeIfPresent(explicitRelationshipSnapshot, forKey: .explicitRelationshipSnapshot)
            try container.encodeIfPresent(semanticRelationshipSnapshot, forKey: .semanticRelationshipSnapshot)
            try container.encodeIfPresent(graphViewSnapshot, forKey: .graphViewSnapshot)
        }
    }

    /// Computes a fingerprint from note URLs and modification dates.
    public func computeFingerprint(for noteURLs: [URL]) -> String {
        let fm = FileManager.default
        var pairs: [(String, TimeInterval)] = []
        for url in noteURLs {
            let mtime: TimeInterval
            if let attrs = try? fm.attributesOfItem(atPath: url.path(percentEncoded: false)),
               let date = attrs[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
            } else {
                mtime = 0
            }
            pairs.append((url.absoluteString, mtime))
        }
        pairs.sort { $0.0 < $1.0 }
        let data = pairs.flatMap { "\($0.0):\($0.1)".utf8 }
        let hash = SHA256.hash(data: Data(data))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func loadDocument() -> CachedGraph? {
        guard FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)) else { return nil }
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CachedGraph.self, from: data)
    }

    /// Loads the authoritative explicit relationship snapshot if its fingerprint matches.
    public func loadExplicitRelationshipSnapshotIfValid(
        fingerprint: String
    ) -> CachedGraph.CachedExplicitRelationshipSnapshot? {
        guard let cached = loadDocument(),
              let snapshot = cached.explicitRelationshipSnapshot,
              snapshot.fingerprint == fingerprint else {
            return nil
        }
        return snapshot
    }

    /// Loads the authoritative related-note similarity snapshot if its fingerprint matches.
    public func loadSemanticRelationshipSnapshotIfValid(
        fingerprint: String
    ) -> CachedGraph.CachedSemanticRelationshipSnapshot? {
        guard let cached = loadDocument(),
              let snapshot = cached.semanticRelationshipSnapshot,
              snapshot.fingerprint == fingerprint else {
            return nil
        }
        return snapshot
    }

    /// Loads the graph-view snapshot if its fingerprint matches.
    public func loadGraphViewSnapshotIfValid(
        fingerprint: String
    ) -> CachedGraph.CachedGraphViewSnapshot? {
        guard let cached = loadDocument(),
              let snapshot = cached.graphViewSnapshot,
              snapshot.fingerprint == fingerprint else {
            return nil
        }
        return snapshot
    }

    /// Saves a merged cache document.
    public func save(_ graph: CachedGraph) throws {
        let dir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(graph)
        try data.write(to: cacheURL, options: .atomic)
    }

    /// Persists the authoritative explicit relationship snapshot while preserving
    /// any separate graph-view snapshot.
    public func saveExplicitRelationshipSnapshot(
        _ snapshot: CachedGraph.CachedExplicitRelationshipSnapshot
    ) throws {
        let existing = loadDocument()
        try save(
            CachedGraph(
                explicitRelationshipSnapshot: snapshot,
                semanticRelationshipSnapshot: existing?.semanticRelationshipSnapshot,
                graphViewSnapshot: existing?.graphViewSnapshot
            )
        )
    }

    /// Persists the authoritative related-note similarity snapshot while preserving
    /// the explicit relationship snapshot and any separate graph-view layout snapshot.
    public func saveSemanticRelationshipSnapshot(
        _ snapshot: CachedGraph.CachedSemanticRelationshipSnapshot
    ) throws {
        let existing = loadDocument()
        try save(
            CachedGraph(
                explicitRelationshipSnapshot: existing?.explicitRelationshipSnapshot,
                semanticRelationshipSnapshot: snapshot,
                graphViewSnapshot: existing?.graphViewSnapshot
            )
        )
    }

    /// Persists the graph-view snapshot while preserving the authoritative explicit
    /// relationship snapshot written by the live relationship owner.
    public func saveGraphViewSnapshot(
        _ snapshot: CachedGraph.CachedGraphViewSnapshot
    ) throws {
        let existing = loadDocument()
        try save(
            CachedGraph(
                explicitRelationshipSnapshot: existing?.explicitRelationshipSnapshot,
                semanticRelationshipSnapshot: existing?.semanticRelationshipSnapshot,
                graphViewSnapshot: snapshot
            )
        )
    }
}

// MARK: - Live Graph Edge Store

/// In-memory store of wiki-link connections between notes.
/// Used by the knowledge graph to draw edges and by the editor to resolve wiki-link navigation.
///
/// Call `updateConnections(for:linkedTitles:allVaultURLs:)` after parsing a note
/// to keep the edge map current.
///
/// Uses `GraphIdentityResolver` for robust wiki-link resolution when available,
/// falling back to simple title matching for backwards compatibility.
public actor GraphEdgeStore {
    /// Maps a canonical source note URL to canonical target URLs via `[[wiki-links]]`.
    /// KG1 treats standardized file URLs as the only explicit note-to-note identity.
    public private(set) var edges: [URL: [URL]] = [:]

    /// Canonical explicit reference payloads keyed by canonical source note URL.
    /// KG2 keeps live explicit graph state on the same interpreted wiki-link payload that
    /// outgoing links, backlinks, and explicit-link exclusion consume.
    public private(set) var explicitReferencesBySource: [URL: [ExplicitNoteReference]] = [:]

    /// Reverse index: maps a target URL to all source URLs that link to it.
    /// Maintained alongside `edges` for O(1) backlink queries.
    /// **Per CODEX.md F5:** Avoids O(n) scan of all edges for backlink lookups.
    private var reverseEdges: [URL: Set<URL>] = [:]

    /// Reverse explicit-reference index keyed by canonical target note URL.
    /// Used for live backlink provenance without reinterpreting wiki-link markdown.
    private var reverseExplicitReferences: [URL: [ExplicitNoteReference]] = [:]

    /// Maps a source note URL to semantically related note URLs.
    /// Discovered by background AI analysis — non-destructive, never alters markdown files.
    public private(set) var semanticEdges: [URL: [URL]] = [:]

    /// Maps a concept string (normalized, lowercase) to the set of note URLs that discuss it.
    /// Populated by `KnowledgeExtractionService`. Used by the Knowledge Graph to render concept hub nodes.
    public private(set) var conceptEdges: [String: Set<URL>] = [:]

    /// Reverse map: note URL → concepts assigned to it. Used by the Inspector.
    public private(set) var noteConcepts: [URL: [String]] = [:]

    /// Reverse lookup: title (lowercased, no extension) → URL.
    /// Used as fallback when no GraphIdentityResolver is configured.
    private var titleIndex: [String: URL] = [:]

    /// Reference to the canonical identity resolver for robust wiki-link resolution.
    /// When set, uses resolver's alias/title/path-qualified resolution.
    /// When nil, falls back to simple title matching.
    private var identityResolver: GraphIdentityResolver?

    public init() {}

    /// Clears all in-memory graph state.
    /// KG3 uses this during relaunch/vault-switch handling so one vault never
    /// leaks explicit, semantic, or concept state into the next.
    public func resetAllState() {
        edges.removeAll(keepingCapacity: true)
        explicitReferencesBySource.removeAll(keepingCapacity: true)
        reverseEdges.removeAll(keepingCapacity: true)
        reverseExplicitReferences.removeAll(keepingCapacity: true)
        semanticEdges.removeAll(keepingCapacity: true)
        conceptEdges.removeAll(keepingCapacity: true)
        noteConcepts.removeAll(keepingCapacity: true)
        titleIndex.removeAll(keepingCapacity: true)
        identityResolver = nil
    }

    /// Builds and installs the canonical explicit-link resolver from the current vault tree.
    /// KG1 keeps explicit relationship resolution on canonical note URLs even before the
    /// broader graph refresh and persistence milestones land.
    public func configureCanonicalResolution(with allNotes: [FileNode]) async {
        let resolver = GraphIdentityResolver()
        for note in collectNotes(from: allNotes) {
            await resolver.register(NoteIdentity(noteNode: note))
        }
        identityResolver = resolver
    }

    /// Configures the identity resolver for robust wiki-link resolution.
    /// Call this after the resolver is populated with note identities.
    public func setIdentityResolver(_ resolver: GraphIdentityResolver) {
        self.identityResolver = resolver
    }

    /// Updates the edge map for a single note.
    ///
    /// - Parameters:
    ///   - sourceURL: The note that contains the wiki-links.
    ///   - linkedTitles: Extracted wiki-link target titles (from `WikiLinkExtractor`).
    ///   - allVaultURLs: All `.md` file URLs in the vault (used to resolve titles to URLs).
    ///
    /// **Per CODEX.md F5:** When `identityResolver` is configured, resolution uses the
    /// robust resolver (aliases, frontmatter titles, paths). The expensive `rebuildTitleIndex`
    /// is ONLY called when falling back to simple title matching.
    public func updateConnections(
        for sourceURL: URL,
        linkedTitles: [String],
        allVaultURLs: [URL]
    ) async {
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)

        // Only rebuild fallback title index if resolver is not configured
        // Per CODEX.md F5: avoids O(n) work on every update when resolver handles resolution
        if identityResolver == nil {
            rebuildTitleIndex(from: allVaultURLs)
        }

        // Resolve each linked title to a canonical explicit reference.
        var references: [ExplicitNoteReference] = []
        for title in linkedTitles {
            if let url = await resolveWikiLink(title), url != canonicalSourceURL {
                let canonicalTargetURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
                references.append(
                    ExplicitNoteReference(
                        sourceNoteURL: canonicalSourceURL,
                        targetNoteURL: canonicalTargetURL,
                        targetNoteName: canonicalTargetURL.deletingPathExtension().lastPathComponent,
                        insertableTarget: canonicalTargetURL.deletingPathExtension().lastPathComponent,
                        rawLinkText: title,
                        rawTargetText: title,
                        displayText: title,
                        headingFragment: nil,
                        matchRange: nil,
                        lineRange: nil,
                        context: ""
                    )
                )
            }
        }

        updateExplicitReferences(for: canonicalSourceURL, references: references)
    }

    /// Resolves a wiki-link title to a note URL, if it exists in the vault.
    /// Uses GraphIdentityResolver for robust matching (aliases, titles, paths),
    /// falling back to simple title matching if resolver not configured.
    public func resolveTitle(_ title: String) async -> URL? {
        await resolveWikiLink(title)
    }

    /// Returns all notes that link TO the given URL (backlinks).
    /// **Per CODEX.md F5:** O(1) lookup via reverse index.
    public func backlinks(for url: URL) -> [URL] {
        Array(reverseEdges[CanonicalNoteIdentity.canonicalFileURL(for: url)] ?? [])
    }

    /// Returns the canonical explicit reference payloads that point to the given target.
    public func explicitBacklinks(to url: URL) -> [ExplicitNoteReference] {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        return reverseExplicitReferences[canonicalURL, default: []].sorted { lhs, rhs in
            if lhs.sourceNoteURL == rhs.sourceNoteURL {
                return (lhs.matchRange?.location ?? Int.max) < (rhs.matchRange?.location ?? Int.max)
            }
            return lhs.sourceNoteURL.absoluteString < rhs.sourceNoteURL.absoluteString
        }
    }

    /// Returns the canonical explicit references published for one source note.
    public func explicitReferences(from sourceURL: URL) -> [ExplicitNoteReference] {
        explicitReferencesBySource[CanonicalNoteIdentity.canonicalFileURL(for: sourceURL), default: []]
    }

    /// Updates the live explicit-reference state for a source note from canonical parsed payloads.
    /// This is the authoritative KG2 entrypoint for explicit edges in production code.
    public func updateExplicitReferences(
        for sourceURL: URL,
        references: [ExplicitNoteReference]
    ) {
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let canonicalReferences = references
            .map {
                ExplicitNoteReference(
                    sourceNoteURL: canonicalSourceURL,
                    targetNoteURL: $0.targetNoteURL,
                    targetNoteName: $0.targetNoteName,
                    insertableTarget: $0.insertableTarget,
                    rawLinkText: $0.rawLinkText,
                    rawTargetText: $0.rawTargetText,
                    displayText: $0.displayText,
                    headingFragment: $0.headingFragment,
                    matchRange: $0.matchRange,
                    lineRange: $0.lineRange,
                    context: $0.context
                )
            }
            .filter { $0.targetNoteURL != canonicalSourceURL }

        if let oldReferences = explicitReferencesBySource[canonicalSourceURL] {
            for targetURL in Set(oldReferences.map(\.targetNoteURL)) {
                reverseExplicitReferences[targetURL]?.removeAll { $0.sourceNoteURL == canonicalSourceURL }
                if reverseExplicitReferences[targetURL]?.isEmpty == true {
                    reverseExplicitReferences.removeValue(forKey: targetURL)
                }
                reverseEdges[targetURL]?.remove(canonicalSourceURL)
                if reverseEdges[targetURL]?.isEmpty == true {
                    reverseEdges.removeValue(forKey: targetURL)
                }
            }
        }

        if canonicalReferences.isEmpty {
            explicitReferencesBySource.removeValue(forKey: canonicalSourceURL)
            edges.removeValue(forKey: canonicalSourceURL)
            return
        }

        explicitReferencesBySource[canonicalSourceURL] = canonicalReferences

        var seenTargets: Set<URL> = []
        var orderedTargets: [URL] = []
        for reference in canonicalReferences {
            reverseExplicitReferences[reference.targetNoteURL, default: []].append(reference)
            reverseEdges[reference.targetNoteURL, default: []].insert(canonicalSourceURL)

            if seenTargets.insert(reference.targetNoteURL).inserted {
                orderedTargets.append(reference.targetNoteURL)
            }
        }

        edges[canonicalSourceURL] = orderedTargets
    }

    /// Loads the authoritative persisted explicit relationship snapshot into the live store.
    /// KG4 keeps persisted explicit relationship ownership aligned with the same runtime owner
    /// used by outgoing links, backlinks, and explicit-link exclusion.
    @discardableResult
    public func loadExplicitRelationshipSnapshot(
        _ snapshot: GraphCache.CachedGraph.CachedExplicitRelationshipSnapshot
    ) -> Set<URL> {
        let grouped = Dictionary(grouping: snapshot.references, by: \.sourceNoteURL)
        return replaceExplicitRelationshipState(with: grouped)
    }

    /// Exports the authoritative explicit relationship snapshot from the live store.
    public func exportExplicitRelationshipSnapshot(
        fingerprint: String
    ) -> GraphCache.CachedGraph.CachedExplicitRelationshipSnapshot {
        let references = explicitReferencesBySource
            .keys
            .sorted(by: { $0.absoluteString < $1.absoluteString })
            .flatMap { explicitReferencesBySource[$0, default: []] }
        return GraphCache.CachedGraph.CachedExplicitRelationshipSnapshot(
            fingerprint: fingerprint,
            references: references
        )
    }

    /// Returns the full canonical explicit reference payloads currently held in live state.
    public func allExplicitReferences() -> [ExplicitNoteReference] {
        explicitReferencesBySource
            .keys
            .sorted(by: { $0.absoluteString < $1.absoluteString })
            .flatMap { explicitReferencesBySource[$0, default: []] }
    }

    /// Replaces the complete explicit relationship state from authoritative parsed
    /// references. Used by KG3 lifecycle repair after rename/move/delete and at
    /// vault load so stale edges do not survive until some later edit or graph-view rebuild.
    ///
    /// - Returns: The union of old and new canonical target URLs that were affected.
    @discardableResult
    public func replaceExplicitRelationshipState(
        with referencesBySource: [URL: [ExplicitNoteReference]]
    ) -> Set<URL> {
        let previousTargets = Set(reverseEdges.keys)

        explicitReferencesBySource.removeAll(keepingCapacity: true)
        reverseExplicitReferences.removeAll(keepingCapacity: true)
        edges.removeAll(keepingCapacity: true)
        reverseEdges.removeAll(keepingCapacity: true)

        for sourceURL in referencesBySource.keys.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let references = referencesBySource[sourceURL] ?? []
            updateExplicitReferences(for: sourceURL, references: references)
        }

        return previousTargets.union(reverseEdges.keys)
    }

    /// Internal resolution method that tries resolver first, then fallback.
    private func resolveWikiLink(_ target: String) async -> URL? {
        // Try the canonical resolver first (supports aliases, frontmatter titles, paths)
        if let resolver = identityResolver {
            if let url = await resolver.resolve(target) {
                return CanonicalNoteIdentity.canonicalFileURL(for: url)
            }
        }

        // Fallback to simple title matching
        let key = GraphIdentityResolver.normalize(target)
        if let resolved = titleIndex[key] {
            return resolved
        }

        let hyphenToSpace = key.replacingOccurrences(of: "-", with: " ")
        if hyphenToSpace != key {
            return titleIndex[hyphenToSpace]
        }

        return nil
    }

    /// Rebuilds the full edge map from a batch of (source, titles) pairs.
    public func rebuildAll(
        connections: [(sourceURL: URL, linkedTitles: [String])],
        allVaultURLs: [URL]
    ) async {
        rebuildTitleIndex(from: allVaultURLs)
        edges.removeAll()
        reverseEdges.removeAll()
        explicitReferencesBySource.removeAll()
        reverseExplicitReferences.removeAll()

        for (sourceURL, linkedTitles) in connections {
            let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
            var references: [ExplicitNoteReference] = []
            for title in linkedTitles {
                if let url = await resolveWikiLink(title), url != canonicalSourceURL {
                    let canonicalTargetURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
                    references.append(
                        ExplicitNoteReference(
                            sourceNoteURL: canonicalSourceURL,
                            targetNoteURL: canonicalTargetURL,
                            targetNoteName: canonicalTargetURL.deletingPathExtension().lastPathComponent,
                            insertableTarget: canonicalTargetURL.deletingPathExtension().lastPathComponent,
                            rawLinkText: title,
                            rawTargetText: title,
                            displayText: title,
                            headingFragment: nil,
                            matchRange: nil,
                            lineRange: nil,
                            context: ""
                        )
                    )
                }
            }
            updateExplicitReferences(for: canonicalSourceURL, references: references)
        }
    }

    /// All unique destination URLs linked from any source.
    public var allLinkedURLs: Set<URL> {
        Set(edges.values.flatMap { $0 })
    }

    // MARK: - Semantic Edges

    /// Updates the semantic connections for a single note.
    /// Called by the background semantic linking engine after vector similarity search.
    ///
    /// - Parameters:
    ///   - url: The source note URL.
    ///   - related: URLs of semantically similar notes (filtered by high threshold).
    public func updateSemanticConnections(for url: URL, related: [URL]) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let canonicalTargets = Array(
            Set(related.map(CanonicalNoteIdentity.canonicalFileURL(for:)).filter { $0 != canonicalURL })
        )
        .sorted(by: { $0.absoluteString < $1.absoluteString })

        if canonicalTargets.isEmpty {
            semanticEdges.removeValue(forKey: canonicalURL)
        } else {
            semanticEdges[canonicalURL] = canonicalTargets
        }
    }

    /// Returns the semantically related note URLs for a given note.
    public func semanticRelations(for url: URL) -> [URL] {
        semanticEdges[CanonicalNoteIdentity.canonicalFileURL(for: url)] ?? []
    }

    /// Returns all note-to-note related-note similarity relations in canonical URL form.
    public func allSemanticConnections() -> [URL: [URL]] {
        semanticEdges
    }

    /// Replaces the complete semantic relationship state from authoritative canonical relations.
    @discardableResult
    public func replaceSemanticRelationshipState(
        with relationsBySource: [URL: [URL]]
    ) -> Set<URL> {
        let previousURLs = Set(semanticEdges.keys).union(semanticEdges.values.flatMap { $0 })
        semanticEdges.removeAll(keepingCapacity: true)

        for sourceURL in relationsBySource.keys.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
            let canonicalTargets = Array(
                Set((relationsBySource[sourceURL] ?? []).map(CanonicalNoteIdentity.canonicalFileURL(for:)).filter {
                    $0 != canonicalSourceURL
                })
            )
            .sorted(by: { $0.absoluteString < $1.absoluteString })

            if !canonicalTargets.isEmpty {
                semanticEdges[canonicalSourceURL] = canonicalTargets
            }
        }

        let currentURLs = Set(semanticEdges.keys).union(semanticEdges.values.flatMap { $0 })
        return previousURLs.union(currentURLs)
    }

    /// Loads the authoritative persisted related-note similarity snapshot into the live store.
    @discardableResult
    public func loadSemanticRelationshipSnapshot(
        _ snapshot: GraphCache.CachedGraph.CachedSemanticRelationshipSnapshot
    ) -> Set<URL> {
        let grouped = Dictionary(
            uniqueKeysWithValues: snapshot.relations.map { relation in
                (
                    CanonicalNoteIdentity.canonicalFileURL(for: relation.sourceURL),
                    relation.targetURLs.map(CanonicalNoteIdentity.canonicalFileURL(for:))
                )
            }
        )
        return replaceSemanticRelationshipState(with: grouped)
    }

    /// Exports the authoritative related-note similarity snapshot from the live store.
    public func exportSemanticRelationshipSnapshot(
        fingerprint: String
    ) -> GraphCache.CachedGraph.CachedSemanticRelationshipSnapshot {
        let relations = semanticEdges
            .keys
            .sorted(by: { $0.absoluteString < $1.absoluteString })
            .map { sourceURL in
                GraphCache.CachedGraph.CachedSemanticRelationshipSnapshot.CachedSemanticRelation(
                    sourceURL: sourceURL,
                    targetURLs: semanticEdges[sourceURL, default: []]
                )
            }
        return GraphCache.CachedGraph.CachedSemanticRelationshipSnapshot(
            fingerprint: fingerprint,
            relations: relations
        )
    }

    /// Removes semantic edges for a deleted note.
    public func removeSemanticConnections(for url: URL) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        semanticEdges.removeValue(forKey: canonicalURL)
        // Also remove this URL from other notes' semantic edges
        for (key, var related) in semanticEdges {
            if related.contains(canonicalURL) {
                related.removeAll { $0 == canonicalURL }
                semanticEdges[key] = related
            }
        }
    }

    // MARK: - Concept Edges (AI Ontology)

    /// Updates the concept assignments for a single note.
    /// Removes the note from any concepts it previously had but no longer does.
    ///
    /// - Parameters:
    ///   - url: The note URL.
    ///   - concepts: Normalized concept strings extracted by the AI.
    public func updateConcepts(for url: URL, concepts: [String]) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let oldConcepts = noteConcepts[canonicalURL] ?? []
        let newConceptSet = Set(concepts)
        let oldConceptSet = Set(oldConcepts)

        // Remove URL from concepts it no longer belongs to
        for removed in oldConceptSet.subtracting(newConceptSet) {
            conceptEdges[removed]?.remove(canonicalURL)
            if conceptEdges[removed]?.isEmpty == true {
                conceptEdges.removeValue(forKey: removed)
            }
        }

        // Add URL to new concepts
        for concept in concepts {
            conceptEdges[concept, default: []].insert(canonicalURL)
        }

        // Update reverse map
        if concepts.isEmpty {
            noteConcepts.removeValue(forKey: canonicalURL)
        } else {
            noteConcepts[canonicalURL] = concepts
        }
    }

    /// Returns the concepts assigned to a note.
    public func concepts(for url: URL) -> [String] {
        noteConcepts[CanonicalNoteIdentity.canonicalFileURL(for: url)] ?? []
    }

    /// Returns all note-to-concept assignments currently held in live state.
    /// KG7 uses this for deterministic restore verification and for consumers that
    /// need the canonical concept snapshot without re-scanning persisted JSON.
    public func allConceptAssignments() -> [URL: [String]] {
        noteConcepts
    }

    /// Returns all concepts that have at least `minNotes` associated notes.
    /// Used to determine which concepts become hub nodes in the graph.
    public func significantConcepts(minNotes: Int = 2) -> [(concept: String, noteURLs: Set<URL>)] {
        conceptEdges
            .filter { $0.value.count >= minNotes }
            .map { (concept: $0.key, noteURLs: $0.value) }
            .sorted { $0.noteURLs.count > $1.noteURLs.count }
    }

    /// Removes all concept associations for a deleted note.
    public func removeConcepts(for url: URL) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        guard let concepts = noteConcepts[canonicalURL] else { return }
        for concept in concepts {
            conceptEdges[concept]?.remove(canonicalURL)
            if conceptEdges[concept]?.isEmpty == true {
                conceptEdges.removeValue(forKey: concept)
            }
        }
        noteConcepts.removeValue(forKey: canonicalURL)
    }

    /// Replaces the complete note-to-concept state from authoritative persisted assignments.
    /// KG7 uses a batch replace during startup and vault switch so concept restore does not
    /// depend on incremental per-note updates arriving in an arbitrary order.
    @discardableResult
    public func replaceConceptState(
        with conceptsByNote: [URL: [String]]
    ) -> Set<URL> {
        let previousURLs = Set(noteConcepts.keys)

        conceptEdges.removeAll(keepingCapacity: true)
        noteConcepts.removeAll(keepingCapacity: true)

        for noteURL in conceptsByNote.keys.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let concepts = (conceptsByNote[noteURL] ?? []).sorted()
            if !concepts.isEmpty {
                updateConcepts(for: noteURL, concepts: concepts)
            }
        }

        return previousURLs.union(noteConcepts.keys)
    }

    // MARK: - Private

    private func rebuildTitleIndex(from urls: [URL]) {
        titleIndex.removeAll(keepingCapacity: true)
        for url in urls {
            let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
            let name = GraphIdentityResolver.normalize(canonicalURL.deletingPathExtension().lastPathComponent)
            // First-match wins (avoids ambiguity from duplicate titles in nested folders)
            if titleIndex[name] == nil {
                titleIndex[name] = canonicalURL
            }
        }
    }

    private func collectNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote {
                result.append(node)
            }
            if let children = node.children {
                result.append(contentsOf: collectNotes(from: children))
            }
        }
        return result
    }
}
