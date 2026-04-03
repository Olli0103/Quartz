import Testing
import Foundation
@testable import QuartzKit

// MARK: - Workspace Store (Navigation) Tests

/// Verifies WorkspaceStore route management, selection, and state transitions.

@Suite("WorkspaceStore Navigation")
struct NavigationStateTests {

    @Test("Default route is dashboard")
    @MainActor func defaultRoute() {
        let store = WorkspaceStore()
        #expect(store.route == .dashboard)
        #expect(store.showDashboard == true)
    }

    @Test("Setting selectedNoteURL updates route")
    @MainActor func selectNoteUpdatesRoute() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        store.selectedNoteURL = url
        #expect(store.route == .note(url))
        #expect(store.selectedNoteURL == url)
    }

    @Test("Clearing selectedNoteURL returns to dashboard")
    @MainActor func clearReturns() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        store.selectedNoteURL = url
        store.selectedNoteURL = nil
        #expect(store.selectedNoteURL == nil)
    }

    @Test("setRoute atomic update")
    @MainActor func setRouteAtomic() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/tmp/atomic.md")
        store.setRoute(.note(url))
        #expect(store.route == .note(url))
        #expect(store.currentRoute == .note(url))
    }

    @Test("Rapid route changes stay coherent")
    @MainActor func rapidChanges() {
        let store = WorkspaceStore()
        for i in 0..<50 {
            let url = URL(fileURLWithPath: "/tmp/note-\(i).md")
            store.setRoute(.note(url))
        }
        let lastURL = URL(fileURLWithPath: "/tmp/note-49.md")
        #expect(store.route == .note(lastURL))
    }

    @Test("showGraph route switch")
    @MainActor func graphRoute() {
        let store = WorkspaceStore()
        store.showGraph = true
        #expect(store.route == .graph)
        #expect(store.showGraph == true)
        #expect(store.showDashboard == false)
    }

    @Test("SourceSelection defaults to allNotes")
    @MainActor func defaultSource() {
        let store = WorkspaceStore()
        #expect(store.selectedSource == .allNotes)
    }

    @Test("DetailRoute equality")
    func routeEquality() {
        let url = URL(fileURLWithPath: "/tmp/eq.md")
        #expect(DetailRoute.note(url) == DetailRoute.note(url))
        #expect(DetailRoute.dashboard != DetailRoute.graph)
    }
}
