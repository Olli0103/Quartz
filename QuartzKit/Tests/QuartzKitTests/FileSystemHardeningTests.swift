import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 2: File System, Sync & Conflicts Tests

// MARK: - Swift Testing Suite for FileSystemVaultProvider

@Suite("FileSystemVaultProvider")
struct FileSystemVaultProviderTests {
    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    @Test("loadFileTree returns empty array for empty vault")
    func loadFileTreeEmpty() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let nodes = try await provider.loadFileTree(at: vault)
        #expect(nodes.isEmpty)
    }

    @Test("loadFileTree finds markdown files")
    func loadFileTreeFindsMarkdown() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        // Create test files
        try "# Note 1".write(to: vault.appendingPathComponent("note1.md"), atomically: true, encoding: .utf8)
        try "# Note 2".write(to: vault.appendingPathComponent("note2.md"), atomically: true, encoding: .utf8)
        try "Not markdown".write(to: vault.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let nodes = try await provider.loadFileTree(at: vault)

        #expect(nodes.count == 2)
        #expect(nodes.allSatisfy { $0.nodeType == .note })
    }

    @Test("loadFileTree handles nested folders")
    func loadFileTreeNestedFolders() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        // Create nested structure
        let subfolder = vault.appendingPathComponent("Subfolder")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try "# Nested".write(to: subfolder.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let nodes = try await provider.loadFileTree(at: vault)

        #expect(nodes.count == 1)
        #expect(nodes.first?.nodeType == .folder)
        #expect(nodes.first?.children?.count == 1)
    }

    @Test("createNote generates valid frontmatter")
    func createNoteWithFrontmatter() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.createNote(named: "Test Note", in: vault)

        #expect(note.frontmatter.title == "Test Note")
        #expect(note.frontmatter.createdAt != nil)
        #expect(FileManager.default.fileExists(atPath: note.fileURL.path(percentEncoded: false)))
    }

    @Test("createNote rejects invalid names")
    func createNoteInvalidNames() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())

        await #expect(throws: FileSystemError.self) {
            _ = try await provider.createNote(named: "", in: vault)
        }

        await #expect(throws: FileSystemError.self) {
            _ = try await provider.createNote(named: ".hidden", in: vault)
        }

        await #expect(throws: FileSystemError.self) {
            _ = try await provider.createNote(named: "path/traversal", in: vault)
        }
    }

    @Test("createNote with initial content")
    func createNoteWithContent() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.createNote(named: "Content Note", in: vault, initialContent: "Hello World")

        #expect(note.body == "Hello World")
    }

    @Test("readNote parses frontmatter correctly")
    func readNoteParsesCorrectly() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let content = """
        ---
        title: My Title
        tags: [swift, testing]
        ---

        # Body Content
        """
        let fileURL = vault.appendingPathComponent("test.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.readNote(at: fileURL)

        #expect(note.frontmatter.title == "My Title")
        #expect(note.frontmatter.tags.contains("swift"))
        #expect(note.body.contains("# Body Content"))
    }

    @Test("saveNote preserves frontmatter")
    func saveNotePreservesFrontmatter() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        var note = try await provider.createNote(named: "Save Test", in: vault)

        // Modify and save
        var fm = note.frontmatter
        fm.tags = ["modified"]
        note = NoteDocument(fileURL: note.fileURL, frontmatter: fm, body: "Updated body", isDirty: false)
        try await provider.saveNote(note)

        // Read back
        let readBack = try await provider.readNote(at: note.fileURL)
        #expect(readBack.frontmatter.tags.contains("modified"))
        #expect(readBack.body.contains("Updated body"))
    }

    @Test("deleteNote moves to trash")
    func deleteNoteMovesToTrash() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.createNote(named: "Delete Me", in: vault)

        // Ensure file exists before delete
        #expect(FileManager.default.fileExists(atPath: note.fileURL.path(percentEncoded: false)))

        // Load tree to set vault root
        _ = try await provider.loadFileTree(at: vault)

        try await provider.deleteNote(at: note.fileURL)

        // Original location should be gone
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path(percentEncoded: false)))

        // Trash folder should exist and contain the file
        let trashFolder = vault.appendingPathComponent(".quartzTrash")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path(percentEncoded: false)))
    }

    @Test("rename validates new name")
    func renameValidation() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.createNote(named: "Original", in: vault)

        await #expect(throws: FileSystemError.self) {
            _ = try await provider.rename(at: note.fileURL, to: "../escape.md")
        }
    }

    @Test("createFolder creates directory")
    func createFolderCreatesDirectory() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let folderURL = try await provider.createFolder(named: "New Folder", in: vault)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false), isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("createFolder rejects path traversal")
    func createFolderRejectsTraversal() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())

        await #expect(throws: FileSystemError.self) {
            _ = try await provider.createFolder(named: "../escape", in: vault)
        }

        await #expect(throws: FileSystemError.self) {
            _ = try await provider.createFolder(named: "..", in: vault)
        }
    }
}

