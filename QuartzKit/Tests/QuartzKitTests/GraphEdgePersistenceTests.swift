import Testing
import Foundation
import CoreGraphics
@testable import QuartzKit

// MARK: - Graph Edge Persistence Tests

@Suite("GraphEdgePersistence")
struct GraphEdgePersistenceTests {

    @Test("loadExplicitRelationshipSnapshot populates edges and reverseEdges")
    func loadExplicitRelationshipSnapshotPopulates() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        let snapshot = GraphCache.CachedGraph.CachedExplicitRelationshipSnapshot(
            fingerprint: "abc123",
            references: [
                ExplicitNoteReference(
                    sourceNoteURL: noteA,
                    targetNoteURL: noteB,
                    targetNoteName: "b",
                    insertableTarget: "b",
                    rawLinkText: "b",
                    rawTargetText: "b",
                    displayText: "b",
                    headingFragment: nil,
                    matchRange: NSRange(location: 4, length: 5),
                    lineRange: NSRange(location: 0, length: 9),
                    context: "See [[b]]"
                )
            ]
        )

        await store.loadExplicitRelationshipSnapshot(snapshot)

        let forwardA = await store.edges[noteA] ?? []
        #expect(forwardA.contains(noteB))

        let backlinksB = await store.backlinks(for: noteB)
        #expect(backlinksB.contains(noteA))

        let explicitBacklinks = await store.explicitBacklinks(to: noteB)
        #expect(explicitBacklinks.count == 1)
        #expect(explicitBacklinks.first?.matchRange == NSRange(location: 4, length: 5))
    }

    @Test("exportExplicitRelationshipSnapshot returns canonical explicit references only")
    func exportExplicitSnapshot() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")
        let noteC = URL(fileURLWithPath: "/vault/c.md")

        await store.updateExplicitReferences(
            for: noteA,
            references: [
                ExplicitNoteReference(
                    sourceNoteURL: noteA,
                    targetNoteURL: noteB,
                    targetNoteName: "b",
                    insertableTarget: "b",
                    rawLinkText: "b",
                    rawTargetText: "b",
                    displayText: "Alias",
                    headingFragment: "Heading",
                    matchRange: NSRange(location: 12, length: 7),
                    lineRange: NSRange(location: 0, length: 20),
                    context: "Link to [[b|Alias]]"
                )
            ]
        )
        await store.updateSemanticConnections(for: noteA, related: [noteC])

        let exported = await store.exportExplicitRelationshipSnapshot(fingerprint: "def456")
        #expect(exported.fingerprint == "def456")
        #expect(exported.references.count == 1)
        #expect(exported.references.first?.targetNoteURL == noteB)
        #expect(exported.references.first?.headingFragment == "Heading")
    }

    @Test("Empty explicit graph produces valid empty snapshot")
    func emptyExplicitGraph() async {
        let store = GraphEdgeStore()
        let exported = await store.exportExplicitRelationshipSnapshot(fingerprint: "empty")
        #expect(exported.fingerprint == "empty")
        #expect(exported.references.isEmpty)
    }

    @Test("Semantic similarity snapshot round-trips through the live store")
    func semanticSnapshotRoundTrip() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        await store.updateSemanticConnections(for: noteA, related: [noteB])
        let exported = await store.exportSemanticRelationshipSnapshot(fingerprint: "semantic")

        #expect(exported.fingerprint == "semantic")
        #expect(exported.relations.count == 1)
        #expect(exported.relations.first?.sourceURL == noteA)
        #expect(exported.relations.first?.targetURLs == [noteB])

        let reloadedStore = GraphEdgeStore()
        await reloadedStore.loadSemanticRelationshipSnapshot(exported)
        let related = await reloadedStore.semanticRelations(for: noteA)
        #expect(related == [noteB])
    }
}
