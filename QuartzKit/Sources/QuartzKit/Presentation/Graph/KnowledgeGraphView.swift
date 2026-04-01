import SwiftUI

// MARK: - Graph Data Structures

/// A node in the knowledge graph representing a note or an AI-discovered concept hub.
public struct GraphNode: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let url: URL
    public var tags: [String]
    public var x: CGFloat
    public var y: CGFloat
    public var vx: CGFloat = 0
    public var vy: CGFloat = 0
    public var connectionCount: Int = 0
    /// True if this node represents an AI-extracted concept (not a note file).
    public var isConcept: Bool = false

    public init(id: String, title: String, url: URL, tags: [String] = [], x: CGFloat = 0, y: CGFloat = 0, vx: CGFloat = 0, vy: CGFloat = 0, connectionCount: Int = 0, isConcept: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = tags
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.connectionCount = connectionCount
        self.isConcept = isConcept
    }

    /// Equatable: Only compare rendering-relevant properties.
    /// Velocity (vx/vy) changes shouldn't trigger view diffs.
    public static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.x == rhs.x &&
        lhs.y == rhs.y &&
        lhs.connectionCount == rhs.connectionCount &&
        lhs.isConcept == rhs.isConcept
    }
}

/// An edge in the knowledge graph connecting two nodes.
public struct GraphEdge: Identifiable, Sendable, Equatable {
    public let id: String
    public let from: String
    public let to: String
    public let isSemantic: Bool
    /// True if this edge connects a note to a concept hub node.
    public let isConcept: Bool

    public init(from: String, to: String, isSemantic: Bool = false, isConcept: Bool = false) {
        self.id = "\(from)->\(to)"
        self.from = from
        self.to = to
        self.isSemantic = isSemantic
        self.isConcept = isConcept
    }
}

// MARK: - Graph View Model

/// Bounds graph build and layout cost for large vaults.
public enum GraphLayoutPolicy: Sendable {
    /// Maximum notes included in one graph build (I/O + layout scale with this).
    public static let maxNodesPerGraph = 280
    /// Skip semantic AI edges above this count (avoids O(n) embedding similarity work).
    public static let semanticLinkingMaxNodes = 200

    static func layoutIterations(forNodeCount n: Int) -> Int {
        guard n > 1 else { return 0 }
        return min(96, max(24, 30_000 / max(n, 8)))
    }
}

@Observable
@MainActor
public final class GraphViewModel {
    public var nodes: [GraphNode] = []
    public var edges: [GraphEdge] = [] {
        didSet { rebuildEdgeCaches() }
    }
    public var isLoading = true
    public var currentNoteID: String?
    public var graphTruncationNote: String?
    /// Optional reference to the shared edge store for reading concept data.
    public var graphEdgeStore: GraphEdgeStore?

    private let linkExtractor = WikiLinkExtractor()
    private var nodeIndex: [String: Int] = [:]
    /// Identity resolver for robust wiki-link matching.
    private let identityResolver = GraphIdentityResolver()

    /// Public read-only access to node index for O(1) canvas lookups.
    public var nodeIDToIndex: [String: Int] { nodeIndex }

    /// Cached hard edges (non-semantic) for efficient rendering.
    public private(set) var hardEdges: [GraphEdge] = []
    /// Cached semantic edges for efficient rendering.
    public private(set) var semanticEdges: [GraphEdge] = []

    public init() {}

    /// Rebuilds the hard/semantic edge caches when edges change.
    private func rebuildEdgeCaches() {
        hardEdges = edges.filter { !$0.isSemantic }
        semanticEdges = edges.filter { $0.isSemantic }
    }

    // MARK: - Live Simulation

    private var simulationTask: Task<Void, Never>?
    /// True while the physics simulation is actively running (settling).
    public var isSimulating: Bool = false

    /// Starts the live physics simulation that runs at ~60fps and settles over time.
    /// The simulation decays its energy each frame and stops when velocity is negligible.
    public func startLiveSimulation() {
        stopSimulation()
        guard nodes.count > 1 else { return }
        isSimulating = true
        simulationTask = Task { [weak self] in
            var totalIterations = 0
            let maxIterations = 300 // Safety cap (~5 seconds at 60fps)
            while !Task.isCancelled, let self, totalIterations < maxIterations {
                self.simulationTick()
                totalIterations += 1
                // Check if the system has settled (max velocity below threshold)
                let maxVelocity = self.nodes.reduce(CGFloat(0)) { maxV, node in
                    max(maxV, abs(node.vx) + abs(node.vy))
                }
                if maxVelocity < 0.5 { break }
                try? await Task.sleep(for: .milliseconds(16)) // ~60fps
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.isSimulating = false
            }
        }
    }

