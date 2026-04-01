import Foundation
import CoreGraphics
import CryptoKit

/// Persisted cache for the knowledge graph. Avoids rebuilding on every open.
///
/// Cache is stored at `{vault}/.quartz/graph-cache.json`.
/// Invalidated when any note's modification date changes.
public struct GraphCache: Sendable {
    private let cacheURL: URL

    public init(vaultRoot: URL) {
        cacheURL = vaultRoot
            .appending(path: ".quartz")
            .appending(path: "graph-cache.json")
    }

    /// Cached graph data.
    public struct CachedGraph: Codable, Sendable {
        public let nodes: [CachedNode]
        public let edges: [CachedEdge]
        public let fingerprint: String

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
            public let isSemantic: Bool
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

    /// Loads cached graph if fingerprint matches.
    public func loadIfValid(fingerprint: String) -> CachedGraph? {
        guard FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)) else { return nil }
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedGraph.self, from: data),
              cached.fingerprint == fingerprint else {
            return nil
        }
        return cached
    }

    /// Saves graph to cache.
    public func save(_ graph: CachedGraph) throws {
        let dir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(graph)
        try data.write(to: cacheURL, options: .atomic)
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
    /// Maps a source note URL to the URLs it links to via `[[wiki-links]]`.
    public private(set) var edges: [URL: [URL]] = [:]

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
    public func updateConnections(
        for sourceURL: URL,
        linkedTitles: [String],
        allVaultURLs: [URL]
    ) async {
        // Rebuild the title index from the vault snapshot (fallback)
        rebuildTitleIndex(from: allVaultURLs)

        // Resolve each linked title to a URL, deduplicating
        var resolvedSet = Set<URL>()
        for title in linkedTitles {
            if let url = await resolveWikiLink(title), url != sourceURL {
                resolvedSet.insert(url)
            }
        }
        edges[sourceURL] = Array(resolvedSet)
    }

    /// Resolves a wiki-link title to a note URL, if it exists in the vault.
    /// Uses GraphIdentityResolver for robust matching (aliases, titles, paths),
    /// falling back to simple title matching if resolver not configured.
    public func resolveTitle(_ title: String) async -> URL? {
        await resolveWikiLink(title)
    }

    /// Internal resolution method that tries resolver first, then fallback.
    private func resolveWikiLink(_ target: String) async -> URL? {
        // Try the canonical resolver first (supports aliases, frontmatter titles, paths)
        if let resolver = identityResolver {
            if let url = await resolver.resolve(target) {
                return url
            }
        }

        // Fallback to simple title matching
        let key = target.lowercased().trimmingCharacters(in: .whitespaces)
        return titleIndex[key]
    }

    /// Rebuilds the full edge map from a batch of (source, titles) pairs.
    public func rebuildAll(
        connections: [(sourceURL: URL, linkedTitles: [String])],
        allVaultURLs: [URL]
    ) async {
        rebuildTitleIndex(from: allVaultURLs)
        edges.removeAll()

        for (sourceURL, linkedTitles) in connections {
            var resolvedSet = Set<URL>()
            for title in linkedTitles {
                if let url = await resolveWikiLink(title), url != sourceURL {
                    resolvedSet.insert(url)
                }
            }
            edges[sourceURL] = Array(resolvedSet)
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
        semanticEdges[url] = related
    }

    /// Returns the semantically related note URLs for a given note.
    public func semanticRelations(for url: URL) -> [URL] {
        semanticEdges[url] ?? []
    }

    /// Removes semantic edges for a deleted note.
    public func removeSemanticConnections(for url: URL) {
        semanticEdges.removeValue(forKey: url)
        // Also remove this URL from other notes' semantic edges
        for (key, var related) in semanticEdges {
            if related.contains(url) {
                related.removeAll { $0 == url }
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
        let oldConcepts = noteConcepts[url] ?? []
        let newConceptSet = Set(concepts)
        let oldConceptSet = Set(oldConcepts)

        // Remove URL from concepts it no longer belongs to
        for removed in oldConceptSet.subtracting(newConceptSet) {
            conceptEdges[removed]?.remove(url)
            if conceptEdges[removed]?.isEmpty == true {
                conceptEdges.removeValue(forKey: removed)
            }
        }

        // Add URL to new concepts
        for concept in concepts {
            conceptEdges[concept, default: []].insert(url)
        }

        // Update reverse map
        if concepts.isEmpty {
            noteConcepts.removeValue(forKey: url)
        } else {
            noteConcepts[url] = concepts
        }
    }

    /// Returns the concepts assigned to a note.
    public func concepts(for url: URL) -> [String] {
        noteConcepts[url] ?? []
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
        guard let concepts = noteConcepts[url] else { return }
        for concept in concepts {
            conceptEdges[concept]?.remove(url)
            if conceptEdges[concept]?.isEmpty == true {
                conceptEdges.removeValue(forKey: concept)
            }
        }
        noteConcepts.removeValue(forKey: url)
    }

    // MARK: - Private

    private func rebuildTitleIndex(from urls: [URL]) {
        titleIndex.removeAll(keepingCapacity: true)
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            // First-match wins (avoids ambiguity from duplicate titles in nested folders)
            if titleIndex[name] == nil {
                titleIndex[name] = url
            }
        }
    }
}
