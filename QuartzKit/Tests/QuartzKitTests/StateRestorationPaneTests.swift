import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - State Restoration Tests
//
// Fills the gap between VaultRestorationTests (startup coordinator phases) and
// SceneStorageTests (cursor/scroll). Tests pane-level state restoration:
// - Route serialization for @SceneStorage persistence
// - Column visibility defaults and focus mode stash/restore
// - SidebarFilter and SidebarSortOrder rawValue round-trips

@Suite("StateRestoration")
struct StateRestorationPaneTests {

    @Test("Route note URL can be serialized to path string")
    @MainActor func routeSerializesToPath() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/vault/Notes/MyNote.md")
        store.route = .note(url)

        // @SceneStorage persists the URL path as a string
        let pathString = store.selectedNoteURL?.path(percentEncoded: false)
        #expect(pathString == "/vault/Notes/MyNote.md",
            "Route note URL should serialize to a path string for @SceneStorage")
    }

    @Test("Route can be reconstructed from path string")
    @MainActor func routeReconstructsFromPath() {
        let pathString = "/vault/Notes/MyNote.md"
        let reconstructedURL = URL(fileURLWithPath: pathString)

        let store = WorkspaceStore()
        store.selectedNoteURL = reconstructedURL

        #expect(store.route == .note(reconstructedURL),
            "Route should be reconstructable from a persisted path string")
        #expect(store.selectedNoteURL?.path(percentEncoded: false) == pathString)
    }

    @Test("Column visibility defaults to .all")
    @MainActor func columnVisibilityDefault() {
        let store = WorkspaceStore()
        #expect(store.columnVisibility == .all,
            "Fresh WorkspaceStore should show all columns")
    }

    @Test("Focus mode stashes and restores column visibility")
    @MainActor func focusModeStashRestore() {
        let store = WorkspaceStore()

        // Verify default
        #expect(store.columnVisibility == .all)

        // Enter focus mode — should switch to detailOnly
        store.applyFocusMode(true)
        #expect(store.columnVisibility == .detailOnly,
            "Focus mode should hide sidebar/list columns")

        // Exit focus mode — should restore original
        store.applyFocusMode(false)
        #expect(store.columnVisibility == .all,
            "Exiting focus mode should restore original column visibility")
    }

    @Test("Source selection defaults to .allNotes")
    @MainActor func sourceSelectionDefault() {
        let store = WorkspaceStore()
        #expect(store.selectedSource == .allNotes,
            "Fresh WorkspaceStore should default to showing all notes")
    }

    @Test("SidebarFilter rawValue round-trips for all cases")
    func sidebarFilterRoundTrip() {
        for filter in SidebarFilter.allCases {
            let raw = filter.rawValue
            let restored = SidebarFilter(rawValue: raw)
            #expect(restored == filter,
                "SidebarFilter.\(filter) should round-trip through rawValue '\(raw)'")
        }
        #expect(SidebarFilter.allCases.count >= 3,
            "Should have at least all/favorites/recent filters")
    }

    @Test("SidebarSortOrder rawValue round-trips for all cases")
    func sidebarSortOrderRoundTrip() {
        for order in SidebarSortOrder.allCases {
            let raw = order.rawValue
            let restored = SidebarSortOrder(rawValue: raw)
            #expect(restored == order,
                "SidebarSortOrder.\(order) should round-trip through rawValue '\(raw)'")
        }
        #expect(SidebarSortOrder.allCases.count >= 3,
            "Should have at least name/modified/created sort orders")
    }
}
