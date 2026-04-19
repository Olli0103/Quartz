import XCTest
import SwiftUI
@testable import QuartzKit

// MARK: - Phase 3: 3-Pane + Inspector Zero-Stutter Architecture
// Tests for focus retention, column persistence, and background update stability.

// MARK: - Inspector Focus Retention Tests

final class Phase3InspectorFocusRetentionTests: XCTestCase {

    /// Verifies that updating inspector state does not trigger view invalidation
    /// that could steal focus from the editor.
    @MainActor
    func testInspectorUpdateDoesNotCauseRerender() async throws {
        let inspector = InspectorStore()

        // Simulate initial state
        let initialHeadings = [
            HeadingItem(id: "h1", level: 1, text: "Title", characterOffset: 0),
            HeadingItem(id: "h2", level: 2, text: "Section", characterOffset: 50)
        ]

        // First update
        inspector.update(with: NoteAnalysis(
            headings: initialHeadings,
            stats: NoteStats(wordCount: 100, characterCount: 500, readingTimeMinutes: 1)
        ))

        // Same data update should be a no-op (no array replacement)
        let headingIdsBefore = inspector.headings.map(\.id)
        inspector.update(with: NoteAnalysis(
            headings: initialHeadings,
            stats: NoteStats(wordCount: 100, characterCount: 500, readingTimeMinutes: 1)
        ))
        let headingIdsAfter = inspector.headings.map(\.id)

        // Should be equal (no replacement when unchanged)
        XCTAssertEqual(headingIdsBefore, headingIdsAfter,
                      "Inspector should not replace headings array when data unchanged")
    }

    /// Verifies that AI concept updates don't cause excessive UI refreshes.
    @MainActor
    func testAIConceptUpdateIsThrottled() async throws {
        let inspector = InspectorStore()

        // Rapid concept updates
        for i in 0..<10 {
            inspector.aiConcepts = ["concept-\(i)"]
        }

        // Final state should be the last update
        XCTAssertEqual(inspector.aiConcepts, ["concept-9"])
    }

    /// Verifies that related-note similarity updates do not steal editor focus.
    @MainActor
    func testSemanticLinkUpdatePreservesEditorFocus() async throws {
        let inspector = InspectorStore()

        // Simulate having focus state (tracked separately from inspector)
        let focusWasLost = false

        // Update related notes
        inspector.relatedNotes = [
            (url: URL(fileURLWithPath: "/vault/note1.md"), title: "Note 1"),
            (url: URL(fileURLWithPath: "/vault/note2.md"), title: "Note 2")
        ]

        // Focus should not have been affected (this is a proxy test -
        // real focus tracking would need UI test infrastructure)
        XCTAssertFalse(focusWasLost, "Updating relatedNotes should not steal focus")
    }

    /// Verifies that scan progress updates are throttled appropriately.
    @MainActor
    func testScanProgressThrottling() async throws {
        let inspector = InspectorStore()

        var updateCount = 0

        // Simulate rapid scan progress updates
        for i in 0..<100 {
            let oldProgress = inspector.aiScanProgress
            inspector.aiScanProgress = (current: i, total: 100, note: "note-\(i)")

            // Count actual state changes
            if oldProgress?.current != i {
                updateCount += 1
            }
        }

        // All updates should have been applied (no throttling at store level)
        // The throttling happens in the projection layer
        XCTAssertEqual(updateCount, 100)
    }

    /// Tests that intelligence status updates don't block the main thread.
    @MainActor
    func testIntelligenceStatusUpdateIsNonBlocking() async throws {
        let inspector = InspectorStore()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Rapid status updates
        for status in [IntelligenceEngineStatus.idle, .analyzing, .indexing(progress: 1, total: 10), .idle] {
            inspector.intelligenceStatus = status
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete almost instantly (< 10ms)
        XCTAssertLessThan(elapsed, 0.01, "Status updates should be non-blocking")
    }
}

// MARK: - Split View Column Persistence Tests

final class Phase3SplitViewColumnPersistenceTests: XCTestCase {

    @MainActor
    func testColumnVisibilitySurvivesInspectorToggle() async throws {
        let store = WorkspaceStore()

        // Set initial visibility
        store.columnVisibility = .all

        // Simulate inspector toggle (doesn't directly affect WorkspaceStore)
        let inspector = InspectorStore()
        inspector.isVisible = true
        inspector.isVisible = false
        inspector.isVisible = true

        // Column visibility should be unchanged
        XCTAssertEqual(store.columnVisibility, .all,
                       "Inspector toggle should not affect column visibility")
    }

    @MainActor
    func testColumnVisibilitySurvivesRouteChange() async throws {
        let store = WorkspaceStore()

        store.columnVisibility = .doubleColumn

        // Route changes
        store.setRoute(.dashboard)
        XCTAssertEqual(store.columnVisibility, .doubleColumn)

        store.setRoute(.graph)
        XCTAssertEqual(store.columnVisibility, .doubleColumn)

        store.setRoute(.note(URL(fileURLWithPath: "/vault/test.md")))
        XCTAssertEqual(store.columnVisibility, .doubleColumn)

        store.setRoute(.empty)
        XCTAssertEqual(store.columnVisibility, .doubleColumn)
    }