// MARK: - VaultTrashService Tests

@Suite("VaultTrashService")
struct VaultTrashServiceTests {
    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrashTestVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    @Test("trashFolderURL returns correct path")
    func trashFolderURL() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VaultTrashService()
        let trashURL = service.trashFolderURL(for: vault)

        #expect(trashURL.lastPathComponent == ".quartzTrash")
    }

    @Test("ensureTrashFolderExists creates folder")
    func ensureTrashFolderExists() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VaultTrashService()
        let trashURL = try service.ensureTrashFolderExists(at: vault)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false), isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("moveItemToTrash moves file")
    func moveItemToTrash() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let fileURL = vault.appendingPathComponent("deleteme.md")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = VaultTrashService()
        try service.moveItemToTrash(fileURL, in: vault)

        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))

        let trashURL = service.trashFolderURL(for: vault)
        let trashedItems = try FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        #expect(trashedItems.count == 1)
    }

    @Test("purgeExpiredItems removes old files")
    func purgeExpiredItems() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VaultTrashService()
        let trashURL = try service.ensureTrashFolderExists(at: vault)

        // Create a file in trash
        let oldFile = trashURL.appendingPathComponent("old.md")
        try "old content".write(to: oldFile, atomically: true, encoding: .utf8)

        // Set modification date to 31 days ago
        let oldDate = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFile.path(percentEncoded: false))

        // Purge
        try service.purgeExpiredItems(in: vault)

        // File should be gone
        #expect(!FileManager.default.fileExists(atPath: oldFile.path(percentEncoded: false)))
    }

    @Test("purgeExpiredItems keeps recent files")
    func purgeExpiredItemsKeepsRecent() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VaultTrashService()
        let trashURL = try service.ensureTrashFolderExists(at: vault)

        // Create a recent file
        let recentFile = trashURL.appendingPathComponent("recent.md")
        try "recent content".write(to: recentFile, atomically: true, encoding: .utf8)

        // Purge (file should remain)
        try service.purgeExpiredItems(in: vault)

        #expect(FileManager.default.fileExists(atPath: recentFile.path(percentEncoded: false)))
    }

    @Test("retentionInterval is 30 days")
    func retentionInterval() {
        #expect(VaultTrashService.retentionInterval == 30 * 24 * 60 * 60)
    }
}

// MARK: - CoordinatedFileWriter Tests

@Suite("CoordinatedFileWriter")
struct CoordinatedFileWriterTests {
    @Test("read and write round-trip")
    func readWriteRoundTrip() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordTest-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let writer = CoordinatedFileWriter()
        let testData = Data("Hello Coordinated World".utf8)

        try writer.write(testData, to: tmpFile)
        let readBack = try writer.read(from: tmpFile)

        #expect(readBack == testData)
    }

    @Test("readString decodes UTF-8")
    func readStringUTF8() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("StringTest-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let writer = CoordinatedFileWriter()
        let text = "Hello with émojis 🎉"
        try writer.write(Data(text.utf8), to: tmpFile)

        let readBack = try writer.readString(from: tmpFile)
        #expect(readBack == text)
    }

    @Test("createDirectory creates nested folders")
    func createDirectoryNested() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirTest-\(UUID().uuidString)/nested/deep")
        defer { try? FileManager.default.removeItem(at: tmpDir.deletingLastPathComponent().deletingLastPathComponent()) }

        let writer = CoordinatedFileWriter()
        try writer.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: tmpDir.path(percentEncoded: false), isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("moveItem moves files")
    func moveItem() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoveTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceURL = tmpDir.appendingPathComponent("source.txt")
        let destURL = tmpDir.appendingPathComponent("dest.txt")
        try "content".write(to: sourceURL, atomically: true, encoding: .utf8)

        let writer = CoordinatedFileWriter()
        try writer.moveItem(from: sourceURL, to: destURL)

        #expect(!FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)))
    }

    @Test("copyItem copies files")
    func copyItem() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceURL = tmpDir.appendingPathComponent("source.txt")
        let destURL = tmpDir.appendingPathComponent("copy.txt")
        try "original".write(to: sourceURL, atomically: true, encoding: .utf8)

        let writer = CoordinatedFileWriter()
        try writer.copyItem(from: sourceURL, to: destURL)

        #expect(FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)))
    }

    @Test("removeItem deletes files")
    func removeItem() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoveTest-\(UUID().uuidString).txt")
        try "content".write(to: tmpFile, atomically: true, encoding: .utf8)

        let writer = CoordinatedFileWriter()
        try writer.removeItem(at: tmpFile)

        #expect(!FileManager.default.fileExists(atPath: tmpFile.path(percentEncoded: false)))
    }
}

