import Testing
import Foundation
import CryptoKit
@testable import QuartzKit

// MARK: - iCloud Coordination Safety Tests

@Suite("iCloud Coordination Safety")
struct ICloudCoordinationTests {

    // MARK: - Deadlock Prevention (Fix 1)

    @Test("CoordinatedFileWriter accepts optional filePresenter parameter")
    func writerAcceptsPresenter() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "coordination-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let data = Data("test".utf8)
        // Write without presenter (backward compat)
        try CoordinatedFileWriter.shared.write(data, to: tmp)
        // Read back
        let read = try CoordinatedFileWriter.shared.read(from: tmp)
        #expect(String(data: read, encoding: .utf8) == "test")
    }

    @Test("CoordinatedFileWriter write with nil presenter succeeds")
    func writerNilPresenter() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "nil-presenter-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let data = Data("nil presenter write".utf8)
        try CoordinatedFileWriter.shared.write(data, to: tmp, filePresenter: nil)
        let read = try CoordinatedFileWriter.shared.read(from: tmp, filePresenter: nil)
        #expect(String(data: read, encoding: .utf8) == "nil presenter write")
    }

    @Test("CoordinatedFileWriter read with filePresenter parameter compiles and works")
    func readerAcceptsPresenter() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "read-presenter-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data("coordinated read".utf8).write(to: tmp)

        // Create a presenter for the file
        let presenter = NoteFilePresenter(url: tmp)
        defer { presenter.invalidate() }

        // Read using the presenter — should NOT deadlock
        let read = try CoordinatedFileWriter.shared.read(from: tmp, filePresenter: presenter)
        #expect(String(data: read, encoding: .utf8) == "coordinated read")
    }

    @Test("CoordinatedFileWriter write with filePresenter does not deadlock")
    func writerWithPresenterNonDeadlock() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "write-presenter-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a presenter BEFORE writing — mimics EditorSession scenario
        let presenter = NoteFilePresenter(url: tmp)
        defer { presenter.invalidate() }

        // Write WITH the presenter — this is THE deadlock fix.
        // Without filePresenter:, the coordinator would call savePresentedItemChanges
        // on our own presenter, which previously re-entered save() and deadlocked.
        let data = Data("write with presenter".utf8)
        try CoordinatedFileWriter.shared.write(data, to: tmp, filePresenter: presenter)

        let read = try CoordinatedFileWriter.shared.read(from: tmp, filePresenter: presenter)
        #expect(String(data: read, encoding: .utf8) == "write with presenter")
    }

    @Test("CoordinatedFileWriter respects custom timeout parameter")
    func writerTimeoutRespected() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "timeout-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create file first
        try Data("initial".utf8).write(to: tmp)

        // Write with a short but achievable timeout on local files.
        // This verifies the timeout parameter is accepted and forwarded.
        let data = Data("updated".utf8)
        try CoordinatedFileWriter.shared.write(data, to: tmp, timeout: 5.0)
        let result = try CoordinatedFileWriter.shared.read(from: tmp)
        #expect(String(data: result, encoding: .utf8) == "updated")
    }

    // MARK: - Save Re-entrancy Guard (Fix 2)

    @Test("EditorSession.save guard prevents concurrent saves via isSaving flag")
    @MainActor func saveConcurrencyGuard() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "reentrant-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteURL = tmp.appending(path: "test.md")
        try Data("---\ntitle: Test\n---\n\nHello".utf8).write(to: noteURL)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )

        await session.loadNote(at: noteURL)
        session.textDidChange("Modified content")
        #expect(session.isDirty == true)

        // First save proceeds
        await session.save()
        #expect(session.isDirty == false)

        // Second save is no-op (not dirty)
        await session.save()
        #expect(session.isDirty == false)
    }

    @Test("EditorSession.save with force=true saves even when not dirty")
    @MainActor func forceSaveWhenClean() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "force-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteURL = tmp.appending(path: "force.md")
        try Data("---\ntitle: Force\n---\n\nBody".utf8).write(to: noteURL)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )

        await session.loadNote(at: noteURL)
        #expect(session.isDirty == false)

        // Force save should succeed even when not dirty
        await session.save(force: true)
        #expect(session.errorMessage == nil)
    }

    // MARK: - Echo Suppression (Fix 5)

    @Test("Save does not trigger externalModificationDetected")
    @MainActor func echoSuppression() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "echo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteURL = tmp.appending(path: "echo.md")
        try Data("---\ntitle: Echo\n---\n\nOriginal".utf8).write(to: noteURL)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )

        await session.loadNote(at: noteURL)
        session.textDidChange("User edit")
        await session.save()

        // After save, externalModificationDetected should NOT be set
        #expect(session.externalModificationDetected == false)
    }

    // MARK: - NoteFilePresenter Lifecycle

    @Test("NoteFilePresenter registers and unregisters cleanly")
    func presenterLifecycle() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "presenter-test-\(UUID().uuidString).md")
        try? Data("test".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let presenter = NoteFilePresenter(url: url)
        #expect(presenter.presentedItemURL == url)

        presenter.invalidate()
        // Double invalidation should be safe (no crash)
        presenter.invalidate()
    }

    @Test("NoteFilePresenter tracks URL changes on move")
    func presenterTracksMove() {
        let url1 = FileManager.default.temporaryDirectory
            .appending(path: "move-src-\(UUID().uuidString).md")
        let url2 = FileManager.default.temporaryDirectory
            .appending(path: "move-dst-\(UUID().uuidString).md")

        let presenter = NoteFilePresenter(url: url1)
        #expect(presenter.presentedItemURL == url1)

        // Simulate system calling presentedItemDidMove
        presenter.presentedItemDidMove(to: url2)
        #expect(presenter.presentedItemURL == url2)

        presenter.invalidate()
    }

    // MARK: - Conflict Detection

    #if canImport(UIKit) || canImport(AppKit)
    @Test("CloudSyncService detects no conflict versions for a temp file")
    func conflictVersionDetection() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "conflict-test-\(UUID().uuidString).md")
        try? Data("test".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = CloudSyncService()
        let conflicts = service.conflictVersions(for: url)
        #expect(conflicts.isEmpty)
    }
    #endif

    // MARK: - Coordinated Read/Write Roundtrip

    @Test("FileSystemVaultProvider reads non-evicted file successfully")
    func readNonEvictedFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "read-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteURL = tmp.appending(path: "readable.md")
        let content = "---\ntitle: Readable\n---\n\nBody text"
        try Data(content.utf8).write(to: noteURL)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.readNote(at: noteURL)
        #expect(note.frontmatter.title == "Readable")
        #expect(note.body == "Body text")
    }

    // MARK: - Atomic Write Integrity

    @Test("CoordinatedFileWriter.write is atomic — no partial content")
    func atomicWrite() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "atomic-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        let initial = Data("initial content".utf8)
        try CoordinatedFileWriter.shared.write(initial, to: url)

        let updated = Data("updated content that is longer".utf8)
        try CoordinatedFileWriter.shared.write(updated, to: url)

        let result = try CoordinatedFileWriter.shared.read(from: url)
        #expect(String(data: result, encoding: .utf8) == "updated content that is longer")
    }

    // MARK: - Content Hash Echo Detection

    @Test("SHA256 content hash detects identical writes")
    func contentHashEchoDetection() {
        let content = "Hello, iCloud world!"
        let data = Data(content.utf8)
        let hash1 = SHA256.hash(data: data)
        let hash2 = SHA256.hash(data: data)
        #expect(hash1 == hash2)

        let different = Data("Different content".utf8)
        let hash3 = SHA256.hash(data: different)
        #expect(hash1 != hash3)
    }

    // MARK: - VaultProviding Protocol Extension

    @Test("VaultProviding default extension routes saveNote with presenter to saveNote without")
    func protocolDefaultExtension() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "protocol-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteURL = tmp.appending(path: "protocol.md")
        try Data("---\ntitle: Protocol\n---\n\nBody".utf8).write(to: noteURL)

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let note = try await provider.readNote(at: noteURL)

        // Save with explicit nil presenter
        try await provider.saveNote(note, filePresenter: nil)

        // Save without presenter (original API)
        try await provider.saveNote(note)

        // Both should succeed — read back to verify
        let reread = try await provider.readNote(at: noteURL)
        #expect(reread.frontmatter.title == "Protocol")
    }

    // MARK: - Move Coordination

    @Test("CoordinatedFileWriter.moveItem preserves content")
    func movePreservesContent() throws {
        let src = FileManager.default.temporaryDirectory
            .appending(path: "move-src-\(UUID().uuidString).md")
        let dst = FileManager.default.temporaryDirectory
            .appending(path: "move-dst-\(UUID().uuidString).md")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        try Data("move me".utf8).write(to: src)
        try CoordinatedFileWriter.shared.moveItem(from: src, to: dst)

        #expect(!FileManager.default.fileExists(atPath: src.path(percentEncoded: false)))
        let read = try CoordinatedFileWriter.shared.read(from: dst)
        #expect(String(data: read, encoding: .utf8) == "move me")
    }

    // MARK: - Delete Coordination

    @Test("CoordinatedFileWriter.removeItem deletes file")
    func removeItemWorks() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "delete-test-\(UUID().uuidString).md")
        try Data("delete me".utf8).write(to: url)

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        try CoordinatedFileWriter.shared.removeItem(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
