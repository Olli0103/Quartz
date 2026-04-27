import SwiftUI

// MARK: - Graph Data Structures

/// A node in the knowledge graph representing a note or an AI-extracted concept hub.
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
    /// Skip graph-view similarity edges above this count (avoids O(n) embedding similarity work).
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
    public private(set) var totalNoteCount = 0
    public private(set) var displayedNoteCount = 0
    public private(set) var activeCoverageMode: GraphCoverageMode = .recent
    public private(set) var buildVersion = 0
    /// Optional reference to the shared canonical relationship store used by the
    /// inspector and by graph-view convergence for explicit links, related notes,
    /// and AI concepts.
    public var graphEdgeStore: GraphEdgeStore?
    private var nodeIndex: [String: Int] = [:]

    static let semanticEdgeLegendTitle = "Related-note similarity"
    static let semanticEdgeCountSuffix = "related-note similarity links"
    static let conceptEdgeLegendTitle = "AI concept links"
    static let conceptEdgeCountSuffix = "AI concept links"

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

            // Attraction: stronger for explicit wiki-links, softer for similarity edges,
            // with separate weight for AI concept hub edges.
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

    /// Builds the graph from canonical relationship state plus cached layout positions.
    /// KG6 keeps graph view as a consumer of authoritative explicit, related-note,
    /// and AI-concept state rather than a competing parser/rebuilder.
    public func buildGraph(
        fileTree: [FileNode],
        currentNoteURL: URL?,
        vaultRootURL: URL?,
        vaultProvider: (any VaultProviding)?,
        embeddingService: VectorEmbeddingService? = nil,
        relatedNotesSimilarityEnabled: Bool = true,
        aiConceptExtractionEnabled: Bool = true,
        coverageMode: GraphCoverageMode = .recent
    ) async {
        let buildStarted = Date()
        isLoading = true
        graphTruncationNote = nil
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .graph,
            name: "graphBuildStarted",
            reasonCode: "graph.buildStarted",
            vaultName: vaultRootURL?.lastPathComponent,
            metadata: ["coverageMode": coverageMode.rawValue]
        )

        let collected = collectNotes(from: fileTree)
        totalNoteCount = collected.count
        activeCoverageMode = coverageMode
        guard !collected.isEmpty else {
            displayedNoteCount = 0
            isLoading = false
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .graph,
                name: "graphBuildFinished",
                reasonCode: "graph.partialData",
                durationMs: Date().timeIntervalSince(buildStarted) * 1_000,
                counts: ["totalVaultNotes": 0, "displayedNoteNodes": 0],
                metadata: ["coverageMode": coverageMode.rawValue, "status.graph": "empty"]
            )
            return
        }

        let allNotes = selectNotesForGraph(
            collected,
            coverageMode: coverageMode,
            limit: GraphLayoutPolicy.maxNodesPerGraph,
            currentNoteURL: currentNoteURL
        )
        displayedNoteCount = allNotes.count
        if collected.count > allNotes.count {
            graphTruncationNote = String(
                localized: "Showing \(allNotes.count) of \(collected.count) notes in Recent mode. Switch to Full Vault to render every note.",
                bundle: .module
            )
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .graph,
                name: "graphCoverageCapped",
                reasonCode: "graph.coverageCapped",
                counts: [
                    "totalVaultNotes": collected.count,
                    "displayedNoteNodes": allNotes.count,
                    "hiddenNoteNodes": collected.count - allNotes.count
                ],
                metadata: ["coverageMode": coverageMode.rawValue, "capReason": "recent cap"]
            )
        } else {
            graphTruncationNote = String(
                localized: "Showing all \(collected.count) notes in the vault.",
                bundle: .module
            )
        }

        let noteURLs = allNotes.map { CanonicalNoteIdentity.canonicalFileURL(for: $0.url) }
        let fullVaultNoteURLs = collected.map { CanonicalNoteIdentity.canonicalFileURL(for: $0.url) }

        let graphCache: GraphCache? = vaultRootURL.map { GraphCache(vaultRoot: $0) }
        let graphViewFingerprint = graphCache?.computeFingerprint(for: noteURLs)
        let relationshipFingerprint = graphCache?.computeFingerprint(for: fullVaultNoteURLs)
        let cachedGraphView: GraphCache.CachedGraph.CachedGraphViewSnapshot?
        if let graphCache, let graphViewFingerprint {
            cachedGraphView = graphCache.loadGraphViewSnapshotIfValid(fingerprint: graphViewFingerprint)
        } else {
            cachedGraphView = nil
        }
        let cachedNodeLayouts = Dictionary(
            uniqueKeysWithValues: (cachedGraphView?.nodes ?? []).map { ($0.id, $0) }
        )
        let liveNodeLayouts = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) }
        )

        let fallbackExplicitReferences: [ExplicitNoteReference]
        if let graphCache, let relationshipFingerprint {
            fallbackExplicitReferences =
                graphCache.loadExplicitRelationshipSnapshotIfValid(fingerprint: relationshipFingerprint)?.references
                ?? []
        } else {
            fallbackExplicitReferences = []
        }

        let fallbackSemanticConnections: [URL: [URL]]
        if let graphCache,
           let relationshipFingerprint,
           let snapshot = graphCache.loadSemanticRelationshipSnapshotIfValid(fingerprint: relationshipFingerprint) {
            fallbackSemanticConnections = Dictionary(
                uniqueKeysWithValues: snapshot.relations.map { relation in
                    (
                        CanonicalNoteIdentity.canonicalFileURL(for: relation.sourceURL),
                        relation.targetURLs.map(CanonicalNoteIdentity.canonicalFileURL(for:))
                    )
                }
            )
        } else {
            fallbackSemanticConnections = [:]
        }

        var builtNodes: [GraphNode] = []
        var builtEdges: [GraphEdge] = []
        var hasCompletePreservedLayout = !allNotes.isEmpty

        for note in allNotes {
            let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: note.url)
            let nodeID = canonicalURL.absoluteString
            let displayName = note.name.replacingOccurrences(of: ".md", with: "")
            let cachedNode = cachedNodeLayouts[nodeID]
            let livePosition = liveNodeLayouts[nodeID]
            let tags = note.frontmatter?.tags ?? cachedNode?.tags ?? []
            builtNodes.append(GraphNode(
                id: nodeID,
                title: displayName,
                url: canonicalURL,
                tags: tags,
                x: livePosition?.x ?? cachedNode?.x ?? 0,
                y: livePosition?.y ?? cachedNode?.y ?? 0
            ))
            if livePosition == nil && cachedNode == nil {
                hasCompletePreservedLayout = false
            }
        }

        currentNoteID = currentNoteURL.map(CanonicalNoteIdentity.canonicalFileURL(for:))?.absoluteString

        let validNodeIDs = Set(builtNodes.map(\.id))

        let explicitReferences: [ExplicitNoteReference]
        if let graphEdgeStore {
            explicitReferences = await graphEdgeStore.allExplicitReferences()
        } else {
            explicitReferences = fallbackExplicitReferences
        }
        builtEdges.append(contentsOf: explicitGraphEdges(from: explicitReferences, validNodeIDs: validNodeIDs))

        if relatedNotesSimilarityEnabled {
            let semanticConnections: [URL: [URL]]
            if let graphEdgeStore {
                semanticConnections = await graphEdgeStore.allSemanticConnections()
            } else {
                semanticConnections = fallbackSemanticConnections
            }
            builtEdges.append(contentsOf: semanticGraphEdges(from: semanticConnections, validNodeIDs: validNodeIDs))
        }

        var connectionCounts: [String: Int] = [:]
        for edge in builtEdges {
            connectionCounts[edge.from, default: 0] += 1
            connectionCounts[edge.to, default: 0] += 1
        }
        for i in builtNodes.indices {
            builtNodes[i].connectionCount = connectionCounts[builtNodes[i].id, default: 0]
        }

        builtNodes = GraphLayoutCoordinator.seededLayout(
            nodes: builtNodes,
            edges: builtEdges,
            currentNoteID: currentNoteID,
            preservedPositions: liveNodeLayouts.merging(
                Dictionary(uniqueKeysWithValues: cachedNodeLayouts.map { ($0.key, CGPoint(x: $0.value.x, y: $0.value.y)) })
            ) { live, _ in live }
        )

        nodes = builtNodes
        edges = builtEdges
        rebuildNodeIndex()

        // Add concept hub nodes from the canonical AI concept store.
        if aiConceptExtractionEnabled {
            await addConceptHubNodes(
                cachedNodeLayouts: cachedNodeLayouts,
                liveNodeLayouts: liveNodeLayouts
            )
        }

        rebuildNodeIndex()
        if !hasCompletePreservedLayout {
            let layoutStarted = Date()
            SubsystemDiagnostics.record(
                level: .debug,
                subsystem: .graph,
                name: "graphLayoutStarted",
                reasonCode: "graph.layoutStarted",
                counts: ["nodes": nodes.count, "edges": edges.count],
                verbose: true
            )
            layoutGraph(iterations: min(32, GraphLayoutPolicy.layoutIterations(forNodeCount: nodes.count)))
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .graph,
                name: "graphLayoutStable",
                reasonCode: "graph.layoutStable",
                durationMs: Date().timeIntervalSince(layoutStarted) * 1_000,
                counts: ["nodes": nodes.count, "edges": edges.count],
                metadata: ["status.graphLayout": "stable"]
            )
        }
        stopSimulation()

        // Persist graph-view layout only; relationship truth stays in the shared store/cache owners.
        if let cache = graphCache, let graphViewFingerprint {
            let cached = GraphCache.CachedGraph.CachedGraphViewSnapshot(
                fingerprint: graphViewFingerprint,
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
                semanticEdges: [],
                conceptEdges: []
            )
            try? cache.saveGraphViewSnapshot(cached)
        }

        isLoading = false
        buildVersion &+= 1
        let explicitEdges = edges.filter { !$0.isSemantic && !$0.isConcept }.count
        let semanticEdges = edges.filter(\.isSemantic).count
        let conceptEdges = edges.filter(\.isConcept).count
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .graph,
            name: "graphBuildFinished",
            reasonCode: "graph.buildFinished",
            durationMs: Date().timeIntervalSince(buildStarted) * 1_000,
            counts: [
                "totalVaultNotes": totalNoteCount,
                "displayedNoteNodes": displayedNoteCount,
                "hiddenNoteNodes": max(0, totalNoteCount - displayedNoteCount),
                "conceptNodes": nodes.filter(\.isConcept).count,
                "explicitEdges": explicitEdges,
                "semanticEdges": semanticEdges,
                "conceptEdges": conceptEdges
            ],
            generation: UInt64(buildVersion),
            metadata: [
                "coverageMode": coverageMode.rawValue,
                "status.graph": "ready",
                "layoutStatus": hasCompletePreservedLayout ? "cachedPositionsUsed" : "stabilized"
            ]
        )
        SubsystemDiagnostics.updateState(
            subsystem: .graph,
            values: [
                "lastGraphBuildStatus": "ready",
                "coverageMode": coverageMode.rawValue,
                "displayedNotes": String(displayedNoteCount),
                "totalNotes": String(totalNoteCount),
                "explicitEdges": String(explicitEdges),
                "semanticEdges": String(semanticEdges),
                "conceptEdges": String(conceptEdges),
                "layoutStatus": hasCompletePreservedLayout ? "cachedPositionsUsed" : "stable"
            ]
        )
    }

    private func rebuildNodeIndex() {
        nodeIndex = [:]
        for (i, node) in nodes.enumerated() {
            nodeIndex[node.id] = i
        }
    }

    // MARK: - Concept Hub Nodes

    /// Reads significant concepts from the canonical edge store and adds them as hub nodes + edges.
    /// Concept nodes are positioned at the centroid of their connected note nodes.
    private func addConceptHubNodes(
        cachedNodeLayouts: [String: GraphCache.CachedGraph.CachedNode] = [:],
        liveNodeLayouts: [String: CGPoint] = [:]
    ) async {
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
            let cachedConceptNode = cachedNodeLayouts[conceptID]
            let liveConceptPosition = liveNodeLayouts[conceptID]
            let posX = liveConceptPosition?.x ?? cachedConceptNode?.x ?? (count > 0 ? cx / count : 0)
            let posY = liveConceptPosition?.y ?? cachedConceptNode?.y ?? (count > 0 ? cy / count : 0)

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

                // Attraction along edges: stronger for explicit wiki-links, softer for
                // similarity edges, with separate weight for AI concept hub edges.
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
    private func selectNotesForGraph(
        _ notes: [FileNode],
        coverageMode: GraphCoverageMode,
        limit: Int,
        currentNoteURL: URL?
    ) -> [FileNode] {
        guard coverageMode == .recent else {
            return notes.sorted { lhs, rhs in
                if lhs.metadata.modifiedAt != rhs.metadata.modifiedAt {
                    return lhs.metadata.modifiedAt > rhs.metadata.modifiedAt
                }
                return lhs.url.absoluteString < rhs.url.absoluteString
            }
        }
        guard notes.count > limit else { return notes }
        let sorted = notes.sorted {
            if $0.metadata.modifiedAt != $1.metadata.modifiedAt {
                return $0.metadata.modifiedAt > $1.metadata.modifiedAt
            }
            return $0.url.absoluteString < $1.url.absoluteString
        }
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
        return neighboringNodeIDs(for: currentID)
    }

    public func neighboringNodeIDs(for nodeID: String) -> Set<String> {
        var connected = Set<String>()
        for edge in edges {
            if edge.from == nodeID { connected.insert(edge.to) }
            if edge.to == nodeID { connected.insert(edge.from) }
        }
        return connected
    }

    public func preferredViewport(in size: CGSize, nodeIDs: Set<String>? = nil) -> GraphViewportState {
        let visibleNodes: [GraphNode]
        if let nodeIDs {
            visibleNodes = nodes.filter { nodeIDs.contains($0.id) }
        } else {
            visibleNodes = nodes
        }
        return GraphLayoutCoordinator.preferredViewport(for: visibleNodes, in: size)
    }

    private func explicitGraphEdges(
        from references: [ExplicitNoteReference],
        validNodeIDs: Set<String>
    ) -> [GraphEdge] {
        var seen = Set<String>()
        var edges: [GraphEdge] = []
        for reference in references {
            let sourceID = reference.sourceNoteURL.absoluteString
            let targetID = reference.targetNoteURL.absoluteString
            guard validNodeIDs.contains(sourceID), validNodeIDs.contains(targetID), sourceID != targetID else {
                continue
            }
            let key = [sourceID, targetID].sorted().joined(separator: "<->")
            guard seen.insert(key).inserted else { continue }
            edges.append(GraphEdge(from: sourceID, to: targetID))
        }
        return edges
    }

    private func semanticGraphEdges(
        from relationsBySource: [URL: [URL]],
        validNodeIDs: Set<String>
    ) -> [GraphEdge] {
        var seen = Set<String>()
        var edges: [GraphEdge] = []

        for sourceURL in relationsBySource.keys.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let sourceID = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL).absoluteString
            guard validNodeIDs.contains(sourceID) else { continue }

            for targetURL in relationsBySource[sourceURL, default: []] {
                let targetID = CanonicalNoteIdentity.canonicalFileURL(for: targetURL).absoluteString
                guard validNodeIDs.contains(targetID), targetID != sourceID else { continue }

                let key = [sourceID, targetID].sorted().joined(separator: "<->")
                guard seen.insert(key).inserted else { continue }
                edges.append(GraphEdge(from: sourceID, to: targetID, isSemantic: true))
            }
        }

        return edges
    }

}

