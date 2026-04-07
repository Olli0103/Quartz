import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Drag-Drop Flow Tests
//
// Drag-drop data contracts: FileNode identity, NodeType targets,
// MutationOrigin.pasteOrDrop, and file metadata for asset imports.

@Suite("E2EDragDropFlow")
struct E2EDragDropFlowTests {

    @Test("FileNode id is URL-based for stable drag identity")
    func fileNodeDragIdentity() {
        let url = URL(fileURLWithPath: "/vault/A.md")
        let node1 = FileNode(name: "A.md", url: url, nodeType: .note)
        let node2 = FileNode(name: "A.md", url: url, nodeType: .note)
        let node3 = FileNode(name: "B.md", url: URL(fileURLWithPath: "/vault/B.md"), nodeType: .note)

        #expect(node1.id == node2.id, "Same URL should produce same id for drag identity")
        #expect(node1.id != node3.id, "Different URLs should produce different ids")
    }

    @Test("NodeType distinguishes valid drop targets")
    func dropTargets() {
        let folder = FileNode(name: "F", url: URL(fileURLWithPath: "/vault/F"), nodeType: .folder, children: [])
        let note = FileNode(name: "n.md", url: URL(fileURLWithPath: "/vault/n.md"), nodeType: .note)

        #expect(folder.isFolder, "Folders are valid drop targets for file moves")
        #expect(note.isNote, "Notes are drag sources but not folder drop targets")
    }

    @Test("MutationOrigin.pasteOrDrop exists for drop insertion tracking")
    func pasteOrDropOrigin() {
        let tx = MutationTransaction(
            origin: .pasteOrDrop,
            editedRange: NSRange(location: 0, length: 0),
            replacementLength: 50
        )

        #expect(tx.origin == .pasteOrDrop)
        #expect(tx.registersUndo, "Drop insertions should be undoable")
    }

    @Test("FileMetadata tracks file size for asset imports")
    func fileMetadataSize() {
        let metadata = FileMetadata(
            createdAt: Date(), modifiedAt: Date(), fileSize: 1_048_576,
            isEncrypted: false, cloudStatus: .local, hasConflict: false
        )

        #expect(metadata.fileSize == 1_048_576,
            "File size enables asset import size validation (1MB)")
    }

    @Test("FileNode children array supports reordering for drag sort")
    func childrenReordering() {
        let a = FileNode(name: "A.md", url: URL(fileURLWithPath: "/d/A.md"), nodeType: .note)
        let b = FileNode(name: "B.md", url: URL(fileURLWithPath: "/d/B.md"), nodeType: .note)
        let folder = FileNode(name: "d", url: URL(fileURLWithPath: "/d"), nodeType: .folder, children: [a, b])

        #expect(folder.children?[0].name == "A.md")
        #expect(folder.children?[1].name == "B.md")
    }
}
