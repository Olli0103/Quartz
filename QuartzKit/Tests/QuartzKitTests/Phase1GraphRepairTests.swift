import XCTest
@testable import QuartzKit

// MARK: - Phase 1: Knowledge Graph Repair
// Tests for wiki-link wiring, concept hub integrity, and backlink determinism.
// Using XCTest instead of Swift Testing due to compiler limits on macro count.

final class Phase1GraphWiringTests: XCTestCase {

    // MARK: - Wiki-link Alias Resolution

    @MainActor
    func testWikiLinkAliasResolution() async throws {
        let resolver = GraphIdentityResolver()
        let noteURL = URL(fileURLWithPath: "/vault/meeting-notes-2024-03-15.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "meeting-notes-2024-03-15",
            frontmatterTitle: "Q1 Planning Meeting",
            aliases: ["planning", "q1-meeting"]
        )
        await resolver.register(identity)

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        let sourceURL = URL(fileURLWithPath: "/vault/project-overview.md")
        await store.updateConnections(
            for: sourceURL,
            linkedTitles: ["planning"],
            allVaultURLs: [sourceURL, noteURL]
        )

        let edges = await store.edges
        XCTAssertTrue(edges[sourceURL]?.contains(noteURL) ?? false, "Alias should resolve")
    }

    @MainActor
    func testWikiLinkFrontmatterTitleResolution() async throws {
        let resolver = GraphIdentityResolver()
        let noteURL = URL(fileURLWithPath: "/vault/api-docs.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "api-docs",
            frontmatterTitle: "REST API Documentation"
        )
        await resolver.register(identity)

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        let sourceURL = URL(fileURLWithPath: "/vault/getting-started.md")
        await store.updateConnections(
            for: sourceURL,
            linkedTitles: ["REST API Documentation"],
            allVaultURLs: [sourceURL, noteURL]
        )

        let edges = await store.edges
        XCTAssertTrue(edges[sourceURL]?.contains(noteURL) ?? false, "Frontmatter title should resolve")
    }

    // MARK: - Folder-Qualified Links

    @MainActor
    func testFolderQualifiedLinksCaseInsensitive() async throws {
        let resolver = GraphIdentityResolver()
        let noteURL = URL(fileURLWithPath: "/vault/Projects/MyApp/design-doc.md")
        await resolver.register(NoteIdentity(url: noteURL, filename: "design-doc"))

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        let sourceURL = URL(fileURLWithPath: "/vault/notes.md")

        for variation in ["Projects/MyApp/design-doc", "projects/myapp/design-doc", "PROJECTS/MYAPP/DESIGN-DOC"] {
            await store.updateConnections(for: sourceURL, linkedTitles: [variation], allVaultURLs: [sourceURL, noteURL])
            let edges = await store.edges
            XCTAssertTrue(edges[sourceURL]?.contains(noteURL) ?? false, "'\(variation)' should resolve")
        }
    }

    // MARK: - Rename Rewiring

    @MainActor
    func testRenameRewiresEdgesViaAlias() async throws {
        let resolver = GraphIdentityResolver()
        let sourceURL = URL(fileURLWithPath: "/vault/source.md")
        let targetURL = URL(fileURLWithPath: "/vault/old-target.md")

        await resolver.register(NoteIdentity(url: sourceURL, filename: "source"))
        await resolver.register(NoteIdentity(url: targetURL, filename: "old-target"))

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        await store.updateConnections(for: sourceURL, linkedTitles: ["old-target"], allVaultURLs: [sourceURL, targetURL])
        var edges = await store.edges
        XCTAssertTrue(edges[sourceURL]?.contains(targetURL) ?? false, "Initial edge should exist")

        // Simulate rename: unregister old, register new with alias
        await resolver.unregister(NoteIdentity(url: targetURL, filename: "old-target"))
        let newTargetURL = URL(fileURLWithPath: "/vault/new-target.md")
        await resolver.register(NoteIdentity(url: newTargetURL, filename: "new-target", aliases: ["old-target"]))

        await store.updateConnections(for: sourceURL, linkedTitles: ["old-target"], allVaultURLs: [sourceURL, newTargetURL])
        edges = await store.edges
        XCTAssertTrue(edges[sourceURL]?.contains(newTargetURL) ?? false, "Edge should rewire to new URL")
    }

    // MARK: - Edge Cases

