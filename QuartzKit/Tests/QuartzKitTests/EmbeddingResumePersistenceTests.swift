import Testing
import Foundation
@testable import QuartzKit

@Suite("Embedding Resume Persistence", .serialized)
struct EmbeddingResumePersistenceTests {
    private func makeTempVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddingResume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeNotes(count: Int, in vault: URL) throws -> [URL] {
        var urls: [URL] = []
        for index in 0..<count {
            let url = vault.appending(path: "note-\(index).md")
            let body = """
            # Note \(index)

            This is a realistic note body for embedding resume tests. It includes enough ordinary prose
            for NaturalLanguage sentence embeddings to produce at least one chunk for the note.
            """
            try body.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }

    private func modificationDate(for url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return try #require(values.contentModificationDate)
    }

    private func pendingSummary(
        service: VectorEmbeddingService,
        urls: [URL],
        vaultRoot: URL
    ) async throws -> [VectorEmbeddingService.PendingReason: Int] {
        var summary: [VectorEmbeddingService.PendingReason: Int] = [:]
        for url in urls {
            let mtime = try modificationDate(for: url)
            if let reason = await service.pendingReason(for: url, vaultRoot: vaultRoot, modificationDate: mtime) {
                summary[reason, default: 0] += 1
            }
        }
        return summary
    }

    @Test("Valid persisted index loads chunks and excludes indexed notes after restart")
    func validIndexLoadExcludesAlreadyIndexedNotes() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let notes = try makeNotes(count: 12, in: vault)

        let service = VectorEmbeddingService(vaultURL: vault)
        for url in notes.prefix(5) {
            let id = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vault)
            try await service.indexNote(noteID: id, content: String(contentsOf: url, encoding: .utf8))
        }
        try await service.saveIndex()

        let restarted = VectorEmbeddingService(vaultURL: vault)
        try await restarted.loadIndex()

        #expect(await restarted.entryCount > 0)
        #expect(await restarted.indexedNoteCount == 5)

