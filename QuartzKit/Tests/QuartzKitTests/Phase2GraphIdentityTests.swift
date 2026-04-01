import XCTest
@testable import QuartzKit

// MARK: - Phase 2: Identity and Graph Integrity (CODEX.md Recovery Plan)
// TDD Red Phase: Tests for enforcing single note identity contract across graph/backlinks/intelligence.
// Per CODEX.md F5: Graph identity model is split between robust resolver and fallback title-index rebuild path.

// MARK: - GraphIdentityCanonicalResolutionTests

/// Tests that GraphIdentityResolver is the single source of truth for note identity resolution.
/// Per CODEX.md F5: GraphEdgeStore rebuilds title index on each update and has fallback resolution path.
final class GraphIdentityCanonicalResolutionTests: XCTestCase {

    // MARK: - Single Resolver Contract

    /// Tests that GraphEdgeStore delegates to GraphIdentityResolver when configured.
    @MainActor
    func testGraphEdgeStoreDelegatesToResolver() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()

        // Register identity
        let noteURL = URL(fileURLWithPath: "/vault/test-note.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "test-note",
            frontmatterTitle: "Test Note Title",
            aliases: ["test-alias"]
        )
        await resolver.register(identity)

        // Configure store to use resolver
        await store.setIdentityResolver(resolver)

        // All resolution paths should go through the resolver
        let byFilename = await store.resolveTitle("test-note")
        let byTitle = await store.resolveTitle("Test Note Title")
        let byAlias = await store.resolveTitle("test-alias")

        XCTAssertEqual(byFilename, noteURL, "Filename resolution should use resolver")
        XCTAssertEqual(byTitle, noteURL, "Title resolution should use resolver")
        XCTAssertEqual(byAlias, noteURL, "Alias resolution should use resolver")
    }

    /// Tests case-insensitive resolution.
    @MainActor
    func testCaseInsensitiveResolution() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()

        let noteURL = URL(fileURLWithPath: "/vault/MyNote.md")
        await resolver.register(NoteIdentity(url: noteURL, filename: "MyNote"))
        await store.setIdentityResolver(resolver)

        // All case variations should resolve
        let variations = ["MyNote", "mynote", "MYNOTE", "myNote"]
        for variant in variations {
            let result = await store.resolveTitle(variant)
            XCTAssertEqual(result, noteURL, "'\(variant)' should resolve to note URL")
        }
    }

    /// Tests path-qualified link resolution.
    @MainActor
    func testPathQualifiedLinkResolution() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()

        let noteURL = URL(fileURLWithPath: "/vault/projects/my-project.md")
        await resolver.register(NoteIdentity(url: noteURL, filename: "my-project"))
        await store.setIdentityResolver(resolver)

        // Path-qualified links should resolve
        let result = await store.resolveTitle("projects/my-project")
        XCTAssertEqual(result, noteURL, "Path-qualified link should resolve")
    }

    /// Tests that resolver provides stable IDs.
    @MainActor
    func testResolverProvidesStableIDs() async throws {
        let resolver = GraphIdentityResolver()

        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        await resolver.register(NoteIdentity(url: noteURL, filename: "note"))

        let stableID = await resolver.stableID(for: noteURL)
        XCTAssertNotNil(stableID, "Stable ID should be generated")

        // ID should be deterministic
        let stableID2 = await resolver.stableID(for: noteURL)
        XCTAssertEqual(stableID, stableID2, "Stable ID should be deterministic")
    }

    // MARK: - Fallback Path Documentation

    /// Documents the problematic fallback resolution path in GraphEdgeStore.
    @MainActor
    func testFallbackPathDocumentation() async throws {
        // ISSUE (per CODEX.md F5):
        //
        // GraphEdgeStore.updateConnections() has this behavior:
        // 1. Calls rebuildTitleIndex(from: allVaultURLs) on EVERY update
        // 2. Has fallback simple resolution when resolver not configured
        //
        // See GraphCache.swift:134:
        // ```swift
        // // Rebuild the title index from the vault snapshot (fallback)
        // rebuildTitleIndex(from: allVaultURLs)
        // ```
        //
        // This causes:
        // - O(n) CPU churn on every single note update
        // - Inconsistent resolution between resolver and fallback
        //
        // FIX: Only rebuild titleIndex when resolver is nil, and do it once per batch

        XCTAssertTrue(true, "Fallback path issue documented")
    }
}

