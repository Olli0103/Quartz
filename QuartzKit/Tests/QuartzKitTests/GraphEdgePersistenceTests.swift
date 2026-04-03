import Testing
import Foundation
import CoreGraphics
@testable import QuartzKit

// MARK: - Graph Edge Persistence Tests

@Suite("GraphEdgePersistence")
struct GraphEdgePersistenceTests {

    @Test("loadFromCache populates edges and reverseEdges")
    func loadFromCachePopulates() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        let cached = GraphCache.CachedGraph(
            nodes: [
                .init(id: noteA.absoluteString, title: "A", url: noteA, x: 0, y: 0, connectionCount: 1, tags: nil),
                .init(id: noteB.absoluteString, title: "B", url: noteB, x: 10, y: 10, connectionCount: 1, tags: nil)
            ],
            edges: [
                .init(from: noteA.absoluteString, to: noteB.absoluteString, isSemantic: false)
            ],
            fingerprint: "abc123"
        )

        await store.loadFromCache(cached, allVaultURLs: [noteA, noteB])

        let forwardA = await store.edges[noteA] ?? []
        #expect(forwardA.contains(noteB))

        let backlinksB = await store.backlinks(for: noteB)
        #expect(backlinksB.contains(noteA))
    }

    @Test("exportForCache returns all edges including semantic")
    func exportRoundTrip() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")
        let noteC = URL(fileURLWithPath: "/vault/c.md")

        // Load wiki-link edge A→B and semantic edge A→C
        let cached = GraphCache.CachedGraph(
            nodes: [
                .init(id: noteA.absoluteString, title: "A", url: noteA, x: 0, y: 0, connectionCount: 2, tags: nil),
                .init(id: noteB.absoluteString, title: "B", url: noteB, x: 10, y: 0, connectionCount: 1, tags: nil),
                .init(id: noteC.absoluteString, title: "C", url: noteC, x: 0, y: 10, connectionCount: 1, tags: nil)
            ],
            edges: [
                .init(from: noteA.absoluteString, to: noteB.absoluteString, isSemantic: false),
                .init(from: noteA.absoluteString, to: noteC.absoluteString, isSemantic: true)
            ],
            fingerprint: "def456"
        )

        await store.loadFromCache(cached, allVaultURLs: [noteA, noteB, noteC])

        let exported = await store.exportForCache()
        #expect(exported.count == 2)

        let wikiLinks = exported.filter { !$0.isSemantic }
        let semantics = exported.filter { $0.isSemantic }
        #expect(wikiLinks.count == 1)
        #expect(semantics.count == 1)
    }

    @Test("Empty graph produces valid empty export")
    func emptyGraph() async {
        let store = GraphEdgeStore()
        let exported = await store.exportForCache()
        #expect(exported.isEmpty)
    }
}
