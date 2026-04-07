import Testing
import Foundation
@testable import QuartzKit

// MARK: - Sidebar Selection Binding Tests
//
// Validates that WorkspaceStore selection binding is correct and stable:
// - selectedNoteURL ↔ route synchronization
// - Selection stability across tree refreshes
// - FileNode identity stability
// - Source change effects on selection

@Suite("SidebarSelection")
struct SidebarSelectionTests {

    @Test("selectedNoteURL derives from route")
    @MainActor func selectedNoteURLDerivesFromRoute() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/vault/note.md")

        store.route = .note(url)
        #expect(store.selectedNoteURL == url,
            "selectedNoteURL should reflect route .note(url)")
    }

    @Test("Setting selectedNoteURL updates route")
    @MainActor func settingSelectedNoteURLUpdatesRoute() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/vault/note.md")

        store.selectedNoteURL = url
        #expect(store.route == .note(url),
            "Setting selectedNoteURL should update route to .note(url)")
    }

    @Test("Clearing selectedNoteURL sets route to empty")
    @MainActor func clearingSelectedNoteURLSetsEmpty() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/vault/note.md")

        store.route = .note(url)
        store.selectedNoteURL = nil
        #expect(store.route == .empty,
            "Clearing selectedNoteURL should set route to .empty")
    }

    @Test("Selection URL survives sidebar tree rebuild")
    @MainActor func selectionSurvivesTreeRebuild() {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/folder/note.md")

        // Select a note
        store.selectedNoteURL = noteURL

        // Simulate tree rebuild — SidebarViewModel.fileTree gets replaced,
        // but WorkspaceStore holds selection independently
        let treeBefore = [
            FileNode(name: "folder", url: URL(fileURLWithPath: "/vault/folder"), nodeType: .folder, children: [
                FileNode(name: "note.md", url: noteURL, nodeType: .note)
            ])
        ]
        let treeAfter = [
            FileNode(name: "folder", url: URL(fileURLWithPath: "/vault/folder"), nodeType: .folder, children: [
                FileNode(name: "note.md", url: noteURL, nodeType: .note),
                FileNode(name: "new.md", url: URL(fileURLWithPath: "/vault/folder/new.md"), nodeType: .note)
            ])
        ]

        // Verify trees are different (new note added)
        #expect(treeBefore.count == treeAfter.count)
        #expect(treeBefore[0].children?.count != treeAfter[0].children?.count)

        // Selection should be unaffected by tree change
        #expect(store.selectedNoteURL == noteURL,
            "Selection URL should survive tree rebuild")
        #expect(store.route == .note(noteURL))
    }

    @Test("FileNode id is stable across refresh")
    func fileNodeIdStableAcrossRefresh() {
        let url = URL(fileURLWithPath: "/vault/Stable.md")
        let node1 = FileNode(name: "Stable.md", url: url, nodeType: .note)
        let node2 = FileNode(name: "Stable.md", url: url, nodeType: .note)

        #expect(node1.id == node2.id,
            "Same URL should produce same id for stable SwiftUI List identity")

        // Different URL produces different id
        let otherURL = URL(fileURLWithPath: "/vault/Other.md")
        let node3 = FileNode(name: "Other.md", url: otherURL, nodeType: .note)
        #expect(node1.id != node3.id,
            "Different URLs should produce different ids")
    }

    @Test("Source change clears unrelated note selection")
    @MainActor func sourceChangeClearsUnrelatedSelection() {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/folderA/note.md")
        let folderBURL = URL(fileURLWithPath: "/vault/folderB")

        // Select a note in folderA
        store.route = .note(noteURL)

        // Switch source to folderB — note is not inside folderB
        store.selectedSource = .folder(folderBURL)

        #expect(store.route == .empty,
            "Changing to a folder that doesn't contain the selected note should clear selection")
        #expect(store.selectedNoteURL == nil)
    }

    @Test("Source change preserves in-folder selection")
    @MainActor func sourceChangePreservesInFolderSelection() {
        let store = WorkspaceStore()
        let folderURL = URL(fileURLWithPath: "/vault/folder")
        let noteURL = URL(fileURLWithPath: "/vault/folder/note.md")

        // Select a note inside the folder
        store.route = .note(noteURL)

        // Switch source to the same folder — note IS inside this folder
        store.selectedSource = .folder(folderURL)

        #expect(store.route == .note(noteURL),
            "Switching to a folder containing the selected note should preserve selection")
        #expect(store.selectedNoteURL == noteURL)
    }

    @Test("routeChangeCount increments on each route change")
    @MainActor func routeChangeCountIncrements() {
        let store = WorkspaceStore()
        let initialCount = store.routeChangeCount

        store.route = .note(URL(fileURLWithPath: "/vault/a.md"))
        #expect(store.routeChangeCount == initialCount + 1)

        store.route = .dashboard
        #expect(store.routeChangeCount == initialCount + 2)

        store.route = .graph
        #expect(store.routeChangeCount == initialCount + 3)

        store.route = .empty
        #expect(store.routeChangeCount == initialCount + 4)
    }
}