    /// Runs one tick of the force simulation. Called from the animation loop.
    private func simulationTick() {
        let n = nodes.count
        guard n > 1 else { return }

        let repulsionStrength: CGFloat = 6000
        let hardLinkAttraction: CGFloat = 0.012
        let semanticLinkAttraction: CGFloat = 0.005
        let conceptLinkAttraction: CGFloat = 0.010
        let damping: CGFloat = 0.85
        let centerGravity: CGFloat = 0.01
        let cellSize = max(36, min(130, 2200 / sqrt(CGFloat(max(n, 2)))))

        // Repulsion via spatial hashing
        var buckets: [String: [Int]] = [:]
        buckets.reserveCapacity(n)
        for i in 0..<n {
            let gx = Int(floor(nodes[i].x / cellSize))
            let gy = Int(floor(nodes[i].y / cellSize))
            buckets["\(gx),\(gy)", default: []].append(i)
        }

        for i in 0..<n {
            let gx = Int(floor(nodes[i].x / cellSize))
            let gy = Int(floor(nodes[i].y / cellSize))
            for dx in -1...1 {
                for dy in -1...1 {
                    guard let bucket = buckets["\(gx + dx),\(gy + dy)"] else { continue }
                    for j in bucket where j > i {
                        let dxn = nodes[i].x - nodes[j].x
                        let dyn = nodes[i].y - nodes[j].y
                        let dist = max(sqrt(dxn * dxn + dyn * dyn), 1)
                        let force = repulsionStrength / (dist * dist)
                        let fx = (dxn / dist) * force
                        let fy = (dyn / dist) * force
                        nodes[i].vx += fx
                        nodes[i].vy += fy
                        nodes[j].vx -= fx
                        nodes[j].vy -= fy
                    }
                }
            }
        }

        // Attraction: stronger for hard wiki-links, softer for semantic AI links
        for edge in edges {
            guard let iFrom = nodeIndex[edge.from],
                  let iTo = nodeIndex[edge.to] else { continue }
            let strength = edge.isConcept ? conceptLinkAttraction : (edge.isSemantic ? semanticLinkAttraction : hardLinkAttraction)
            let dx = nodes[iTo].x - nodes[iFrom].x
            let dy = nodes[iTo].y - nodes[iFrom].y
            let fx = dx * strength
            let fy = dy * strength
            nodes[iFrom].vx += fx
            nodes[iFrom].vy += fy
            nodes[iTo].vx -= fx
            nodes[iTo].vy -= fy
        }

        // Centering + damping
        for i in 0..<n {
            nodes[i].vx -= nodes[i].x * centerGravity
            nodes[i].vy -= nodes[i].y * centerGravity
            nodes[i].vx *= damping
            nodes[i].vy *= damping
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
        }
    }