// MARK: - Knowledge Graph View

/// Graph filter options matching the design.
public enum GraphFilterOption: String, CaseIterable {
    case all
    case neighborhood
    case connected
    case isolated

    var label: String {
        switch self {
        case .all: String(localized: "All Nodes", bundle: .module)
        case .neighborhood: String(localized: "Focus", bundle: .module)
        case .connected: String(localized: "Connected", bundle: .module)
        case .isolated: String(localized: "Isolated", bundle: .module)
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
    @State private var coverageMode: GraphCoverageMode = .recent
    @State private var lastMagnification: CGFloat = 1.0
    @State private var relatedNotesSimilarityEnabled = KnowledgeAnalysisSettings.relatedNotesSimilarityEnabled()
    @State private var aiConceptExtractionEnabled = KnowledgeAnalysisSettings.aiConceptExtractionEnabled()
    @State private var relationshipRefreshToken = 0
    @State private var viewportResetToken = 0
    @State private var refreshDebounceTask: Task<Void, Never>?
    @State private var hasAppliedAutomaticViewport = false

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

            if !viewModel.isLoading && !viewModel.nodes.isEmpty {
                // Bottom filter bar
                filterBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                // Zoom controls (bottom-right)
                zoomControls
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

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
        .task(id: "\(currentNoteURL?.absoluteString ?? "none")-\(fileTree.count)-\(relatedNotesSimilarityEnabled)-\(aiConceptExtractionEnabled)-\(relationshipRefreshToken)-\(coverageMode.rawValue)") {
            viewModel.graphEdgeStore = graphEdgeStoreRef
            await viewModel.buildGraph(
                fileTree: fileTree,
                currentNoteURL: currentNoteURL,
                vaultRootURL: vaultRootURL,
                vaultProvider: vaultProvider,
                embeddingService: embeddingService,
                relatedNotesSimilarityEnabled: relatedNotesSimilarityEnabled,
                aiConceptExtractionEnabled: aiConceptExtractionEnabled,
                coverageMode: effectiveCoverageMode
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzReferenceGraphDidChange)) { notification in
            guard graphNotificationBelongsToCurrentVault(notification) else { return }
            scheduleGraphRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzRelatedNotesUpdated)) { notification in
            guard graphNotificationBelongsToCurrentVault(notification) else { return }
            scheduleGraphRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzConceptsUpdated)) { notification in
            guard graphNotificationBelongsToCurrentVault(notification) else { return }
            scheduleGraphRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let updatedRelatedNotesSetting = KnowledgeAnalysisSettings.relatedNotesSimilarityEnabled()
            let updatedAIConceptSetting = KnowledgeAnalysisSettings.aiConceptExtractionEnabled()
            if relatedNotesSimilarityEnabled != updatedRelatedNotesSetting {
                relatedNotesSimilarityEnabled = updatedRelatedNotesSetting
            }
            if aiConceptExtractionEnabled != updatedAIConceptSetting {
                aiConceptExtractionEnabled = updatedAIConceptSetting
            }
        }
        .onChange(of: coverageMode) { _, _ in
            hasAppliedAutomaticViewport = false
            if let selectedNodeID, !renderedNodeIDs.contains(selectedNodeID) {
                self.selectedNodeID = nil
            }
        }
        .onChange(of: activeFilter) { _, _ in
            hasAppliedAutomaticViewport = false
            if let selectedNodeID, !renderedNodeIDs.contains(selectedNodeID) {
                self.selectedNodeID = nil
            }
        }
        .onChange(of: currentNoteURL?.absoluteString) { _, _ in
            hasAppliedAutomaticViewport = false
        }
        .onDisappear {
            refreshDebounceTask?.cancel()
            viewModel.stopSimulation()
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
        let hardLinks = viewModel.edges.filter { !$0.isSemantic && !$0.isConcept && ($0.from == node.id || $0.to == node.id) }.count
        let semanticLinks = viewModel.edges.filter { $0.isSemantic && ($0.from == node.id || $0.to == node.id) }.count
        let conceptLinks = viewModel.edges.filter { $0.isConcept && ($0.from == node.id || $0.to == node.id) }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ACTIVE NODE", bundle: .module))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if node.isConcept {
                Text(String(localized: "AI concept", bundle: .module))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
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
                        Text(String(localized: "\(semanticLinks) related", bundle: .module))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if conceptLinks > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(QuartzColors.folderYellow)
                            .frame(width: 6, height: 6)
                        Text(String(localized: "\(conceptLinks) AI concepts", bundle: .module))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if hardLinks == 0 && semanticLinks == 0 && conceptLinks == 0 {
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
            if !node.isConcept {
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
        .accessibilityLabel(
            node.isConcept
                ? String(localized: "Selected AI concept: \(node.title)", bundle: .module)
                : String(localized: "Selected note: \(node.title)", bundle: .module)
        )
        .accessibilityHint(
            node.isConcept
                ? String(localized: "\(conceptLinks) AI concept links.", bundle: .module)
                : String(localized: "\(hardLinks) wiki-links, \(semanticLinks) related-note similarity links, \(conceptLinks) AI concept links. Double tap Open Note to view.", bundle: .module)
        )
    }

    private var totalAvailableNoteCount: Int {
        countNotes(in: fileTree)
    }

    private var effectiveCoverageMode: GraphCoverageMode {
        totalAvailableNoteCount > GraphLayoutPolicy.maxNodesPerGraph ? coverageMode : .fullVault
    }

    private var focusAnchorNodeID: String? {
        selectedNodeID ?? viewModel.currentNoteID
    }

    private var emphasizedNodeIDs: Set<String> {
        guard let anchor = focusAnchorNodeID else { return [] }
        return viewModel.neighboringNodeIDs(for: anchor).union([anchor])
    }

    private var renderedNodeIDs: Set<String> {
        let baseIDs: Set<String>
        switch activeFilter {
        case .all:
            baseIDs = Set(viewModel.nodes.map(\.id))
        case .neighborhood:
            if let anchor = focusAnchorNodeID {
                baseIDs = viewModel.neighboringNodeIDs(for: anchor).union([anchor])
            } else {
                baseIDs = Set(viewModel.nodes.map(\.id))
            }
        case .connected:
            baseIDs = Set(viewModel.nodes.filter { $0.connectionCount > 0 || $0.id == viewModel.currentNoteID }.map(\.id))
        case .isolated:
            baseIDs = Set(viewModel.nodes.filter { !$0.isConcept && $0.connectionCount == 0 }.map(\.id))
        }

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseIDs
        }

        let matches = Set(viewModel.nodes.compactMap { node in
            node.title.localizedCaseInsensitiveContains(searchText) ? node.id : nil
        })
        guard !matches.isEmpty else { return baseIDs }
        let neighborhoodMatches = matches.reduce(into: matches) { partial, nodeID in
            partial.formUnion(viewModel.neighboringNodeIDs(for: nodeID))
        }
        return baseIDs.intersection(neighborhoodMatches)
    }

    private var renderedNodes: [GraphNode] {
        viewModel.nodes.filter { renderedNodeIDs.contains($0.id) }
    }

    private var renderedHardEdges: [GraphEdge] {
        viewModel.hardEdges.filter { renderedNodeIDs.contains($0.from) && renderedNodeIDs.contains($0.to) }
    }

    private var renderedSemanticEdges: [GraphEdge] {
        viewModel.semanticEdges.filter { renderedNodeIDs.contains($0.from) && renderedNodeIDs.contains($0.to) }
    }

    private var coverageSummaryText: String {
        if effectiveCoverageMode == .fullVault || viewModel.displayedNoteCount >= viewModel.totalNoteCount {
            return String(
                localized: "\(viewModel.displayedNoteCount) of \(viewModel.totalNoteCount) notes • Full vault",
                bundle: .module
            )
        }

        return String(
            localized: "\(viewModel.displayedNoteCount) of \(viewModel.totalNoteCount) notes • Recent subset",
            bundle: .module
        )
    }

    private func scheduleGraphRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            relationshipRefreshToken &+= 1
        }
    }

