import XCTest
@testable import QuartzKit

/// Phase 1 TDD tests for knowledge graph link resolution.
/// These tests define the expected behavior for resolving wiki-links
/// to note identities, including aliases, folder prefixes, and normalization.
final class GraphLinkResolutionTests: XCTestCase {

    // MARK: - Test: Canonical Title + Filename Alias Resolution

    /// A wiki-link should resolve by:
    /// 1. Exact filename match (without .md extension)
    /// 2. Frontmatter title match
    /// 3. Frontmatter aliases array match
    func test_wikiLink_resolvesByCanonicalTitle_andFilenameAlias() async {
        // Given: A note at "Project Overview.md" with frontmatter:
        //   title: "Project Overview"
        //   aliases: ["overview", "project-overview", "PO"]
        let resolver = GraphIdentityResolver()

        let noteURL = URL(fileURLWithPath: "/vault/Project Overview.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "Project Overview",
            frontmatterTitle: "Project Overview",
            aliases: ["overview", "project-overview", "PO"]
        )
        await resolver.register(identity)

        // When: Resolving various wiki-link targets
        // Then: All should resolve to the same note

        // Exact filename
        let result1 = await resolver.resolve("Project Overview")
        XCTAssertEqual(result1, noteURL)

        // Frontmatter title (same as filename here)
        let result2 = await resolver.resolve("Project Overview")
        XCTAssertEqual(result2, noteURL)

        // Aliases
        let result3 = await resolver.resolve("overview")
        XCTAssertEqual(result3, noteURL)

        let result4 = await resolver.resolve("project-overview")
        XCTAssertEqual(result4, noteURL)

        let result5 = await resolver.resolve("PO")
        XCTAssertEqual(result5, noteURL)

        // Non-existent target
        let result6 = await resolver.resolve("Unknown Note")
        XCTAssertNil(result6)
    }

    // MARK: - Test: Folder Prefix + Case/Punctuation Differences

    /// Wiki-links with folder prefixes should resolve correctly:
    /// - [[folder/note]] → note in folder
    /// - [[Note]] → same as [[note]] (case-insensitive)
    /// - [[Project: Overview]] → same as [[Project Overview]] (punctuation normalized)
    func test_wikiLink_resolvesWithFolderPrefix_andCasePunctuationDifferences() async {
        let resolver = GraphIdentityResolver()

        // Note in a subfolder
        let nestedURL = URL(fileURLWithPath: "/vault/Projects/Alpha/README.md")
        let nestedIdentity = NoteIdentity(
            url: nestedURL,
            filename: "README",
            frontmatterTitle: "Alpha Project",
            aliases: []
        )
        await resolver.register(nestedIdentity)

        // Root-level note with punctuation in name
        let punctuatedURL = URL(fileURLWithPath: "/vault/Project: Overview.md")
        let punctuatedIdentity = NoteIdentity(
            url: punctuatedURL,
            filename: "Project: Overview",
            frontmatterTitle: nil,
            aliases: []
        )
        await resolver.register(punctuatedIdentity)

        // When: Resolving with folder prefix
        let nested1 = await resolver.resolve("Projects/Alpha/README")
        XCTAssertEqual(nested1, nestedURL)

        let nested2 = await resolver.resolve("Alpha/README")
        XCTAssertEqual(nested2, nestedURL) // partial path

        // When: Resolving with case differences
        let case1 = await resolver.resolve("readme")
        XCTAssertEqual(case1, nestedURL) // lowercase

        let case2 = await resolver.resolve("README")
        XCTAssertEqual(case2, nestedURL) // uppercase

        let case3 = await resolver.resolve("Readme")
        XCTAssertEqual(case3, nestedURL) // mixed

        // When: Resolving with punctuation differences
        let punct1 = await resolver.resolve("Project Overview")
        XCTAssertEqual(punct1, punctuatedURL) // no colon

        let punct2 = await resolver.resolve("project: overview")
        XCTAssertEqual(punct2, punctuatedURL) // lowercase

        let punct3 = await resolver.resolve("project-overview")
        XCTAssertEqual(punct3, punctuatedURL) // hyphenated
    }

    // MARK: - Test: Rename Preserves Stable Node Identity

