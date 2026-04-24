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

    @Test("Fingerprint changes when file size changes even if modification date is preserved")
    func fingerprintIncludesFileSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-size-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.md")
        let preservedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try "short".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path(percentEncoded: false))
        let fp1 = VaultSearchIndex.computeFingerprint(for: [file])

        try "much longer content".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path(percentEncoded: false))
        let fp2 = VaultSearchIndex.computeFingerprint(for: [file])

        #expect(fp1 != fp2)
    }

    @Test("Fingerprint changes when same-size content changes and modification date is preserved")
    func fingerprintIncludesContentDigest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-content-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.md")
        let preservedDate = Date(timeIntervalSince1970: 1_700_000_001)
        try "Body token alpha.\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path(percentEncoded: false))
        let fp1 = VaultSearchIndex.computeFingerprint(for: [file])

        try "Body token bravo.\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path(percentEncoded: false))
        let fp2 = VaultSearchIndex.computeFingerprint(for: [file])

        #expect(fp1 != fp2)
    }

    @Test("Fingerprint remains stable when content and metadata are unchanged")
    func fingerprintStableForUnchangedContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-stable-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.md")
        let preservedDate = Date(timeIntervalSince1970: 1_700_000_002)
        let content = "Stable body content.\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path(percentEncoded: false))
        let fp1 = VaultSearchIndex.computeFingerprint(for: [file])

        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path(percentEncoded: false))
        let fp2 = VaultSearchIndex.computeFingerprint(for: [file])

        #expect(fp1 == fp2)
    }

    @Test("Same-size preserved-mtime content changes rebuild cached search index")
    func sameSizePreservedMtimeContentChangeRebuildsCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-cache-content-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".quartz"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("same-size.md")
        let preservedDate = Date(timeIntervalSince1970: 1_700_000_003)
        try Self.writeSearchNote(body: "Body token alpha.\n", to: noteURL, modificationDate: preservedDate)

        let parser = FrontmatterParser()
        let provider = CountingFileSystemVaultProvider(frontmatterParser: parser)
        let firstTree = try await provider.loadFileTree(at: root)
        let firstIndex = VaultSearchIndex(vaultProvider: provider)
        await firstIndex.buildIndex(fromPreloadedTree: firstTree, at: root)

        let initialReads = await provider.readCount()
        #expect(initialReads == 1)
        #expect(await firstIndex.search(query: "alpha").count == 1)

        try Self.writeSearchNote(body: "Body token bravo.\n", to: noteURL, modificationDate: preservedDate)

        let secondTree = try await provider.loadFileTree(at: root)
        let secondIndex = VaultSearchIndex(vaultProvider: provider)
        await secondIndex.buildIndex(fromPreloadedTree: secondTree, at: root)

        #expect(await provider.readCount() == initialReads + 1)
        #expect(await secondIndex.latestBuildSource == .rebuild)
        #expect(await secondIndex.search(query: "alpha").isEmpty)
        #expect(await secondIndex.search(query: "bravo").count == 1)
    }

    @Test("Fingerprinting many small notes is bounded")
    func fingerprintManySmallNotesSanity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-many-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = try (0..<256).map { index in
            let file = root.appendingPathComponent("note-\(index).md")
            try String(repeating: "Note \(index) content.\n", count: 32)
                .write(to: file, atomically: true, encoding: .utf8)
            return file
        }

        let start = ContinuousClock.now
        let fingerprint = VaultSearchIndex.computeFingerprint(for: urls)
        let elapsed = start.duration(to: .now)

        #expect(fingerprint.count == 64)
        #expect(elapsed < .seconds(5))
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

    private static func writeSearchNote(body: String, to url: URL, modificationDate: Date) throws {
        let content = """
        ---
        title: Same Size
        tags: [test]
        ---
        \(body)
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path(percentEncoded: false)
        )
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