    private func applyAutomaticViewport(in size: CGSize) {
        guard !hasAppliedAutomaticViewport else { return }
        let viewport = viewModel.preferredViewport(
            in: size,
            nodeIDs: renderedNodeIDs.isEmpty ? nil : renderedNodeIDs
        )
        zoom = viewport.zoom
        pan = viewport.pan
        dragOffset = .zero
        lastMagnification = 1
        hasAppliedAutomaticViewport = true
    }

    private func countNotes(in nodes: [FileNode]) -> Int {
        nodes.reduce(into: 0) { total, node in
            if node.isNote { total += 1 }
            if let children = node.children {
                total += countNotes(in: children)
            }
        }
    }

    private func graphNotificationBelongsToCurrentVault(_ notification: Notification) -> Bool {
        guard let vaultRootURL else { return true }

        if let updatedVaultRoot = notification.userInfo?["vaultRootURL"] as? URL {
            return updatedVaultRoot.standardizedFileURL == vaultRootURL.standardizedFileURL
        }

        if let updatedURL = notification.object as? URL {
            return CanonicalNoteIdentity
                .canonicalFileURL(for: updatedURL)
                .path(percentEncoded: false)
                .hasPrefix(vaultRootURL.standardizedFileURL.path(percentEncoded: false))
        }

        return true
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if totalAvailableNoteCount > GraphLayoutPolicy.maxNodesPerGraph {
                Picker(
                    String(localized: "Graph coverage", bundle: .module),
                    selection: $coverageMode
                ) {
                    ForEach(GraphCoverageMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(coverageSummaryText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let note = viewModel.graphTruncationNote,
               effectiveCoverageMode == .recent {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ForEach(GraphFilterOption.allCases, id: \.self) { option in
                    filterButton(option: option)
                }
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
        .accessibilityValue(isSelected
            ? String(localized: "Active", bundle: .module)
            : String(localized: "Inactive", bundle: .module))
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
            .accessibilityInputLabels([Text("Zoom in"), Text("Plus")])
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
            .accessibilityInputLabels([Text("Zoom out"), Text("Minus")])
            Button {
                withAnimation {
                    hasAppliedAutomaticViewport = false
                    viewportResetToken &+= 1
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
                    .quartzMaterialCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Reset view", bundle: .module))
            .accessibilityInputLabels([Text("Reset view"), Text("Reset"), Text("Center")])
        }
    }

    // MARK: - Edge Legend

    private var edgeLegend: some View {
        let hardCount = renderedHardEdges.filter { !$0.isConcept }.count
        let semanticCount = renderedSemanticEdges.count
        let conceptCount = viewModel.edges.filter {
            $0.isConcept && renderedNodeIDs.contains($0.from) && renderedNodeIDs.contains($0.to)
        }.count

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
                    Text(String(localized: "\(GraphViewModel.semanticEdgeLegendTitle) (\(semanticCount))", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if conceptCount > 0 {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(QuartzColors.folderYellow.opacity(0.85))
                        .frame(width: 20, height: 1.5)
                    Text(String(localized: "\(GraphViewModel.conceptEdgeLegendTitle) (\(conceptCount))", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .quartzFloatingUltraThinSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "\(hardCount) wiki-links, \(semanticCount) \(GraphViewModel.semanticEdgeCountSuffix), \(conceptCount) \(GraphViewModel.conceptEdgeCountSuffix)",
                bundle: .module
            )
        )
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
                let focusedNodeIDs = emphasizedNodeIDs
                let hasFocusedSelection = selectedNodeID != nil && !focusedNodeIDs.isEmpty

                // Draw edges — hard links first (behind), then related-note similarity edges (on top with glow)
                for edge in renderedHardEdges {
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
                    let focusOpacity: Double
                    if hasFocusedSelection {
                        focusOpacity = focusedNodeIDs.contains(edge.from) && focusedNodeIDs.contains(edge.to) ? 1 : 0.14
                    } else {
                        focusOpacity = 1
                    }
                    let edgeColor: Color = isHighlighted
                        ? QuartzColors.accent.opacity(0.6)
                        : Color.secondary.opacity(0.4 * focusOpacity)
                    let lineWidth: CGFloat = isHighlighted ? 1.8 : 0.8
                    context.stroke(path, with: .color(edgeColor), lineWidth: lineWidth)
                }

                for edge in renderedSemanticEdges {
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
                    let focusOpacity: Double
                    if hasFocusedSelection {
                        focusOpacity = focusedNodeIDs.contains(edge.from) && focusedNodeIDs.contains(edge.to) ? 1 : 0.12
                    } else {
                        focusOpacity = 1
                    }
                    let edgeColor: Color = isHighlighted
                        ? QuartzColors.canvasPurple.opacity(0.7)
                        : QuartzColors.canvasPurple.opacity(0.35 * focusOpacity)
                    let lineWidth: CGFloat = isHighlighted ? 1.6 : 1.0

                    // Soft glow behind semantic edges
                    context.stroke(path, with: .color(QuartzColors.canvasPurple.opacity(0.12 * focusOpacity)), lineWidth: lineWidth + 3)
                    context.stroke(path, with: .color(edgeColor), style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
                }

                // Draw nodes
                for node in renderedNodes {
                    let pos = viewModel.nodePosition(node, in: canvasSize).applying(transform)
                    let radius = viewModel.nodeRadius(for: node) * zoom
                    let color = viewModel.nodeColor(for: node)
                    let isCurrentNote = node.id == viewModel.currentNoteID
                    let isSelected = node.id == hoveredNodeID || node.id == selectedNodeID
                    let isEmphasized = focusedNodeIDs.contains(node.id) || !hasFocusedSelection
                    let nodeOpacity: Double = isEmphasized ? 1 : 0.24

                    if node.isConcept {
                        // Concept hub: diamond shape with golden glow
                        let glowRadius = radius * 2.0
                        let glowRect = CGRect(x: pos.x - glowRadius, y: pos.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                        context.fill(Circle().path(in: glowRect), with: .color(QuartzColors.folderYellow.opacity(0.12 * nodeOpacity)))

                        // Diamond shape (45-degree rotated square)
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: pos.x, y: pos.y - radius))
                        diamond.addLine(to: CGPoint(x: pos.x + radius, y: pos.y))
                        diamond.addLine(to: CGPoint(x: pos.x, y: pos.y + radius))
                        diamond.addLine(to: CGPoint(x: pos.x - radius, y: pos.y))
                        diamond.closeSubpath()

                        context.fill(diamond, with: .color(color.opacity(nodeOpacity)))
                        context.stroke(diamond, with: .color(color.opacity(0.5 * nodeOpacity)), lineWidth: 1.0)

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
                                .foregroundColor(QuartzColors.folderYellow.opacity(nodeOpacity)),
                            at: CGPoint(x: pos.x, y: pos.y + radius + 10 * zoom)
                        )
                    } else {
                        // Note node: standard circle

                        // Glow effect for current note
                        if isCurrentNote {
                            let glowRadius = radius * 2.5
                            let glowRect = CGRect(x: pos.x - glowRadius, y: pos.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                            context.fill(Circle().path(in: glowRect), with: .color(QuartzColors.accent.opacity(0.15 * nodeOpacity)))
                        }

                        // Glass-like outer ring for connected or selected nodes
                        if node.connectionCount > 0 || isSelected {
                            let ringRadius = radius + 2.5 * zoom
                            let ringRect = CGRect(x: pos.x - ringRadius, y: pos.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
                            context.stroke(Circle().path(in: ringRect), with: .color(color.opacity(0.3 * nodeOpacity)), lineWidth: 1.0)
                        }

                        // Node fill
                        let nodeRect = CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Circle().path(in: nodeRect), with: .color(color.opacity(nodeOpacity)))

                        // Accent border for hovered/selected node
                        if isSelected {
                            context.stroke(Circle().path(in: nodeRect.insetBy(dx: -2, dy: -2)), with: .color(QuartzColors.accent.opacity(0.8)), lineWidth: 2)
                        }

                    // Labels for significant note nodes
                    let showLabel = isCurrentNote ||
                        focusedNodeIDs.contains(node.id) ||
                        node.id == hoveredNodeID ||
                        node.id == selectedNodeID ||
                        (zoom > 1.5 && node.connectionCount > 0) ||
                        zoom > 2.5

                    if showLabel {
                        let labelColor: Color = isCurrentNote
                            ? QuartzColors.accent
                            : Color.primary.opacity(isEmphasized ? 0.85 : 0.35)
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
                        hasAppliedAutomaticViewport = true
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
                        hasAppliedAutomaticViewport = true
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
                        if selectedNodeID == tapped.id, !tapped.isConcept {
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
            .onAppear {
                applyAutomaticViewport(in: size)
            }
            .onChange(of: viewModel.buildVersion) { _, _ in
                applyAutomaticViewport(in: size)
            }
            .onChange(of: activeFilter) { _, _ in
                applyAutomaticViewport(in: size)
            }
            .onChange(of: coverageMode) { _, _ in
                applyAutomaticViewport(in: size)
            }
            .onChange(of: viewportResetToken) { _, _ in
                applyAutomaticViewport(in: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(graphAccessibilityLabel)
        .accessibilityHint(String(localized: "Use the node list below for VoiceOver navigation", bundle: .module))
        .accessibilityRepresentation {
            // Provide a list-based alternative for VoiceOver users
            List(viewModel.nodes) { node in
                Button {
                    selectedNodeID = node.id
                    if !node.isConcept {
                        navigateToNote(node)
                    }
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
                .accessibilityHint(
                    node.isConcept
                        ? String(localized: "\(node.connectionCount) AI concept connections. Double tap to inspect.", bundle: .module)
                        : (node.connectionCount > 0
                            ? String(localized: "\(node.connectionCount) connections. Double tap to open.", bundle: .module)
                            : String(localized: "No connections. Double tap to open.", bundle: .module))
                )
            }
        }
    }

    // MARK: - Navigation Helper

    /// Navigates to a note via the onSelectNote callback AND the wiki-link notification system.
    /// This ensures both modal (sheet) and embedded (workspace) presentations route correctly.
    private func navigateToNote(_ node: GraphNode) {
        guard !node.isConcept else { return }
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
        let noteCount = viewModel.nodes.filter { !$0.isConcept }.count
        let conceptCount = viewModel.nodes.filter(\.isConcept).count
        let explicitEdgeCount = viewModel.edges.filter { !$0.isSemantic && !$0.isConcept }.count
        let similarityEdgeCount = viewModel.edges.filter(\.isSemantic).count
        let conceptEdgeCount = viewModel.edges.filter(\.isConcept).count
        let coveragePrefix: String
        if effectiveCoverageMode == .recent && viewModel.totalNoteCount > noteCount {
            coveragePrefix = String(
                localized: "Knowledge graph showing \(noteCount) of \(viewModel.totalNoteCount) notes in Recent mode, ",
                bundle: .module
            )
        } else {
            coveragePrefix = String(
                localized: "Knowledge graph with \(noteCount) notes, ",
                bundle: .module
            )
        }
        if let currentID = viewModel.currentNoteID,
           let currentNode = viewModel.nodes.first(where: { $0.id == currentID }) {
            let connectedCount = viewModel.connectedNodeIDs.count
            return coveragePrefix + String(
                localized: "\(conceptCount) AI concepts, \(explicitEdgeCount) wiki-links, \(similarityEdgeCount) related-note similarity links, and \(conceptEdgeCount) AI concept links. Current note: \(currentNode.title) with \(connectedCount) directly connected notes.",
                bundle: .module
            )
        }
        return coveragePrefix + String(
            localized: "\(conceptCount) AI concepts, \(explicitEdgeCount) wiki-links, \(similarityEdgeCount) related-note similarity links, and \(conceptEdgeCount) AI concept links.",
            bundle: .module
        )
    }

    // MARK: - Embedded Header (macOS 26 toolbar crash workaround)

    private var embeddedHeader: some View {
        VStack(spacing: 2) {
            Text(String(localized: "Knowledge Graph", bundle: .module))
                .font(.headline)
            if !viewModel.nodes.isEmpty {
                Text(coverageSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = viewModel.graphTruncationNote,
               effectiveCoverageMode == .recent {
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