// MARK: - XCTest Performance Tests for File I/O

final class FileSystemPerformanceTests: XCTestCase {
    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerfTestVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    func testParallelReadWritePerformance() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let group = DispatchGroup()
            let writer = CoordinatedFileWriter()

            // Parallel writes (100 operations)
            for i in 0..<100 {
                group.enter()
                DispatchQueue.global().async {
                    let url = vault.appendingPathComponent("file\(i).md")
                    let data = Data("Content for file \(i)".utf8)
                    try? writer.write(data, to: url)
                    group.leave()
                }
            }

            // Wait for all writes
            group.wait()

            // Parallel reads
            for i in 0..<100 {
                group.enter()
                DispatchQueue.global().async {
                    let url = vault.appendingPathComponent("file\(i).md")
                    _ = try? writer.read(from: url)
                    group.leave()
                }
            }

            group.wait()
        }
    }

    func testFileTreeBuildingPerformance() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        // Create 200 files in nested folders
        for folder in 0..<10 {
            let folderURL = vault.appendingPathComponent("Folder\(folder)")
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for file in 0..<20 {
                let content = "# Note \(folder)-\(file)"
                try content.write(to: folderURL.appendingPathComponent("note\(file).md"), atomically: true, encoding: .utf8)
            }
        }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Tree built")
            Task {
                _ = try await provider.loadFileTree(at: vault)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testNoteCreationAndSavePerformance() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Notes created")
            Task {
                for i in 0..<50 {
                    _ = try await provider.createNote(named: "PerfNote\(i)", in: vault)
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30.0)
        }
    }

    func testTrashPurgePerformance() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VaultTrashService()
        let trashURL = try service.ensureTrashFolderExists(at: vault)

        // Create 100 files in trash
        let oldDate = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        for i in 0..<100 {
            let file = trashURL.appendingPathComponent("trash\(i).md")
            try "trash content \(i)".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path(percentEncoded: false))
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            try? service.purgeExpiredItems(in: vault)
        }
    }

    func testCoordinatedFileWriterConcurrencyStress() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let writer = CoordinatedFileWriter()
            let queue = DispatchQueue.global(qos: .userInitiated)
            let group = DispatchGroup()

            // Stress test: 200 concurrent operations on same directory
            for i in 0..<200 {
                group.enter()
                queue.async {
                    let url = vault.appendingPathComponent("stress\(i % 50).md")
                    let data = Data(String(repeating: "X", count: 1000).utf8)
                    do {
                        try writer.write(data, to: url)
                        _ = try writer.read(from: url)
                    } catch {
                        // Expected for concurrent writes to same file
                    }
                    group.leave()
                }
            }

            group.wait()
        }
    }
}

// MARK: - FileChangeEvent Tests

@Suite("FileChangeEvent")
struct FileChangeEventTests {
    @Test("FileChangeEvent cases are constructible")
    func eventCases() {
        let url = URL(fileURLWithPath: "/test.md")
        let created = FileChangeEvent.created(url)
        let modified = FileChangeEvent.modified(url)
        let deleted = FileChangeEvent.deleted(url)

        switch created {
        case .created(let u): #expect(u == url)
        default: Issue.record("Expected created")
        }

        switch modified {
        case .modified(let u): #expect(u == url)
        default: Issue.record("Expected modified")
        }

        switch deleted {
        case .deleted(let u): #expect(u == url)
        default: Issue.record("Expected deleted")
        }
    }
}

// MARK: - ConflictDiffState Tests

#if canImport(UIKit) || canImport(AppKit)
@Suite("ConflictDiffState")
struct ConflictDiffStateTests {
    @Test("ConflictDiffState initializes correctly")
    func initialization() {
        let url = URL(fileURLWithPath: "/test.md")
        let localDate = Date()
        let cloudDate = Date().addingTimeInterval(-3600)

        let state = ConflictDiffState(
            fileURL: url,
            localContent: "Local content",
            cloudContent: "Cloud content",
            localModified: localDate,
            cloudModified: cloudDate
        )

        #expect(state.fileURL == url)
        #expect(state.localContent == "Local content")
        #expect(state.cloudContent == "Cloud content")
        #expect(state.localModified == localDate)
        #expect(state.cloudModified == cloudDate)
    }

    @Test("ConflictDiffState handles nil dates")
    func nilDates() {
        let state = ConflictDiffState(
            fileURL: URL(fileURLWithPath: "/test.md"),
            localContent: "",
            cloudContent: "",
            localModified: nil,
            cloudModified: nil
        )

        #expect(state.localModified == nil)
        #expect(state.cloudModified == nil)
    }
}
#endif
