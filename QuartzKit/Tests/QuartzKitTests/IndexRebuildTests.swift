import Testing
import Foundation
import CoreGraphics
@testable import QuartzKit

// MARK: - Index Rebuild Tests

@Suite("IndexRebuild")
struct IndexRebuildTests {

    @Test("GraphCache saves and loads explicit and graph-view snapshots independently")
    func graphCacheRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-rebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: ".quartz"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = GraphCache(vaultRoot: root)
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        let explicitSnapshot = GraphCache.CachedGraph.CachedExplicitRelationshipSnapshot(
            fingerprint: "explicit-fp",
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
                    matchRange: NSRange(location: 0, length: 5),
                    lineRange: NSRange(location: 0, length: 5),
                    context: "[[B]]"
                )
            ]
        )
        let semanticSnapshot = GraphCache.CachedGraph.CachedSemanticRelationshipSnapshot(
            fingerprint: "semantic-fp",
            relations: [
                .init(sourceURL: noteA, targetURLs: [noteB])
            ]
        )
        let graphViewSnapshot = GraphCache.CachedGraph.CachedGraphViewSnapshot(
            fingerprint: "graph-fp",
            nodes: [
                .init(id: "a", title: "A", url: noteA, x: 10, y: 20, connectionCount: 1, tags: ["test"]),
                .init(id: "b", title: "B", url: noteB, x: 30, y: 40, connectionCount: 1, tags: nil)
            ],
            semanticEdges: [
                .init(from: "a", to: "b", kind: .semanticSimilarity)
            ],
            conceptEdges: [
                .init(from: "a", to: "concept:swift", kind: .aiConcept)
            ]
        )

        try cache.saveExplicitRelationshipSnapshot(explicitSnapshot)
        try cache.saveSemanticRelationshipSnapshot(semanticSnapshot)
        try cache.saveGraphViewSnapshot(graphViewSnapshot)

        let loadedExplicit = cache.loadExplicitRelationshipSnapshotIfValid(fingerprint: "explicit-fp")
        #expect(loadedExplicit != nil)
        #expect(loadedExplicit?.references.count == 1)
        #expect(loadedExplicit?.references.first?.targetNoteURL == noteB)

        let loadedSemantic = cache.loadSemanticRelationshipSnapshotIfValid(fingerprint: "semantic-fp")
        #expect(loadedSemantic != nil)
        #expect(loadedSemantic?.relations.count == 1)
        #expect(loadedSemantic?.relations.first?.sourceURL == noteA)
        #expect(loadedSemantic?.relations.first?.targetURLs == [noteB])

        let loadedGraphView = cache.loadGraphViewSnapshotIfValid(fingerprint: "graph-fp")
        #expect(loadedGraphView != nil)
        #expect(loadedGraphView?.nodes.count == 2)
        #expect(loadedGraphView?.semanticEdges.count == 1)
        #expect(loadedGraphView?.semanticEdges.first?.kind == .semanticSimilarity)
        #expect(loadedGraphView?.conceptEdges.count == 1)
        #expect(loadedGraphView?.conceptEdges.first?.kind == .aiConcept)

        #expect(cache.loadExplicitRelationshipSnapshotIfValid(fingerprint: "wrong-fp") == nil)
        #expect(cache.loadSemanticRelationshipSnapshotIfValid(fingerprint: "wrong-fp") == nil)
        #expect(cache.loadGraphViewSnapshotIfValid(fingerprint: "wrong-fp") == nil)
    }

    @Test("Saving graph-view snapshot preserves authoritative explicit and semantic snapshots")
    func graphViewSavePreservesRelationshipSnapshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-preserve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: ".quartz"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = GraphCache(vaultRoot: root)
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        try cache.saveExplicitRelationshipSnapshot(
            .init(
                fingerprint: "explicit-fp",
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
                        context: "[[B]]"
                    )
                ]
            )
        )
        try cache.saveSemanticRelationshipSnapshot(
            .init(
                fingerprint: "semantic-fp",
                relations: [
                    .init(sourceURL: noteA, targetURLs: [noteB])
                ]
            )
        )

        try cache.saveGraphViewSnapshot(
            .init(
                fingerprint: "graph-fp",
                nodes: [],
                semanticEdges: [],
                conceptEdges: []
            )
        )

        let loadedExplicit = cache.loadExplicitRelationshipSnapshotIfValid(fingerprint: "explicit-fp")
        #expect(loadedExplicit?.references.count == 1)
        let loadedSemantic = cache.loadSemanticRelationshipSnapshotIfValid(fingerprint: "semantic-fp")
        #expect(loadedSemantic?.relations.count == 1)
    }

    @Test("Fingerprint changes when files are modified")
    func fingerprintInvalidation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-rebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = GraphCache(vaultRoot: root)
        let file = root.appendingPathComponent("note.md")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let fp1 = cache.computeFingerprint(for: [file])

        // Modify
        try "world".write(to: file, atomically: true, encoding: .utf8)
        let fp2 = cache.computeFingerprint(for: [file])

        #expect(fp1 != fp2)

        // Adding a file changes fingerprint
        let file2 = root.appendingPathComponent("note2.md")
        try "extra".write(to: file2, atomically: true, encoding: .utf8)
        let fp3 = cache.computeFingerprint(for: [file, file2])
        #expect(fp2 != fp3)
    }

    @Test("Rebuild idempotency — same inputs produce same fingerprint")
    func idempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("idem-rebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("stable.md")
        try "consistent content".write(to: file, atomically: true, encoding: .utf8)

        let cache = GraphCache(vaultRoot: root)
        let fp1 = cache.computeFingerprint(for: [file])
        let fp2 = cache.computeFingerprint(for: [file])
        #expect(fp1 == fp2)
    }
}