    @MainActor
    func testSelfReferenceAndNonExistentCreateNoEdges() async throws {
        let resolver = GraphIdentityResolver()
        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        await resolver.register(NoteIdentity(url: noteURL, filename: "note"))

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        // Self-reference
        await store.updateConnections(for: noteURL, linkedTitles: ["note"], allVaultURLs: [noteURL])
        var edges = await store.edges
        XCTAssertTrue(edges[noteURL]?.isEmpty ?? true, "Self-reference should not create edge")

        // Non-existent
        await store.updateConnections(for: noteURL, linkedTitles: ["ghost"], allVaultURLs: [noteURL])
        edges = await store.edges
        XCTAssertTrue(edges[noteURL]?.isEmpty ?? true, "Non-existent should not create edge")
    }

    @MainActor
    func testDuplicateLinksCreateSingleEdge() async throws {
        let resolver = GraphIdentityResolver()
        let sourceURL = URL(fileURLWithPath: "/vault/source.md")
        let targetURL = URL(fileURLWithPath: "/vault/target.md")

        await resolver.register(NoteIdentity(url: sourceURL, filename: "source"))
        await resolver.register(NoteIdentity(url: targetURL, filename: "target"))

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        await store.updateConnections(for: sourceURL, linkedTitles: ["target", "target", "target"], allVaultURLs: [sourceURL, targetURL])

        let edges = await store.edges
        let targetEdges = edges[sourceURL] ?? []
        let targetCount = targetEdges.filter { $0 == targetURL }.count
        XCTAssertEqual(targetCount, 1, "Duplicate links should create single edge")
    }
}

// MARK: - Concept Hub Integrity Tests

final class Phase1ConceptHubIntegrityTests: XCTestCase {

    @MainActor
    func testNoOrphanConceptNodesAfterRemoval() async throws {
        let store = GraphEdgeStore()

        let noteA = URL(fileURLWithPath: "/vault/note-a.md")
        let noteB = URL(fileURLWithPath: "/vault/note-b.md")

        await store.updateConcepts(for: noteA, concepts: ["swift", "ios"])
        await store.updateConcepts(for: noteB, concepts: ["swift", "macos"])

        await store.removeConcepts(for: noteA)

        let conceptEdges = await store.conceptEdges
        XCTAssertNil(conceptEdges["ios"], "'ios' should be removed (only noteA had it)")
        XCTAssertTrue(conceptEdges["swift"]?.contains(noteB) ?? false, "'swift' should still have noteB")
    }

    @MainActor
    func testConceptUpdateAtomicReverseMap() async throws {
        let store = GraphEdgeStore()
        let noteURL = URL(fileURLWithPath: "/vault/note.md")

        await store.updateConcepts(for: noteURL, concepts: ["alpha", "beta", "gamma"])

        var noteConcepts = await store.noteConcepts
        XCTAssertTrue(noteConcepts[noteURL]?.contains("alpha") ?? false)
        XCTAssertTrue(noteConcepts[noteURL]?.contains("beta") ?? false)
        XCTAssertTrue(noteConcepts[noteURL]?.contains("gamma") ?? false)

        // Update: remove alpha/gamma, keep beta, add delta
        await store.updateConcepts(for: noteURL, concepts: ["beta", "delta"])

        noteConcepts = await store.noteConcepts
        let conceptEdges = await store.conceptEdges

        XCTAssertFalse(noteConcepts[noteURL]?.contains("alpha") ?? true)
        XCTAssertFalse(noteConcepts[noteURL]?.contains("gamma") ?? true)
        XCTAssertTrue(noteConcepts[noteURL]?.contains("beta") ?? false)
        XCTAssertTrue(noteConcepts[noteURL]?.contains("delta") ?? false)

        // Orphan check
        XCTAssertNil(conceptEdges["alpha"], "'alpha' should be removed from edges")
        XCTAssertNil(conceptEdges["gamma"], "'gamma' should be removed from edges")
    }

    @MainActor
    func testSignificantConceptsFiltering() async throws {
        let store = GraphEdgeStore()

        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")
        let noteC = URL(fileURLWithPath: "/vault/c.md")

        await store.updateConcepts(for: noteA, concepts: ["common", "shared", "rare"])
        await store.updateConcepts(for: noteB, concepts: ["common", "shared"])
        await store.updateConcepts(for: noteC, concepts: ["common"])

        let significant2 = await store.significantConcepts(minNotes: 2)
        let names2 = significant2.map(\.concept)
        XCTAssertTrue(names2.contains("common"))
        XCTAssertTrue(names2.contains("shared"))
        XCTAssertFalse(names2.contains("rare"))

        let significant3 = await store.significantConcepts(minNotes: 3)
        let names3 = significant3.map(\.concept)
        XCTAssertTrue(names3.contains("common"))
        XCTAssertFalse(names3.contains("shared"))
    }
}

// MARK: - Backlink Determinism Tests