    /// Stops any in-flight simulation.
    public func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        isSimulating = false
    }

    /// Builds the graph from a file tree and the currently selected note.
    /// Uses disk cache when notes haven't changed to avoid slow rebuilds.
    /// When embeddingService is provided and semanticAutoLinkingEnabled, adds AI-assisted semantic links between similar notes.
    public func buildGraph(
        fileTree: [FileNode],
        currentNoteURL: URL?,
        vaultRootURL: URL?,
        vaultProvider: (any VaultProviding)?,
        embeddingService: VectorEmbeddingService? = nil,
        semanticAutoLinkingEnabled: Bool = true
    ) async {
        isLoading = true
        graphTruncationNote = nil

        let collected = collectNotes(from: fileTree)
        guard !collected.isEmpty else {
            isLoading = false
            return
        }

        let allNotes = selectNotesForGraph(collected, limit: GraphLayoutPolicy.maxNodesPerGraph, currentNoteURL: currentNoteURL)
        if collected.count > allNotes.count {
            graphTruncationNote = String(
                localized: "Showing \(allNotes.count) of \(collected.count) notes (most recently edited). Open the graph from a note to keep it in view.",
                bundle: .module
            )
        }

        let noteURLs = allNotes.map(\.url)

        // Try cache first (avoids reading 300+ files on every open)
        if let root = vaultRootURL {
            let cache = GraphCache(vaultRoot: root)
            let fingerprint = cache.computeFingerprint(for: noteURLs)
            if let cached = cache.loadIfValid(fingerprint: fingerprint) {
                nodes = cached.nodes.map { n in
                    GraphNode(
                        id: n.id,
                        title: n.title,
                        url: n.url,
                        tags: n.tags ?? [],
                        x: n.x,
                        y: n.y,
                        vx: 0,
                        vy: 0,
                        connectionCount: n.connectionCount
                    )
                }
                edges = cached.edges.map { e in GraphEdge(from: e.from, to: e.to, isSemantic: e.isSemantic) }
                currentNoteID = currentNoteURL?.absoluteString
                rebuildNodeIndex()
                isLoading = false
                return
            }
        }

        var builtNodes: [GraphNode] = []
        var builtEdges: [GraphEdge] = []
        var urlToFrontmatter: [URL: Frontmatter] = [:]
        var urlToLinks: [URL: [WikiLink]] = [:]

        if let provider = vaultProvider {
            await withTaskGroup(of: (URL, Frontmatter, [WikiLink]).self) { group in
                for note in allNotes {
                    group.addTask { [linkExtractor] in
                        do {
                            let doc = try await provider.readNote(at: note.url)
                            let links = linkExtractor.extractLinks(from: doc.body)
                            return (note.url, doc.frontmatter, links)
                        } catch {
                            return (note.url, Frontmatter(), [])
                        }
                    }
                }
                for await (url, frontmatter, links) in group {
                    urlToFrontmatter[url] = frontmatter
                    urlToLinks[url] = links
                }
            }
        }

        // Register all notes with the identity resolver for robust link matching
        for note in allNotes {
            let displayName = note.name.replacingOccurrences(of: ".md", with: "")
            let frontmatter = urlToFrontmatter[note.url]
            let identity = NoteIdentity(
                url: note.url,
                filename: displayName,
                frontmatterTitle: frontmatter?.title,
                aliases: frontmatter?.aliases ?? [],
                tags: frontmatter?.tags ?? []
            )
            await identityResolver.register(identity)
        }

        for note in allNotes {
            let nodeID = note.url.absoluteString
            let displayName = note.name.replacingOccurrences(of: ".md", with: "")
            let randomX = CGFloat.random(in: -200...200)
            let randomY = CGFloat.random(in: -200...200)
            let tags = urlToFrontmatter[note.url]?.tags ?? []
            builtNodes.append(GraphNode(
                id: nodeID,
                title: displayName,
                url: note.url,
                tags: tags,
                x: randomX,
                y: randomY
            ))
        }

        if let currentURL = currentNoteURL {
            currentNoteID = currentURL.absoluteString
        }

        var edgeSet = Set<String>()

        if vaultProvider != nil {
            for note in allNotes {
                let sourceID = note.url.absoluteString
                let links = urlToLinks[note.url] ?? []
                for link in links {
                    // Use identity resolver for robust matching (aliases, folder paths, normalization)
                    if let targetURL = await identityResolver.resolve(link.target) {
                        let targetID = targetURL.absoluteString
                        let edgeKey = [sourceID, targetID].sorted().joined(separator: "<->")
                        if !edgeSet.contains(edgeKey) {
                            edgeSet.insert(edgeKey)
                            builtEdges.append(GraphEdge(from: sourceID, to: targetID))
                        }
                    }
                }
            }
        }

        // AI-assisted semantic linking: add edges between semantically similar notes (when enabled)
        if semanticAutoLinkingEnabled,
           allNotes.count <= GraphLayoutPolicy.semanticLinkingMaxNodes,
           let embedding = embeddingService,
           let root = vaultRootURL {
            var stableIDToNodeID: [UUID: String] = [:]
            for note in allNotes {
                let sid = VectorEmbeddingService.stableNoteID(for: note.url, vaultRoot: root)
                stableIDToNodeID[sid] = note.url.absoluteString
            }
            for note in allNotes {
                let stableID = VectorEmbeddingService.stableNoteID(for: note.url, vaultRoot: root)
                let sourceID = note.url.absoluteString
                let similarIDs = await embedding.findSimilarNoteIDs(for: stableID, limit: 5, threshold: 0.35)
                for similarUUID in similarIDs {
                    guard let targetID = stableIDToNodeID[similarUUID], targetID != sourceID else { continue }
                    let edgeKey = [sourceID, targetID].sorted().joined(separator: "<->")
                    if !edgeSet.contains(edgeKey) {
                        edgeSet.insert(edgeKey)
                        builtEdges.append(GraphEdge(from: sourceID, to: targetID, isSemantic: true))
                    }
                }
            }
        }

        var connectionCounts: [String: Int] = [:]
        for edge in builtEdges {
            connectionCounts[edge.from, default: 0] += 1
            connectionCounts[edge.to, default: 0] += 1
        }
        for i in builtNodes.indices {
            builtNodes[i].connectionCount = connectionCounts[builtNodes[i].id, default: 0]
        }

        nodes = builtNodes
        edges = builtEdges

        // Add concept hub nodes from the AI ontology engine
        await addConceptHubNodes()

        rebuildNodeIndex()
        layoutGraph() // Initial fast layout
        startLiveSimulation() // Animate settling

        // Persist to cache for next time
        if let root = vaultRootURL {
            let cache = GraphCache(vaultRoot: root)
            let fingerprint = cache.computeFingerprint(for: noteURLs)
            let cached = GraphCache.CachedGraph(
                nodes: nodes.map { n in
                    GraphCache.CachedGraph.CachedNode(
                        id: n.id,
                        title: n.title,
                        url: n.url,
                        x: n.x,
                        y: n.y,
                        connectionCount: n.connectionCount,
                        tags: n.tags.isEmpty ? nil : n.tags
                    )
                },
                edges: edges.map { e in
                    GraphCache.CachedGraph.CachedEdge(from: e.from, to: e.to, isSemantic: e.isSemantic)
                },
                fingerprint: fingerprint
            )
            try? cache.save(cached)
        }

        isLoading = false
    }

    private func rebuildNodeIndex() {
        nodeIndex = [:]
        for (i, node) in nodes.enumerated() {
            nodeIndex[node.id] = i
        }
    }

    // MARK: - Concept Hub Nodes

    /// Reads significant concepts from the edge store and adds them as hub nodes + edges.
    /// Concept nodes are positioned at the centroid of their connected note nodes.
    private func addConceptHubNodes() async {
        guard let store = graphEdgeStore else { return }
        let significant = await store.significantConcepts(minNotes: 2)
        guard !significant.isEmpty else { return }

        // Build a lookup from note URL string → node index
        let urlToNodeID: [String: String] = Dictionary(
            uniqueKeysWithValues: nodes.compactMap { node in
                node.isConcept ? nil : (node.url.absoluteString, node.id)
            }
        )

        for (concept, noteURLs) in significant {
            let conceptID = "concept:\(concept)"

            // Find connected note nodes and compute centroid for initial position
            var connectedNodeIDs: [String] = []
            var cx: CGFloat = 0
            var cy: CGFloat = 0
            var count: CGFloat = 0

            for noteURL in noteURLs {
                guard let nodeID = urlToNodeID[noteURL.absoluteString],
                      let idx = nodeIndex[nodeID] else { continue }
                connectedNodeIDs.append(nodeID)
                cx += nodes[idx].x
                cy += nodes[idx].y
                count += 1
            }

            guard !connectedNodeIDs.isEmpty else { continue }

            // Position at centroid with slight jitter
            let posX = (count > 0 ? cx / count : 0) + CGFloat.random(in: -20...20)
            let posY = (count > 0 ? cy / count : 0) + CGFloat.random(in: -20...20)

            // Create the concept hub node
            let conceptNode = GraphNode(
                id: conceptID,
                title: concept.capitalized,
                url: URL(fileURLWithPath: "/concept/\(concept)"), // Placeholder URL for concept nodes
                x: posX,
                y: posY,
                connectionCount: connectedNodeIDs.count,
                isConcept: true
            )
            nodes.append(conceptNode)

            // Create edges from each note to the concept hub
            for nodeID in connectedNodeIDs {
                edges.append(GraphEdge(from: nodeID, to: conceptID, isConcept: true))
            }
        }
    }

    // MARK: - Force-Directed Layout

    /// Runs a simplified force-directed layout to position nodes.
    /// Uses spatial hashing for repulsion (neighboring grid cells) so large graphs stay responsive; iterations scale down with node count.
    public func layoutGraph(iterations: Int? = nil) {
        guard nodes.count > 1 else { return }

        let iterations = iterations ?? GraphLayoutPolicy.layoutIterations(forNodeCount: nodes.count)
        guard iterations > 0 else { return }

        let n = nodes.count
        let repulsionStrength: CGFloat = 6000
        let hardLinkAttraction: CGFloat = 0.012
        let semanticLinkAttraction: CGFloat = 0.005
        let conceptLinkAttraction: CGFloat = 0.010
        let damping: CGFloat = 0.85
        let centerGravity: CGFloat = 0.01
        let cellSize = max(36, min(130, 2200 / sqrt(CGFloat(max(n, 2)))))

        for _ in 0..<iterations {
            // Repulsion: only between nodes in the same or adjacent grid cells (avoids O(n²) all-pairs).
            var buckets: [String: [Int]] = [:]
            buckets.reserveCapacity(n)
            for i in 0..<n {
                let gx = Int(floor(nodes[i].x / cellSize))
                let gy = Int(floor(nodes[i].y / cellSize))
                let key = "\(gx),\(gy)"
                buckets[key, default: []].append(i)
            }

            for i in 0..<n {
                let gx = Int(floor(nodes[i].x / cellSize))
                let gy = Int(floor(nodes[i].y / cellSize))
                for dx in -1...1 {
                    for dy in -1...1 {
                        let key = "\(gx + dx),\(gy + dy)"
                        guard let bucket = buckets[key] else { continue }
                        for j in bucket where j > i {
                            let dxn = nodes[i].x - nodes[j].x
                            let dyn = nodes[i].y - nodes[j].y
                            let dist = max(sqrt(dxn * dxn + dyn * dyn), 1)
                            let force = repulsionStrength / (dist * dist)
                            let fx = (dxn / dist) * force
                            let fy = (dyn / dist) * force
                            nodes[i].vx += fx
                            nodes[i].vy += fy
                            nodes[j].vx -= fx
                            nodes[j].vy -= fy
                        }
                    }
                }
            }

            // Attraction along edges: stronger for hard wiki-links, softer for semantic AI links
            for edge in edges {
                guard let iFrom = nodeIndex[edge.from],
                      let iTo = nodeIndex[edge.to] else { continue }
                let strength = edge.isConcept ? conceptLinkAttraction : (edge.isSemantic ? semanticLinkAttraction : hardLinkAttraction)
                let dx = nodes[iTo].x - nodes[iFrom].x
                let dy = nodes[iTo].y - nodes[iFrom].y
                let fx = dx * strength
                let fy = dy * strength
                nodes[iFrom].vx += fx
                nodes[iFrom].vy += fy
                nodes[iTo].vx -= fx
                nodes[iTo].vy -= fy
            }

            // Center gravity to prevent drift
            for i in 0..<nodes.count {
                nodes[i].vx -= nodes[i].x * centerGravity
                nodes[i].vy -= nodes[i].y * centerGravity
            }

            // Apply velocities with damping
            for i in 0..<nodes.count {
                nodes[i].vx *= damping
                nodes[i].vy *= damping
                nodes[i].x += nodes[i].vx
                nodes[i].y += nodes[i].vy
            }
        }
    }

    // MARK: - Coordinate Mapping

    /// Maps a node's simulation coordinates to view coordinates within the given size.
    public func nodePosition(_ node: GraphNode, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + node.x,
            y: size.height / 2 + node.y
        )
    }

    // MARK: - Helpers

    /// Finds the node closest to a tap point.
    public func nodeAt(point: CGPoint, in size: CGSize, threshold: CGFloat = 24) -> GraphNode? {
        for node in nodes {
            let pos = nodePosition(node, in: size)
            let dx = pos.x - point.x
            let dy = pos.y - point.y
            let dist = sqrt(dx * dx + dy * dy)
            let radius = nodeRadius(for: node)
            if dist <= radius + threshold {
                return node
            }
        }
        return nil
    }

    /// Returns the visual radius for a node based on its state.
    public func nodeRadius(for node: GraphNode) -> CGFloat {
        if node.isConcept { return max(8, min(14, CGFloat(node.connectionCount) * 2 + 4)) }
        if node.id == currentNoteID { return 14 }
        if node.connectionCount > 0 { return max(6, min(12, CGFloat(node.connectionCount) * 2 + 4)) }
        return 5
    }

    /// Returns the color for a node based on its type and relationship to the current note.
    public func nodeColor(for node: GraphNode) -> Color {
        if node.isConcept { return QuartzColors.folderYellow }
        if node.id == currentNoteID { return .orange }
        let isConnected = edges.contains { edge in
            (edge.from == currentNoteID && edge.to == node.id) ||
            (edge.to == currentNoteID && edge.from == node.id)
        }
        if isConnected { return QuartzColors.noteBlue }
        if node.connectionCount > 0 { return QuartzColors.canvasPurple.opacity(0.7) }
        return Color.secondary.opacity(0.5)
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

    /// Caps graph size for performance; always includes `currentNoteURL` when present.
    private func selectNotesForGraph(_ notes: [FileNode], limit: Int, currentNoteURL: URL?) -> [FileNode] {
        guard notes.count > limit else { return notes }
        let sorted = notes.sorted { $0.metadata.modifiedAt > $1.metadata.modifiedAt }
        var result = Array(sorted.prefix(limit))
        if let cur = currentNoteURL,
           !result.contains(where: { $0.url == cur }),
           let currentNode = notes.first(where: { $0.url == cur }) {
            result.removeLast()
            result.append(currentNode)
        }
        return result
    }

    /// Set of node IDs directly connected to the current note.
    public var connectedNodeIDs: Set<String> {
        guard let currentID = currentNoteID else { return [] }
        var connected = Set<String>()
        for edge in edges {
            if edge.from == currentID { connected.insert(edge.to) }
            if edge.to == currentID { connected.insert(edge.from) }
        }
        return connected
    }
}

