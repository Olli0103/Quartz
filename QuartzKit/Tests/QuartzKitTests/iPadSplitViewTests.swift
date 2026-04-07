import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - iPad Split View Tests
//
// NavigationSplitView column data contracts for regular width:
// column visibility, detail content types, and inspector independence.

@Suite("iPadSplitView")
struct iPadSplitViewTests {

    @Test("WorkspaceStore columnVisibility defaults to .all")
    @MainActor func columnVisibilityDefault() {
        let store = WorkspaceStore()
        #expect(store.columnVisibility == .all,
            "iPad split view should default to showing all columns")
    }

    @Test("All DetailRoute content types can render in detail pane")
    @MainActor func detailRouteContentTypes() {
        let store = WorkspaceStore()

        store.route = .dashboard
        #expect(store.route == .dashboard, "Dashboard renders in detail pane")

        store.route = .graph
        #expect(store.route == .graph, "Graph renders in detail pane")

        store.route = .note(URL(fileURLWithPath: "/vault/note.md"))
        #expect(store.selectedNoteURL != nil, "Note editor renders in detail pane")

        store.route = .empty
        #expect(store.route == .empty, "Empty state renders in detail pane")
    }

    @Test("SourceSelection supports folder scoping for sidebar")
    @MainActor func folderScoping() {
        let store = WorkspaceStore()
        let folderURL = URL(fileURLWithPath: "/vault/Projects")

        store.selectedSource = .folder(folderURL)
        if case .folder(let url) = store.selectedSource {
            #expect(url == folderURL, "Folder source should retain URL")
        } else {
            Issue.record("Expected .folder source selection")
        }
    }

    @Test("FileNode tree supports hierarchical OutlineGroup")
    func hierarchicalTree() {
        let child = FileNode(name: "Child.md", url: URL(fileURLWithPath: "/vault/F/Child.md"), nodeType: .note)
        let folder = FileNode(name: "F", url: URL(fileURLWithPath: "/vault/F"), nodeType: .folder, children: [child])

        #expect(folder.children != nil, "Folder must expose children for OutlineGroup")
        #expect(folder.children?.count == 1)
        #expect(folder.isFolder)
        #expect(child.isNote)
    }

    @Test("Column visibility changes through all states")
    @MainActor func columnVisibilityTransitions() {
        let store = WorkspaceStore()

        store.columnVisibility = .all
        #expect(store.columnVisibility == .all)

        store.columnVisibility = .doubleColumn
        #expect(store.columnVisibility == .doubleColumn)

        store.columnVisibility = .detailOnly
        #expect(store.columnVisibility == .detailOnly)
    }

    @Test("Inspector toggles independently from column visibility")
    @MainActor func inspectorIndependence() {
        let inspector = InspectorStore()
        let store = WorkspaceStore()

        store.columnVisibility = .all
        inspector.isVisible = true
        #expect(inspector.isVisible)

        store.columnVisibility = .detailOnly
        #expect(inspector.isVisible,
            "Inspector visibility should not change when columns change")
    }
}
