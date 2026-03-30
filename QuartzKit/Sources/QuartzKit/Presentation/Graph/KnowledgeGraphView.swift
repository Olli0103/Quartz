import SwiftUI

// MARK: - Graph Data Structures

/// A node in the knowledge graph representing a single note.
public struct GraphNode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public var tags: [String]
    public var x: CGFloat
    public var y: CGFloat
    public var vx: CGFloat = 0
    public var vy: CGFloat = 0
    public var connectionCount: Int = 0

    public init(id: String, title: String, url: URL, tags: [String] = [], x: CGFloat = 0, y: CGFloat = 0, vx: CGFloat = 0, vy: CGFloat = 0, connectionCount: Int = 0) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = tags
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.connectionCount = connectionCount
    }
}

/// An edge in the knowledge graph connecting two notes.
public struct GraphEdge: Identifiable, Sendable {
    public let id: String
    public let from: String
    public let to: String
    public let isSemantic: Bool

    public init(from: String, to: String, isSemantic: Bool = false) {
        self.id = "\(from)->\(to)"
        self.from = from
        self.to = to
        self.isSemantic = isSemantic
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
    public var edges: [GraphEdge] = []
    public var isLoading = true
    public var currentNoteID: String?
    /// Non-nil when the vault had more notes than ``GraphLayoutPolicy/maxNodesPerGraph`` and the graph was capped.
    public var graphTruncationNote: String?

    private let linkExtractor = WikiLinkExtractor()
    private var nodeIndex: [String: Int] = [:]

    public init() {}

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
        let attractionStrength: CGFloat = 0.008
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

        // Attraction
        for edge in edges {
            guard let iFrom = nodeIndex[edge.from],
                  let iTo = nodeIndex[edge.to] else { continue }
            let dx = nodes[iTo].x - nodes[iFrom].x
            let dy = nodes[iTo].y - nodes[iFrom].y
            let fx = dx * attractionStrength
            let fy = dy * attractionStrength
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
        var nameToID: [String: String] = [:]
        var urlToTags: [URL: [String]] = [:]
        var urlToLinks: [URL: [WikiLink]] = [:]

        if let provider = vaultProvider {
            await withTaskGroup(of: (URL, [String], [WikiLink]).self) { group in
                for note in allNotes {
                    group.addTask { [linkExtractor] in
                        do {
                            let doc = try await provider.readNote(at: note.url)
                            let links = linkExtractor.extractLinks(from: doc.body)
                            return (note.url, doc.frontmatter.tags, links)
                        } catch {
                            return (note.url, [], [])
                        }
                    }
                }
                for await (url, tags, links) in group {
                    urlToTags[url] = tags
                    urlToLinks[url] = links
                }
            }
        }

        for note in allNotes {
            let nodeID = note.url.absoluteString
            let displayName = note.name.replacingOccurrences(of: ".md", with: "")
            let randomX = CGFloat.random(in: -200...200)
            let randomY = CGFloat.random(in: -200...200)
            let tags = urlToTags[note.url] ?? []
            builtNodes.append(GraphNode(
                id: nodeID,
                title: displayName,
                url: note.url,
                tags: tags,
                x: randomX,
                y: randomY
            ))
            nameToID[displayName.lowercased()] = nodeID
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
                    let targetName = link.target.lowercased()
                    if let targetID = nameToID[targetName] {
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

    // MARK: - Force-Directed Layout

    /// Runs a simplified force-directed layout to position nodes.
    /// Uses spatial hashing for repulsion (neighboring grid cells) so large graphs stay responsive; iterations scale down with node count.
    public func layoutGraph(iterations: Int? = nil) {
        guard nodes.count > 1 else { return }

        let iterations = iterations ?? GraphLayoutPolicy.layoutIterations(forNodeCount: nodes.count)
        guard iterations > 0 else { return }

        let n = nodes.count
        let repulsionStrength: CGFloat = 6000
        let attractionStrength: CGFloat = 0.008
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

            // Attraction along edges (Hooke's law)
            for edge in edges {
                guard let iFrom = nodeIndex[edge.from],
                      let iTo = nodeIndex[edge.to] else { continue }
                let dx = nodes[iTo].x - nodes[iFrom].x
                let dy = nodes[iTo].y - nodes[iFrom].y
                let fx = dx * attractionStrength
                let fy = dy * attractionStrength
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
        if node.id == currentNoteID { return 14 }
        if node.connectionCount > 0 { return max(6, min(12, CGFloat(node.connectionCount) * 2 + 4)) }
        return 5
    }

    /// Returns the color for a node based on its relationship to the current note.
    public func nodeColor(for node: GraphNode) -> Color {
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
        isEmbedded: Bool = false
    ) {
        self.fileTree = fileTree
        self.currentNoteURL = currentNoteURL
        self.vaultRootURL = vaultRootURL
        self.vaultProvider = vaultProvider
        self.embeddingService = embeddingService
        self.onSelectNote = onSelectNote
        self.isEmbedded = isEmbedded
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
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ACTIVE NODE", bundle: .module))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(node.title)
                .font(.headline.weight(.bold))
            Text(String(localized: "Note in your vault", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .accessibilityHint(node.tags.isEmpty
            ? String(localized: "Double tap Open Note to view", bundle: .module)
            : String(localized: "Tags: \(node.tags.prefix(3).joined(separator: ", ")). Double tap Open Note to view", bundle: .module))
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

                // Draw edges
                for edge in viewModel.edges {
                    guard let fromNode = viewModel.nodes.first(where: { $0.id == edge.from }),
                          let toNode = viewModel.nodes.first(where: { $0.id == edge.to }) else { continue }

                    let fromPos = viewModel.nodePosition(fromNode, in: canvasSize).applying(transform)
                    let toPos = viewModel.nodePosition(toNode, in: canvasSize).applying(transform)

                    var path = Path()
                    path.move(to: fromPos)
                    path.addLine(to: toPos)

                    let isHighlightedEdge = viewModel.currentNoteID != nil &&
                        (edge.from == viewModel.currentNoteID || edge.to == viewModel.currentNoteID)
                    let edgeColor: Color = isHighlightedEdge
                        ? QuartzColors.accent.opacity(0.5)
                        : edge.isSemantic
                            ? QuartzColors.canvasPurple.opacity(0.6)
                            : Color.gray.opacity(0.25)
                    let lineWidth: CGFloat = isHighlightedEdge ? 1.5 : (edge.isSemantic ? 1.2 : 0.8)
                    let strokeStyle: StrokeStyle = edge.isSemantic
                        ? StrokeStyle(lineWidth: lineWidth, dash: [6, 4])
                        : StrokeStyle(lineWidth: lineWidth)

                    if edge.isSemantic {
                        context.stroke(path, with: .color(QuartzColors.canvasPurple.opacity(0.25)), lineWidth: lineWidth + 2)
                    }
                    context.stroke(path, with: .color(edgeColor), style: strokeStyle)
                }

                // Draw nodes
                for node in viewModel.nodes {
                    let pos = viewModel.nodePosition(node, in: canvasSize).applying(transform)
                    let radius = viewModel.nodeRadius(for: node) * zoom
                    let color = viewModel.nodeColor(for: node)
                    let isCurrentNote = node.id == viewModel.currentNoteID

                    // Glow effect for current note
                    if isCurrentNote {
                        let glowRadius = radius * 2.5
                        let glowRect = CGRect(
                            x: pos.x - glowRadius,
                            y: pos.y - glowRadius,
                            width: glowRadius * 2,
                            height: glowRadius * 2
                        )
                        context.fill(
                            Circle().path(in: glowRect),
                            with: .color(QuartzColors.accent.opacity(0.2))
                        )
                    }

                    let nodeRect = CGRect(
                        x: pos.x - radius,
                        y: pos.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Circle().path(in: nodeRect),
                        with: .color(color)
                    )

                    // Border for hovered/selected node
                    if node.id == hoveredNodeID || node.id == selectedNodeID {
                        context.stroke(
                            Circle().path(in: nodeRect.insetBy(dx: -2, dy: -2)),
                            with: .color(QuartzColors.accent.opacity(0.8)),
                            lineWidth: 2
                        )
                    }

                    // Labels for significant nodes
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
