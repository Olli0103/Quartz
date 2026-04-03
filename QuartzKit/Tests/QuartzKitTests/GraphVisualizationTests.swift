import Testing
import Foundation
import CoreGraphics
@testable import QuartzKit

// MARK: - Graph Visualization Model Tests

@Suite("GraphVisualization")
struct GraphVisualizationTests {

    @Test("GraphNode, GraphEdge models and GraphLayoutPolicy constants")
    func graphModelsAndPolicy() {
        // GraphNode construction and Equatable
        let nodeA = GraphNode(
            id: "a", title: "Note A",
            url: URL(fileURLWithPath: "/vault/a.md"),
            tags: ["tag1", "tag2"],
            x: 10, y: 20,
            connectionCount: 3
        )
        #expect(nodeA.id == "a")
        #expect(nodeA.title == "Note A")
        #expect(nodeA.tags.count == 2)
        #expect(nodeA.connectionCount == 3)
        #expect(nodeA.isConcept == false)

        // Equatable ignores velocity
        var nodeA2 = GraphNode(
            id: "a", title: "Note A",
            url: URL(fileURLWithPath: "/vault/a.md"),
            x: 10, y: 20,
            connectionCount: 3
        )
        nodeA2.vx = 999
        nodeA2.vy = -999
        #expect(nodeA == nodeA2) // velocity ignored in ==

        // Different position = not equal
        let nodeA3 = GraphNode(
            id: "a", title: "Note A",
            url: URL(fileURLWithPath: "/vault/a.md"),
            x: 99, y: 20,
            connectionCount: 3
        )
        #expect(nodeA != nodeA3)

        // GraphEdge
        let edge = GraphEdge(from: "a", to: "b", isSemantic: false)
        #expect(edge.id == "a->b")
        #expect(edge.from == "a")
        #expect(edge.to == "b")
        #expect(edge.isSemantic == false)
        #expect(edge.isConcept == false)

        let semanticEdge = GraphEdge(from: "a", to: "c", isSemantic: true)
        #expect(semanticEdge.isSemantic == true)

        // GraphLayoutPolicy
        #expect(GraphLayoutPolicy.maxNodesPerGraph == 280)
        #expect(GraphLayoutPolicy.semanticLinkingMaxNodes == 200)
    }
}
