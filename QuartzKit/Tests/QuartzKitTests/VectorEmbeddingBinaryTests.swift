import Testing
import Foundation
@testable import QuartzKit

@Suite("VectorEmbeddingService Binary Format")
struct VectorEmbeddingBinaryTests {
    private func makeTempVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("saveIndex and loadIndex round-trip empty index")
    func emptyRoundTrip() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VectorEmbeddingService(vaultURL: vault)

        try await service.saveIndex()
        try await service.loadIndex()

        let count = await service.entryCount
        #expect(count == 0)
    }

    @Test("saveIndex and loadIndex round-trip with entries")
    func entryRoundTrip() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VectorEmbeddingService(vaultURL: vault)

        // Manually index a note via the public API
        try await service.indexNote(noteID: UUID(), content: "This is a test note with some content for embedding")

        let countBefore = await service.entryCount

        // Save and reload
        try await service.saveIndex()

        let service2 = VectorEmbeddingService(vaultURL: vault)
        try await service2.loadIndex()

        let countAfter = await service2.entryCount
        #expect(countAfter == countBefore)
    }

    @Test("unchanged index does not rewrite embeddings checkpoint")
    func unchangedIndexDoesNotRewriteCheckpoint() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VectorEmbeddingService(vaultURL: vault)
        try await service.indexNote(noteID: UUID(), content: "Stable note content for checkpoint gating")
        try await service.saveIndex()

        let indexFile = VectorEmbeddingService.indexFileURL(for: vault)
        let firstModified = try #require(
            FileManager.default.attributesOfItem(atPath: indexFile.path(percentEncoded: false))[.modificationDate] as? Date
        )
        try await Task.sleep(for: .milliseconds(30))

        try await service.saveIndex(force: true)
        let secondModified = try #require(
            FileManager.default.attributesOfItem(atPath: indexFile.path(percentEncoded: false))[.modificationDate] as? Date
        )

        #expect(secondModified == firstModified)
    }

    @Test("save pressure pauses dirty checkpoint and resumes after recovery")
    func savePressurePausesDirtyCheckpointAndResumes() async throws {
        let vault = try makeTempVault()
        defer {
            VectorEmbeddingService.resumeCheckpointingAfterSaveRecovery(vaultURL: vault)
            try? FileManager.default.removeItem(at: vault)
        }

        let service = VectorEmbeddingService(vaultURL: vault)
        try await service.indexNote(noteID: UUID(), content: "Dirty content that should wait for save recovery")
        VectorEmbeddingService.pauseCheckpointingForSavePressure(seconds: 60, vaultURL: vault)

        try await service.saveIndex(force: true)
        let indexFile = VectorEmbeddingService.indexFileURL(for: vault)
        #expect(!FileManager.default.fileExists(atPath: indexFile.path(percentEncoded: false)))

        VectorEmbeddingService.resumeCheckpointingAfterSaveRecovery(vaultURL: vault)
        try await service.saveIndex(force: true)
        #expect(FileManager.default.fileExists(atPath: indexFile.path(percentEncoded: false)))
    }

    @Test("automatic checkpoint rejects catastrophic shrink and preserves existing index")
    func automaticCheckpointRejectsCatastrophicShrink() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        var noteIDs: [UUID] = []
        let healthy = VectorEmbeddingService(vaultURL: vault)
        for index in 0..<12 {
            let id = UUID()
            noteIDs.append(id)
            try await healthy.indexNote(noteID: id, content: "Healthy persisted note \(index) with enough content for a stable embedding chunk.")
        }
        try await healthy.saveIndex(force: true)
        let healthyChunks = await healthy.entryCount
        #expect(healthyChunks >= 10)

        let shrinking = VectorEmbeddingService(vaultURL: vault)
        try await shrinking.loadIndex()
        for id in noteIDs.dropFirst() {
            await shrinking.removeNote(id)
        }

        do {
            try await shrinking.saveIndex(force: true)
            Issue.record("Automatic checkpoint should reject replacing a healthy index with a tiny partial index")
        } catch let error as EmbeddingIndexError {
            guard case .shrinkingCheckpointRejected = error else {
                Issue.record("Unexpected embedding error: \(error)")
                return
            }
        }

        let reloaded = VectorEmbeddingService(vaultURL: vault)
        try await reloaded.loadIndex()
        #expect(await reloaded.entryCount == healthyChunks)
        #expect(await reloaded.indexedNoteCount == 12)
    }

    @Test("explicit rebuild may replace a larger index with a smaller index")
    func explicitRebuildMayReplaceLargeIndex() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        var noteIDs: [UUID] = []
        let service = VectorEmbeddingService(vaultURL: vault)
        for index in 0..<12 {
            let id = UUID()
            noteIDs.append(id)
            try await service.indexNote(noteID: id, content: "Explicit rebuild source note \(index) with enough content for embedding.")
        }
        try await service.saveIndex(force: true)

        for id in noteIDs.dropFirst() {
            await service.removeNote(id)
        }
        try await service.saveIndex(force: true, explicitRebuild: true)

        let reloaded = VectorEmbeddingService(vaultURL: vault)
        try await reloaded.loadIndex()
        #expect(await reloaded.indexedNoteCount == 1)
    }

    @Test("checkpoint creates backup and backup can restore index")
    func checkpointBackupRestoresIndex() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstID = UUID()
        let secondID = UUID()
        let service = VectorEmbeddingService(vaultURL: vault)
        try await service.indexNote(noteID: firstID, content: "First checkpoint note with durable content.")
        try await service.saveIndex(force: true)
        try await service.indexNote(noteID: secondID, content: "Second checkpoint note creates a backup before replacement.")
        try await service.saveIndex(force: true)

        let backupURL = VectorEmbeddingService.backupIndexFileURL(for: vault)
        #expect(FileManager.default.fileExists(atPath: backupURL.path(percentEncoded: false)))

        let indexURL = VectorEmbeddingService.indexFileURL(for: vault)
        try Data([0x01, 0x02, 0x03]).write(to: indexURL, options: .atomic)

        let restored = VectorEmbeddingService(vaultURL: vault)
        let didRestore = try await restored.restoreIndexFromBackup()
        #expect(didRestore)
        #expect(await restored.indexedNoteCount == 1)
    }

    @Test("loadIndex with no file returns empty index")
    func loadNonexistent() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VectorEmbeddingService(vaultURL: vault)
        try await service.loadIndex()

        let count = await service.entryCount
        #expect(count == 0)
    }

    @Test("missing iCloud-backed index defers rebuild instead of loading as empty")
    func missingICloudIndexDefersRebuild() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Mobile Documents", directoryHint: .isDirectory)
            .appending(path: "com~apple~CloudDocs", directoryHint: .isDirectory)
            .appending(path: "EmbeddingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let quartz = base.appending(path: ".quartz", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: quartz, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: quartz.appending(path: "search-index.json"))

        let service = VectorEmbeddingService(vaultURL: base)
        do {
            try await service.loadIndex()
            Issue.record("A missing iCloud-backed embedding index should defer the sweep instead of loading as a valid empty index")
        } catch let error as EmbeddingIndexError {
            guard case .indexUnavailable(let reason) = error else {
                Issue.record("Unexpected embedding index error: \(error)")
                return
            }
            #expect(reason.contains("iCloud-backed vault"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("brand-new iCloud-backed vault without prior quartz state can start empty")
    func brandNewICloudVaultCanStartEmpty() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Mobile Documents", directoryHint: .isDirectory)
            .appending(path: "com~apple~CloudDocs", directoryHint: .isDirectory)
            .appending(path: "NewEmbeddingVault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let service = VectorEmbeddingService(vaultURL: base)
        try await service.loadIndex()

        let count = await service.entryCount
        #expect(count == 0)
    }

    @Test("diagnostics and loader use the same canonical index path")
    func canonicalIndexPathMatchesServicePath() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let service = VectorEmbeddingService(vaultURL: vault)
        let expected = CanonicalNoteIdentity.canonicalFileURL(for: vault)
            .appending(path: ".quartz", directoryHint: .isDirectory)
            .appending(path: "embeddings.idx")

        #expect(VectorEmbeddingService.indexFileURL(for: vault) == expected)
        #expect(await service.indexFileURL == expected)
    }

    @Test("loadIndex with corrupted data throws")
    func corruptedData() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let indexDir = vault.appendingPathComponent(".quartz")
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        let indexFile = indexDir.appendingPathComponent("embeddings.idx")

        // Write garbage data
        try Data([0xFF, 0xFE, 0xFD]).write(to: indexFile)

        let service = VectorEmbeddingService(vaultURL: vault)
        do {
            try await service.loadIndex()
            Issue.record("Should have thrown for corrupted data")
        } catch {
            // Expected — either corruptedIndex or unsupportedVersion
        }
    }

    @Test("loadIndex rejects zero declared entries with trailing bytes")
    func zeroEntryHeaderWithPayloadIsRejected() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let indexDir = vault.appendingPathComponent(".quartz")
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        let indexFile = indexDir.appendingPathComponent("embeddings.idx")

        var data = Data()
        var version = UInt32(1).littleEndian
        var count = UInt32(0).littleEndian
        data.append(Data(bytes: &version, count: 4))
        data.append(Data(bytes: &count, count: 4))
        data.append(Data(repeating: 0xA5, count: 256))
        try data.write(to: indexFile)

        let service = VectorEmbeddingService(vaultURL: vault)
        do {
            try await service.loadIndex()
            Issue.record("A non-empty index file that declares zero entries must not silently load as 0 chunks")
        } catch let error as EmbeddingIndexError {
            guard case .trailingDataAfterDeclaredEntries(let declaredEntries, let trailingBytes) = error else {
                Issue.record("Unexpected embedding index error: \(error)")
                return
            }
            #expect(declaredEntries == 0)
            #expect(trailingBytes == 256)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("removeNote clears entries for that note")
    func removeNote() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = UUID()
        let service = VectorEmbeddingService(vaultURL: vault)

        try await service.indexNote(noteID: noteID, content: "Some test content for indexing")

        let countBefore = await service.entryCount
        #expect(countBefore > 0)

        await service.removeNote(noteID)
        let countAfter = await service.entryCount
        #expect(countAfter == 0)
    }

    @Test("EmbeddingEntry preserves all fields through binary round-trip")
    func fieldPreservation() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = UUID()
        let service = VectorEmbeddingService(vaultURL: vault)

        try await service.indexNote(noteID: noteID, content: "Ümlauts, Sönderzeichen & Emojis: 🎉 日本語")

        try await service.saveIndex()

        let service2 = VectorEmbeddingService(vaultURL: vault)
        try await service2.loadIndex()

        let noteIDs = await service2.indexedNoteIDs
        #expect(noteIDs.contains(noteID))
    }

    @Test("EmbeddingIndexError provides error descriptions")
    func errorDescriptions() {
        let corrupted = EmbeddingIndexError.corruptedIndex
        let unsupported = EmbeddingIndexError.unsupportedVersion(99)
        let unavailable = EmbeddingIndexError.indexUnavailable("missing due to iCloud materialization")
        let trailing = EmbeddingIndexError.trailingDataAfterDeclaredEntries(declaredEntries: 0, trailingBytes: 128)

        #expect(corrupted.errorDescription != nil)
        #expect(unsupported.errorDescription != nil)
        #expect(unsupported.errorDescription!.contains("99"))
        #expect(unavailable.errorDescription?.contains("iCloud") == true)
        #expect(trailing.errorDescription?.contains("trailing bytes") == true)
    }
}
