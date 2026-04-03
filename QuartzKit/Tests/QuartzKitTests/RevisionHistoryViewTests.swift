import Testing
import Foundation
@testable import QuartzKit

// MARK: - Revision History View / VersionHistoryService Model Tests

@Suite("RevisionHistoryView")
struct RevisionHistoryViewTests {

    @Test("NoteVersion model properties, VersionHistoryService constants, and error types")
    func noteVersionModelAndConstants() throws {
        // VersionHistoryService max snapshots constant
        #expect(VersionHistoryService.maxSnapshotsPerNote == 50)

        // Create a temp vault and snapshot to verify NoteVersion model
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rev-hist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("history-test.md")
        try "Test content".write(to: noteURL, atomically: true, encoding: .utf8)

        let service = VersionHistoryService()
        service.saveSnapshot(for: noteURL, content: "Version 1", vaultRoot: root)

        let versions = service.fetchVersions(for: noteURL, vaultRoot: root)
        #expect(versions.count == 1)

        if let v = versions.first {
            // NoteVersion has expected properties
            #expect(v.isEncrypted == false)
            #expect(v.snapshotURL.pathExtension == "md")

            // Read text succeeds
            let text = try service.readText(from: v)
            #expect(text == "Version 1")
        }

        // No versions for non-existent file
        let fakeURL = URL(fileURLWithPath: "/no-such-file.md")
        let empty = service.fetchVersions(for: fakeURL, vaultRoot: root)
        #expect(empty.isEmpty)
    }
}
