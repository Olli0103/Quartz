import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Sidebar Accessibility Tests

@Suite("VoiceOverSidebar")
struct VoiceOverSidebarTests {

    @Test("FileNode provides accessible name via name property")
    func fileNodeAccessibleName() {
        let noteNode = FileNode(
            name: "My Note.md",
            url: URL(fileURLWithPath: "/vault/My Note.md"),
            nodeType: .note
        )
        #expect(noteNode.name == "My Note.md")
        #expect(noteNode.isNote == true)
        #expect(noteNode.isFolder == false)

        let folderNode = FileNode(
            name: "Projects",
            url: URL(fileURLWithPath: "/vault/Projects"),
            nodeType: .folder,
            children: []
        )
        #expect(folderNode.name == "Projects")
        #expect(folderNode.isFolder == true)
    }

    @Test("FileNode distinguishes notes from folders for VoiceOver hints")
    func fileNodeTypeDistinction() {
        let note = FileNode(name: "a.md", url: URL(fileURLWithPath: "/v/a.md"), nodeType: .note)
        let folder = FileNode(name: "b", url: URL(fileURLWithPath: "/v/b"), nodeType: .folder, children: [])

        #expect(note.isNote == true)
        #expect(note.isFolder == false)
        #expect(folder.isFolder == true)
        #expect(folder.isNote == false)
    }

    @Test("FileNode id is stable across refreshes for VoiceOver identity")
    func fileNodeStableId() {
        let url = URL(fileURLWithPath: "/vault/Stable.md")
        let node1 = FileNode(name: "Stable.md", url: url, nodeType: .note)
        let node2 = FileNode(name: "Stable.md", url: url, nodeType: .note)
        #expect(node1.id == node2.id, "Same URL should produce same id for VoiceOver stability")
    }

    @Test("FileNode children are accessible for folder disclosure")
    func fileNodeChildrenAccessible() {
        let child1 = FileNode(name: "A.md", url: URL(fileURLWithPath: "/v/d/A.md"), nodeType: .note)
        let child2 = FileNode(name: "B.md", url: URL(fileURLWithPath: "/v/d/B.md"), nodeType: .note)
        let folder = FileNode(
            name: "Docs",
            url: URL(fileURLWithPath: "/v/d"),
            nodeType: .folder,
            children: [child1, child2]
        )
        #expect(folder.children?.count == 2,
            "VoiceOver should announce child count for folder disclosure")
    }

    @Test("CommandRegistry commands all have IDs, titles, and icons")
    @MainActor func commandRegistryCompleteness() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
        #expect(commands.count >= 8)

        for cmd in commands {
            #expect(!cmd.id.isEmpty, "Command must have a non-empty id")
            #expect(!cmd.title.isEmpty, "Command must have a non-empty title for VoiceOver")
            #expect(!cmd.icon.isEmpty, "Command must have a non-empty icon")
        }
    }

    @Test("CommandRegistry command IDs are unique for Voice Control disambiguation")
    @MainActor func commandIdsUnique() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
        let ids = commands.map(\.id)
        #expect(Set(ids).count == ids.count, "All command IDs must be unique")
    }

    @Test("CommandRegistry command titles are unique for Voice Control")
    @MainActor func commandTitlesUnique() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
        let titles = commands.map(\.title)
        #expect(Set(titles).count == titles.count,
            "All command titles must be unique for Voice Control disambiguation")
    }

    @Test("FileNode metadata exposes modification date for VoiceOver sorting context")
    func fileNodeMetadataAccessible() {
        let node = FileNode(
            name: "Recent.md",
            url: URL(fileURLWithPath: "/vault/Recent.md"),
            nodeType: .note
        )
        // metadata.modifiedAt should be accessible
        let _ = node.metadata.modifiedAt
        let _ = node.metadata.fileSize
    }

    // NOTE: True VoiceOver custom-action and focus-order testing requires XCUITest.

    @Test("FileNode name is non-empty for all node types (VoiceOver label source)")
    func nodeNameNonEmpty() {
        let note = FileNode(name: "Note.md", url: URL(fileURLWithPath: "/d/Note.md"), nodeType: .note)
        let folder = FileNode(name: "Projects", url: URL(fileURLWithPath: "/d/Projects"), nodeType: .folder, children: [])
        #expect(!note.name.isEmpty, "Note name is the VoiceOver label")
        #expect(!folder.name.isEmpty, "Folder name is the VoiceOver label")
    }

    @Test("Folder children count available for VoiceOver hint")
    func folderChildrenCountForHint() {
        let child1 = FileNode(name: "A.md", url: URL(fileURLWithPath: "/d/A.md"), nodeType: .note)
        let child2 = FileNode(name: "B.md", url: URL(fileURLWithPath: "/d/B.md"), nodeType: .note)
        let folder = FileNode(name: "Docs", url: URL(fileURLWithPath: "/d"), nodeType: .folder, children: [child1, child2])
        #expect(folder.children?.count == 2, "Children count enables 'folder with N items' VoiceOver hint")
    }
}