// MARK: - Knowledge Graph View

/// Graph filter options matching the design.
public enum GraphFilterOption: String, CaseIterable {
    case all
    case recent
    case highPriority
    case unlinked

    var label: String {
        switch self {
        case .all: String(localized: "All Nodes", bundle: .module)
        case .recent: String(localized: "Recent", bundle: .module)
        case .highPriority: String(localized: "High Priority", bundle: .module)
        case .unlinked: String(localized: "Unlinked", bundle: .module)
        }
    }
}

/// Interactive force-directed graph visualization of vault notes and their connections.
/// Light theme with search, floating node card, and filter bar per design.
public struct KnowledgeGraphView: View {
    @State private var viewModel = GraphViewModel()
    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredNodeID: String?
    @State private var selectedNodeID: String?
    @State private var searchText = ""
    @State private var activeFilter: GraphFilterOption = .all
    @State private var lastMagnification: CGFloat = 1.0
    @AppStorage("semanticAutoLinkingEnabled") private var semanticAutoLinkingEnabled = true

    private let fileTree: [FileNode]
    private let currentNoteURL: URL?
    private let vaultRootURL: URL?
    private let vaultProvider: (any VaultProviding)?
    private let embeddingService: VectorEmbeddingService?
    private let onSelectNote: ((URL) -> Void)?
    private let graphEdgeStoreRef: GraphEdgeStore?

