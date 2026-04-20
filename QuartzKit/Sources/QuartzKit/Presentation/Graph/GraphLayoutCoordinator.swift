import CoreGraphics
import Foundation

public struct GraphViewportState: Sendable, Equatable {
    public let zoom: CGFloat
    public let pan: CGSize

    public init(zoom: CGFloat, pan: CGSize) {
        self.zoom = zoom
        self.pan = pan
    }
}

public enum GraphCoverageMode: String, CaseIterable, Sendable {
    case recent
    case fullVault

    public var label: String {
        switch self {
        case .recent:
            return String(localized: "Recent 280", bundle: .module)
        case .fullVault:
            return String(localized: "Full Vault", bundle: .module)
        }
    }

    public var shortLabel: String {
        switch self {
        case .recent:
            return String(localized: "Recent", bundle: .module)
        case .fullVault:
            return String(localized: "Full vault", bundle: .module)
        }
    }
}

enum GraphLayoutCoordinator {
    static func seededLayout(
        nodes: [GraphNode],
        edges: [GraphEdge],
        currentNoteID: String?,
        preservedPositions: [String: CGPoint]
    ) -> [GraphNode] {
        guard !nodes.isEmpty else { return [] }

        let nodeIDs = nodes.map(\.id)
        let nodeIDSet = Set(nodeIDs)
        let adjacency = adjacencyMap(nodeIDs: nodeIDs, edges: edges)
        let degrees = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, adjacency[$0, default: []].count) })
        let components = connectedComponents(nodeIDs: nodeIDs, adjacency: adjacency, currentNoteID: currentNoteID)
        let componentCenters = centeredGrid(componentCount: components.count, totalNodeCount: nodes.count)

        var resolvedPositions = preservedPositions

        for (componentIndex, component) in components.enumerated() {
            let anchoredPoints = component.compactMap { resolvedPositions[$0] }
            let componentCenter = anchoredPoints.isEmpty
                ? componentCenters[componentIndex]
                : centroid(of: anchoredPoints)

            let orderedNodes = component.sorted { lhs, rhs in
                if lhs == currentNoteID { return true }
                if rhs == currentNoteID { return false }
                let lhsDegree = degrees[lhs, default: 0]
                let rhsDegree = degrees[rhs, default: 0]
                if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
                return lhs < rhs
            }

            let missingNodeIDs = orderedNodes.filter { resolvedPositions[$0] == nil }
            guard !missingNodeIDs.isEmpty else { continue }

            let baseRadius = max(52, min(180, 28 + sqrt(CGFloat(max(component.count, 1))) * 22))
            let anchorAngle = stableFraction(for: orderedNodes.first ?? "\(componentIndex)") * .pi * 2

            for (missingIndex, nodeID) in missingNodeIDs.enumerated() {
                let neighborPoints = adjacency[nodeID, default: []]
                    .filter { nodeIDSet.contains($0) }
                    .compactMap { resolvedPositions[$0] }
                let localCenter = neighborPoints.isEmpty ? componentCenter : centroid(of: neighborPoints)

                let position: CGPoint
                if anchoredPoints.isEmpty && missingIndex == 0 {
                    position = localCenter
                } else {
                    let ring = ringIndex(forSequentialIndex: missingIndex)
                    let slotInRing = slotIndex(forSequentialIndex: missingIndex)
                    let slotsInRing = max(1, ring * 6)
                    let angle = anchorAngle
                        + (CGFloat(slotInRing) / CGFloat(slotsInRing)) * .pi * 2
                        + stableFraction(for: nodeID) * 0.35
                    let radius = baseRadius * CGFloat(max(ring, 1))
                    position = CGPoint(
                        x: localCenter.x + cos(angle) * radius,
                        y: localCenter.y + sin(angle) * radius
                    )
                }

                resolvedPositions[nodeID] = position
            }
        }

        return nodes.map { node in
            guard let position = resolvedPositions[node.id] else { return node }
            var updated = node
            updated.x = position.x
            updated.y = position.y
            updated.vx = 0
            updated.vy = 0
            return updated
        }
    }

    static func preferredViewport(
        for nodes: [GraphNode],
        in size: CGSize,
        padding: CGFloat = 72,
        minZoom: CGFloat = 0.32,
        maxZoom: CGFloat = 1.35
    ) -> GraphViewportState {
        guard !nodes.isEmpty, size.width > 0, size.height > 0 else {
            return GraphViewportState(zoom: 1, pan: .zero)
        }

        let minX = nodes.map(\.x).min() ?? 0
        let maxX = nodes.map(\.x).max() ?? 0
        let minY = nodes.map(\.y).min() ?? 0
        let maxY = nodes.map(\.y).max() ?? 0
        let contentWidth = max(160, maxX - minX + padding * 2)
        let contentHeight = max(160, maxY - minY + padding * 2)

        let fitZoom = min(size.width / contentWidth, size.height / contentHeight)
        let zoom = min(maxZoom, max(minZoom, fitZoom))
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2

        return GraphViewportState(
            zoom: zoom,
            pan: CGSize(width: -midX * zoom, height: -midY * zoom)
        )
    }

    private static func adjacencyMap(nodeIDs: [String], edges: [GraphEdge]) -> [String: Set<String>] {
        let nodeSet = Set(nodeIDs)
        var adjacency: [String: Set<String>] = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, []) })

        for edge in edges {
            guard nodeSet.contains(edge.from), nodeSet.contains(edge.to) else { continue }
            adjacency[edge.from, default: []].insert(edge.to)
            adjacency[edge.to, default: []].insert(edge.from)
        }

        return adjacency
    }

    private static func connectedComponents(
        nodeIDs: [String],
        adjacency: [String: Set<String>],
        currentNoteID: String?
    ) -> [[String]] {
        var remaining = Set(nodeIDs)
        var components: [[String]] = []

        while let start = remaining.first {
            var queue = [start]
            var index = 0
            var component: [String] = []
            remaining.remove(start)

            while index < queue.count {
                let nodeID = queue[index]
                index += 1
                component.append(nodeID)

                for neighbor in adjacency[nodeID, default: []] where remaining.contains(neighbor) {
                    remaining.remove(neighbor)
                    queue.append(neighbor)
                }
            }

            components.append(component)
        }

        return components.sorted { lhs, rhs in
            let lhsContainsCurrent = currentNoteID.map(lhs.contains) ?? false
            let rhsContainsCurrent = currentNoteID.map(rhs.contains) ?? false
            if lhsContainsCurrent != rhsContainsCurrent { return lhsContainsCurrent }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs.min() ?? "") < (rhs.min() ?? "")
        }
    }

    private static func centeredGrid(componentCount: Int, totalNodeCount: Int) -> [CGPoint] {
        guard componentCount > 0 else { return [] }

        let columns = Int(ceil(sqrt(Double(componentCount))))
        let rows = Int(ceil(Double(componentCount) / Double(columns)))
        let spacing = max(260, min(620, 180 + sqrt(CGFloat(max(totalNodeCount, 1))) * 24))

        return (0..<componentCount).map { index in
            let row = index / columns
            let column = index % columns
            let x = (CGFloat(column) - CGFloat(columns - 1) / 2) * spacing
            let y = (CGFloat(row) - CGFloat(rows - 1) / 2) * spacing * 0.88
            return CGPoint(x: x, y: y)
        }
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let total = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: total.x / CGFloat(points.count),
            y: total.y / CGFloat(points.count)
        )
    }

    private static func ringIndex(forSequentialIndex index: Int) -> Int {
        guard index > 0 else { return 0 }
        var remaining = index - 1
        var ring = 1
        while remaining >= ring * 6 {
            remaining -= ring * 6
            ring += 1
        }
        return ring
    }

    private static func slotIndex(forSequentialIndex index: Int) -> Int {
        guard index > 0 else { return 0 }
        var remaining = index - 1
        var ring = 1
        while remaining >= ring * 6 {
            remaining -= ring * 6
            ring += 1
        }
        return remaining
    }

    private static func stableFraction(for value: String) -> CGFloat {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let bucket = hash % 10_000
        return CGFloat(bucket) / 10_000
    }
}