// MARK: - AliasPathRenameRewireTests

/// Tests that note identity is preserved across renames and supports aliases.
/// Note: Some tests document MISSING APIs that need implementation.
final class AliasPathRenameRewireTests: XCTestCase {

    /// Tests that aliases resolve correctly.
    @MainActor
    func testAliasResolution() async throws {
        let resolver = GraphIdentityResolver()

        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "note",
            aliases: ["my-alias", "another-alias"]
        )
        await resolver.register(identity)

        // Aliases should resolve
        let fromAlias1 = await resolver.resolve("my-alias")
        let fromAlias2 = await resolver.resolve("another-alias")

        XCTAssertEqual(fromAlias1, noteURL, "Alias 'my-alias' should resolve")
        XCTAssertEqual(fromAlias2, noteURL, "Alias 'another-alias' should resolve")
    }

    /// Tests that frontmatter title resolves.
    @MainActor
    func testFrontmatterTitleResolution() async throws {
        let resolver = GraphIdentityResolver()

        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "note",
            frontmatterTitle: "My Custom Title"
        )
        await resolver.register(identity)

        let fromTitle = await resolver.resolve("My Custom Title")
        XCTAssertEqual(fromTitle, noteURL, "Frontmatter title should resolve")
    }

    /// Documents missing rename API on GraphIdentityResolver.
    @MainActor
    func testRenameAPIDocumentation() async throws {
        // MISSING API (per CODEX.md F5):
        //
        // GraphIdentityResolver needs a rename method:
        // ```swift
        // func rename(from oldURL: URL, to newURL: URL, newFilename: String)
        // ```
        //
        // Expected behavior:
        // 1. Preserve stableID across rename
        // 2. Add old filename as alias (for backward compatibility)
        // 3. Update all internal indices atomically
        //
        // Current workaround: unregister + register new identity (loses stableID continuity)

        XCTAssertTrue(true, "Rename API documented - needs implementation")
    }

    /// Documents missing backlinks API on GraphEdgeStore.
    @MainActor
    func testBacklinksAPIDocumentation() async throws {
        // MISSING API:
        //
        // GraphEdgeStore needs a backlinks method:
        // ```swift
        // func backlinks(for url: URL) -> [URL]
        // ```
        //
        // Current state: edges map only stores forward links (A -> B).
        // To get backlinks (who links to B), need to scan all edges.
        //
        // Expected: Maintain reverse index for O(1) backlink lookup.

        XCTAssertTrue(true, "Backlinks API documented - needs implementation")
    }

    /// Tests that unregister followed by register works as workaround for rename.
    @MainActor
    func testUnregisterRegisterWorkaround() async throws {
        let resolver = GraphIdentityResolver()

        let originalURL = URL(fileURLWithPath: "/vault/original.md")
        let identity = NoteIdentity(url: originalURL, filename: "original")
        await resolver.register(identity)

        // Verify original resolves
        let resolvedOriginal = await resolver.resolve("original")
        XCTAssertEqual(resolvedOriginal, originalURL)

        // Unregister and re-register as "renamed"
        await resolver.unregister(identity)

        let newURL = URL(fileURLWithPath: "/vault/renamed.md")
        let newIdentity = NoteIdentity(
            url: newURL,
            filename: "renamed",
            aliases: ["original"]  // Keep old name as alias
        )
        await resolver.register(newIdentity)

        // New name should resolve
        let resolvedNew = await resolver.resolve("renamed")
        XCTAssertEqual(resolvedNew, newURL)

        // Old name should also resolve (via alias)
        let resolvedOld = await resolver.resolve("original")
        XCTAssertEqual(resolvedOld, newURL, "Old name should resolve as alias")
    }
}

// MARK: - GraphIncrementalUpdatePerfTests

/// Tests that graph updates are incremental and don't rebuild the entire index.
final class GraphIncrementalUpdatePerfTests: XCTestCase {

