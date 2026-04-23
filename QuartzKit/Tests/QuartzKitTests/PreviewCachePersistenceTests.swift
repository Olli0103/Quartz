import Testing
import Foundation
@testable import QuartzKit

@Suite("PreviewCachePersistence")
struct PreviewCachePersistenceTests {

    @Test("Full preview reindex prunes deleted notes from the persisted cache")
    func fullReindexPrunesDeletedNotes() async throws {
        let root = try makeTempVault(noteNames: ["alpha", "beta"])
        defer { try? FileManager.default.removeItem(at: root) }

        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        let repository = NotePreviewRepository(vaultRoot: root)
        let indexer = NotePreviewIndexer(
            vaultRoot: root,
            repository: repository,
            frontmatterParser: parser
        )

        let initialTree = try await provider.loadFileTree(at: root)
        await indexer.indexAll(from: initialTree)
        #expect(await repository.count == 2)

        try FileManager.default.removeItem(at: root.appending(path: "beta.md"))

        let rebuiltTree = try await provider.loadFileTree(at: root)
        await indexer.indexAll(from: rebuiltTree)

        let previews = await repository.allPreviews()
        #expect(previews.count == 1)
        #expect(previews.first?.url.lastPathComponent == "alpha.md")
    }

    private func makeTempVault(noteNames: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".quartz"), withIntermediateDirectories: true)

        for name in noteNames {
            let content = """
            ---
            title: \(name.capitalized)
            tags: [preview, \(name)]
            ---
            Body for \(name).
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
