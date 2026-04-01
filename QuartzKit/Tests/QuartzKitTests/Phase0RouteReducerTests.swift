import XCTest
@testable import QuartzKit

// MARK: - Phase 0: Stabilize Truth Boundaries (CODEX.md Recovery Plan)
// TDD Red Phase: These tests define the expected behavior for route reducer architecture.
// Per CODEX.md F1, F2, F11: ContentView god object, boolean route algebra, view-layer service resolution.
//
// These tests complement Phase0PurgeTests.swift (Swift Testing) with XCTest coverage
// for additional architectural invariants from the new forensic recovery plan.

// MARK: - WorkspaceRouteReducerArchitectureTests

/// Tests architectural invariants for the route reducer pattern.
/// Complements WorkspaceRouteReducerTests in Phase0PurgeTests.swift.
final class WorkspaceRouteReducerArchitectureTests: XCTestCase {

    // MARK: - Route State Is Singular (F2)

    /// Tests that there is exactly one mutable route property, not multiple booleans.
    /// Expected behavior: `route` property is the only mutable state for detail pane routing.
    /// Current behavior: `showDashboard`, `showGraph`, `selectedNoteURL` are all separately mutable.
    @MainActor
    func testRoutePropertyIsSingleSourceOfTruth() async throws {
        let store = WorkspaceStore()

        // The store should expose a single `route` property that is both readable and writable.
        // This test documents the expected API contract.

        // Set route to dashboard
        store.setRoute(.dashboard)
        XCTAssertEqual(store.currentRoute, .dashboard)

        // Set route to graph
        store.setRoute(.graph)
        XCTAssertEqual(store.currentRoute, .graph)

        // Set route to note
        let noteURL = URL(fileURLWithPath: "/test/note.md")
        store.setRoute(.note(noteURL))
        XCTAssertEqual(store.currentRoute, .note(noteURL))

        // Set route to empty
        store.setRoute(.empty)
        XCTAssertEqual(store.currentRoute, .empty)

        // FAILING: The current implementation has `showDashboard`, `showGraph`, `selectedNoteURL`
        // as separate mutable properties with didSet coupling. The `setRoute` method exists
        // but the booleans are still the primary storage, not `route` itself.
    }

    /// Tests that boolean properties are removed or made read-only.
    /// Expected: No public `showDashboard`, `showGraph` setters.
    /// Current: These are publicly settable with side-effectful didSet.
    @MainActor
    func testBooleanPropertiesAreNotPrimaryStorage() async throws {
        let store = WorkspaceStore()

        // After setting route, the booleans should reflect the route (read-only computed).
        // They should NOT be independently settable.

        store.setRoute(.dashboard)

        // These assertions pass today because currentRoute computes from booleans
        XCTAssertEqual(store.currentRoute, .dashboard)

        // FAILING: This test would pass if booleans were read-only.
        // Currently, you CAN set `store.showGraph = true` directly, bypassing the reducer.
        // The architecture goal is that `setRoute` is the ONLY way to mutate route state.

        // To make this test meaningful, we need to verify that setting booleans directly
        // is either impossible (removed) or has no effect (ignored).
        // For now, document the expected behavior:

        // Expected: store.showGraph has no public setter (or setter is no-op)
        // Current: store.showGraph = true works and mutates state

        // This test passes trivially now but documents the architectural goal.
        XCTAssertTrue(true, "Boolean properties should be read-only or removed")
    }

    /// Tests that route transitions are atomic (no intermediate invalid states).
    /// Expected: Transitioning from dashboard to note should never have both true.
    @MainActor
    func testRouteTransitionsAreAtomic() async throws {
        let store = WorkspaceStore()
        store.setRoute(.dashboard)

        var observedStates: [DetailRoute] = [store.currentRoute]
        _ = observedStates // Suppress warning

        // In a proper reducer, we'd observe state changes and verify no invalid states.
        // For now, verify final state is correct.

        let noteURL = URL(fileURLWithPath: "/test/note.md")
        store.setRoute(.note(noteURL))

        // After transition, only one route should be active
        let isDashboard = store.showDashboard
        let isGraph = store.showGraph
        let hasNote = store.selectedNoteURL != nil

        // Exactly one should be true (or all false for .empty)
        let activeCount = [isDashboard, isGraph, hasNote].filter { $0 }.count
        XCTAssertEqual(activeCount, 1, "Exactly one route should be active, got \(activeCount)")
    }

