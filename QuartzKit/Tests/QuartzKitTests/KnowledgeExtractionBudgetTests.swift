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
        let retryDiagnosticRecorded = await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let diagnostics = await SubsystemDiagnostics.snapshot()
            let events = diagnostics.eventsBySubsystem[.aiIndexing] ?? []
            return events.contains { $0.name == "ai.retryNowScheduled" }
        }
        #expect(retryDiagnosticRecorded)

        await service.cancelCurrentAIJob()
        snapshot = await service.statusSnapshot()
        #expect(snapshot.status == .pendingBacklogIdle || snapshot.status == .running)
    }

    @Test("expired providerSlow backoff becomes retryable status")
    func expiredProviderSlowBackoffBecomesRetryableStatus() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let quartzDir = vault.appending(path: ".quartz", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: quartzDir, withIntermediateDirectories: true)
        let note = vault.appending(path: "pending-after-backoff.md")
        try """
        # Pending after backoff

        This note remains pending when the providerSlow backoff expires.
        """.write(to: note, atomically: true, encoding: .utf8)
        var state = AIIndexState()
        state.lastStatus = AIIndexingStatus.providerSlow.rawValue
        state.lastFailureReason = "ai.providerSlow"
        state.lastFailureAt = Date().addingTimeInterval(-600)
        state.backoffUntil = Date().addingTimeInterval(-60)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: quartzDir.appending(path: "ai_index.json"), options: .atomic)

        let service = KnowledgeExtractionService(
            edgeStore: GraphEdgeStore(),
            vaultRootURL: vault,
            scanInterval: .milliseconds(100),
            extractionOverride: { _ in ["retryable"] }
        )

        let snapshot = await service.statusSnapshot()
        #expect(snapshot.status == .retryableIdle)
        #expect(snapshot.backoffUntil == nil)
        #expect(snapshot.pendingNotes == 1)
        let summary = KnowledgeExtractionService.persistedHealthSummary(vaultRootURL: vault)
        #expect(summary["aiIndex.status"] == AIIndexingStatus.retryableIdle.rawValue)
    }

    @Test("plain idle is not reported when pending backlog has no scheduled work")
    func pendingBacklogIdleIsNotPlainIdle() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appending(path: "pending-backlog.md")
        try """
        # Pending backlog

        This note is pending and no scan has been scheduled yet.
        """.write(to: note, atomically: true, encoding: .utf8)

        let service = KnowledgeExtractionService(
            edgeStore: GraphEdgeStore(),
            vaultRootURL: vault,
            scanInterval: .milliseconds(100),
            extractionOverride: { _ in ["pending"] }
        )

        let snapshot = await service.statusSnapshot()
        #expect(snapshot.status == .pendingBacklogIdle)
        #expect(snapshot.pendingNotes == 1)
        let summary = KnowledgeExtractionService.persistedHealthSummary(vaultRootURL: vault)
        #expect(summary["aiIndex.status"] == AIIndexingStatus.pendingBacklogIdle.rawValue)
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