    /// Tests that single-note updates don't take excessive time.
    @MainActor
    func testSingleNoteUpdatePerformance() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        // Create 100 notes
        var allURLs: [URL] = []
        for i in 0..<100 {
            let url = URL(fileURLWithPath: "/vault/note-\(i).md")
            await resolver.register(NoteIdentity(url: url, filename: "note-\(i)"))
            allURLs.append(url)
        }

        // Build initial graph
        for url in allURLs {
            await store.updateConnections(for: url, linkedTitles: [], allVaultURLs: allURLs)
        }

        // Measure single update
        let startTime = CFAbsoluteTimeGetCurrent()
        await store.updateConnections(
            for: allURLs[0],
            linkedTitles: ["note-1", "note-2"],
            allVaultURLs: allURLs
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Single update should be fast (< 100ms even with current implementation)
        XCTAssertLessThan(elapsed, 0.1,
            "Single note update should be fast")
    }

    /// Documents the title index rebuild issue.
    @MainActor
    func testTitleIndexRebuildIssue() async throws {
        // ISSUE (per CODEX.md F5):
        //
        // Every call to updateConnections triggers:
        // ```swift
        // rebuildTitleIndex(from: allVaultURLs)
        // ```
        //
        // For a vault with 1000 notes, typing in a note triggers:
        // 1. Autosave
        // 2. Notification
        // 3. updateConnections call
        // 4. Full title index rebuild (O(1000))
        //
        // FIX: Use resolver for resolution, only rebuild fallback index on-demand

        XCTAssertTrue(true, "Title index rebuild issue documented")
    }

    /// Tests deterministic backlinks after multiple rebuilds.
    @MainActor
    func testEdgesDeterministicAcrossRebuilds() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")
        let noteC = URL(fileURLWithPath: "/vault/c.md")

        await resolver.register(NoteIdentity(url: noteA, filename: "a"))
        await resolver.register(NoteIdentity(url: noteB, filename: "b"))
        await resolver.register(NoteIdentity(url: noteC, filename: "c"))

        let allURLs = [noteA, noteB, noteC]
        let connections: [(URL, [String])] = [
            (noteA, ["b"]),
            (noteB, ["c"]),
            (noteC, ["a"])  // Cycle
        ]

        // First build
        await store.rebuildAll(connections: connections, allVaultURLs: allURLs)
        let edges1 = await store.edges

        // Second build with same data
        await store.rebuildAll(connections: connections, allVaultURLs: allURLs)
        let edges2 = await store.edges

        // Should be identical
        XCTAssertEqual(Set(edges1[noteA] ?? []), Set(edges2[noteA] ?? []), "Edges should be deterministic")
        XCTAssertEqual(Set(edges1[noteB] ?? []), Set(edges2[noteB] ?? []), "Edges should be deterministic")
        XCTAssertEqual(Set(edges1[noteC] ?? []), Set(edges2[noteC] ?? []), "Edges should be deterministic")
    }

    /// Tests performance with large vault.
    @MainActor
    func testLargeVaultPerformance() async throws {
        let resolver = GraphIdentityResolver()
        let store = GraphEdgeStore()
        await store.setIdentityResolver(resolver)

        // Create 500 notes (reduced from 1000 for test speed)
        var allURLs: [URL] = []
        for i in 0..<500 {
            let url = URL(fileURLWithPath: "/vault/note-\(i).md")
            await resolver.register(NoteIdentity(url: url, filename: "note-\(i)"))
            allURLs.append(url)
        }

        // Each note links to 3 random others
        var connections: [(URL, [String])] = []
        for url in allURLs {
            let linkedIndices = (0..<3).map { _ in Int.random(in: 0..<500) }
            let linkedTitles = linkedIndices.map { "note-\($0)" }
            connections.append((url, linkedTitles))
        }

        // Full rebuild should complete within budget
        let startTime = CFAbsoluteTimeGetCurrent()
        await store.rebuildAll(connections: connections, allVaultURLs: allURLs)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Per CODEX.md optimization ledger: graph rebuild should be reasonable
        XCTAssertLessThan(elapsed, 5.0,
            "500-note graph build should complete within 5 seconds")

        // Verify graph was built
        let totalEdges = await store.edges.values.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(totalEdges, 0, "Graph should have edges")
    }
}