    /// Light cream background per design (#FDFBF8).
    private static let graphBackgroundColor = Color(hex: 0xFDFBF8)

    /// Whether the graph is shown as a full workspace pane (vs modal sheet).
    private let isEmbedded: Bool

    public init(
        fileTree: [FileNode],
        currentNoteURL: URL?,
        vaultRootURL: URL?,
        vaultProvider: (any VaultProviding)?,
        embeddingService: VectorEmbeddingService? = nil,
        onSelectNote: ((URL) -> Void)? = nil,
        isEmbedded: Bool = false,
        graphEdgeStore: GraphEdgeStore? = nil
    ) {
        self.fileTree = fileTree
        self.currentNoteURL = currentNoteURL
        self.vaultRootURL = vaultRootURL
        self.vaultProvider = vaultProvider
        self.embeddingService = embeddingService
        self.onSelectNote = onSelectNote
        self.isEmbedded = isEmbedded
        self.graphEdgeStoreRef = graphEdgeStore
    }

    public var body: some View {
        ZStack {
            graphBackground

            if viewModel.isLoading {
                loadingOverlay
            } else if viewModel.nodes.isEmpty {
                emptyState
            } else {
                graphCanvas
            }

            // Inline header for embedded mode (toolbar items removed to prevent macOS 26 crash)
            if isEmbedded {
                embeddedHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // Floating node detail card (top-right overlay)
            if let nodeID = selectedNodeID ?? hoveredNodeID,
               let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                nodeDetailCard(for: node)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Bottom filter bar
            filterBar
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            // Zoom controls (bottom-right)
            zoomControls
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Edge type legend (bottom-left)
            if !viewModel.isLoading && !viewModel.nodes.isEmpty {
                edgeLegend
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .navigationTitle(String(localized: "Graph View", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Only add toolbar items when NOT embedded in the workspace detail column.
        // macOS 26 beta: NSToolbar crashes (EXC_BREAKPOINT in _insertNewItemWithItemIdentifier)
        // when toolbar items change across conditional detail-column branches inside NavigationSplitView.
        .modifier(GraphToolbarModifier(
            viewModel: viewModel,
            searchText: $searchText,
            isEmbedded: isEmbedded
        ))
        .task(id: semanticAutoLinkingEnabled) {
            viewModel.graphEdgeStore = graphEdgeStoreRef
            await viewModel.buildGraph(
                fileTree: fileTree,
                currentNoteURL: currentNoteURL,
                vaultRootURL: vaultRootURL,
                vaultProvider: vaultProvider,
                embeddingService: embeddingService,
                semanticAutoLinkingEnabled: semanticAutoLinkingEnabled
            )
        }
    }

    // MARK: - Background

    private var graphBackground: some View {
        Group {
            if isEmbedded {
                // Embedded mode: use the ambient mesh for Liquid Glass feel
                QuartzAmbientMeshBackground(style: .shell)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(Self.graphBackgroundColor)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Node Detail Card

    private func nodeDetailCard(for node: GraphNode) -> some View {
        let hardLinks = viewModel.edges.filter { !$0.isSemantic && ($0.from == node.id || $0.to == node.id) }.count
        let semanticLinks = viewModel.edges.filter { $0.isSemantic && ($0.from == node.id || $0.to == node.id) }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ACTIVE NODE", bundle: .module))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(node.title)
                .font(.headline.weight(.bold))

            // Connection breakdown
            HStack(spacing: 12) {
                if hardLinks > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(String(localized: "\(hardLinks) links", bundle: .module))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if semanticLinks > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(QuartzColors.canvasPurple)
                            .frame(width: 6, height: 6)
                        Text(String(localized: "\(semanticLinks) AI", bundle: .module))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if hardLinks == 0 && semanticLinks == 0 {
                    Text(String(localized: "No connections", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !node.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(node.tags.prefix(5), id: \.self) { tag in
                        Text(tag.hasPrefix("#") ? tag : "#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
            Button {
                navigateToNote(node)
            } label: {
                HStack {
                    Text(String(localized: "Open Note", bundle: .module))
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .foregroundStyle(QuartzColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Open \(node.title)", bundle: .module))
        }
        .padding(16)
        .frame(maxWidth: 200, alignment: .leading)
        .quartzFloatingUltraThinSurface(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Selected note: \(node.title)", bundle: .module))
        .accessibilityHint(String(localized: "\(hardLinks) wiki-links, \(semanticLinks) AI links. Double tap Open Note to view.", bundle: .module))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(GraphFilterOption.allCases, id: \.self) { option in
                filterButton(option: option)
            }
        }
        .padding(12)
        .quartzMaterialBackground(cornerRadius: 16, shadowRadius: 12)
    }

    private func filterButton(option: GraphFilterOption) -> some View {
        let isSelected = activeFilter == option
        return Button {
            withAnimation(QuartzAnimation.standard) { activeFilter = option }
        } label: {
            Text(option.label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? QuartzColors.accent : Color.secondary.opacity(0.12)))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityHint(isSelected
            ? String(localized: "Currently selected", bundle: .module)
            : String(localized: "Double tap to filter", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation { zoom = min(5.0, zoom + 0.2) }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
                    .quartzMaterialCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Zoom in", bundle: .module))
            Button {
                withAnimation { zoom = max(0.3, zoom - 0.2) }
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
                    .quartzMaterialCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Zoom out", bundle: .module))
            Button {
                withAnimation { pan = .zero; zoom = 1.0 }
            } label: {
                Image(systemName: "location.fill")
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
                    .quartzMaterialCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Reset view", bundle: .module))
        }
    }

    // MARK: - Edge Legend

    private var edgeLegend: some View {
        let hardCount = viewModel.edges.filter { !$0.isSemantic }.count
        let semanticCount = viewModel.edges.filter { $0.isSemantic }.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 20, height: 1.5)
                Text(String(localized: "Wiki-links (\(hardCount))", bundle: .module))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if semanticCount > 0 {
                HStack(spacing: 8) {
                    StrokeDash()
                        .stroke(QuartzColors.canvasPurple.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 20, height: 1.5)
                    Text(String(localized: "AI-discovered (\(semanticCount))", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .quartzFloatingUltraThinSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(hardCount) wiki-links, \(semanticCount) AI-discovered links", bundle: .module))
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(QuartzColors.accent)
                .scaleEffect(1.2)
            Text(String(localized: "Building graph…", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(String(localized: "No notes to display", bundle: .module))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "Create notes with [[wiki-links]] to see connections.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Graph Canvas

    private var graphCanvas: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, canvasSize in
                let transform = CGAffineTransform(translationX: pan.width + dragOffset.width, y: pan.height + dragOffset.height)
                    .scaledBy(x: zoom, y: zoom)

                // PERF: Use cached filtered arrays and O(1) node index lookups
                let nodeIndex = viewModel.nodeIDToIndex
                let nodes = viewModel.nodes

                // Draw edges — hard links first (behind), then semantic links (on top with glow)
                for edge in viewModel.hardEdges {
                    // O(1) lookup instead of O(n) .first(where:)
                    guard let fromIdx = nodeIndex[edge.from],
                          let toIdx = nodeIndex[edge.to],
                          fromIdx < nodes.count, toIdx < nodes.count else { continue }
                    let fromNode = nodes[fromIdx]
                    let toNode = nodes[toIdx]

                    let fromPos = viewModel.nodePosition(fromNode, in: canvasSize).applying(transform)
                    let toPos = viewModel.nodePosition(toNode, in: canvasSize).applying(transform)

                    var path = Path()
                    path.move(to: fromPos)
                    path.addLine(to: toPos)

                    let isHighlighted = viewModel.currentNoteID != nil &&
                        (edge.from == viewModel.currentNoteID || edge.to == viewModel.currentNoteID)
                    let edgeColor: Color = isHighlighted
                        ? QuartzColors.accent.opacity(0.6)
                        : Color.secondary.opacity(0.4)
                    let lineWidth: CGFloat = isHighlighted ? 1.8 : 0.8
                    context.stroke(path, with: .color(edgeColor), lineWidth: lineWidth)
                }

                for edge in viewModel.semanticEdges {
                    // O(1) lookup instead of O(n) .first(where:)
                    guard let fromIdx = nodeIndex[edge.from],
                          let toIdx = nodeIndex[edge.to],
                          fromIdx < nodes.count, toIdx < nodes.count else { continue }
                    let fromNode = nodes[fromIdx]
                    let toNode = nodes[toIdx]

                    let fromPos = viewModel.nodePosition(fromNode, in: canvasSize).applying(transform)
                    let toPos = viewModel.nodePosition(toNode, in: canvasSize).applying(transform)

                    var path = Path()
                    path.move(to: fromPos)
                    path.addLine(to: toPos)

                    let isHighlighted = viewModel.currentNoteID != nil &&
                        (edge.from == viewModel.currentNoteID || edge.to == viewModel.currentNoteID)
                    let edgeColor: Color = isHighlighted
                        ? QuartzColors.canvasPurple.opacity(0.7)
                        : QuartzColors.canvasPurple.opacity(0.35)
                    let lineWidth: CGFloat = isHighlighted ? 1.6 : 1.0

                    // Soft glow behind semantic edges
                    context.stroke(path, with: .color(QuartzColors.canvasPurple.opacity(0.12)), lineWidth: lineWidth + 3)
                    context.stroke(path, with: .color(edgeColor), style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
                }

                // Draw nodes
                for node in viewModel.nodes {
                    let pos = viewModel.nodePosition(node, in: canvasSize).applying(transform)
                    let radius = viewModel.nodeRadius(for: node) * zoom
                    let color = viewModel.nodeColor(for: node)
                    let isCurrentNote = node.id == viewModel.currentNoteID
                    let isSelected = node.id == hoveredNodeID || node.id == selectedNodeID

                    if node.isConcept {
                        // Concept hub: diamond shape with golden glow
                        let glowRadius = radius * 2.0
                        let glowRect = CGRect(x: pos.x - glowRadius, y: pos.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                        context.fill(Circle().path(in: glowRect), with: .color(QuartzColors.folderYellow.opacity(0.12)))

                        // Diamond shape (45-degree rotated square)
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: pos.x, y: pos.y - radius))
                        diamond.addLine(to: CGPoint(x: pos.x + radius, y: pos.y))
                        diamond.addLine(to: CGPoint(x: pos.x, y: pos.y + radius))
                        diamond.addLine(to: CGPoint(x: pos.x - radius, y: pos.y))
                        diamond.closeSubpath()

                        context.fill(diamond, with: .color(color))
                        context.stroke(diamond, with: .color(color.opacity(0.5)), lineWidth: 1.0)

                        if isSelected {
                            var outerDiamond = Path()
                            let r2 = radius + 3
                            outerDiamond.move(to: CGPoint(x: pos.x, y: pos.y - r2))
                            outerDiamond.addLine(to: CGPoint(x: pos.x + r2, y: pos.y))
                            outerDiamond.addLine(to: CGPoint(x: pos.x, y: pos.y + r2))
                            outerDiamond.addLine(to: CGPoint(x: pos.x - r2, y: pos.y))
                            outerDiamond.closeSubpath()
                            context.stroke(outerDiamond, with: .color(QuartzColors.accent.opacity(0.8)), lineWidth: 2)
                        }

                        // Concept label — always visible, bold
                        context.draw(
                            Text(node.title)
                                .font(.system(size: 10 * zoom, weight: .bold))
                                .foregroundColor(QuartzColors.folderYellow),
                            at: CGPoint(x: pos.x, y: pos.y + radius + 10 * zoom)
                        )
                    } else {
                        // Note node: standard circle

                        // Glow effect for current note
                        if isCurrentNote {
                            let glowRadius = radius * 2.5
                            let glowRect = CGRect(x: pos.x - glowRadius, y: pos.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                            context.fill(Circle().path(in: glowRect), with: .color(QuartzColors.accent.opacity(0.15)))
                        }

                        // Glass-like outer ring for connected or selected nodes
                        if node.connectionCount > 0 || isSelected {
                            let ringRadius = radius + 2.5 * zoom
                            let ringRect = CGRect(x: pos.x - ringRadius, y: pos.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
                            context.stroke(Circle().path(in: ringRect), with: .color(color.opacity(0.3)), lineWidth: 1.0)
                        }

                        // Node fill
                        let nodeRect = CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Circle().path(in: nodeRect), with: .color(color))

                        // Accent border for hovered/selected node
                        if isSelected {
                            context.stroke(Circle().path(in: nodeRect.insetBy(dx: -2, dy: -2)), with: .color(QuartzColors.accent.opacity(0.8)), lineWidth: 2)
                        }

                    // Labels for significant note nodes
                    let showLabel = isCurrentNote ||
                        viewModel.connectedNodeIDs.contains(node.id) ||
                        node.id == hoveredNodeID ||
                        node.id == selectedNodeID ||
                        (zoom > 1.5 && node.connectionCount > 0) ||
                        zoom > 2.5

                    if showLabel {
                        let labelColor: Color = isCurrentNote ? QuartzColors.accent : Color.primary.opacity(0.85)
                        let fontSize: CGFloat = isCurrentNote ? 11 : 9
                        context.draw(
                            Text(node.title)
                                .font(.system(size: fontSize * zoom, weight: isCurrentNote ? .semibold : .regular))
                                .foregroundColor(labelColor),
                            at: CGPoint(x: pos.x, y: pos.y + radius + 10 * zoom)
                        )
                    }
                    } // end else (note node)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        pan = CGSize(
                            width: pan.width + value.translation.width,
                            height: pan.height + value.translation.height
                        )
                        dragOffset = .zero
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = max(0.3, min(5.0, zoom * value.magnification / lastMagnification))
                        lastMagnification = value.magnification
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
            .onTapGesture { location in
                let inverseTransform = CGAffineTransform(translationX: pan.width + dragOffset.width, y: pan.height + dragOffset.height)
                    .scaledBy(x: zoom, y: zoom)
                    .inverted()
                let adjustedLocation = location.applying(inverseTransform)
                let adjustedInCanvasCoords = CGPoint(
                    x: adjustedLocation.x,
                    y: adjustedLocation.y
                )
                if let tapped = viewModel.nodeAt(point: adjustedInCanvasCoords, in: size, threshold: 20 / zoom) {
                    withAnimation(QuartzAnimation.standard) {
                        if selectedNodeID == tapped.id {
                            // Second tap on same node → navigate
                            navigateToNote(tapped)
                        } else {
                            selectedNodeID = tapped.id
                        }
                    }
                } else {
                    selectedNodeID = nil
                }
            }
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let inverseTransform = CGAffineTransform(translationX: pan.width + dragOffset.width, y: pan.height + dragOffset.height)
                        .scaledBy(x: zoom, y: zoom)
                        .inverted()
                    let adjusted = location.applying(inverseTransform)
                    hoveredNodeID = viewModel.nodeAt(point: adjusted, in: size, threshold: 20 / zoom)?.id
                case .ended:
                    hoveredNodeID = nil
                }
            }
            #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(graphAccessibilityLabel)
        .accessibilityHint(String(localized: "Use the node list below for VoiceOver navigation", bundle: .module))
        .accessibilityRepresentation {
            // Provide a list-based alternative for VoiceOver users
            List(viewModel.nodes) { node in
                Button {
                    selectedNodeID = node.id
                    navigateToNote(node)
                } label: {
                    VStack(alignment: .leading) {
                        Text(node.title)
                        if node.connectionCount > 0 {
                            Text(String(localized: "\(node.connectionCount) connections", bundle: .module))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel(node.title)
                .accessibilityHint(node.connectionCount > 0
                    ? String(localized: "\(node.connectionCount) connections. Double tap to open.", bundle: .module)
                    : String(localized: "No connections. Double tap to open.", bundle: .module))
            }
        }
    }

    // MARK: - Navigation Helper

    /// Navigates to a note via the onSelectNote callback AND the wiki-link notification system.
    /// This ensures both modal (sheet) and embedded (workspace) presentations route correctly.
    private func navigateToNote(_ node: GraphNode) {
        QuartzFeedback.primaryAction()
        onSelectNote?(node.url)
        // Also post the wiki-link navigation notification for embedded workspace routing
        NotificationCenter.default.post(
            name: .quartzWikiLinkNavigation,
            object: nil,
            userInfo: ["url": node.url, "title": node.title]
        )
    }

    private var graphAccessibilityLabel: String {
        let nodeCount = viewModel.nodes.count
        let edgeCount = viewModel.edges.count
        if let currentID = viewModel.currentNoteID,
           let currentNode = viewModel.nodes.first(where: { $0.id == currentID }) {
            let connectedCount = viewModel.connectedNodeIDs.count
            return String(localized: "Knowledge graph with \(nodeCount) notes and \(edgeCount) connections. Current note: \(currentNode.title) with \(connectedCount) linked notes.", bundle: .module)
        }
        return String(localized: "Knowledge graph with \(nodeCount) notes and \(edgeCount) connections.", bundle: .module)
    }

    // MARK: - Embedded Header (macOS 26 toolbar crash workaround)

    private var embeddedHeader: some View {
        VStack(spacing: 2) {
            Text(String(localized: "Knowledge Graph", bundle: .module))
                .font(.headline)
            if !viewModel.nodes.isEmpty {
                Text("\(viewModel.nodes.count) \(String(localized: "nodes", bundle: .module))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = viewModel.graphTruncationNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .quartzAmbientGlassBackground(style: .editorChrome)
    }
}

// MARK: - Graph Toolbar Modifier

/// A horizontal line shape for drawing dashed strokes in the legend.
private struct StrokeDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Conditionally applies toolbar items and searchable only when NOT embedded in the workspace.
/// macOS 26 beta crashes (EXC_BREAKPOINT in NSToolbar._insertNewItemWithItemIdentifier)
/// when toolbar items change across conditional branches in NavigationSplitView's detail column.
private struct GraphToolbarModifier: ViewModifier {
    let viewModel: GraphViewModel
    @Binding var searchText: String
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        if isEmbedded {
            // No toolbar items — header is rendered inline to avoid NSToolbar crash
            content
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(String(localized: "Graph View", bundle: .module))
                                .font(.headline)
                            if !viewModel.nodes.isEmpty {
                                Text("\(viewModel.nodes.count) \(String(localized: "nodes", bundle: .module))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: Text(String(localized: "Search knowledge…", bundle: .module)))
        }
    }
}
