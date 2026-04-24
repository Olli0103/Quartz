import Testing
import Foundation
import CryptoKit
@testable import QuartzKit

// MARK: - Version History Service Tests

@Suite("VersionHistoryPersistence")
struct VersionHistoryPersistenceTests {

    private func makeTempVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("version-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("Snapshot save, fetch, and read round-trip")
    func snapshotRoundTrip() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("test.md")
        try "Original content".write(to: noteURL, atomically: true, encoding: .utf8)

        let service = VersionHistoryService()

        // Save a snapshot
        service.saveSnapshot(for: noteURL, content: "Snapshot v1", vaultRoot: root)

        // Fetch versions
        let versions = service.fetchVersions(for: noteURL, vaultRoot: root)
        #expect(versions.count == 1)
        #expect(versions.first?.isEncrypted == false)

        // Read back
        if let version = versions.first {
            let text = try service.readText(from: version)
            #expect(text == "Snapshot v1")
        }
    }

    @Test("Rapid meaningful snapshots do not overwrite each other")
    func rapidMeaningfulSnapshotsDoNotOverwrite() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("rapid.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)

        let service = VersionHistoryService()
        #expect(service.saveSnapshot(for: noteURL, content: "v1", vaultRoot: root))
        #expect(service.saveSnapshot(for: noteURL, content: "v2", vaultRoot: root))
        #expect(service.saveSnapshot(for: noteURL, content: "v3", vaultRoot: root))

        let versions = service.fetchVersions(for: noteURL, vaultRoot: root)
        let contents = try versions.map { try service.readFullText(from: $0) }
        #expect(versions.count == 3)
        #expect(Set(contents) == Set(["v1", "v2", "v3"]))
    }

    @Test("Duplicate plaintext snapshots are skipped")
    func duplicatePlaintextSnapshotsSkipped() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("duplicate.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)

        let service = VersionHistoryService()
        #expect(service.saveSnapshot(for: noteURL, content: "same", vaultRoot: root))
        #expect(service.saveSnapshot(for: noteURL, content: "same", vaultRoot: root) == false)

        let versions = service.fetchVersions(for: noteURL, vaultRoot: root)
        #expect(versions.count == 1)
    }

    @Test("Snapshot write failure reports false without creating a version")
    func snapshotWriteFailureReturnsFalse() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileRoot = root.appendingPathComponent("not-a-directory")
        try "blocking file".write(to: fileRoot, atomically: true, encoding: .utf8)
        let noteURL = fileRoot.appendingPathComponent("blocked.md")

        let service = VersionHistoryService()
        #expect(service.saveSnapshot(for: noteURL, content: "cannot write", vaultRoot: fileRoot) == false)
        #expect(service.fetchVersions(for: noteURL, vaultRoot: fileRoot).isEmpty)
    }

    @Test("Multiple snapshots sorted by date, encryption works")
    func multipleAndEncryption() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("multi.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)

        let service = VersionHistoryService()

        // Save multiple snapshots — need >1s gap for ISO8601 second-granularity filenames
        service.saveSnapshot(for: noteURL, content: "v1", vaultRoot: root)
        Thread.sleep(forTimeInterval: 1.1)
        service.saveSnapshot(for: noteURL, content: "v2", vaultRoot: root)

        let versions = service.fetchVersions(for: noteURL, vaultRoot: root)
        #expect(versions.count == 2)
        // Newest first
        if versions.count == 2 {
            let text1 = try service.readText(from: versions[0])
            let text2 = try service.readText(from: versions[1])
            #expect(text1 == "v2")
            #expect(text2 == "v1")
        }

        // Encrypted snapshot
        let key = SymmetricKey(size: .bits256)
        service.saveSnapshot(for: noteURL, content: "secret", vaultRoot: root, encryptionKey: key)

        let allVersions = service.fetchVersions(for: noteURL, vaultRoot: root)
        let encrypted = allVersions.filter(\.isEncrypted)
        #expect(encrypted.count == 1)

        if let enc = encrypted.first {
            let decrypted = try service.readText(from: enc, encryptionKey: key)
            #expect(decrypted == "secret")
        }
    }

    @Test("Restore writes selected version content to note")
    func restoreWritesSelectedVersionContent() async throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("restore.md")
        try "current".write(to: noteURL, atomically: true, encoding: .utf8)

        let service = VersionHistoryService()
        #expect(service.saveSnapshot(for: noteURL, content: "restored body", vaultRoot: root))

        let versions = service.fetchVersions(for: noteURL, vaultRoot: root)
        guard let version = versions.first else {
            Issue.record("Expected a version to restore")
            return
        }

        try await service.restore(version: version, to: noteURL)

        let restored = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(restored == "restored body")
    }

    @Test("No versions for nonexistent note, max snapshots constant")
    func edgeCases() {
        let service = VersionHistoryService()
        let fakeNote = URL(fileURLWithPath: "/nonexistent/note.md")
        let fakeRoot = URL(fileURLWithPath: "/nonexistent")

        let versions = service.fetchVersions(for: fakeNote, vaultRoot: fakeRoot)
        #expect(versions.isEmpty)
        #expect(VersionHistoryService.maxSnapshotsPerNote == 50)
    }
}
