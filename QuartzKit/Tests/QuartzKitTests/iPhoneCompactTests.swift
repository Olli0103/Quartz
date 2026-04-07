import Testing
import Foundation
@testable import QuartzKit

// MARK: - iPhone Compact Layout Tests
//
// Stack navigation data contracts for compact width:
// touch target sizing, column preferences, and flat traversal.

@Suite("iPhoneCompact")
struct iPhoneCompactTests {

    @Test("DetailRoute.note triggers detail column preference")
    @MainActor func noteRoutePrefersDetail() {
        let store = WorkspaceStore()
        store.route = .note(URL(fileURLWithPath: "/vault/note.md"))

        // On iPhone, .note should push to detail column
        #expect(store.route == .note(URL(fileURLWithPath: "/vault/note.md")))
        #expect(store.selectedNoteURL != nil,
            "Compact layout needs selectedNoteURL to show editor")
    }

    @Test("DetailRoute.empty allows content column focus")
    @MainActor func emptyRouteAllowsContent() {
        let store = WorkspaceStore()
        store.route = .empty

        #expect(store.selectedNoteURL == nil,
            "Empty route on compact should show note list, not editor")
    }

    @Test("QuartzHIG minTouchTarget is 44pt per Apple HIG")
    func minTouchTarget() {
        #expect(QuartzHIG.minTouchTarget == 44,
            "Apple HIG requires minimum 44pt touch targets")
    }

    @Test("FileNode tree supports flat traversal for stack navigation")
    func flatTraversal() {
        let tree = [
            FileNode(name: "A.md", url: URL(fileURLWithPath: "/vault/A.md"), nodeType: .note),
            FileNode(name: "Folder", url: URL(fileURLWithPath: "/vault/Folder"), nodeType: .folder, children: [
                FileNode(name: "B.md", url: URL(fileURLWithPath: "/vault/Folder/B.md"), nodeType: .note)
            ]),
            FileNode(name: "C.md", url: URL(fileURLWithPath: "/vault/C.md"), nodeType: .note)
        ]

        // Flat collection of all notes for stack nav list
        var notes: [FileNode] = []
        func collect(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isNote { notes.append(node) }
                if let children = node.children { collect(children) }
            }
        }
        collect(tree)

        #expect(notes.count == 3, "Flat traversal should find all notes for compact list")
    }

    @Test("NoteListItem has sufficient data for compact cell")
    func compactCellData() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/vault/note.md"),
            title: "Note Title",
            modifiedAt: Date(),
            fileSize: 2048,
            snippet: "Preview text...",
            tags: ["tag1"],
            isFavorite: false
        )

        #expect(!item.title.isEmpty, "Compact cell needs title")
        #expect(!item.snippet.isEmpty, "Compact cell needs snippet preview")
        #expect(item.modifiedAt <= Date(), "Modified date for relative timestamp")
    }

    @Test("SourceSelection variants are all navigable")
    @MainActor func sourceSelectionNavigable() {
        let store = WorkspaceStore()
        let sources: [SourceSelection] = [
            .allNotes, .favorites, .recent,
            .folder(URL(fileURLWithPath: "/vault/Docs")),
            .tag("swift")
        ]

        for source in sources {
            store.selectedSource = source
            #expect(store.selectedSource == source,
                "SourceSelection.\(source) should be settable for compact nav")
        }
    }
}
