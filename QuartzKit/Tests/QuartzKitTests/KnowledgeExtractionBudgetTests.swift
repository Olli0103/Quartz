import Testing
import Foundation
@testable import QuartzKit

@Suite("Knowledge extraction automatic budget")
struct KnowledgeExtractionBudgetTests {
    private func makeTempVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeBudget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("slow automatic extraction pauses provider slow without processing note")
    func slowAutomaticExtractionPausesProviderSlow() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appending(path: "slow.md")
        try """
        # Slow

        This note is intentionally long enough for concept extraction and its provider call
        will exceed the automatic per-note budget in this focused regression test.
        """.write(to: note, atomically: true, encoding: .utf8)

        let service = KnowledgeExtractionService(
            edgeStore: GraphEdgeStore(),
            vaultRootURL: vault,
            scanInterval: .milliseconds(1),
            automaticMaxPerNoteDurationMs: 25,
            extractionOverride: { _ in
                try? await Task.sleep(for: .milliseconds(250))
                return ["slow provider"]
            }
        )

        await service.startVaultScan(mode: .automatic)

        let reachedProviderSlow = await waitUntil(timeout: .seconds(2)) {
            let summary = KnowledgeExtractionService.persistedHealthSummary(vaultRootURL: vault)
            return summary["aiIndex.status"] == AIIndexingStatus.providerSlow.rawValue
                && summary["aiIndex.lastFailureReason"] == "ai.providerSlow"
        }

        #expect(reachedProviderSlow)
        let classification = await service.classifyPendingNotesForTesting([note], mode: .automatic)
        #expect(classification.totalPending == 1)
    }

    @Test("manual rebuild is not constrained by automatic per-note timeout")
    func manualRebuildIgnoresAutomaticPerNoteTimeout() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appending(path: "manual.md")
        try """
        # Manual

        This note is long enough for concept extraction and proves manual rebuild can use
        a longer provider call than the automatic scan budget allows.
        """.write(to: note, atomically: true, encoding: .utf8)

        let service = KnowledgeExtractionService(
            edgeStore: GraphEdgeStore(),
            vaultRootURL: vault,
            scanInterval: .milliseconds(1),
            automaticMaxPerNoteDurationMs: 25,
            extractionOverride: { _ in
                try? await Task.sleep(for: .milliseconds(80))
                return ["manual rebuild"]
            }
        )

        await service.startVaultScan(mode: .manualRebuild)

        let processed = await waitUntil(timeout: .seconds(2)) {
            let classification = await service.classifyPendingNotesForTesting([note], mode: .automatic)
            return classification.totalPending == 0
        }

        #expect(processed)
    }

    @Test("pause, retry, and cancel publish visible indexing state")
    func indexingControlsPublishVisibleState() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appending(path: "pending.md")
        try """
        # Pending

        This note is intentionally long enough to be eligible for the indexing status model.
        """.write(to: note, atomically: true, encoding: .utf8)

        let service = KnowledgeExtractionService(
            edgeStore: GraphEdgeStore(),
            vaultRootURL: vault,
            scanInterval: .milliseconds(100),
            extractionOverride: { _ in ["visible status"] }
        )

        await service.pauseAIIndexing()
        var snapshot = await service.statusSnapshot()
        #expect(snapshot.status == .paused)
        #expect(snapshot.pendingNotes == 1)

        let recreated = KnowledgeExtractionService(
            edgeStore: GraphEdgeStore(),
            vaultRootURL: vault,
            scanInterval: .milliseconds(100),
            extractionOverride: { _ in ["should not run while paused"] }
        )
        await recreated.startVaultScan(mode: .automatic)
        snapshot = await recreated.statusSnapshot()
        #expect(snapshot.status == .paused)

        await service.retryAIIndexingNow()
        snapshot = await service.statusSnapshot()
        #expect(snapshot.status != .paused)
        #expect(snapshot.scanMode == .automatic)

        await service.cancelCurrentAIJob()
        snapshot = await service.statusSnapshot()
        #expect(snapshot.status == .idle || snapshot.status == .running)
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(20),
        condition: () async -> Bool
    ) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if await condition() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return false
    }
}
