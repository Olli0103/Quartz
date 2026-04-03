import Testing
import Foundation
@testable import QuartzKit

// MARK: - Search Index Persistence Tests

@Suite("SearchIndexPersistence")
struct SearchIndexPersistenceTests {

    private func makeTempVault() throws -> (URL, any VaultProviding) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-test-\(UUID().uuidString)")
        let quartzDir = root.appending(path: ".quartz")
        try FileManager.default.createDirectory(at: quartzDir, withIntermediateDirectories: true)

        // Create a few test notes
        for i in 1...3 {
            let content = """
            ---
            title: Note \(i)
            tags: [test, note\(i)]
            ---
            Body of note \(i) with some #inline content.
            """
            try content.write(
                to: root.appendingPathComponent("note\(i).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let provider = AdvancedMockVaultProvider()
        return (root, provider)
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

        // Modify file — fingerprint should change
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
}
