import Testing
import Foundation
@testable import QuartzKit

@Suite("Knowledge graph consumer convergence")
struct KnowledgeGraphConsumerConvergenceTests {

    @MainActor
    @Test("Graph view consumes authoritative explicit and related-note state from the shared store")
    func graphViewConsumesCanonicalExplicitAndSemanticState() async {
        let noteA = URL(fileURLWithPath: "/vault/Alpha.md")
        let noteB = URL(fileURLWithPath: "/vault/Beta.md")
        let store = GraphEdgeStore()

        await store.updateExplicitReferences(
            for: noteA,
            references: [
                ExplicitNoteReference(
                    sourceNoteURL: noteA,
                    targetNoteURL: noteB,
                    targetNoteName: "Beta",
                    insertableTarget: "Beta",
                    rawLinkText: "Beta",
                    rawTargetText: "Beta",
                    displayText: "Beta",
                    headingFragment: nil,
                    matchRange: NSRange(location: 8, length: 8),
                    lineRange: NSRange(location: 0, length: 20),
                    context: "See [[Beta]]"
                )
            ]
        )
        await store.updateSemanticConnections(for: noteA, related: [noteB])

        let viewModel = GraphViewModel()
        viewModel.graphEdgeStore = store

        await viewModel.buildGraph(
            fileTree: [
                FileNode(name: "Alpha.md", url: noteA, nodeType: .note),
                FileNode(name: "Beta.md", url: noteB, nodeType: .note)
            ],
            currentNoteURL: noteA,
            vaultRootURL: nil,
            vaultProvider: nil,
            embeddingService: nil,
            relatedNotesSimilarityEnabled: true,
            aiConceptExtractionEnabled: false
        )

        let explicitEdges = viewModel.edges.filter { !$0.isSemantic && !$0.isConcept }
        #expect(explicitEdges.count == 1)
        #expect(Set([explicitEdges[0].from, explicitEdges[0].to]) == Set([noteA.absoluteString, noteB.absoluteString]))

        let semanticEdges = viewModel.edges.filter(\.isSemantic)
        #expect(semanticEdges.count == 1)
        #expect(Set([semanticEdges[0].from, semanticEdges[0].to]) == Set([noteA.absoluteString, noteB.absoluteString]))
    }

    @MainActor
    @Test("Graph view concept hubs consume canonical AI concept state from the shared store")
    func graphViewConsumesCanonicalConceptState() async {
        let noteA = URL(fileURLWithPath: "/vault/Alpha.md")
        let noteB = URL(fileURLWithPath: "/vault/Beta.md")
        let store = GraphEdgeStore()

        await store.updateConcepts(for: noteA, concepts: ["swift"])
        await store.updateConcepts(for: noteB, concepts: ["swift"])

        let viewModel = GraphViewModel()
        viewModel.graphEdgeStore = store

        await viewModel.buildGraph(
            fileTree: [
                FileNode(name: "Alpha.md", url: noteA, nodeType: .note),
                FileNode(name: "Beta.md", url: noteB, nodeType: .note)
            ],
            currentNoteURL: noteA,
            vaultRootURL: nil,
            vaultProvider: nil,
            embeddingService: nil,
            relatedNotesSimilarityEnabled: false,
            aiConceptExtractionEnabled: true
        )

        #expect(viewModel.nodes.contains(where: { $0.isConcept && $0.id == "concept:swift" }))
        #expect(viewModel.edges.filter(\.isConcept).count == 2)
        #expect(viewModel.edges.filter(\.isSemantic).isEmpty)
    }
}
