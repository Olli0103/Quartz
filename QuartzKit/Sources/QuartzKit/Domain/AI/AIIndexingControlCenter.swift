import Foundation

@MainActor
@Observable
public final class AIIndexingControlCenter {
    public static let shared = AIIndexingControlCenter()

    public private(set) var service: KnowledgeExtractionService?
    public private(set) var status: AIIndexingStatus = .idle
    public private(set) var conceptCount: Int = 0
    public private(set) var processedNotes: Int = 0
    public private(set) var pendingNotes: Int = 0
    public private(set) var currentBatchProcessed: Int = 0
    public private(set) var currentBatchTarget: Int = 0
    public private(set) var continuationScheduled: Bool = false
    public private(set) var continuationScheduledAt: Date?
    public private(set) var continuationStartedAt: Date?
    public private(set) var lastProcessedNoteAt: Date?
    public private(set) var notesPerMinute: Double = 0
    public private(set) var lastSuccessAt: Date?
    public private(set) var lastFailureAt: Date?
    public private(set) var lastFailureReason: String?
    public private(set) var backoffUntil: Date?
    public private(set) var scanMode: AIConceptScanMode = .automatic

    private init() {}

    public func register(service: KnowledgeExtractionService?) {
        self.service = service
        Task { await refresh() }
    }

    public func refresh() async {
        guard let service else {
            status = KnowledgeAnalysisSettings.aiConceptExtractionEnabled() ? .idle : .disabled
            return
        }
        let snapshot = await service.statusSnapshot()
        status = snapshot.status
        conceptCount = snapshot.conceptCount
        processedNotes = snapshot.processedNotes
        pendingNotes = snapshot.pendingNotes
        currentBatchProcessed = snapshot.currentBatchProcessed
        currentBatchTarget = snapshot.currentBatchTarget
        continuationScheduled = snapshot.continuationScheduled
        continuationScheduledAt = snapshot.continuationScheduledAt
        continuationStartedAt = snapshot.continuationStartedAt
        lastProcessedNoteAt = snapshot.lastProcessedNoteAt
        notesPerMinute = snapshot.notesPerMinute
        lastSuccessAt = snapshot.lastSuccessAt
        lastFailureAt = snapshot.lastFailureAt
        lastFailureReason = snapshot.lastFailureReason
        backoffUntil = snapshot.backoffUntil
        scanMode = snapshot.scanMode
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.statusVisibleInSettings",
            reasonCode: "ai.statusVisibleInSettings",
            counts: [
                "conceptCount": conceptCount,
                "processedNotes": processedNotes,
                "pendingNotes": pendingNotes,
                "aiIndex.currentBatchProcessed": currentBatchProcessed,
                "aiIndex.currentBatchTarget": currentBatchTarget
            ],
            metadata: [
                "status.aiIndexing": status.rawValue,
                "scanMode": scanMode.rawValue,
                "aiIndex.uiStatus": status.rawValue,
                "aiIndex.backendStatus": snapshot.status.rawValue,
                "aiIndex.continuationScheduled": String(continuationScheduled),
                "aiIndex.notesPerMinute": String(format: "%.2f", notesPerMinute)
            ]
        )
        SubsystemDiagnostics.updateState(subsystem: .aiIndexing, values: [
            "aiIndex.uiStatus": status.rawValue,
            "aiIndex.backendStatus": snapshot.status.rawValue,
            "aiIndex.pendingNotes": "\(pendingNotes)",
            "aiIndex.currentBatchProcessed": "\(currentBatchProcessed)",
            "aiIndex.currentBatchTarget": "\(currentBatchTarget)",
            "aiIndex.continuationScheduled": String(continuationScheduled),
            "aiIndex.continuationScheduledAt": continuationScheduledAt.map(Self.iso8601String) ?? "none",
            "aiIndex.continuationStartedAt": continuationStartedAt.map(Self.iso8601String) ?? "none",
            "aiIndex.lastProcessedNoteAt": lastProcessedNoteAt.map(Self.iso8601String) ?? "none",
            "aiIndex.notesPerMinute": String(format: "%.2f", notesPerMinute)
        ])
    }

    public func startOrResume() {
        SubsystemDiagnostics.record(level: .info, subsystem: .aiIndexing, name: "ai.userStartRequested", reasonCode: "ai.userStartRequested")
        Task {
            await service?.startVaultScan(mode: .automatic)
            await refresh()
        }
    }

    public func pause() {
        SubsystemDiagnostics.record(level: .info, subsystem: .aiIndexing, name: "ai.userPauseRequested", reasonCode: "ai.userPauseRequested")
        Task {
            await service?.pauseAIIndexing()
            await refresh()
        }
    }

    public func retryNow() {
        SubsystemDiagnostics.record(level: .info, subsystem: .aiIndexing, name: "ai.userRetryRequested", reasonCode: "ai.userRetryRequested")
        Task {
            await service?.retryAIIndexingNow()
            await refresh()
        }
    }

    public func rebuild() {
        SubsystemDiagnostics.record(level: .info, subsystem: .aiIndexing, name: "ai.userRebuildRequested", reasonCode: "ai.userRebuildRequested")
        Task {
            await service?.startManualRebuildScan()
            await refresh()
        }
    }

    public func resetFailure() {
        SubsystemDiagnostics.record(level: .info, subsystem: .aiIndexing, name: "ai.userResetFailureRequested", reasonCode: "ai.userResetFailureRequested")
        Task {
            await service?.resetFailureState()
            await refresh()
        }
    }

    public func cancel() {
        SubsystemDiagnostics.record(level: .info, subsystem: .aiIndexing, name: "ai.userCancelRequested", reasonCode: "ai.userCancelRequested")
        Task {
            await service?.cancelCurrentAIJob()
            await refresh()
        }
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