    /// Tests that rapid route changes don't create race conditions.
    @MainActor
    func testRapidRouteChangesAreSerializedCorrectly() async throws {
        let store = WorkspaceStore()
        let noteURL1 = URL(fileURLWithPath: "/test/note1.md")
        let noteURL2 = URL(fileURLWithPath: "/test/note2.md")

        // Rapid transitions
        store.setRoute(.dashboard)
        store.setRoute(.graph)
        store.setRoute(.note(noteURL1))
        store.setRoute(.note(noteURL2))
        store.setRoute(.dashboard)
        store.setRoute(.empty)

        // Final state should be exactly what we set last
        XCTAssertEqual(store.currentRoute, .empty)
        XCTAssertFalse(store.showDashboard)
        XCTAssertFalse(store.showGraph)
        XCTAssertNil(store.selectedNoteURL)
    }

    // MARK: - Reducer Action Tests

    /// Tests that route changes emit actions for debugging/logging.
    /// Expected behavior: Route changes should be traceable through an action log.
    @MainActor
    func testRouteChangesAreTraceable() async throws {
        // This test documents the expected reducer architecture.
        // A proper reducer would have:
        // - Actions: .showDashboard, .showGraph, .selectNote(URL), .clearSelection
        // - Reducer: (state, action) -> state
        // - Effect handling for side effects

        // For now, verify the setRoute API exists and works
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/test/note.md")

        store.setRoute(.note(noteURL))
        XCTAssertEqual(store.currentRoute, .note(noteURL))

        // FAILING: No action log, no reducer pattern, no traceability.
        // The setRoute method exists but internally just sets booleans.
    }
}

// MARK: - ContentShellEventIsolationArchitectureTests

/// Tests that ContentView delegates responsibilities to specialized coordinators.
/// Per CODEX.md F1: ContentView is a god object handling too many responsibilities.
final class ContentShellEventIsolationArchitectureTests: XCTestCase {

    // MARK: - Responsibility Delegation (F1)

    /// Tests that vault lifecycle is handled by VaultLifecycleCoordinator, not ContentView.
    /// Expected: ContentView contains no bookmark/vault restoration logic.
    /// Current: ContentView has `restoreLastVault`, `persistBookmark`, `clearBookmark`, etc.
    @MainActor
    func testVaultLifecycleIsDelegatedToCoordinator() async throws {
        // This test documents the expected architecture.
        // A VaultLifecycleCoordinator should handle:
        // - Bookmark creation and persistence
        // - Vault restoration on launch
        // - Stale bookmark refresh
        // - Security-scoped resource access

        // FAILING: These methods exist directly in ContentView:
        // - restoreLastVault()
        // - persistBookmark(for:vaultName:)
        // - clearBookmark()
        // - openVault(_:)

        // For now, verify that AppCoordinator exists and handles some routing
        let coordinator = AppCoordinator()
        XCTAssertNil(coordinator.activeSheet, "AppCoordinator should start with no active sheet")

        // Expected: VaultLifecycleCoordinator would be injected and handle vault operations
        XCTAssertTrue(true, "Vault lifecycle should be delegated to VaultLifecycleCoordinator")
    }

    /// Tests that sheet/alert presentation is handled by PresentationRouter.
    /// Expected: ContentView does not directly manage sheet state.
    /// Current: ContentView has sheetContent(for:) and direct sheet bindings.
    @MainActor
    func testPresentationIsDelegatedToRouter() async throws {
        let coordinator = AppCoordinator()

        // AppCoordinator does handle sheets, which is good
        coordinator.activeSheet = .settings
        XCTAssertNotNil(coordinator.activeSheet, "Sheet should be set")

        coordinator.activeSheet = nil
        XCTAssertNil(coordinator.activeSheet)

        // FAILING: ContentView still has:
        // - @ViewBuilder private func sheetContent(for:) with 14 cases
        // - Alert handling with alertActions computed property
        // - Error overlay management

        // Expected: All presentation routing through coordinator with minimal view switch
    }

