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

    private let fileTree: [FileNode]
    private let currentNoteURL: URL?
    private let vaultRootURL: URL?
    private let vaultProvider: (any VaultProviding)?
    private let onSelectNote: ((URL) -> Void)?

    /// Light cream background per design (#FDFBF8).
    private static let graphBackgroundColor = Color(hex: 0xFDFBF8)

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
            .fill(Self.graphBackgroundColor)
            .ignoresSafeArea()
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
            HStack(spacing: 8) {
                ForEach(["#philosophy", "#systems"], id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            }
            Button {
                onSelectNote?(node.url)
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
        }
        .padding(16)
        .frame(maxWidth: 200, alignment: .leading)
        .quartzMaterialBackground(cornerRadius: 16, shadowRadius: 16)
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
                            ? QuartzColors.canvasPurple.opacity(0.25)
                            : Color.gray.opacity(0.25)
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
                        selectedNodeID = tapped.id
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
    }
}