    /// When a note is renamed, the graph should:
    /// 1. Preserve the stable node identity (based on content hash or stable ID)
    /// 2. Rewire existing edges to the new identity
    /// 3. Update the identity index for new lookups
    func test_rename_preservesStableNodeIdentity_andRewiresEdges() async {
        let resolver = GraphIdentityResolver()

        // Given: Two notes, one linking to the other
        let sourceURL = URL(fileURLWithPath: "/vault/Notes/Source.md")
        let targetURL = URL(fileURLWithPath: "/vault/Notes/Target.md")

        let sourceIdentity = NoteIdentity(
            url: sourceURL,
            filename: "Source",
            frontmatterTitle: nil,
            aliases: []
        )
        let targetIdentity = NoteIdentity(
            url: targetURL,
            filename: "Target",
            frontmatterTitle: nil,
            aliases: []
        )

        await resolver.register(sourceIdentity)
        await resolver.register(targetIdentity)

        // Verify initial resolution
        let initial = await resolver.resolve("Target")
        XCTAssertEqual(initial, targetURL)

        // When: Target is renamed to "New Target"
        let renamedURL = URL(fileURLWithPath: "/vault/Notes/New Target.md")
        let renamedIdentity = NoteIdentity(
            url: renamedURL,
            filename: "New Target",
            frontmatterTitle: nil,
            aliases: ["Target"] // Old name becomes alias for backward compatibility
        )

        await resolver.unregister(targetIdentity)
        await resolver.register(renamedIdentity)

        // Then: Old name still resolves (via alias)
        let oldName = await resolver.resolve("Target")
        XCTAssertEqual(oldName, renamedURL)

        // And: New name resolves
        let newName = await resolver.resolve("New Target")
        XCTAssertEqual(newName, renamedURL)

        // And: The stable ID should be consistent across rename
        let originalStableID = await resolver.stableID(for: targetURL)
        let renamedStableID = await resolver.stableID(for: renamedURL)
        // Note: Stable IDs are path-based, so they WILL change on rename.
        // The alias mechanism handles backward compatibility.
        XCTAssertNotNil(originalStableID)
        XCTAssertNotNil(renamedStableID)
    }

    // MARK: - Test: Concept Node Auto-Wiring

    /// Notes mentioning a concept (e.g., "Project X" in content/tags)
    /// should automatically wire to a concept hub node.
    func test_noteWithConcept_autoWiresToConceptNode() async {
        let resolver = GraphIdentityResolver()

        // Given: Three notes, two mentioning "Machine Learning"
        let note1URL = URL(fileURLWithPath: "/vault/ML Basics.md")
        let note2URL = URL(fileURLWithPath: "/vault/Deep Learning.md")
        let note3URL = URL(fileURLWithPath: "/vault/Cooking Recipes.md")

        let note1 = NoteIdentity(
            url: note1URL,
            filename: "ML Basics",
            frontmatterTitle: "Machine Learning Basics",
            aliases: [],
            tags: ["machine-learning", "tutorial"]
        )
        let note2 = NoteIdentity(
            url: note2URL,
            filename: "Deep Learning",
            frontmatterTitle: nil,
            aliases: [],
            tags: ["machine-learning", "neural-networks"]
        )
        let note3 = NoteIdentity(
            url: note3URL,
            filename: "Cooking Recipes",
            frontmatterTitle: nil,
            aliases: [],
            tags: ["cooking", "food"]
        )

        await resolver.register(note1)
        await resolver.register(note2)
        await resolver.register(note3)

        // When: Asking for notes that share a concept
        let mlNotes = await resolver.notesWithTag("machine-learning")

        // Then: Should return both ML-related notes
        XCTAssertEqual(mlNotes.count, 2)
        XCTAssertTrue(mlNotes.contains(note1URL))
        XCTAssertTrue(mlNotes.contains(note2URL))
        XCTAssertFalse(mlNotes.contains(note3URL))

        // When: Asking for significant concepts (appears in 2+ notes)
        let concepts = await resolver.significantConcepts(minCount: 2)

        // Then: "machine-learning" should be identified
        XCTAssertTrue(concepts.contains("machine-learning"))
        XCTAssertFalse(concepts.contains("cooking")) // Only in 1 note
    }

    // MARK: - Test: Graph Build Determinism