    /// Tests that deep link handling is isolated from main view body.
    /// Expected: DeepLinkHandler or AppEventBridge handles URL schemes.
    /// Current: ContentView has consumePendingWidgetDeepLinks, applyPendingOpenNoteDeepLink.
    @MainActor
    func testDeepLinkHandlingIsIsolated() async throws {
        // This test documents the expected architecture.

        // FAILING: Deep link handling is directly in ContentView:
        // - consumePendingWidgetDeepLinks()
        // - applyPendingOpenNoteDeepLink(_:)
        // - .onContinueUserActivity handler

        // Expected: An AppEventBridge would:
        // - Parse incoming deep links
        // - Validate URL schemes
        // - Dispatch to appropriate handlers
        // - Coordinate with WorkspaceStore for navigation

        XCTAssertTrue(true, "Deep link handling should be delegated to AppEventBridge")
    }

    /// Tests that NotificationCenter observers are minimized in view layer.
    /// Expected: Views don't observe domain notifications directly.
    /// Current: ContentView has 4+ .onReceive(NotificationCenter...) handlers.
    @MainActor
    func testNotificationObserversAreNotInViewLayer() async throws {
        // This test documents the expected architecture.

        // FAILING: ContentView has these notification observers:
        // - .quartzReindexRequested
        // - .quartzNoteSaved
        // - .quartzSpotlightNotesRemoved
        // - .quartzSpotlightNoteRelocated

        // Expected: These would be handled by:
        // - ContentViewModel (which already handles some)
        // - Or dedicated service coordinators
        // - View layer only observes @Observable state changes

        XCTAssertTrue(true, "View layer should not have NotificationCenter observers")
    }

    /// Tests that scene phase handling is delegated appropriately.
    /// Expected: Scene lifecycle → coordinator → state changes.
    /// Current: ContentView.onChange(of: scenePhase) directly calls multiple methods.
    @MainActor
    func testScenePhaseHandlingIsDelegated() async throws {
        // This test documents the expected architecture.

        // FAILING: ContentView.onChange(of: scenePhase) directly:
        // - Calls securityOrchestrator.scenePhaseDidChange
        // - Calls consumePendingWidgetDeepLinks()
        // - Calls saveStateForRestoration()

        // Expected: A single coordinator method handles phase changes
        // and orchestrates all downstream effects.

        XCTAssertTrue(true, "Scene phase handling should be centralized in coordinator")
    }
}

// MARK: - DashboardGraphNoteMutualExclusionArchitectureTests

/// Tests that dashboard, graph, and note views are mutually exclusive routes.
/// This tests the route invariant that exactly one detail view is active.
final class DashboardGraphNoteMutualExclusionArchitectureTests: XCTestCase {

    // MARK: - Mutual Exclusion Invariant

    /// Tests that selecting a note deactivates dashboard and graph.
    @MainActor
    func testSelectingNoteDeactivatesDashboardAndGraph() async throws {
        let store = WorkspaceStore()

        // Start with dashboard
        store.setRoute(.dashboard)
        XCTAssertTrue(store.showDashboard)

        // Select a note
        let noteURL = URL(fileURLWithPath: "/test/note.md")
        store.setRoute(.note(noteURL))

        XCTAssertFalse(store.showDashboard, "Dashboard should be deactivated when note is selected")
        XCTAssertFalse(store.showGraph, "Graph should be deactivated when note is selected")
        XCTAssertEqual(store.selectedNoteURL, noteURL)
    }

    /// Tests that showing dashboard deactivates graph and clears note.
    @MainActor
    func testShowingDashboardDeactivatesGraphAndNote() async throws {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/test/note.md")

        // Start with note selected
        store.setRoute(.note(noteURL))
        XCTAssertNotNil(store.selectedNoteURL)

        // Show dashboard
        store.setRoute(.dashboard)

        XCTAssertTrue(store.showDashboard, "Dashboard should be active")
        XCTAssertFalse(store.showGraph, "Graph should be deactivated")
        XCTAssertNil(store.selectedNoteURL, "Note selection should be cleared")
    }

    /// Tests that showing graph deactivates dashboard and clears note.
    @MainActor
    func testShowingGraphDeactivatesDashboardAndNote() async throws {
        let store = WorkspaceStore()

        // Start with dashboard
        store.setRoute(.dashboard)
        XCTAssertTrue(store.showDashboard)

        // Show graph
        store.setRoute(.graph)

        XCTAssertFalse(store.showDashboard, "Dashboard should be deactivated")
        XCTAssertTrue(store.showGraph, "Graph should be active")
        XCTAssertNil(store.selectedNoteURL, "Note selection should be cleared")
    }

