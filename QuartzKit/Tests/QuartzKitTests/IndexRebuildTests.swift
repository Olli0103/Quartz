import Testing
import Foundation
import CoreGraphics
@testable import QuartzKit

// MARK: - Index Rebuild Tests

@Suite("IndexRebuild")
struct IndexRebuildTests {

    @Test("GraphCache save and load round-trip with fingerprint validation")
    func graphCacheRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-rebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: ".quartz"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = GraphCache(vaultRoot: root)
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        let graph = GraphCache.CachedGraph(
            nodes: [
                .init(id: "a", title: "A", url: noteA, x: 10, y: 20, connectionCount: 1, tags: ["test"]),
                .init(id: "b", title: "B", url: noteB, x: 30, y: 40, connectionCount: 1, tags: nil)
            ],
            edges: [
                .init(from: "a", to: "b", isSemantic: false)
            ],
            fingerprint: "test-fp-123"
        )

        // Save
        try cache.save(graph)

        // Load with matching fingerprint
        let loaded = cache.loadIfValid(fingerprint: "test-fp-123")
        #expect(loaded != nil)
        #expect(loaded?.nodes.count == 2)
        #expect(loaded?.edges.count == 1)
        #expect(loaded?.fingerprint == "test-fp-123")

        // Load with mismatched fingerprint — cache rejected
        let rejected = cache.loadIfValid(fingerprint: "wrong-fp")
        #expect(rejected == nil)
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