        let summary = try await pendingSummary(service: restarted, urls: notes, vaultRoot: vault)
        #expect(summary[.neverIndexed] == 7)
        #expect(summary[.modifiedAfterIndex] == nil)
        #expect(summary[.missingModificationDate] == nil)
    }

    @Test("Partial checkpoint resumes from remaining notes after service recreation")
    func partialCheckpointResumesFromRemainingNotes() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let notes = try makeNotes(count: 10, in: vault)

        let firstRun = VectorEmbeddingService(vaultURL: vault)
        for url in notes.prefix(4) {
            let id = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vault)
            try await firstRun.indexNote(noteID: id, content: String(contentsOf: url, encoding: .utf8))
        }
        try await firstRun.saveIndex()

        let resumed = VectorEmbeddingService(vaultURL: vault)
        try await resumed.loadIndex()

        let initialPending = try await pendingSummary(service: resumed, urls: notes, vaultRoot: vault)
        #expect(initialPending[.neverIndexed] == 6)

        for url in notes {
            let mtime = try modificationDate(for: url)
            guard await resumed.pendingReason(for: url, vaultRoot: vault, modificationDate: mtime) != nil else {
                continue
            }
            let id = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vault)
            try await resumed.indexNote(noteID: id, content: String(contentsOf: url, encoding: .utf8))
        }
        try await resumed.saveIndex()

        let finalRun = VectorEmbeddingService(vaultURL: vault)
        try await finalRun.loadIndex()

        #expect(await finalRun.indexedNoteCount == notes.count)
        let finalPending = try await pendingSummary(service: finalRun, urls: notes, vaultRoot: vault)
        #expect(finalPending.isEmpty)
    }

    @Test("Stable note IDs survive canonical vault path differences across restart")
    func stableNoteIDsSurviveCanonicalPathDifferences() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = try makeNotes(count: 1, in: vault)[0]

        let canonicalID = VectorEmbeddingService.stableNoteID(for: note, vaultRoot: vault)
        let nonCanonicalRoot = vault
            .appending(path: "subdir", directoryHint: .isDirectory)
            .appending(path: "..", directoryHint: .isDirectory)
        let nonCanonicalNote = nonCanonicalRoot.appending(path: note.lastPathComponent)
        let restartedID = VectorEmbeddingService.stableNoteID(for: nonCanonicalNote, vaultRoot: nonCanonicalRoot)

        #expect(restartedID == canonicalID)
    }

    @Test("Modified note is the only pending note after persisted index reload")
    func modifiedNoteIsOnlyPendingAfterReload() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let notes = try makeNotes(count: 6, in: vault)

        let service = VectorEmbeddingService(vaultURL: vault)
        for url in notes {
            let id = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vault)
            try await service.indexNote(noteID: id, content: String(contentsOf: url, encoding: .utf8))
        }
        try await service.saveIndex()

        try await Task.sleep(for: .milliseconds(20))
        try "Changed content after checkpoint".write(to: notes[2], atomically: true, encoding: .utf8)

        let restarted = VectorEmbeddingService(vaultURL: vault)
        try await restarted.loadIndex()
        let summary = try await pendingSummary(service: restarted, urls: notes, vaultRoot: vault)

        #expect(summary[.modifiedAfterIndex] == 1)
        #expect(summary[.neverIndexed] == nil)
    }

    @Test("Legacy unmatched chunks are pruned so new checkpoint progress survives restart")
    func legacyUnmatchedChunksArePrunedBeforeResumeCheckpoint() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let notes = try makeNotes(count: 9, in: vault)

        let legacy = VectorEmbeddingService(vaultURL: vault)
        for url in notes.prefix(4) {
            try await legacy.indexNote(
                noteID: UUID(),
                content: String(contentsOf: url, encoding: .utf8)
            )
        }
        try await legacy.saveIndex()

        let restarted = VectorEmbeddingService(vaultURL: vault)
        try await restarted.loadIndex()
        #expect(await restarted.entryCount > 0)
        #expect(await restarted.indexedNoteIDOverlapCount(with: Set(notes.map {
            VectorEmbeddingService.stableNoteID(for: $0, vaultRoot: vault)
        })) == 0)

        let knownIDs = Set(notes.map { VectorEmbeddingService.stableNoteID(for: $0, vaultRoot: vault) })
        let pruneResult = await restarted.pruneToKnownNoteIDs(knownIDs)
        #expect(pruneResult.removedChunks > 0)
        #expect(pruneResult.remainingChunks == 0)

        for url in notes.prefix(3) {
            let id = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vault)
            try await restarted.indexNote(noteID: id, content: String(contentsOf: url, encoding: .utf8))
        }
        try await restarted.saveIndex()

        let secondRestart = VectorEmbeddingService(vaultURL: vault)
        try await secondRestart.loadIndex()
        let summary = try await pendingSummary(service: secondRestart, urls: notes, vaultRoot: vault)
        #expect(await secondRestart.indexedNoteCount == 3)
        #expect(summary[.neverIndexed] == 6)
        #expect(summary[.modifiedAfterIndex] == nil)
    }

    @MainActor
    @Test("Save pressure pauses embedding sweep and recovery resumes it")
    func savePressurePausesAndRecoveryResumesEmbeddingSweep() async throws {
        let vault = try makeTempVault()
        defer {
            ServiceContainer.shared.reset()
            try? FileManager.default.removeItem(at: vault)
        }
        let notes = try makeNotes(count: 10, in: vault)

        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        ServiceContainer.shared.reset()
        ServiceContainer.shared.bootstrap(vaultProvider: provider, frontmatterParser: parser)

        let viewModel = ContentViewModel(appState: AppState())
        viewModel.loadVault(VaultConfig(name: "Embedding Resume", rootURL: vault))

        NotificationCenter.default.post(
            name: .quartzEditorSaveHealthChanged,
            object: notes[0],
            userInfo: ["state": "failed"]
        )

        try await Task.sleep(for: .seconds(1))
        let pausedCount = await viewModel.embeddingService?.indexedNoteCount ?? 0
        #expect(pausedCount == 0)

        NotificationCenter.default.post(
            name: .quartzEditorSaveHealthChanged,
            object: notes[0],
            userInfo: ["state": "recovered"]
        )

        let resumed = await waitUntil(timeout: .seconds(12)) {
            let indexed = await viewModel.embeddingService?.indexedNoteCount ?? 0
            return indexed == notes.count
        }
        #expect(resumed)
    }

    @MainActor
    @Test("Editor save completes while embedding sweep is active")
    func editorSaveCompletesWhileEmbeddingSweepIsActive() async throws {
        let vault = try makeTempVault()
        defer {
            ServiceContainer.shared.reset()
            try? FileManager.default.removeItem(at: vault)
        }
        let notes = try makeNotes(count: 80, in: vault)

        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        ServiceContainer.shared.reset()
        ServiceContainer.shared.bootstrap(vaultProvider: provider, frontmatterParser: parser)

        let viewModel = ContentViewModel(appState: AppState())
        viewModel.loadVault(VaultConfig(name: "Save During Indexing", rootURL: vault))

        guard let session = viewModel.editorSession else {
            Issue.record("Expected editor session after vault load")
            return
        }

        let noteURL = notes[0]
        await session.loadNote(at: noteURL)
        let editedText = """
        # Save During Indexing

        This edit must persist while the embedding sweep is still warming the vault.
        """
        session.textDidChange(editedText)

        let start = Date()
        await session.manualSave()
        let elapsed = Date().timeIntervalSince(start)

        let diskText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(diskText.contains("This edit must persist while the embedding sweep is still warming the vault."))
        #expect(session.isDirty == false)
        #expect(session.errorMessage == nil)
        #expect(elapsed < 2.0, "Editor save should remain bounded while background embedding work is active")
    }

    @MainActor
    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(50),
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return await condition()
    }
}