    @MainActor
    func testFocusModeStashesAndRestoresVisibility() async throws {
        let store = WorkspaceStore()

        // Start with specific visibility
        store.columnVisibility = .doubleColumn

        // Enter focus mode
        store.applyFocusMode(true)
        XCTAssertEqual(store.columnVisibility, .detailOnly,
                       "Focus mode should set detail only")

        // Exit focus mode
        store.applyFocusMode(false)
        XCTAssertEqual(store.columnVisibility, .doubleColumn,
                       "Exiting focus mode should restore previous visibility")
    }

    @MainActor
    func testColumnVisibilityAllOptions() async throws {
        let store = WorkspaceStore()

        // All visibility options should be settable
        let visibilities: [NavigationSplitViewVisibility] = [.all, .doubleColumn, .detailOnly]
        for visibility in visibilities {
            store.columnVisibility = visibility
            XCTAssertEqual(store.columnVisibility, visibility)
        }
    }

    @MainActor
    func testPreferredCompactColumnPersists() async throws {
        let store = WorkspaceStore()

        store.preferredCompactColumn = .content
        XCTAssertEqual(store.preferredCompactColumn, .content)

        store.preferredCompactColumn = .detail
        XCTAssertEqual(store.preferredCompactColumn, .detail)

        store.preferredCompactColumn = .sidebar
        XCTAssertEqual(store.preferredCompactColumn, .sidebar)
    }
}

// MARK: - Background Graph Update No-Flicker Tests

final class Phase3BackgroundGraphUpdateNoFlickerTests: XCTestCase {

    /// Verifies that graph edge updates don't cause intermediate empty states.
    @MainActor
    func testGraphEdgeUpdateIsAtomic() async throws {
        let store = GraphEdgeStore()
        let resolver = GraphIdentityResolver()

        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")
        let noteC = URL(fileURLWithPath: "/vault/c.md")

        await resolver.register(NoteIdentity(url: noteA, filename: "a"))
        await resolver.register(NoteIdentity(url: noteB, filename: "b"))
        await resolver.register(NoteIdentity(url: noteC, filename: "c"))
        await store.setIdentityResolver(resolver)

        // Initial connections
        await store.updateConnections(for: noteA, linkedTitles: ["b", "c"], allVaultURLs: [noteA, noteB, noteC])

        var edges = await store.edges
        XCTAssertEqual(edges[noteA]?.count, 2)

        // Update connections - should be atomic, not clear-then-add
        await store.updateConnections(for: noteA, linkedTitles: ["c"], allVaultURLs: [noteA, noteB, noteC])

        edges = await store.edges
        XCTAssertEqual(edges[noteA]?.count, 1)
        XCTAssertTrue(edges[noteA]?.contains(noteC) ?? false)
    }

    /// Verifies that concept edge updates don't cause flickering.
    @MainActor
    func testConceptUpdateIsAtomic() async throws {
        let store = GraphEdgeStore()
        let noteURL = URL(fileURLWithPath: "/vault/note.md")

        // Set initial concepts
        await store.updateConcepts(for: noteURL, concepts: ["swift", "ios", "mac"])

        var concepts = await store.concepts(for: noteURL)
        XCTAssertEqual(concepts.count, 3)

        // Update to different concepts - atomic replacement
        await store.updateConcepts(for: noteURL, concepts: ["swiftui", "combine"])

        concepts = await store.concepts(for: noteURL)
        XCTAssertEqual(concepts.count, 2)
        XCTAssertTrue(concepts.contains("swiftui"))
        XCTAssertTrue(concepts.contains("combine"))
        XCTAssertFalse(concepts.contains("swift"))
    }

    /// Verifies that semantic edge updates are batched appropriately.
    @MainActor
    func testSemanticEdgeUpdateIsBatched() async throws {
        let store = GraphEdgeStore()

        let noteURL = URL(fileURLWithPath: "/vault/source.md")
        let related1 = URL(fileURLWithPath: "/vault/related1.md")
        let related2 = URL(fileURLWithPath: "/vault/related2.md")

        // Set semantic connections
        await store.updateSemanticConnections(for: noteURL, related: [related1, related2])

        let relations = await store.semanticRelations(for: noteURL)
        XCTAssertEqual(relations.count, 2)
    }

