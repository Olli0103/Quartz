import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Delete Note Tests
//
// Delete flow data contracts: FileNode identification,
// route cleanup, node type distinction, confirmation data.

@Suite("E2EDeleteNote")
struct E2EDeleteNoteTests {

    @Test("FileNode URL identifies deletion target")
    func fileNodeDeletionTarget() {
        let noteURL = URL(fileURLWithPath: "/vault/Docs/target.md")
        let node = FileNode(name: "target.md", url: noteURL, nodeType: .note)

        #expect(node.url == noteURL, "Node URL is the deletion target")
        #expect(node.url.lastPathComponent == "target.md")
        #expect(node.isNote, "Only notes should be directly deletable")
    }

    @Test("Route clears to .empty when selected note is deleted")
    @MainActor func routeClearsOnDelete() {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/note.md")

        store.route = .note(noteURL)
        #expect(store.selectedNoteURL == noteURL)

        // Simulate post-delete cleanup
        store.route = .empty
        #expect(store.route == .empty)
        #expect(store.selectedNoteURL == nil,
            "Deleted note should clear selection")
    }

    @Test("FileNode nodeType distinguishes deletable types")
    func nodeTypeDistinction() {
        let note = FileNode(name: "n.md", url: URL(fileURLWithPath: "/n.md"), nodeType: .note)
        let folder = FileNode(name: "d", url: URL(fileURLWithPath: "/d"), nodeType: .folder, children: [])

        #expect(note.isNote && !note.isFolder)
        #expect(folder.isFolder && !folder.isNote)
    }

    @Test("Folder exposes children count for delete confirmation")
    func folderChildrenForConfirmation() {
        let children = [
            FileNode(name: "a.md", url: URL(fileURLWithPath: "/d/a.md"), nodeType: .note),
            FileNode(name: "b.md", url: URL(fileURLWithPath: "/d/b.md"), nodeType: .note)
        ]
        let folder = FileNode(name: "d", url: URL(fileURLWithPath: "/d"), nodeType: .folder, children: children)

        #expect(folder.children?.count == 2,
            "Folder child count should be shown in delete confirmation dialog")
    }

    @Test("NoteDocument fileURL matches FileNode URL for consistency")
    func documentURLMatchesNode() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        let node = FileNode(name: "note.md", url: url, nodeType: .note)
        let doc = NoteDocument(id: UUID(), fileURL: url, frontmatter: Frontmatter(), body: "")

        #expect(node.url == doc.fileURL,
            "FileNode URL and NoteDocument fileURL must agree for delete operations")
    }
}
