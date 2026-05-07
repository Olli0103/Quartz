import Testing
import Foundation
@testable import QuartzKit

// MARK: - Mock VaultProvider

/// A simple mock VaultProvider for tests.
actor MockVaultProvider: VaultProviding {
    var notes: [URL: NoteDocument] = [:]
    var folders: [URL] = []
    var fileTree: [FileNode] = []
    var loadFileTreeCallCount = 0
    var loadDelay: Duration?

    func loadFileTree(at root: URL) async throws -> [FileNode] {
        loadFileTreeCallCount += 1
        if let loadDelay {
            try? await Task.sleep(for: loadDelay)
        }
        return fileTree
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

@Suite("SidebarViewModel", .serialized)
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

    @Test("same-vault load uses fresh cache until explicit refresh")
    @MainActor
    func sameVaultLoadSkipsFullReloadSemantics() async {
        let provider = MockVaultProvider()
        let first = FileNode(name: "a.md", url: vaultRoot.appendingPathComponent("a.md"), nodeType: .note)
        let second = FileNode(name: "b.md", url: vaultRoot.appendingPathComponent("b.md"), nodeType: .note)
        await provider.setFileTree([first])

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        #expect(vm.fileTree.map(\.name) == ["a.md"])

        await provider.setFileTree([second])
        await vm.loadTree(at: vaultRoot)

        #expect(vm.fileTree.map(\.name) == ["a.md"])
        await vm.refresh()
        #expect(vm.fileTree.map(\.name) == ["b.md"])
        #expect(!vm.isLoading)
    }

    @Test("concurrent same-vault background refresh requests coalesce")
    @MainActor
    func concurrentRefreshRequestsCoalesce() async {
        let provider = MockVaultProvider()
        let first = FileNode(name: "a.md", url: vaultRoot.appendingPathComponent("a.md"), nodeType: .note)
        let second = FileNode(name: "b.md", url: vaultRoot.appendingPathComponent("b.md"), nodeType: .note)
        await provider.setFileTree([first])
        await provider.setLoadDelay(.milliseconds(120))

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)

        await provider.setFileTree([second])
        async let firstRefresh: Void = vm.refresh()
        async let secondRefresh: Void = vm.refresh()
        _ = await (firstRefresh, secondRefresh)

        #expect(await provider.loadCount() == 2)
        #expect(vm.fileTree.map(\.name) == ["b.md"])
    }

    @Test("content-only file event updates row without background refresh")
    @MainActor
    func contentOnlyFileEventUsesModifiedOnlyFastPath() async {
        await SubsystemDiagnostics.resetCurrentDiagnostics()
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SidebarModifiedOnly-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let noteURL = root.appendingPathComponent("note.md")
        try? "before".write(to: noteURL, atomically: true, encoding: .utf8)

        let provider = MockVaultProvider()
        let node = FileNode(name: "note.md", url: noteURL, nodeType: .note)
        await provider.setFileTree([node])

        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: root)
        let loadCountBefore = await provider.loadCount()
        try? "after content-only edit".write(to: noteURL, atomically: true, encoding: .utf8)

        vm.noteContentChanged(at: noteURL)
        vm.flushModifiedOnlyUpdatesForTesting()

        #expect(await provider.loadCount() == loadCountBefore)
        #expect(vm.fileTree.count == 1)
        let snapshot = await SubsystemDiagnostics.snapshot()
        let events = snapshot.eventsBySubsystem[.vaultRestore] ?? []
        #expect(events.contains { $0.name == "sidebar.modifiedOnlyFastPathStarted" })
        #expect(events.contains { $0.name == "sidebar.backgroundRefreshSuppressedForModifiedOnly" })
        #expect(events.contains { $0.name == "sidebar.fullTreeTraversalSkipped" })
        #expect(!events.contains {
            $0.name == "sidebar.backgroundRefreshStarted"
                && $0.noteBasename == noteURL.lastPathComponent
        })
    }

    @Test("many content-only events coalesce into one row update batch")
    @MainActor
    func contentOnlyEventsCoalesce() async {
        await SubsystemDiagnostics.resetCurrentDiagnostics()
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SidebarModifiedOnlyCoalesce-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let noteURL = root.appendingPathComponent("note.md")
        try? "before".write(to: noteURL, atomically: true, encoding: .utf8)

        let provider = MockVaultProvider()
        await provider.setFileTree([FileNode(name: "note.md", url: noteURL, nodeType: .note)])
        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: root)
        let loadCountBefore = await provider.loadCount()

        for index in 0..<100 {
            try? "edit \(index)".write(to: noteURL, atomically: true, encoding: .utf8)
            vm.noteContentChanged(at: noteURL)
        }
        vm.flushModifiedOnlyUpdatesForTesting()

        #expect(await provider.loadCount() == loadCountBefore)
        let snapshot = await SubsystemDiagnostics.snapshot()
        let events = snapshot.eventsBySubsystem[.vaultRestore] ?? []
        let finished = events.filter { $0.name == "sidebar.modifiedOnlyFastPathFinished" }
        #expect(finished.count == 1)
        #expect(finished.first?.counts["updatedRows"] == 1)
    }

    @Test("identical modified-only metadata skips visible sidebar invalidation")
    @MainActor
    func identicalModifiedOnlyMetadataSkipsVisibleInvalidation() async {
        await SubsystemDiagnostics.resetCurrentDiagnostics()
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SidebarModifiedOnlyNoChange-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let noteURL = root.appendingPathComponent("note.md")
        try? "same".write(to: noteURL, atomically: true, encoding: .utf8)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: noteURL.path(percentEncoded: false))) ?? [:]
        let metadata = FileMetadata(
            createdAt: attributes[.creationDate] as? Date ?? Date(),
            modifiedAt: attributes[.modificationDate] as? Date ?? Date(),
            fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0
        )

        let provider = MockVaultProvider()
        await provider.setFileTree([FileNode(name: "note.md", url: noteURL, nodeType: .note, metadata: metadata)])
        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: root)
        var invalidations = 0
        vm.onFileTreeDidChange = { _ in invalidations += 1 }

        vm.noteContentChanged(at: noteURL)
        vm.flushModifiedOnlyUpdatesForTesting()
        invalidations = 0
        await SubsystemDiagnostics.resetCurrentDiagnostics()

        vm.noteContentChanged(at: noteURL)
        vm.flushModifiedOnlyUpdatesForTesting()

        #expect(invalidations == 0)
        let snapshot = await SubsystemDiagnostics.snapshot()
        let events = snapshot.eventsBySubsystem[.vaultRestore] ?? []
        #expect(events.contains { $0.name == "sidebar.rowUpdateSkippedNoVisibleChange" })
        #expect(events.contains { $0.name == "sidebar.sidebarViewReloadAvoided" })
    }

    @Test("structural refresh still loads tree")
    @MainActor
    func structuralRefreshStillLoadsTree() async {
        let provider = MockVaultProvider()
        let first = FileNode(name: "a.md", url: vaultRoot.appendingPathComponent("a.md"), nodeType: .note)
        let second = FileNode(name: "b.md", url: vaultRoot.appendingPathComponent("b.md"), nodeType: .note)
        await provider.setFileTree([first])
        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)
        await provider.setFileTree([first, second])

        await vm.refresh()

        #expect(await provider.loadCount() == 2)
        #expect(vm.fileTree.map(\.name).contains("b.md"))
    }

    @Test("internal quartz files are ignored for modified-only fast path")
    @MainActor
    func internalQuartzFilesIgnoredForModifiedOnly() async {
        await SubsystemDiagnostics.resetCurrentDiagnostics()
        let provider = MockVaultProvider()
        let vm = SidebarViewModel(vaultProvider: provider)
        let internalURL = vaultRoot
            .appendingPathComponent(".quartz")
            .appendingPathComponent("versions")
            .appendingPathComponent("file.md")

        vm.noteContentChanged(at: internalURL)
        vm.flushModifiedOnlyUpdatesForTesting()
        try? await Task.sleep(for: .milliseconds(20))

        let snapshot = await SubsystemDiagnostics.snapshot()
        let events = snapshot.eventsBySubsystem[.vaultRestore] ?? []
        #expect(events.contains {
            $0.name.hasPrefix("sidebar.backgroundRefreshSuppressedForModifiedOnly")
                && $0.metadata["reason"] == "internalQuartzFileIgnored"
        })
        #expect(!events.contains { $0.name == "sidebar.modifiedOnlyFastPathStarted" })
    }

    @Test("modified-only fallback emits reason when row is missing")
    @MainActor
    func modifiedOnlyFallbackWhenRowMissing() async {
        await SubsystemDiagnostics.resetCurrentDiagnostics()
        let provider = MockVaultProvider()
        await provider.setFileTree([])
        let vm = SidebarViewModel(vaultProvider: provider)
        await vm.loadTree(at: vaultRoot)

        vm.noteContentChanged(at: vaultRoot.appendingPathComponent("missing.md"))
        vm.flushModifiedOnlyUpdatesForTesting()

        let snapshot = await SubsystemDiagnostics.snapshot()
        let events = snapshot.eventsBySubsystem[.vaultRestore] ?? []
        #expect(events.contains {
            $0.name == "sidebar.modifiedOnlySlowPathFallback"
                && $0.metadata["reason"] == "rowMissing"
        })
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

    func setLoadDelay(_ delay: Duration?) {
        self.loadDelay = delay
    }

    func loadCount() -> Int {
        loadFileTreeCallCount
    }

    func addNote(_ note: NoteDocument) {
        self.notes[note.fileURL] = note
    }
}
