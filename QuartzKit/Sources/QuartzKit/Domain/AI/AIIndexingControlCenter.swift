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
                "pendingNotes": pendingNotes
            ],
            metadata: ["status.aiIndexing": status.rawValue, "scanMode": scanMode.rawValue]
        )
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
}
