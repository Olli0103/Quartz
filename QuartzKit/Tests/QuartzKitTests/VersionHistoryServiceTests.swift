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
