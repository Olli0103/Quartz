import Testing
import Foundation
@testable import QuartzKit

@Suite("SearchIndexPersistence")
struct SearchIndexPersistenceTests {

    @Test("Preloaded-tree startup reuses persisted search cache")
    func preloadedTreeStartupReusesCache() async throws {
        let root = try makeTempVault(noteNames: ["note1", "note2", "note3"])
        defer { try? FileManager.default.removeItem(at: root) }

        let parser = FrontmatterParser()
        let provider = CountingFileSystemVaultProvider(frontmatterParser: parser)

        let firstTree = try await provider.loadFileTree(at: root)
        let firstIndex = VaultSearchIndex(vaultProvider: provider)
        await firstIndex.buildIndex(fromPreloadedTree: firstTree, at: root)

        let initialReads = await provider.readCount()
        #expect(initialReads == 3)
        #expect(await firstIndex.entryCount == 3)

        let secondTree = try await provider.loadFileTree(at: root)
        let secondIndex = VaultSearchIndex(vaultProvider: provider)
        await secondIndex.buildIndex(fromPreloadedTree: secondTree, at: root)

        #expect(await provider.readCount() == initialReads)
        #expect(await secondIndex.entryCount == 3)
        #expect(await secondIndex.search(query: "inline").count == 3)
    }

    @Test("Rebuild from preloaded tree drops deleted notes from persisted cache")
    func rebuildDropsDeletedNotes() async throws {
        let root = try makeTempVault(noteNames: ["keep", "remove"])
        defer { try? FileManager.default.removeItem(at: root) }

        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        let initialTree = try await provider.loadFileTree(at: root)

        let firstIndex = VaultSearchIndex(vaultProvider: provider)
        await firstIndex.buildIndex(fromPreloadedTree: initialTree, at: root)
        #expect(await firstIndex.entryCount == 2)

        let removedURL = root.appending(path: "remove.md")
        try FileManager.default.removeItem(at: removedURL)

        let rebuiltTree = try await provider.loadFileTree(at: root)
        let rebuiltIndex = VaultSearchIndex(vaultProvider: provider)
        await rebuiltIndex.buildIndex(fromPreloadedTree: rebuiltTree, at: root)

        #expect(await rebuiltIndex.entryCount == 1)
        #expect(await rebuiltIndex.search(query: "Note remove").isEmpty)
        #expect(await rebuiltIndex.search(query: "Note keep").count == 1)
    }

    @Test("Fingerprint changes when files change")
    func fingerprintSensitivity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file1 = root.appendingPathComponent("a.md")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)

        let fp1 = VaultSearchIndex.computeFingerprint(for: [file1])

        try "world".write(to: file1, atomically: true, encoding: .utf8)
        let fp2 = VaultSearchIndex.computeFingerprint(for: [file1])

        #expect(fp1 != fp2)
    }

    @Test("Empty fingerprint is deterministic")
    func emptyFingerprint() {
        let fp1 = VaultSearchIndex.computeFingerprint(for: [])
        let fp2 = VaultSearchIndex.computeFingerprint(for: [])
        #expect(fp1 == fp2)
    }

    @Test("Fingerprint is order-independent")
    func fingerprintOrderIndependent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file1 = root.appendingPathComponent("a.md")
        let file2 = root.appendingPathComponent("b.md")
        try "aaa".write(to: file1, atomically: true, encoding: .utf8)
        try "bbb".write(to: file2, atomically: true, encoding: .utf8)

        let fp1 = VaultSearchIndex.computeFingerprint(for: [file1, file2])
        let fp2 = VaultSearchIndex.computeFingerprint(for: [file2, file1])
        #expect(fp1 == fp2)
    }

    private func makeTempVault(noteNames: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".quartz"), withIntermediateDirectories: true)

        for name in noteNames {
            let content = """
            ---
            title: Note \(name)
            tags: [test, \(name)]
            ---
            Body of note \(name) with some #inline content.
            """
            try content.write(
                to: root.appendingPathComponent("\(name).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        return root
    }
}

private actor CountingFileSystemVaultProvider: VaultProviding {
    private let base: FileSystemVaultProvider
    private var readNoteCallCount = 0

    init(frontmatterParser: any FrontmatterParsing) {
        base = FileSystemVaultProvider(frontmatterParser: frontmatterParser)
    }

    func readCount() -> Int {
        readNoteCallCount
    }

    func loadFileTree(at root: URL) async throws -> [FileNode] {
        try await base.loadFileTree(at: root)
    }

    func readNote(at url: URL) async throws -> NoteDocument {
        readNoteCallCount += 1
        return try await base.readNote(at: url)
    }

    func saveNote(_ note: NoteDocument) async throws {
        try await base.saveNote(note)
    }

    func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        try await base.createNote(named: name, in: folder)
    }

    func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        try await base.createNote(named: name, in: folder, initialContent: initialContent)
    }

    func deleteNote(at url: URL) async throws {
        try await base.deleteNote(at: url)
    }

    func rename(at url: URL, to newName: String) async throws -> URL {
        try await base.rename(at: url, to: newName)
    }

    func createFolder(named name: String, in parent: URL) async throws -> URL {
        try await base.createFolder(named: name, in: parent)
    }
}