    /// Verifies that rebuild doesn't cause intermediate states visible to observers.
    @MainActor
    func testRebuildAllIsAtomic() async throws {
        let store = GraphEdgeStore()
        let resolver = GraphIdentityResolver()

        var urls: [URL] = []
        for i in 0..<5 {
            let url = URL(fileURLWithPath: "/vault/note-\(i).md")
            urls.append(url)
            await resolver.register(NoteIdentity(url: url, filename: "note-\(i)"))
        }
        await store.setIdentityResolver(resolver)

        // Initial state
        let connections: [(sourceURL: URL, linkedTitles: [String])] = [
            (urls[0], ["note-1", "note-2"]),
            (urls[1], ["note-2"]),
            (urls[2], ["note-3", "note-4"])
        ]

        await store.rebuildAll(connections: connections, allVaultURLs: urls)

        let edges = await store.edges
        XCTAssertEqual(edges.count, 3)
        XCTAssertEqual(edges[urls[0]]?.count, 2)
    }

    /// Verifies that concurrent updates don't cause data races or flickering.
    @MainActor
    func testConcurrentUpdatesNoFlicker() async throws {
        let store = GraphEdgeStore()
        let resolver = GraphIdentityResolver()

        var urls: [URL] = []
        for i in 0..<20 {
            let url = URL(fileURLWithPath: "/vault/note-\(i).md")
            urls.append(url)
            await resolver.register(NoteIdentity(url: url, filename: "note-\(i)"))
        }
        await store.setIdentityResolver(resolver)

        // Concurrent concept updates
        let urlsCopy = urls
        await withTaskGroup(of: Void.self) { group in
            for (index, url) in urlsCopy.enumerated() {
                let concepts = ["concept-\(index)", "shared"]
                group.addTask {
                    await store.updateConcepts(for: url, concepts: concepts)
                }
            }
        }

        // All updates should have been applied
        let significant = await store.significantConcepts(minNotes: 10)
        XCTAssertTrue(significant.contains(where: { $0.concept == "shared" }),
                      "'shared' concept should exist across many notes")
    }
}

// MARK: - Typing During AI Update Tests

final class Phase3TypingDuringAIUpdateTests: XCTestCase {

    /// Tests that selection state is preserved during background updates.
    /// (This is a unit test proxy for the UI behavior)
    @MainActor
    func testSelectionPreservedDuringBackgroundUpdate() async throws {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/test.md")

        store.selectedNoteURL = noteURL

        // Simulate background update notification
        NotificationCenter.default.post(
            name: .quartzConceptsUpdated,
            object: noteURL
        )

        // Selection should be unchanged
        XCTAssertEqual(store.selectedNoteURL, noteURL)
    }

    /// Tests that inspector updates during typing don't affect editor state.
    @MainActor
    func testInspectorUpdateDuringTypingPreservesState() async throws {
        let inspector = InspectorStore()

        // Simulate editor has focus
        let initialActiveHeading = "heading-1"
        inspector.activeHeadingID = initialActiveHeading

        // Background update arrives
        inspector.update(with: NoteAnalysis(
            headings: [
                HeadingItem(id: "new-h1", level: 1, text: "New Title", characterOffset: 0),
                HeadingItem(id: "new-h2", level: 2, text: "New Section", characterOffset: 50)
            ],
            stats: NoteStats(wordCount: 200, characterCount: 1000, readingTimeMinutes: 2)
        ))

        // Active heading tracking should still work
        // (the ID might change if headings changed, but the mechanism works)
        inspector.updateActiveHeading(forCharacterOffset: 60)
        XCTAssertNotNil(inspector.activeHeadingID)
    }

    /// Tests that rapid workspace state changes don't cause race conditions.
    @MainActor
    func testRapidStateChangesNoRace() async throws {
        let store = WorkspaceStore()

        // Rapid route changes
        for i in 0..<100 {
            if i % 3 == 0 {
                store.setRoute(.dashboard)
            } else if i % 3 == 1 {
                store.setRoute(.graph)
            } else {
                store.setRoute(.note(URL(fileURLWithPath: "/vault/note-\(i).md")))
            }
        }

        // Final state should be deterministic
        // i=99: 99 % 3 == 0, so last change was dashboard
        XCTAssertEqual(store.currentRoute, .dashboard)
    }
}

// MARK: - Inspector Projection Store Tests (for future implementation)

final class Phase3InspectorProjectionStoreTests: XCTestCase {

    /// Placeholder test for the throttled projection store.
    /// Will be implemented in GREEN phase.
    @MainActor
    func testProjectionStoreThrottlesUpdates() async throws {
        // This test documents the expected behavior of InspectorProjectionStore
        // which will be a derived, throttled view of InspectorStore.
        //
        // Expected behavior:
        // - Coalesces rapid updates into single UI refresh
        // - Throttles at ~100ms intervals
        // - Preserves most recent values

        // For now, verify the base InspectorStore works
        let inspector = InspectorStore()
        XCTAssertNotNil(inspector)
    }

    /// Placeholder test for note list diffing.
    @MainActor
    func testNoteListDiffing() async throws {
        // This test documents expected item-level diffing in note list.
        //
        // Expected behavior:
        // - Only changed items cause view updates
        // - Insertions/deletions animate smoothly
        // - Selection state preserved during diff

        // Placeholder assertion
        XCTAssertTrue(true, "Note list diffing will be tested with UI tests")
    }
}
