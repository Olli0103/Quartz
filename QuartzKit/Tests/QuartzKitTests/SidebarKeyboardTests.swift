import Testing
import Foundation
@testable import QuartzKit

// MARK: - Sidebar Keyboard Navigation Data Contract Tests
//
// SwiftUI's List + OutlineGroup handles arrow key navigation natively on macOS.
// These tests verify the data model contracts that keyboard navigation relies on:
// - Hierarchical tree structure (expand/collapse)
// - Consistent ordering
// - Valid selection targets
// - CommandRegistry keyboard accessibility

@Suite("SidebarKeyboard")
struct SidebarKeyboardTests {

    // MARK: - Helpers

    private func makeSampleTree() -> [FileNode] {
        let noteA = FileNode(name: "Alpha.md", url: URL(fileURLWithPath: "/vault/Alpha.md"), nodeType: .note)
        let noteB = FileNode(name: "Beta.md", url: URL(fileURLWithPath: "/vault/Beta.md"), nodeType: .note)
        let noteC = FileNode(name: "Gamma.md", url: URL(fileURLWithPath: "/vault/Docs/Gamma.md"), nodeType: .note)
        let noteD = FileNode(name: "Delta.md", url: URL(fileURLWithPath: "/vault/Docs/Delta.md"), nodeType: .note)
        let folder = FileNode(
            name: "Docs",
            url: URL(fileURLWithPath: "/vault/Docs"),
            nodeType: .folder,
            children: [noteC, noteD]
        )
        let emptyFolder = FileNode(
            name: "Empty",
            url: URL(fileURLWithPath: "/vault/Empty"),
            nodeType: .folder,
            children: []
        )
        return [noteA, noteB, folder, emptyFolder]
    }

    private func collectLeafNotes(_ nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote {
                result.append(node)
            } else if let children = node.children {
                result.append(contentsOf: collectLeafNotes(children))
            }
        }
        return result
    }

    // MARK: - Tree Structure

    @Test("FileNode tree supports hierarchical traversal")
    func hierarchicalTraversal() {
        let tree = makeSampleTree()
        let folder = tree.first(where: { $0.isFolder && $0.name == "Docs" })

        #expect(folder != nil, "Tree should contain a folder")
        #expect(folder?.children != nil, "Folder should have children for expand/collapse")
        #expect(folder?.children?.count == 2, "Docs folder should contain 2 notes")

        // Children should be accessible for keyboard arrow-right expansion
        let childNames = folder?.children?.map(\.name) ?? []
        #expect(childNames.contains("Gamma.md"))
        #expect(childNames.contains("Delta.md"))
    }

    @Test("Flat notes list has consistent ordering")
    func flatNotesConsistentOrdering() {
        let tree = makeSampleTree()

        // Collect leaves twice — should be same order
        let first = collectLeafNotes(tree).map(\.name)
        let second = collectLeafNotes(tree).map(\.name)

        #expect(first == second,
            "Flat note ordering should be consistent across traversals")
        #expect(first.count == 4, "Should have 4 leaf notes total")
    }

    @Test("First leaf note in tree is a valid selection target")
    func firstLeafNoteSelectable() {
        let tree = makeSampleTree()
        let leaves = collectLeafNotes(tree)

        let first = leaves.first
        #expect(first != nil, "Tree should have at least one leaf note")
        #expect(first?.isNote == true, "First leaf should be a note")
        #expect(first?.url.pathExtension == "md", "Note should have .md extension")
    }

    @Test("Sequential sibling URLs are distinct")
    func sequentialSiblingURLsDistinct() {
        let tree = makeSampleTree()
        let leaves = collectLeafNotes(tree)

        // All leaf note URLs should be unique
        let urls = leaves.map(\.url)
        let uniqueURLs = Set(urls)
        #expect(uniqueURLs.count == urls.count,
            "All leaf note URLs should be unique for unambiguous keyboard selection")
    }

    @Test("Folder expand exposes children")
    func folderExpandExposesChildren() {
        let tree = makeSampleTree()
        let docsFolder = tree.first(where: { $0.name == "Docs" })

        #expect(docsFolder?.children != nil,
            "Folder with children should expose them for OutlineGroup expansion")
        #expect(docsFolder?.children?.isEmpty == false,
            "Children list should not be empty")

        // Each child should have correct parent path
        for child in docsFolder?.children ?? [] {
            #expect(child.url.deletingLastPathComponent().lastPathComponent == "Docs",
                "Child \(child.name) should be inside Docs folder")
        }
    }

    @Test("Empty folder has empty children array")
    func emptyFolderIsLeaf() {
        let tree = makeSampleTree()
        let emptyFolder = tree.first(where: { $0.name == "Empty" })

        #expect(emptyFolder != nil, "Tree should contain Empty folder")
        #expect(emptyFolder?.isFolder == true)
        #expect(emptyFolder?.children != nil, "Folder should have children array (even if empty)")
        #expect(emptyFolder?.children?.isEmpty == true,
            "Empty folder should have zero children")
    }

    @Test("FileNode delete target URL is correct")
    func deleteTargetURLCorrect() {
        let noteURL = URL(fileURLWithPath: "/vault/Docs/target.md")
        let node = FileNode(name: "target.md", url: noteURL, nodeType: .note)

        // The URL used for deletion should match the node's URL
        #expect(node.url == noteURL)
        #expect(node.url.lastPathComponent == "target.md")
        #expect(node.url.deletingLastPathComponent().lastPathComponent == "Docs",
            "Delete operation should use correct parent path")
    }

    @Test("CommandRegistry commands are keyboard-invocable via Cmd+K palette")
    @MainActor func commandRegistryKeyboardAccessible() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )

        #expect(commands.count >= 8,
            "CommandRegistry should provide sufficient commands for Cmd+K palette")

        // All commands should have non-empty titles for keyboard invocation
        for cmd in commands {
            #expect(!cmd.title.isEmpty,
                "Command '\(cmd.id)' must have a title for keyboard palette selection")
            #expect(!cmd.keywords.isEmpty,
                "Command '\(cmd.id)' must have keywords for fuzzy keyboard search")
        }
    }
}
