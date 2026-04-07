import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - E2E Focus Mode Flow Tests
//
// Focus enter → chrome hidden → exit → restore: column visibility
// stash/restore, route preservation, source selection stability.

@Suite("E2EFocusModeFlow")
struct E2EFocusModeFlowTests {

    @Test("applyFocusMode(true) sets detailOnly")
    @MainActor func enterFocusMode() {
        let store = WorkspaceStore()
        store.applyFocusMode(true)
        #expect(store.columnVisibility == .detailOnly,
            "Focus mode should hide sidebar and content columns")
    }

    @Test("applyFocusMode(false) restores stashed visibility")
    @MainActor func exitFocusMode() {
        let store = WorkspaceStore()
        #expect(store.columnVisibility == .all)

        store.applyFocusMode(true)
        store.applyFocusMode(false)
        #expect(store.columnVisibility == .all,
            "Exiting focus should restore to pre-focus visibility")
    }

    @Test("Focus mode preserves active route")
    @MainActor func routePreserved() {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/writing.md")
        store.route = .note(noteURL)

        store.applyFocusMode(true)
        #expect(store.route == .note(noteURL), "Route must survive focus mode entry")

        store.applyFocusMode(false)
        #expect(store.route == .note(noteURL), "Route must survive focus mode exit")
    }

    @Test("Focus mode preserves selected source")
    @MainActor func sourcePreserved() {
        let store = WorkspaceStore()
        store.selectedSource = .favorites

        store.applyFocusMode(true)
        #expect(store.selectedSource == .favorites, "Source should not change in focus mode")

        store.applyFocusMode(false)
        #expect(store.selectedSource == .favorites)
    }

    @Test("Double-toggle returns to exact original state")
    @MainActor func doubleToggle() {
        let store = WorkspaceStore()
        store.columnVisibility = .doubleColumn

        store.applyFocusMode(true)
        store.applyFocusMode(false)
        #expect(store.columnVisibility == .doubleColumn,
            "Double-toggle should return to exact original column state")
    }

    @Test("Focus mode from non-default visibility restores correctly")
    @MainActor func nonDefaultRestore() {
        let store = WorkspaceStore()

        // Start from doubleColumn (not the .all default)
        store.columnVisibility = .doubleColumn
        store.applyFocusMode(true)
        #expect(store.columnVisibility == .detailOnly)

        store.applyFocusMode(false)
        #expect(store.columnVisibility == .doubleColumn,
            "Focus mode should stash/restore any starting visibility")
    }
}
