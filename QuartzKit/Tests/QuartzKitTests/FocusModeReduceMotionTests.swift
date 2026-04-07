import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Focus Mode Reduce Motion Tests
//
// Focus mode transitions respect Reduce Motion: instant state swaps,
// no animation dependency in the state machine.

@Suite("FocusModeReduceMotion")
struct FocusModeReduceMotionTests {

    @Test("Focus mode toggle is a synchronous state swap")
    @MainActor func focusModeInstant() {
        let store = WorkspaceStore()
        #expect(store.columnVisibility == .all)

        // Enter focus — instant swap, no animation needed
        store.applyFocusMode(true)
        #expect(store.columnVisibility == .detailOnly,
            "Focus mode should instantly change visibility without animation dependency")

        // Exit focus — instant restore
        store.applyFocusMode(false)
        #expect(store.columnVisibility == .all,
            "Exiting focus should instantly restore visibility")
    }

    @Test("Column visibility change is a simple enum swap")
    @MainActor func columnVisibilityEnumSwap() {
        let store = WorkspaceStore()

        // Direct enum assignment — no animation required
        store.columnVisibility = .detailOnly
        #expect(store.columnVisibility == .detailOnly)

        store.columnVisibility = .all
        #expect(store.columnVisibility == .all)
    }

    @Test("Focus mode stash/restore is synchronous without async")
    @MainActor func stashRestoreSynchronous() {
        let store = WorkspaceStore()

        // Start from non-default state
        store.columnVisibility = .doubleColumn
        store.applyFocusMode(true)
        #expect(store.columnVisibility == .detailOnly)

        store.applyFocusMode(false)
        #expect(store.columnVisibility == .doubleColumn,
            "Stash/restore must be synchronous for Reduce Motion compliance")
    }

    @Test("Focus mode preserves route during transition")
    @MainActor func routePreserved() {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        store.route = .note(noteURL)

        store.applyFocusMode(true)
        #expect(store.route == .note(noteURL), "Route must not change during focus transition")

        store.applyFocusMode(false)
        #expect(store.route == .note(noteURL), "Route must not change when exiting focus")
    }
}
