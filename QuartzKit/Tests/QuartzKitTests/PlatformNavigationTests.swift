import Testing
import Foundation
@testable import QuartzKit

// MARK: - Platform Navigation Tests

@Suite("PlatformNavigation")
struct PlatformNavigationTests {

    @Test("WorkspaceStore route lifecycle: dashboard → note → graph")
    @MainActor func routeLifecycle() {
        let store = WorkspaceStore()

        // Initial route
        store.route = .dashboard
        #expect(store.showDashboard == true)
        #expect(store.showGraph == false)

        // Navigate to note
        let noteURL = URL(fileURLWithPath: "/vault/test.md")
        store.route = .note(noteURL)
        #expect(store.selectedNoteURL == noteURL)
        #expect(store.showDashboard == false)

        // Navigate to graph
        store.route = .graph
        #expect(store.showGraph == true)
        #expect(store.showDashboard == false)
    }

    @Test("SourceSelection cases are distinct")
    func sourceSelectionCases() {
        let allNotes = SourceSelection.allNotes
        let favorites = SourceSelection.favorites
        let recent = SourceSelection.recent
        let folder = SourceSelection.folder(URL(fileURLWithPath: "/vault/Projects"))
        let tag = SourceSelection.tag("swift")

        // All cases are distinct
        #expect(allNotes != favorites)
        #expect(favorites != recent)
        #expect(allNotes != recent)

        // Associated value cases
        if case .folder(let url) = folder {
            #expect(url.lastPathComponent == "Projects")
        } else {
            Issue.record("Expected .folder case")
        }

        if case .tag(let t) = tag {
            #expect(t == "swift")
        } else {
            Issue.record("Expected .tag case")
        }
    }
}