final class Phase1BacklinkDeterminismTests: XCTestCase {

    @MainActor
    func testBacklinkSetsStableAcrossRebuilds() async throws {
        let resolver = GraphIdentityResolver()

        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")
        let noteC = URL(fileURLWithPath: "/vault/c.md")

        await resolver.register(NoteIdentity(url: noteA, filename: "a"))
        await resolver.register(NoteIdentity(url: noteB, filename: "b"))
        await resolver.register(NoteIdentity(url: noteC, filename: "c"))

        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        let allURLs = [noteA, noteB, noteC]
        await store.updateConnections(for: noteA, linkedTitles: ["b", "c"], allVaultURLs: allURLs)
        await store.updateConnections(for: noteB, linkedTitles: ["c"], allVaultURLs: allURLs)
        let edges1 = await store.edges

        await store.rebuildAll(
            connections: [
                (sourceURL: noteA, linkedTitles: ["b", "c"]),
                (sourceURL: noteB, linkedTitles: ["c"])
            ],
            allVaultURLs: allURLs
        )
        let edges2 = await store.edges

        XCTAssertEqual(
            edges1[noteA]?.sorted(by: { $0.path < $1.path }),
            edges2[noteA]?.sorted(by: { $0.path < $1.path }),
            "A's edges should be identical"
        )
        XCTAssertEqual(
            edges1[noteB]?.sorted(by: { $0.path < $1.path }),
            edges2[noteB]?.sorted(by: { $0.path < $1.path }),
            "B's edges should be identical"
        )
    }

    @MainActor
    func testConcurrentUpdatesThreadSafe() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        var urls: [URL] = []
        for i in 0..<20 {
            let url = URL(fileURLWithPath: "/vault/note-\(i).md")
            urls.append(url)
            await resolver.register(NoteIdentity(url: url, filename: "note-\(i)"))
        }

        // Copy for Sendable closure
        let urlsCopy = urls

        await withTaskGroup(of: Void.self) { group in
            for (index, url) in urlsCopy.enumerated() {
                let targetIndex = (index + 1) % urlsCopy.count
                let targetName = "note-\(targetIndex)"
                let allURLs = urlsCopy
                group.addTask {
                    await store.updateConnections(for: url, linkedTitles: [targetName], allVaultURLs: allURLs)
                }
            }
        }

        let edges = await store.edges
        XCTAssertEqual(edges.count, 20, "All notes should have edges")
    }

    @MainActor
    func testEmptyVaultNoEdges() async throws {
        let store = GraphEdgeStore()
        await store.rebuildAll(connections: [], allVaultURLs: [])
        let edges = await store.edges
        XCTAssertTrue(edges.isEmpty, "Empty vault should have no edges")
    }
}

// MARK: - Stable ID Tests

final class Phase1StableIDTests: XCTestCase {

    @MainActor
    func testStableIDsConsistentAcrossInstances() async throws {
        let url = URL(fileURLWithPath: "/vault/test-note.md")

        let resolver1 = GraphIdentityResolver()
        await resolver1.register(NoteIdentity(url: url, filename: "test-note"))
        let id1 = await resolver1.stableID(for: url)

        let resolver2 = GraphIdentityResolver()
        await resolver2.register(NoteIdentity(url: url, filename: "test-note"))
        let id2 = await resolver2.stableID(for: url)

        XCTAssertEqual(id1, id2, "Stable IDs should be identical across instances")
    }

    @MainActor
    func testDifferentPathsDifferentIDs() async throws {
        let resolver = GraphIdentityResolver()

        let url1 = URL(fileURLWithPath: "/vault/note1.md")
        let url2 = URL(fileURLWithPath: "/vault/note2.md")

        await resolver.register(NoteIdentity(url: url1, filename: "note1"))
        await resolver.register(NoteIdentity(url: url2, filename: "note2"))

        let id1 = await resolver.stableID(for: url1)
        let id2 = await resolver.stableID(for: url2)

        XCTAssertNotEqual(id1, id2, "Different paths should produce different stable IDs")
    }

    @MainActor
    func testStableIDFormat() async throws {
        let resolver = GraphIdentityResolver()
        let url = URL(fileURLWithPath: "/vault/test.md")
        await resolver.register(NoteIdentity(url: url, filename: "test"))

        let stableID = await resolver.stableID(for: url)
        XCTAssertNotNil(stableID)

        let id = stableID!
        XCTAssertEqual(id.count, 32, "Stable ID should be 32 hex characters")
        XCTAssertTrue(id.allSatisfy { $0.isHexDigit }, "Should only contain hex characters")
    }
}
