import Testing
import Foundation
@testable import QuartzKit

// MARK: - Mock VaultProvider

/// A simple mock VaultProvider for tests.
actor MockVaultProvider: VaultProviding {
    var notes: [URL: NoteDocument] = [:]
    var folders: [URL] = []
    var fileTree: [FileNode] = []

    func loadFileTree(at root: URL) async throws -> [FileNode] {
        fileTree
    }

    func readNote(at url: URL) async throws -> NoteDocument {
        guard let note = notes[url] else {
            throw MockError.notFound
        }
        return note
    }

    func saveNote(_ note: NoteDocument) async throws {
        notes[note.fileURL] = note
    }

    func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        try await createNote(named: name, in: folder, initialContent: "")
    }

    func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        let url = folder.appendingPathComponent("\(name).md")
        let note = NoteDocument(fileURL: url, frontmatter: Frontmatter(title: name), body: initialContent)
        notes[url] = note

        let node = FileNode(name: "\(name).md", url: url, nodeType: .note)
        fileTree.append(node)

        return note
    }

    func deleteNote(at url: URL) async throws {
        notes.removeValue(forKey: url)
        fileTree.removeAll { $0.url == url }
    }

    func rename(at url: URL, to newName: String) async throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        if let note = notes.removeValue(forKey: url) {
            var renamed = note
            renamed.fileURL = newURL
            notes[newURL] = renamed
        }
        return newURL
    }

    func createFolder(named name: String, in parent: URL) async throws -> URL {
        let url = parent.appendingPathComponent(name)
        folders.append(url)
        let folderNode = FileNode(name: name, url: url, nodeType: .folder, children: [])
        fileTree.append(folderNode)
        return url
    }
}

enum MockError: Error {
    case notFound
}

// MARK: - SidebarViewModel Tests

@Suite("SidebarViewModel")
struct SidebarViewModelTests {
    let vaultRoot = URL(fileURLWithPath: "/vault")

    @Test("loadTree populates fileTree")
    @MainActor
    func loadTree() async {
        let provider = MockVaultProvider()
        let noteURL = vaultRoot.appendingPathComponent("test.md")
        let node = FileNode(name: "test.md", url: noteURL, nodeType: .note)
        await provider.setFileTree([node])

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)

        #expect(vm.fileTree.count == 1)
        #expect(vm.fileTree[0].name == "test.md")
        #expect(!vm.isLoading)
    }

    @Test("searchText filters notes")
    @MainActor
    func searchFilter() async {
        let provider = MockVaultProvider()
        let notes = [
            FileNode(name: "apple.md", url: vaultRoot.appendingPathComponent("apple.md"), nodeType: .note),
            FileNode(name: "banana.md", url: vaultRoot.appendingPathComponent("banana.md"), nodeType: .note),
            FileNode(name: "apricot.md", url: vaultRoot.appendingPathComponent("apricot.md"), nodeType: .note),
        ]
        await provider.setFileTree(notes)

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        vm.searchText = "ap"

        let filtered = vm.filteredTree
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.name.lowercased().contains("ap") })
    }

    @Test("Empty search returns all items")
    @MainActor
    func emptySearchReturnsAll() async {
        let provider = MockVaultProvider()
        let notes = [
            FileNode(name: "a.md", url: vaultRoot.appendingPathComponent("a.md"), nodeType: .note),
            FileNode(name: "b.md", url: vaultRoot.appendingPathComponent("b.md"), nodeType: .note),
        ]
        await provider.setFileTree(notes)

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        vm.searchText = ""

        #expect(vm.filteredTree.count == 2)
    }

    @Test("Tag filter works")
    @MainActor
    func tagFilter() async {
        let provider = MockVaultProvider()
        let notes = [
            FileNode(
                name: "tagged.md",
                url: vaultRoot.appendingPathComponent("tagged.md"),
                nodeType: .note,
                frontmatter: Frontmatter(tags: ["swift"])
            ),
            FileNode(
                name: "untagged.md",
                url: vaultRoot.appendingPathComponent("untagged.md"),
                nodeType: .note,
                frontmatter: Frontmatter()
            ),
        ]
        await provider.setFileTree(notes)

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        vm.selectedTag = "swift"

        let filtered = vm.filteredTree
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "tagged.md")
    }

    @Test("collectTags gathers tags from tree")
    @MainActor
    func collectTags() async {
        let provider = MockVaultProvider()
        let notes = [
            FileNode(name: "a.md", url: vaultRoot.appendingPathComponent("a.md"), nodeType: .note, frontmatter: Frontmatter(tags: ["swift", "ios"])),
            FileNode(name: "b.md", url: vaultRoot.appendingPathComponent("b.md"), nodeType: .note, frontmatter: Frontmatter(tags: ["swift"])),
        ]
        await provider.setFileTree(notes)

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        vm.collectTags()

        #expect(vm.tagInfos.count == 2)
        let swiftTag = vm.tagInfos.first { $0.name == "swift" }
        #expect(swiftTag?.count == 2)
        let iosTag = vm.tagInfos.first { $0.name == "ios" }
        #expect(iosTag?.count == 1)
    }

    @Test("createNote adds to tree")
    @MainActor
    func createNote() async {
        let provider = MockVaultProvider()
        await provider.setFileTree([])

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        await vm.createNote(named: "New Note", in: vaultRoot)

        // After refresh, tree should contain the new note
        #expect(vm.fileTree.count == 1)
    }

    @Test("delete removes from tree")
    @MainActor
    func deleteNote() async {
        let provider = MockVaultProvider()
        let noteURL = vaultRoot.appendingPathComponent("test.md")
        let note = NoteDocument(fileURL: noteURL)
        await provider.addNote(note)
        let node = FileNode(name: "test.md", url: noteURL, nodeType: .note)
        await provider.setFileTree([node])

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        #expect(vm.fileTree.count == 1)

        await vm.delete(at: noteURL)
        #expect(vm.fileTree.isEmpty)
    }

    @Test("vaultRootURL is accessible")
    @MainActor
    func vaultRootAccess() async {
        let provider = MockVaultProvider()
        let vm = SidebarViewModel(vaultProvider: provider)

        #expect(vm.vaultRootURL == nil)
        await vm.loadTree(at: vaultRoot)
        #expect(vm.vaultRootURL == vaultRoot)
    }
}

// MARK: - AppState Tests

@Suite("AppState")
struct AppStateTests {
    @Test("Initial state")
    @MainActor
    func initialState() {
        let state = AppState()
        #expect(state.currentVault == nil)
        #expect(state.errorMessage == nil)
        #expect(state.pendingCommand == .none)
    }

    @Test("Vault can be set")
    @MainActor
    func setVault() {
        let state = AppState()
        let vault = VaultConfig(name: "Test", rootURL: URL(fileURLWithPath: "/test"))
        state.switchVault(to: vault)
        #expect(state.currentVault?.name == "Test")
    }
}

// MARK: - Mock Helpers

extension MockVaultProvider {
    func setFileTree(_ tree: [FileNode]) {
        self.fileTree = tree
    }

    func addNote(_ note: NoteDocument) {
        self.notes[note.fileURL] = note
    }
}
