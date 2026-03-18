import SwiftUI

// MARK: - Graph Data Structures

/// A node in the knowledge graph representing a single note.
public struct GraphNode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public var x: CGFloat
    public var y: CGFloat
    public var vx: CGFloat = 0
    public var vy: CGFloat = 0
    public var connectionCount: Int = 0

    public init(id: String, title: String, url: URL, x: CGFloat = 0, y: CGFloat = 0) {
        self.id = id
        self.title = title
        self.url = url
        self.x = x
        self.y = y
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

@Observable
@MainActor
public final class GraphViewModel {
    public var nodes: [GraphNode] = []
    public var edges: [GraphEdge] = []
    public var isLoading = true
    public var currentNoteID: String?

    private let linkExtractor = WikiLinkExtractor()
    private var nodeIndex: [String: Int] = [:]

    public init() {}

    /// Builds the graph from a file tree and the currently selected note.
    public func buildGraph(
        fileTree: [FileNode],
        currentNoteURL: URL?,
        vaultRootURL: URL?,
        vaultProvider: (any VaultProviding)?
    ) async {
        isLoading = true

        let allNotes = collectNotes(from: fileTree)
        guard !allNotes.isEmpty else {
            isLoading = false
            return
        }

        var builtNodes: [GraphNode] = []
        var builtEdges: [GraphEdge] = []
        var nameToID: [String: String] = [:]

        for note in allNotes {
            let nodeID = note.url.absoluteString
            let displayName = note.name.replacingOccurrences(of: ".md", with: "")
            let randomX = CGFloat.random(in: -200...200)
            let randomY = CGFloat.random(in: -200...200)
            builtNodes.append(GraphNode(
                id: nodeID,
                title: displayName,
                url: note.url,
                x: randomX,
                y: randomY
            ))
            nameToID[displayName.lowercased()] = nodeID
        }

        if let currentURL = currentNoteURL {
            currentNoteID = currentURL.absoluteString
        }

        var edgeSet = Set<String>()

        if let provider = vaultProvider {
            await withTaskGroup(of: (String, [WikiLink]).self) { group in
                for note in allNotes {
                    let nodeID = note.url.absoluteString
                    group.addTask { [linkExtractor] in
                        do {
                            let doc = try await provider.readNote(at: note.url)
                            let links = linkExtractor.extractLinks(from: doc.body)
                            return (nodeID, links)
                        } catch {
                            return (nodeID, [])
                        }
                    }
                }

                for await (sourceID, links) in group {
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
        layoutGraph()
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
    public func layoutGraph(iterations: Int = 120) {
        guard nodes.count > 1 else { return }

        let repulsionStrength: CGFloat = 6000
        let attractionStrength: CGFloat = 0.008
        let damping: CGFloat = 0.85
        let centerGravity: CGFloat = 0.01

        for _ in 0..<iterations {
            // Repulsion between all pairs (Coulomb's law)
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let dx = nodes[i].x - nodes[j].x
                    let dy = nodes[i].y - nodes[j].y
                    let distSq = dx * dx + dy * dy
                    let dist = max(sqrt(distSq), 1)
                    let force = repulsionStrength / (dist * dist)
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force
                    nodes[i].vx += fx
                    nodes[i].vy += fy
                    nodes[j].vx -= fx
                    nodes[j].vy -= fy
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
        return Color.gray.opacity(0.5)
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

/// Interactive force-directed graph visualization of vault notes and their connections.
public struct KnowledgeGraphView: View {
    @State private var viewModel = GraphViewModel()
    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredNodeID: String?

    private let fileTree: [FileNode]
    private let currentNoteURL: URL?
    private let vaultRootURL: URL?
    private let vaultProvider: (any VaultProviding)?
    private let onSelectNote: ((URL) -> Void)?

    public init(
        fileTree: [FileNode],
        currentNoteURL: URL?,
        vaultRootURL: URL?,
        vaultProvider: (any VaultProviding)?,
        onSelectNote: ((URL) -> Void)? = nil
    ) {
        self.fileTree = fileTree
        self.currentNoteURL = currentNoteURL
        self.vaultRootURL = vaultRootURL
        self.vaultProvider = vaultProvider
        self.onSelectNote = onSelectNote
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
        }
        .navigationTitle(String(localized: "Knowledge Graph", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done", bundle: .module)) {
                    // Dismiss handled by parent
                }
            }
        }
        .task {
            await viewModel.buildGraph(
                fileTree: fileTree,
                currentNoteURL: currentNoteURL,
                vaultRootURL: vaultRootURL,
                vaultProvider: vaultProvider
            )
        }
    }

    // MARK: - Background

    private var graphBackground: some View {
        Rectangle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.95),
                    ],
                    center: .center,
                    startRadius: 100,
                    endRadius: 500
                )
            )
            .ignoresSafeArea()
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.orange)
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
                        ? .orange.opacity(0.4)
                        : edge.isSemantic
                            ? Color.purple.opacity(0.2)
                            : Color.white.opacity(0.12)
                    let lineWidth: CGFloat = isHighlightedEdge ? 1.5 : 0.8

                    context.stroke(path, with: .color(edgeColor), lineWidth: lineWidth)
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
                            with: .color(.orange.opacity(0.15))
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

                    // Border for hovered node
                    if node.id == hoveredNodeID {
                        context.stroke(
                            Circle().path(in: nodeRect.insetBy(dx: -2, dy: -2)),
                            with: .color(.white.opacity(0.6)),
                            lineWidth: 1.5
                        )
                    }

                    // Labels for significant nodes
                    let showLabel = isCurrentNote ||
                        viewModel.connectedNodeIDs.contains(node.id) ||
                        node.id == hoveredNodeID ||
                        (zoom > 1.5 && node.connectionCount > 0) ||
                        zoom > 2.5

                    if showLabel {
                        let labelColor: Color = isCurrentNote ? .orange : .white.opacity(0.8)
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
                        zoom = max(0.3, min(5.0, value.magnification))
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
                    onSelectNote?(tapped.url)
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

            // Legend overlay
            graphLegend
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Stats overlay
            graphStats
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    // MARK: - Legend

    private var graphLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendItem(color: .orange, label: String(localized: "Current Note", bundle: .module))
            legendItem(color: QuartzColors.noteBlue, label: String(localized: "Linked Notes", bundle: .module))
            legendItem(color: QuartzColors.canvasPurple.opacity(0.7), label: String(localized: "Other Connected", bundle: .module))
            legendItem(color: .gray.opacity(0.5), label: String(localized: "Unlinked Notes", bundle: .module))
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats

    private var graphStats: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(viewModel.nodes.count) notes")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(viewModel.edges.count) links")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
