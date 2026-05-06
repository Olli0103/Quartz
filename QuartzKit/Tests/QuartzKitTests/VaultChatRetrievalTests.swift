import Testing
import Foundation
@testable import QuartzKit

@Suite("VaultChat exact-match retrieval")
struct VaultChatRetrievalTests {
    @Test("synthetic person name exact match is returned before semantic-only ranking")
    func syntheticPersonNameExactMatchIsReturned() async throws {
        let vault = FileManager.default.temporaryDirectory
            .appending(path: "VaultChatExact-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        let hanchunID = UUID()
        let otherID = UUID()
        let service = VectorEmbeddingService(vaultURL: vault, embeddingProvider: { text in
            text.localizedCaseInsensitiveContains("unrelated") ? [0, 1] : [1, 0]
        })
        try await service.indexNote(
            noteID: otherID,
            content: "Unrelated planning note with strong semantic-vector score."
        )
        try await service.indexNote(
            noteID: hanchunID,
            content: "Hanchun owns the launch checklist and should be cited for exact-name questions."
        )

        let results = await service.exactMatchSearch(query: "What did Hanchun own?", limit: 8)

        #expect(results.first?.entry.noteID == hanchunID)
        #expect(results.contains { $0.entry.chunkText.contains("Hanchun owns the launch checklist") })
    }

    @Test("wiki-link alias exact match is retained")
    func wikiLinkAliasExactMatchIsRetained() async throws {
        let vault = FileManager.default.temporaryDirectory
            .appending(path: "VaultChatAlias-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        let noteID = UUID()
        let service = VectorEmbeddingService(vaultURL: vault, embeddingProvider: { _ in [1, 0] })
        try await service.indexNote(
            noteID: noteID,
            content: "Contact trail: [[Andreas|CAS]] introduced Hanchun to Christian."
        )

        let results = await service.exactMatchSearch(query: "CAS", limit: 8)

        #expect(results.first?.entry.noteID == noteID)
        #expect(results.first?.entry.chunkText.contains("[[Andreas|CAS]]") == true)
    }
}
