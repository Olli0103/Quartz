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
        #expect(GraphCoverageMode.recent.label == "Recent 280")
        #expect(GraphCoverageMode.fullVault.label == "Full Vault")
    }

    @MainActor
    @Test("Coverage mode exposes recent subset and full-vault graph truthfully")
    func coverageModeIsTruthfulAndControllable() async {
        let notes = (0..<320).map { index in
            FileNode(
                name: "Note-\(index).md",
                url: URL(fileURLWithPath: "/vault/Note-\(index).md"),
                nodeType: .note,
                metadata: FileMetadata(modifiedAt: Date(timeIntervalSince1970: Double(320 - index)))
            )
        }

        let recentViewModel = GraphViewModel()
        await recentViewModel.buildGraph(
            fileTree: notes,
            currentNoteURL: nil,
            vaultRootURL: nil,
            vaultProvider: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: false,
            coverageMode: .recent
        )
        #expect(recentViewModel.totalNoteCount == 320)
        #expect(recentViewModel.displayedNoteCount == GraphLayoutPolicy.maxNodesPerGraph)
        #expect(recentViewModel.graphTruncationNote?.contains("Recent mode") == true)

        let fullViewModel = GraphViewModel()
        await fullViewModel.buildGraph(
            fileTree: notes,
            currentNoteURL: nil,
            vaultRootURL: nil,
            vaultProvider: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: false,
            coverageMode: .fullVault
        )
        #expect(fullViewModel.totalNoteCount == 320)
        #expect(fullViewModel.displayedNoteCount == 320)
        #expect(fullViewModel.graphTruncationNote?.contains("Showing all 320 notes") == true)
    }

    @MainActor
    @Test("First uncached graph build uses deterministic layout without live shake")
    func firstBuildIsDeterministicWithoutLiveSimulation() async {
        let noteA = URL(fileURLWithPath: "/vault/A.md")
        let noteB = URL(fileURLWithPath: "/vault/B.md")
        let noteC = URL(fileURLWithPath: "/vault/C.md")
        let store = GraphEdgeStore()
        await store.updateExplicitReferences(
            for: noteA,
            references: [
                ExplicitNoteReference(
                    sourceNoteURL: noteA,
                    targetNoteURL: noteB,
                    targetNoteName: "B",
                    insertableTarget: "B",
                    rawLinkText: "B",
                    rawTargetText: "B",
                    displayText: "B",
                    headingFragment: nil,
                    matchRange: nil,
                    lineRange: nil,
                    context: "A -> B"
                )
            ]
        )
        await store.updateExplicitReferences(
            for: noteB,
            references: [
                ExplicitNoteReference(
                    sourceNoteURL: noteB,
                    targetNoteURL: noteC,
                    targetNoteName: "C",
                    insertableTarget: "C",
                    rawLinkText: "C",
                    rawTargetText: "C",
                    displayText: "C",
                    headingFragment: nil,
                    matchRange: nil,
                    lineRange: nil,
                    context: "B -> C"
                )
            ]
        )

        let fileTree = [
            FileNode(name: "A.md", url: noteA, nodeType: .note),
            FileNode(name: "B.md", url: noteB, nodeType: .note),
            FileNode(name: "C.md", url: noteC, nodeType: .note)
        ]

        let first = GraphViewModel()
        first.graphEdgeStore = store
        await first.buildGraph(
            fileTree: fileTree,
            currentNoteURL: noteA,
            vaultRootURL: nil,
            vaultProvider: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: false,
            coverageMode: .fullVault
        )

        let second = GraphViewModel()
        second.graphEdgeStore = store
        await second.buildGraph(
            fileTree: fileTree,
            currentNoteURL: noteA,
            vaultRootURL: nil,
            vaultProvider: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: false,
            coverageMode: .fullVault
        )

        let firstPositions = Dictionary(uniqueKeysWithValues: first.nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
        let secondPositions = Dictionary(uniqueKeysWithValues: second.nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })

        #expect(firstPositions == secondPositions)
        #expect(first.isSimulating == false)
        #expect(second.isSimulating == false)
    }

    @MainActor
    @Test("Graph rebuild keeps existing node positions stable when late concept state arrives")
    func rebuildPreservesExistingPositionsForExistingNodes() async {
        let noteA = URL(fileURLWithPath: "/vault/A.md")
        let noteB = URL(fileURLWithPath: "/vault/B.md")
        let store = GraphEdgeStore()
        await store.updateExplicitReferences(
            for: noteA,
            references: [
                ExplicitNoteReference(
                    sourceNoteURL: noteA,
                    targetNoteURL: noteB,
                    targetNoteName: "B",
                    insertableTarget: "B",
                    rawLinkText: "B",
                    rawTargetText: "B",
                    displayText: "B",
                    headingFragment: nil,
                    matchRange: nil,
                    lineRange: nil,
                    context: "A -> B"
                )
            ]
        )

        let viewModel = GraphViewModel()
        viewModel.graphEdgeStore = store
        let fileTree = [
            FileNode(name: "A.md", url: noteA, nodeType: .note),
            FileNode(name: "B.md", url: noteB, nodeType: .note)
        ]

        await viewModel.buildGraph(
            fileTree: fileTree,
            currentNoteURL: noteA,
            vaultRootURL: nil,
            vaultProvider: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: true,
            coverageMode: .fullVault
        )

        let initialPositions = Dictionary(uniqueKeysWithValues: viewModel.nodes.filter { !$0.isConcept }.map {
            ($0.id, CGPoint(x: $0.x, y: $0.y))
        })

        await store.updateConcepts(for: noteA, concepts: ["swift"])
        await store.updateConcepts(for: noteB, concepts: ["swift"])

        await viewModel.buildGraph(
            fileTree: fileTree,
            currentNoteURL: noteA,
            vaultRootURL: nil,
            vaultProvider: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: true,
            coverageMode: .fullVault
        )

        for node in viewModel.nodes where !node.isConcept {
            #expect(initialPositions[node.id] == CGPoint(x: node.x, y: node.y))
        }
        #expect(viewModel.nodes.contains(where: { $0.isConcept && $0.id == "concept:swift" }))
    }
}
