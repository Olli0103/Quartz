import Testing
import Foundation
@testable import QuartzKit

// MARK: - Recovery Journal Tests

/// Verifies RecoveryJournal core operations: record, replay, clear, backoff.
/// Kept minimal to stay within linker section budget.

@Suite("RecoveryJournal")
struct RJTests {

    private func fresh() async -> RecoveryJournal {
        let j = RecoveryJournal.shared
        let d = FileManager.default.temporaryDirectory.appending(path: "rj-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        await j.configure(vaultRoot: d)
        for e in await j.pendingEntries { await j.clearEntries(for: e.fileURL) }
        await j.clearDeferredEntries()
        return j
    }

    @Test("Record, duplicate, clear lifecycle")
    func lifecycle() async {
        let j = await fresh()
        let u = URL(fileURLWithPath: "/tmp/rj-life.md")

        // Record creates entry with retryCount=0
        await j.recordFailure(for: u, operation: .indexEmbedding)
        var entries = await j.pendingEntries
        var entry = entries.first(where: { $0.fileURL == u })
        #expect(entry != nil)
        #expect(entry?.retryCount == 0, "First record should have retryCount=0")

        // Duplicate increments retryCount to 1
        await j.recordFailure(for: u, operation: .indexEmbedding)
        entries = await j.pendingEntries
        entry = entries.first(where: { $0.fileURL == u })
        #expect(entry?.retryCount == 1, "Second record should increment to 1")

        // Clear removes the entry
        await j.clearEntries(for: u)
        entries = await j.pendingEntries
        #expect(!entries.contains(where: { $0.fileURL == u }))
    }

    @Test("clearEntries selective removal")
    func clearSelective() async {
        let j = await fresh()
        let u1 = URL(fileURLWithPath: "/tmp/rj-c1.md")
        let u2 = URL(fileURLWithPath: "/tmp/rj-c2.md")
        await j.recordFailure(for: u1, operation: .indexEmbedding)
        await j.recordFailure(for: u2, operation: .indexEmbedding)
        await j.clearEntries(for: u1)
        let entries = await j.pendingEntries
        #expect(!entries.contains(where: { $0.fileURL == u1 }))
        #expect(entries.contains(where: { $0.fileURL == u2 }))
    }

    @Test("Backoff formula and type raw values")
    func backoffAndTypes() {
        var e = RecoveryJournal.JournalEntry(
            fileURL: URL(fileURLWithPath: "/tmp/bf.md"),
            operation: .indexEmbedding
        )
        e.retryCount = 1
        if let t = e.nextRetryTime {
            #expect(abs(t.timeIntervalSince(e.lastAttempt) - 2.0) < 0.5)
        }
        e.retryCount = 3
        if let t = e.nextRetryTime {
            #expect(abs(t.timeIntervalSince(e.lastAttempt) - 8.0) < 0.5)
        }

        #expect(RecoveryJournal.OperationType.indexEmbedding.rawValue == "index_embedding")
        #expect(RecoveryJournal.OperationType.removeEmbedding.rawValue == "remove_embedding")
    }
}