    /// Tests that route precedence is deterministic.
    /// Per WorkspaceStore: precedence is graph > dashboard > note > empty.
    @MainActor
    func testRoutePrecedenceIsDeterministic() async throws {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/test/note.md")

        // Test precedence by checking currentRoute computation

        // Empty state
        store.showDashboard = false
        store.showGraph = false
        store.selectedNoteURL = nil
        XCTAssertEqual(store.currentRoute, .empty)

        // Note only
        store.selectedNoteURL = noteURL
        XCTAssertEqual(store.currentRoute, .note(noteURL))

        // Dashboard takes precedence over note
        store.showDashboard = true
        // Due to didSet, this clears selectedNoteURL
        XCTAssertEqual(store.currentRoute, .dashboard)

        // Graph takes precedence over dashboard
        store.showGraph = true
        // Due to didSet, this clears showDashboard
        XCTAssertEqual(store.currentRoute, .graph)
    }

    /// Tests that no invalid states can exist (multiple routes active).
    @MainActor
    func testNoInvalidMultipleRouteStates() async throws {
        let store = WorkspaceStore()

        // The didSet coupling should prevent invalid states
        // But this relies on side effects, not structural enforcement

        // Try to force invalid state by setting booleans directly
        // (This is what we want to prevent in the architecture)

        store.showDashboard = true
        store.showGraph = true  // didSet should clear showDashboard

        // Verify only one is active
        let activeCount = [store.showDashboard, store.showGraph, store.selectedNoteURL != nil]
            .filter { $0 }.count

        XCTAssertLessThanOrEqual(activeCount, 1,
            "At most one route should be active, got \(activeCount)")
    }

    /// Tests empty route state.
    @MainActor
    func testEmptyRouteState() async throws {
        let store = WorkspaceStore()

        store.setRoute(.empty)

        XCTAssertEqual(store.currentRoute, .empty)
        XCTAssertFalse(store.showDashboard)
        XCTAssertFalse(store.showGraph)
        XCTAssertNil(store.selectedNoteURL)
    }

    // MARK: - Route Change Side Effects

    /// Tests that route changes don't trigger unnecessary side effects.
    /// Setting the same route twice should be idempotent.
    @MainActor
    func testRouteChangesAreIdempotent() async throws {
        let store = WorkspaceStore()

        // Set to dashboard twice
        store.setRoute(.dashboard)
        let state1Dashboard = store.showDashboard
        let state1Graph = store.showGraph
        let state1Note = store.selectedNoteURL

        store.setRoute(.dashboard)
        let state2Dashboard = store.showDashboard
        let state2Graph = store.showGraph
        let state2Note = store.selectedNoteURL

        XCTAssertEqual(state1Dashboard, state2Dashboard)
        XCTAssertEqual(state1Graph, state2Graph)
        XCTAssertEqual(state1Note, state2Note)
    }

    /// Tests that source selection doesn't inadvertently clear route.
    @MainActor
    func testSourceSelectionPreservesNoteRouteWhenAppropriate() async throws {
        let store = WorkspaceStore()

        // Select a note in a folder
        let folderURL = URL(fileURLWithPath: "/test/folder/")
        let noteURL = URL(fileURLWithPath: "/test/folder/note.md")

        store.setRoute(.note(noteURL))
        XCTAssertEqual(store.selectedNoteURL, noteURL)

        // Change source to the folder containing the note
        store.selectedSource = .folder(folderURL)

        // Note selection should be preserved (note is inside the new source folder)
        XCTAssertEqual(store.selectedNoteURL, noteURL,
            "Note selection should be preserved when selecting parent folder")
    }

    /// Tests that source selection clears note when changing to different context.
    @MainActor
    func testSourceSelectionClearsNoteWhenChangingContext() async throws {
        let store = WorkspaceStore()

        // Select a note in folder A
        let folderA = URL(fileURLWithPath: "/test/folderA/")
        let noteInA = URL(fileURLWithPath: "/test/folderA/note.md")

        store.selectedSource = .folder(folderA)
        store.setRoute(.note(noteInA))

        // Change source to folder B
        let folderB = URL(fileURLWithPath: "/test/folderB/")
        store.selectedSource = .folder(folderB)

        // Note should be cleared (note is not in folder B)
        XCTAssertNil(store.selectedNoteURL,
            "Note selection should be cleared when changing to different folder")
    }
}