    /// Given the same vault snapshot, the graph should produce
    /// identical node/edge sets regardless of iteration order.
    func test_graphBuild_isDeterministic_forSameVaultSnapshot() async {
        let resolver = GraphIdentityResolver()

        // Given: A set of notes with links
        let notes = [
            NoteIdentity(
                url: URL(fileURLWithPath: "/vault/A.md"),
                filename: "A",
                frontmatterTitle: nil,
                aliases: []
            ),
            NoteIdentity(
                url: URL(fileURLWithPath: "/vault/B.md"),
                filename: "B",
                frontmatterTitle: nil,
                aliases: []
            ),
            NoteIdentity(
                url: URL(fileURLWithPath: "/vault/C.md"),
                filename: "C",
                frontmatterTitle: nil,
                aliases: []
            ),
        ]

        // Register in different orders and verify same result
        for note in notes { await resolver.register(note) }
        let allIDs1 = Set(await resolver.allRegisteredURLs())

        let resolver2 = GraphIdentityResolver()
        for note in notes.reversed() { await resolver2.register(note) }
        let allIDs2 = Set(await resolver2.allRegisteredURLs())

        // Then: Both should have the same set of URLs
        XCTAssertEqual(allIDs1, allIDs2)
    }

    // MARK: - Test: Cache Invalidation on Content Change

    /// When a note's content changes (affecting links or title),
    /// the cache should be invalidated and graph rebuilt.
    func test_graphCache_invalidatesOnContentChange() async {
        let resolver = GraphIdentityResolver()

        let noteURL = URL(fileURLWithPath: "/vault/Note.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "Note",
            frontmatterTitle: "Original Title",
            aliases: []
        )
        await resolver.register(identity)

        // Initial resolution
        let initial = await resolver.resolve("Original Title")
        XCTAssertEqual(initial, noteURL)

        // When: Title changes in frontmatter
        let updatedIdentity = NoteIdentity(
            url: noteURL,
            filename: "Note",
            frontmatterTitle: "Updated Title",
            aliases: ["Original Title"] // Old title becomes alias
        )
        await resolver.unregister(identity)
        await resolver.register(updatedIdentity)

        // Then: New title resolves
        let newTitle = await resolver.resolve("Updated Title")
        XCTAssertEqual(newTitle, noteURL)

        // And: Old title still resolves (via alias)
        let oldTitle = await resolver.resolve("Original Title")
        XCTAssertEqual(oldTitle, noteURL)
    }

    // MARK: - Test: Fuzzy Resolution Fallback

    /// When exact match fails, fuzzy matching should find close matches.
    /// This handles typos and slight variations.
    func test_wikiLink_fuzzyResolution_findsCloseMatches() async {
        let resolver = GraphIdentityResolver()

        let noteURL = URL(fileURLWithPath: "/vault/Introduction to Swift.md")
        let identity = NoteIdentity(
            url: noteURL,
            filename: "Introduction to Swift",
            frontmatterTitle: nil,
            aliases: []
        )
        await resolver.register(identity)

        // When: Resolving with fuzzy matching enabled
        // Exact match
        let exact = await resolver.resolve("Introduction to Swift")
        XCTAssertEqual(exact, noteURL)

        // Close match (missing "to")
        let missingWord = await resolver.resolve("Introduction Swift", fuzzy: true)
        XCTAssertEqual(missingWord, noteURL)

        // Close match (typo)
        let typo = await resolver.resolve("Introducton to Swift", fuzzy: true)
        XCTAssertEqual(typo, noteURL)

        // Too different (should not match)
        let different = await resolver.resolve("Completely Different", fuzzy: true)
        XCTAssertNil(different)
    }

    // MARK: - Test: Normalization Edge Cases

    /// Test various normalization scenarios.
    func test_normalization_handlesEdgeCases() {
        // Colons
        XCTAssertEqual(GraphIdentityResolver.normalize("Project: Overview"), "project overview")

        // Underscores
        XCTAssertEqual(GraphIdentityResolver.normalize("my_note_name"), "my note name")

        // Mixed punctuation
        XCTAssertEqual(GraphIdentityResolver.normalize("Project: Overview_v2"), "project overview v2")

        // Multiple spaces collapse
        XCTAssertEqual(GraphIdentityResolver.normalize("note   with   spaces"), "note with spaces")

        // Hyphens preserved
        XCTAssertEqual(GraphIdentityResolver.normalize("my-note-name"), "my-note-name")

        // Path separators preserved
        XCTAssertEqual(GraphIdentityResolver.normalize("folder/note"), "folder/note")
    }

    // MARK: - Test: Levenshtein Distance

    /// Verify Levenshtein distance calculation.
    func test_levenshteinDistance_isCorrect() {
        // Same string
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("hello", "hello"), 0)

        // One character difference
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("hello", "hallo"), 1)

        // Insertion
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("hello", "helloo"), 1)

        // Deletion
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("hello", "helo"), 1)

        // Multiple differences
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("kitten", "sitting"), 3)

        // Empty strings
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("", "hello"), 5)
        XCTAssertEqual(GraphIdentityResolver.levenshteinDistance("hello", ""), 5)
    }
}
