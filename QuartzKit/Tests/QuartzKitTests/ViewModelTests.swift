import Testing
import Foundation
@testable import QuartzKit

// MARK: - Mock VaultProvider

/// Ein einfacher Mock-VaultProvider für Tests.
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
        let url = folder.appendingPathComponent("\(name).md")
        let note = NoteDocument(fileURL: url, frontmatter: Frontmatter(title: name))
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

// MARK: - NoteEditorViewModel Tests

@Suite("NoteEditorViewModel")
struct NoteEditorViewModelTests {
    let testURL = URL(fileURLWithPath: "/vault/test.md")

    @Test("loadNote sets content and note")
    @MainActor
    func loadNote() async {
        let provider = MockVaultProvider()
        let note = NoteDocument(
            fileURL: testURL,
            frontmatter: Frontmatter(title: "Test"),
            body: "Hello world"
        )
        await provider.addNote(note)

        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)
        await vm.loadNote(at: testURL)

        #expect(vm.content == "Hello world")
        #expect(vm.note?.frontmatter.title == "Test")
        #expect(!vm.isDirty)
    }

    @Test("Content change marks dirty")
    @MainActor
    func contentMarksDirty() async {
        let provider = MockVaultProvider()
        let note = NoteDocument(fileURL: testURL, body: "Original")
        await provider.addNote(note)

        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)
        await vm.loadNote(at: testURL)

        #expect(!vm.isDirty)
        vm.content = "Modified"
        #expect(vm.isDirty)
    }

    @Test("save clears dirty flag")
    @MainActor
    func saveClearsDirty() async {
        let provider = MockVaultProvider()
        let note = NoteDocument(fileURL: testURL, body: "Original")
        await provider.addNote(note)

        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)
        await vm.loadNote(at: testURL)
        vm.content = "Modified"

        #expect(vm.isDirty)
        await vm.save()
        #expect(!vm.isDirty)
    }

    @Test("save persists content")
    @MainActor
    func savePersists() async {
        let provider = MockVaultProvider()
        let note = NoteDocument(fileURL: testURL, body: "Original")
        await provider.addNote(note)

        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)
        await vm.loadNote(at: testURL)
        vm.content = "Updated content"
        await vm.save()

        // Verify the provider has the updated content
        let saved = try? await provider.readNote(at: testURL)
        #expect(saved?.body == "Updated content")
    }

    @Test("updateFrontmatter marks dirty")
    @MainActor
    func updateFrontmatterDirty() async {
        let provider = MockVaultProvider()
        let note = NoteDocument(fileURL: testURL, body: "Content")
        await provider.addNote(note)

        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)
        await vm.loadNote(at: testURL)

        var newFM = vm.note?.frontmatter ?? Frontmatter()
        newFM.title = "New Title"
        vm.updateFrontmatter(newFM)

        #expect(vm.isDirty)
        #expect(vm.note?.frontmatter.title == "New Title")
    }

    @Test("loadNote with bad URL sets error")
    @MainActor
    func loadBadURL() async {
        let provider = MockVaultProvider()
        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)

        await vm.loadNote(at: URL(fileURLWithPath: "/nonexistent.md"))
        #expect(vm.errorMessage != nil)
    }

    @Test("Initial state is clean")
    @MainActor
    func initialState() {
        let provider = MockVaultProvider()
        let parser = FrontmatterParser()
        let vm = NoteEditorViewModel(vaultProvider: provider, frontmatterParser: parser)

        #expect(vm.content.isEmpty)
        #expect(!vm.isDirty)
        #expect(!vm.isSaving)
        #expect(vm.note == nil)
        #expect(vm.errorMessage == nil)
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
        #expect(state.fileTree.isEmpty)
        #expect(state.selectedNote == nil)
        #expect(!state.isLoading)
        #expect(state.errorMessage == nil)
    }

    @Test("Vault can be set")
    @MainActor
    func setVault() {
        let state = AppState()
        let vault = VaultConfig(name: "Test", rootURL: URL(fileURLWithPath: "/test"))
        state.currentVault = vault
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
