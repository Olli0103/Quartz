import Foundation
import os

// MARK: - AI Index State (Codable Persistence)

/// Persisted AI state — saved to `{vault}/.quartz/ai_index.json`.
/// Uses relative paths as keys so the data is portable across devices and iCloud sync.
public struct AIIndexState: Codable, Sendable {
    /// Map of relative note path → file modification date at last processing time.
    public var processedTimestamps: [String: Date] = [:]

    /// Map of concept string → set of relative note paths that discuss it.
    public var conceptEdges: [String: Set<String>] = [:]

    /// Last known AI indexing health. Persisted so a failing provider does not
    /// look healthy after relaunch.
    public var lastStatus: String?
    public var lastFailureReason: String?
    public var lastFailureAt: Date?
    public var lastSuccessAt: Date?
    public var backoffUntil: Date?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case processedTimestamps
        case conceptEdges
        case lastStatus
        case lastFailureReason
        case lastFailureAt
        case lastSuccessAt
        case backoffUntil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processedTimestamps = try container.decodeIfPresent([String: Date].self, forKey: .processedTimestamps) ?? [:]
        conceptEdges = try container.decodeIfPresent([String: Set<String>].self, forKey: .conceptEdges) ?? [:]
        lastStatus = try container.decodeIfPresent(String.self, forKey: .lastStatus)
        lastFailureReason = try container.decodeIfPresent(String.self, forKey: .lastFailureReason)
        lastFailureAt = try container.decodeIfPresent(Date.self, forKey: .lastFailureAt)
        lastSuccessAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        backoffUntil = try container.decodeIfPresent(Date.self, forKey: .backoffUntil)
    }
}

public enum AIIndexingStatus: String, Sendable {
    case idle
    case running
    case paused
    case backoff
    case failedConfig
    case failedConfiguration
    case waitingForNetwork
    case completedWithPending
    case retryableIdle
    case pendingBacklogIdle
    case automaticScanScheduled
    case disabled
    case failed
    case providerSlow
}

public enum AIConceptScanMode: String, Sendable {
    case automatic
    case manualIncremental
    case manualRebuild
}

public struct AIIndexingStatusSnapshot: Sendable, Equatable {
    public let status: AIIndexingStatus
    public let conceptCount: Int
    public let processedNotes: Int
    public let pendingNotes: Int
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let lastFailureReason: String?
    public let backoffUntil: Date?
    public let scanMode: AIConceptScanMode
}

public struct AIIndexingPendingClassification: Sendable, Equatable {
    public let missingConcepts: Int
    public let modifiedNotes: Int
    public let failedRetry: Int
    public let alreadyCurrent: Int
    public let pendingURLs: [URL]

    public var totalPending: Int { pendingURLs.count }
}

// MARK: - Knowledge Extraction Service

/// Background service that extracts high-level concepts from notes using the AI provider.
///
/// Two modes:
/// 1. **On-save**: `scheduleExtraction(for:)` — debounced single-note extraction
/// 2. **Vault scan**: `startVaultScan()` — crawls entire vault with rate limiting
///
/// State is persisted to `{vault}/.quartz/ai_index.json` so the crawler remembers
/// what it has already processed across app launches and device syncs.
///
/// **Per CODEX.md F9:** Routes all AI operations through `AIExecutionPolicy` for
/// consistent circuit breaker, fallback, and health semantics.
public actor KnowledgeExtractionService {
    private let edgeStore: GraphEdgeStore
    private let vaultRootURL: URL
    private let executionPolicy: AIExecutionPolicy?
    private let debounceInterval: Duration
    private let scanInterval: Duration
    private let automaticContinuationCooldown: Duration
    private let automaticMaxPerNoteDurationMs: UInt64
    private let extractionOverride: (@Sendable (String) async -> [String])?
    private let logger = Logger(subsystem: "com.quartz", category: "KnowledgeExtraction")

    // MARK: - Persisted State

    private var state: AIIndexState

    private var stateFileURL: URL {
        vaultRootURL.appending(path: ".quartz").appending(path: "ai_index.json")
    }

    // MARK: - On-Save Debounce

    private var pendingURLs: Set<URL> = []
    private var debounceTask: Task<Void, Never>?
    private var serviceGeneration: UInt64 = 0
    private var requestedRevisionByURL: [URL: UInt64] = [:]
    private var hasRestoredPersistedConceptsForCurrentGeneration = false

    // MARK: - Vault Scan

    private var scanTask: Task<Void, Never>?
    private var scanContinuationTask: Task<Void, Never>?
    private var isScanRunning = false
    public private(set) var scanProgress: ScanProgress?
    private var saveDebouncTask: Task<Void, Never>?
    private var aiBackoffUntil: Date?
    private var aiFailureStatus: String?
    private var lastAIFailureReason: String?
    private var isPausedByUser = false
    private var currentScanMode: AIConceptScanMode = .automatic

    private static let automaticMaxNotesPerScan = 25
    private static let automaticMaxDurationSeconds: UInt64 = 60
    public static let defaultAutomaticMaxPerNoteDurationMs: UInt64 = 12_000
    public static let automaticMaxNotesPerScanForTesting = automaticMaxNotesPerScan

    public struct ScanProgress: Sendable {
        public let current: Int
        public let total: Int
        public let currentNote: String
    }

    private static let systemPrompt = """
    You are an ontology engine for a Second Brain note-taking app. \
    Read the note below and extract the 3-5 most critical underlying concepts. \
    These can be Projects, People, Technologies, or Abstract Ideas. \
    Return ONLY a valid JSON array of strings. Example: ["Project Apollo", "Bhargav", "SwiftUI Architecture"]. \
    Keep each concept concise (1-3 words). Do not include explanations.
    """

    // MARK: - Init

    public init(
        edgeStore: GraphEdgeStore,
        vaultRootURL: URL,
        executionPolicy: AIExecutionPolicy? = nil,
        debounceInterval: Duration = .seconds(5),
        scanInterval: Duration = .seconds(2),
        automaticContinuationCooldown: Duration = .seconds(5),
        automaticMaxPerNoteDurationMs: UInt64 = KnowledgeExtractionService.defaultAutomaticMaxPerNoteDurationMs,
        extractionOverride: (@Sendable (String) async -> [String])? = nil
    ) {
        self.edgeStore = edgeStore
        self.vaultRootURL = vaultRootURL
        self.executionPolicy = executionPolicy
        self.debounceInterval = debounceInterval
        self.scanInterval = scanInterval
        self.automaticContinuationCooldown = automaticContinuationCooldown
        self.automaticMaxPerNoteDurationMs = automaticMaxPerNoteDurationMs
        self.extractionOverride = extractionOverride
        self.state = Self.loadState(from: vaultRootURL)
        self.aiBackoffUntil = state.backoffUntil
        self.aiFailureStatus = state.lastStatus
        self.lastAIFailureReason = state.lastFailureReason
        self.isPausedByUser = state.lastStatus == AIIndexingStatus.paused.rawValue
        Self.publishPersistedAIHealth(state)
    }

    // MARK: - On-Save Extraction

    public func scheduleExtraction(for noteURL: URL) {
        guard isEnabled else {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "extractionSkipped",
                reasonCode: "ai.disabled",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["status.aiIndexing": "disabled"]
            )
            return
        }
        guard !isPausedByUser else {
            updateAIStatus(AIIndexingStatus.paused.rawValue)
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "conceptScanSkipped",
                reasonCode: "ai.paused",
                metadata: ["status.aiIndexing": AIIndexingStatus.paused.rawValue]
            )
            return
        }
        if isAIBackoffActive() {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .aiIndexing,
                name: "extractionSkipped",
                reasonCode: "ai.backoff",
                noteBasename: noteURL.lastPathComponent,
                metadata: [
                    "status.aiIndexing": aiFailureStatus ?? "backoff",
                    "backoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "unknown"
                ]
            )
            return
        }
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        pendingURLs.insert(canonicalURL)
        requestedRevisionByURL[canonicalURL, default: 0] &+= 1
        SubsystemDiagnostics.record(
            level: .debug,
            subsystem: .aiIndexing,
            name: "extractionScheduled",
            reasonCode: "ai.extractionScheduled",
            noteBasename: canonicalURL.lastPathComponent,
            generation: serviceGeneration,
            verbose: true
        )
        debounceTask?.cancel()
        let generation = serviceGeneration
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.runPendingExtractions(expectedGeneration: generation)
        }
    }

    // MARK: - Vault Scan

    public func startVaultScan(mode: AIConceptScanMode = .automatic) {
        guard isEnabled else {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "conceptScanSkipped",
                reasonCode: "ai.disabled",
                metadata: ["status.aiIndexing": "disabled"]
            )
            return
        }
        if isAIBackoffActive() {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .aiIndexing,
                name: "ai.scanPausedBackoff",
                reasonCode: "ai.backoff",
                metadata: [
                    "status.aiIndexing": aiFailureStatus ?? "backoff",
                    "scanMode": mode.rawValue,
                    "backoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "unknown"
                ]
            )
            updateAIStatus(aiFailureStatus ?? AIIndexingStatus.backoff.rawValue)
            return
        }
        guard !isScanRunning else {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "conceptScanSkipped",
                reasonCode: "ai.scanAlreadyRunning",
                metadata: ["status.aiIndexing": "running"]
            )
            return
        }
        scanTask?.cancel()
        currentScanMode = mode
        let generation = serviceGeneration
        let previousStatus = state.lastStatus
        updateAIStatus(AIIndexingStatus.running.rawValue)
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "conceptScanScheduled",
            reasonCode: "ai.scanScheduled",
            generation: generation,
            metadata: [
                "status.aiIndexing": AIIndexingStatus.running.rawValue,
                "scanMode": mode.rawValue
            ]
        )
        if mode == .automatic, previousStatus == AIIndexingStatus.retryableIdle.rawValue {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.automaticScanScheduledAfterBackoff",
                reasonCode: "ai.automaticScanScheduledAfterBackoff",
                generation: generation,
                metadata: [
                    "status.aiIndexing": AIIndexingStatus.automaticScanScheduled.rawValue,
                    "previousStatus.aiIndexing": previousStatus ?? "none"
                ]
            )
        }
        scanTask = Task(priority: .utility) { [weak self] in
            await self?.runVaultScan(expectedGeneration: generation, mode: mode)
        }
    }

    /// Restores persisted AI concept assignments into the live edge store without
    /// starting a new vault scan. Used by KG6 so graph and inspector consumers can
    /// read the same canonical concept state immediately after vault load.
    public func restorePersistedConcepts() async {
        hasRestoredPersistedConceptsForCurrentGeneration = true
        await restoreConceptEdgesFromState(expectedGeneration: serviceGeneration)
    }

    public func stopVaultScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanRunning = false
        scanProgress = nil
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "conceptScanStopped",
            reasonCode: "ai.scanStopped",
            metadata: ["status.aiIndexing": "idle"]
        )
    }

    public func pauseAIIndexing() {
        isPausedByUser = true
        scanTask?.cancel()
        scanContinuationTask?.cancel()
        scanTask = nil
        scanContinuationTask = nil
        isScanRunning = false
        scanProgress = nil
        updateAIStatus(AIIndexingStatus.paused.rawValue)
        saveStateToDisk()
    }

    public func cancelCurrentAIJob() {
        scanTask?.cancel()
        scanContinuationTask?.cancel()
        debounceTask?.cancel()
        scanTask = nil
        scanContinuationTask = nil
        debounceTask = nil
        isScanRunning = false
        scanProgress = nil
        updateAIStatus(isPausedByUser ? AIIndexingStatus.paused.rawValue : AIIndexingStatus.idle.rawValue)
    }

    public func retryAIIndexingNow() {
        isPausedByUser = false
        aiBackoffUntil = nil
        aiFailureStatus = nil
        lastAIFailureReason = nil
        state.backoffUntil = nil
        state.lastStatus = "idle"
        state.lastFailureReason = nil
        saveStateToDisk()
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "retryRequested",
            reasonCode: "ai.retryRequested",
            metadata: ["status.aiIndexing": "idle"]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.retryNowScheduled",
            reasonCode: "ai.retryNowScheduled",
            metadata: ["status.aiIndexing": AIIndexingStatus.automaticScanScheduled.rawValue]
        )
        startVaultScan(mode: .automatic)
    }

    public func startManualRebuildScan() {
        isPausedByUser = false
        startVaultScan(mode: .manualRebuild)
    }

    public func resetFailureState() {
        aiBackoffUntil = nil
        aiFailureStatus = nil
        lastAIFailureReason = nil
        state.backoffUntil = nil
        state.lastFailureReason = nil
        state.lastFailureAt = nil
        state.lastStatus = isPausedByUser ? AIIndexingStatus.paused.rawValue : AIIndexingStatus.idle.rawValue
        saveStateToDisk()
        updateAIStatus(state.lastStatus ?? AIIndexingStatus.idle.rawValue, extra: ["aiBackoffUntil": "none"])
    }

    public func statusSnapshot() -> AIIndexingStatusSnapshot {
        _ = isAIBackoffActive()
        let allNotes = collectMarkdownFiles(in: vaultRootURL)
        let pending = classifyPendingNotes(allNotes, mode: .automatic).totalPending
        var status: AIIndexingStatus
        if !isEnabled {
            status = .disabled
        } else if isPausedByUser {
            status = .paused
        } else if let raw = state.lastStatus, let parsed = AIIndexingStatus(rawValue: raw) {
            status = parsed
        } else {
            status = isScanRunning ? .running : .idle
        }
        if status == .idle, pending > 0, !isScanRunning, !isPausedByUser, isEnabled {
            status = .pendingBacklogIdle
            publishPendingBacklogIdle(pendingNotes: pending, reason: "noAutomaticScanScheduled")
        }
        return AIIndexingStatusSnapshot(
            status: status,
            conceptCount: state.conceptEdges.count,
            processedNotes: state.processedTimestamps.count,
            pendingNotes: pending,
            lastSuccessAt: state.lastSuccessAt,
            lastFailureAt: state.lastFailureAt,
            lastFailureReason: state.lastFailureReason ?? lastAIFailureReason,
            backoffUntil: aiBackoffUntil,
            scanMode: currentScanMode
        )
    }

    /// Cancels queued save/scan work and invalidates suspended older extractions so they
    /// cannot overwrite newer concept state after a vault switch or relaunch.
    public func invalidateBackgroundWork() {
        serviceGeneration &+= 1
        pendingURLs.removeAll(keepingCapacity: false)
        debounceTask?.cancel()
        debounceTask = nil
        scanTask?.cancel()
        scanTask = nil
        saveDebouncTask?.cancel()
        saveDebouncTask = nil
        isScanRunning = false
        scanProgress = nil
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "backgroundWorkInvalidated",
            reasonCode: "ai.vaultSwitchCancellation",
            generation: serviceGeneration,
            metadata: ["status.aiIndexing": "idle"]
        )
        hasRestoredPersistedConceptsForCurrentGeneration = false
    }

    public func handleNoteDeletion(at noteURL: URL) async {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        pendingURLs.remove(canonicalURL)
        requestedRevisionByURL[canonicalURL, default: 0] &+= 1

        let relPath = relativePath(for: canonicalURL)
        state.processedTimestamps.removeValue(forKey: relPath)
        for (concept, var paths) in state.conceptEdges {
            if paths.remove(relPath) != nil {
                state.conceptEdges[concept] = paths.isEmpty ? nil : paths
            }
        }

        await edgeStore.removeConcepts(for: canonicalURL)
        saveStateToDisk()

        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzConceptsUpdated,
                object: canonicalURL,
                userInfo: ["vaultRootURL": notificationVaultRootURL]
            )
        }
    }

    public func handleNoteRelocation(from oldURL: URL, to newURL: URL) async {
        let canonicalOldURL = CanonicalNoteIdentity.canonicalFileURL(for: oldURL)
        let canonicalNewURL = CanonicalNoteIdentity.canonicalFileURL(for: newURL)

        pendingURLs.remove(canonicalOldURL)
        requestedRevisionByURL[canonicalOldURL, default: 0] &+= 1

        let oldRelPath = relativePath(for: canonicalOldURL)
        let newRelPath = relativePath(for: canonicalNewURL)
        guard oldRelPath != newRelPath else { return }

        let existingConcepts = await edgeStore.concepts(for: canonicalOldURL)
        let persistedConcepts = state.conceptEdges.compactMap { concept, paths in
            paths.contains(oldRelPath) ? concept : nil
        }
        let conceptsToMove = Array(Set(existingConcepts + persistedConcepts)).sorted()

        if let oldTimestamp = state.processedTimestamps.removeValue(forKey: oldRelPath) {
            state.processedTimestamps[newRelPath] = fileModificationDate(for: canonicalNewURL) ?? oldTimestamp
        }

        for (concept, var paths) in state.conceptEdges {
            guard paths.remove(oldRelPath) != nil else { continue }
            if conceptsToMove.contains(concept) {
                paths.insert(newRelPath)
            }
            state.conceptEdges[concept] = paths.isEmpty ? nil : paths
        }

        if !conceptsToMove.isEmpty {
            await edgeStore.removeConcepts(for: canonicalOldURL)
            await edgeStore.updateConcepts(for: canonicalNewURL, concepts: conceptsToMove)
        } else {
            await edgeStore.removeConcepts(for: canonicalOldURL)
        }

        saveStateToDisk()

        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzConceptsUpdated,
                object: canonicalNewURL,
                userInfo: ["vaultRootURL": notificationVaultRootURL]
            )
        }
    }

    private func runPendingExtractions(expectedGeneration: UInt64) async {
        guard serviceGeneration == expectedGeneration else { return }

        let urls = pendingURLs.sorted(by: { $0.absoluteString < $1.absoluteString })
        pendingURLs.removeAll(keepingCapacity: true)

        for noteURL in urls {
            guard serviceGeneration == expectedGeneration else { break }
            guard !isAIBackoffActive() else { break }
            let revision = currentRevision(for: noteURL)
            _ = await extractConcepts(
                for: noteURL,
                expectedGeneration: expectedGeneration,
                expectedRevision: revision
            )
        }

        guard serviceGeneration == expectedGeneration else { return }
        scheduleSave()
    }

    private func runVaultScan(expectedGeneration: UInt64, mode: AIConceptScanMode) async {
        guard serviceGeneration == expectedGeneration else { return }
        let scanStart = DispatchTime.now().uptimeNanoseconds
        let deadline = scanStart + Self.automaticMaxDurationSeconds * 1_000_000_000
        isScanRunning = true
        updateAIStatus(AIIndexingStatus.running.rawValue)
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "conceptScanStarted",
            reasonCode: "ai.scanStarted",
            generation: expectedGeneration,
            metadata: [
                "status.aiIndexing": AIIndexingStatus.running.rawValue,
                "scanMode": mode.rawValue
            ]
        )
        defer {
            if serviceGeneration == expectedGeneration {
                isScanRunning = false
                scanProgress = nil
            }
        }

        // Restore concepts from persisted state into the live edge store once per generation.
        if !hasRestoredPersistedConceptsForCurrentGeneration {
            hasRestoredPersistedConceptsForCurrentGeneration = true
            await restoreConceptEdgesFromState(expectedGeneration: expectedGeneration)
        }

        guard serviceGeneration == expectedGeneration else { return }

        let noteURLs = collectMarkdownFiles(in: vaultRootURL)
        guard !noteURLs.isEmpty else {
            updateAIStatus(AIIndexingStatus.idle.rawValue)
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.scanCompletedFull",
                reasonCode: "ai.scanNoNotes",
                counts: ["totalNotes": 0],
                generation: expectedGeneration,
                metadata: ["status.aiIndexing": "idle"]
            )
            return
        }

        let classification = classifyPendingNotes(noteURLs, mode: mode)
        let unprocessed = classification.pendingURLs
        recordPendingClassification(classification, totalNotes: noteURLs.count, generation: expectedGeneration, mode: mode)

        guard !unprocessed.isEmpty else {
            logger.info("Vault scan: all \(noteURLs.count) notes already indexed")
            updateAIStatus(AIIndexingStatus.idle.rawValue)
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.scanCompletedFull",
                reasonCode: "ai.scanNoPendingNotes",
                counts: ["totalNotes": noteURLs.count, "pendingNotes": 0],
                generation: expectedGeneration,
                metadata: ["status.aiIndexing": "idle"]
            )
            return
        }

        logger.info("Vault scan: \(unprocessed.count)/\(noteURLs.count) need processing")
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "conceptScanPending",
            reasonCode: "ai.scanPending",
            counts: ["pendingNotes": unprocessed.count, "totalNotes": noteURLs.count],
            generation: expectedGeneration,
            metadata: [
                "status.aiIndexing": AIIndexingStatus.running.rawValue,
                "scanMode": mode.rawValue
            ]
        )

        let budgetedURLs: [URL]
        if mode == .automatic, unprocessed.count > Self.automaticMaxNotesPerScan {
            budgetedURLs = Array(unprocessed.prefix(Self.automaticMaxNotesPerScan))
        } else {
            budgetedURLs = unprocessed
        }

        var processedCount = 0
        var pausedForBackoff = false
        var pausedForProviderSlow = false
        var budgetReached = false
        var stoppedReason = "none"

        for (index, noteURL) in budgetedURLs.enumerated() {
            guard !Task.isCancelled, serviceGeneration == expectedGeneration else { break }
            if mode == .automatic, DispatchTime.now().uptimeNanoseconds >= deadline {
                budgetReached = true
                break
            }

            scanProgress = ScanProgress(
                current: index + 1,
                total: min(unprocessed.count, budgetedURLs.count),
                currentNote: noteURL.deletingPathExtension().lastPathComponent
            )

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .quartzConceptScanProgress,
                    object: nil,
                    userInfo: ["current": index + 1, "total": min(unprocessed.count, budgetedURLs.count),
                               "note": noteURL.deletingPathExtension().lastPathComponent]
                )
            }

            let revision = currentRevision(for: noteURL)
            let outcome = await extractConcepts(
                for: noteURL,
                expectedGeneration: expectedGeneration,
                expectedRevision: revision,
                automaticTimeoutMs: mode == .automatic ? automaticMaxPerNoteDurationMs : nil
            )
            if outcome == .processed {
                processedCount += 1
            }

            if outcome == .providerSlow {
                pausedForProviderSlow = true
                stoppedReason = "providerSlow"
                updateAIStatus(AIIndexingStatus.providerSlow.rawValue)
                let remaining = max(0, unprocessed.count - processedCount)
                SubsystemDiagnostics.record(
                    level: .warning,
                    subsystem: .aiIndexing,
                    name: "ai.scanPausedProviderSlow",
                    reasonCode: "ai.scanPausedProviderSlow",
                    durationMs: Double((DispatchTime.now().uptimeNanoseconds - scanStart) / 1_000_000),
                    counts: ["processedNotes": processedCount, "pendingNotes": remaining, "totalNotes": noteURLs.count],
                    generation: expectedGeneration,
                    metadata: [
                        "status.aiIndexing": AIIndexingStatus.providerSlow.rawValue,
                        "scanMode": mode.rawValue,
                        "ai.automaticScanStoppedReason": stoppedReason,
                        "ai.maxPerNoteDurationMs": String(automaticMaxPerNoteDurationMs)
                    ]
                )
                break
            }

            if isAIBackoffActive() {
                pausedForBackoff = true
                stoppedReason = "backoff"
                updateAIStatus(aiFailureStatus ?? AIIndexingStatus.backoff.rawValue)
                SubsystemDiagnostics.record(
                    level: .warning,
                    subsystem: .aiIndexing,
                    name: "ai.scanPausedBackoff",
                    reasonCode: "ai.backoff",
                    counts: ["processedNotes": processedCount, "pendingNotes": max(0, unprocessed.count - processedCount)],
                    generation: expectedGeneration,
                    metadata: [
                        "status.aiIndexing": aiFailureStatus ?? "backoff",
                        "scanMode": mode.rawValue,
                        "ai.automaticScanStoppedReason": stoppedReason,
                        "backoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "unknown"
                    ]
                )
                SubsystemDiagnostics.record(
                    level: .warning,
                    subsystem: .aiIndexing,
                    name: "conceptScanPaused",
                    reasonCode: "ai.backoff",
                    counts: ["processedNotes": processedCount, "pendingNotes": max(0, unprocessed.count - processedCount)],
                    generation: expectedGeneration,
                    metadata: [
                        "status.aiIndexing": aiFailureStatus ?? "backoff",
                        "ai.automaticScanStoppedReason": stoppedReason
                    ]
                )
                break
            }

            // Save state every 5 notes (resilient to crashes mid-scan)
            if serviceGeneration == expectedGeneration, (index + 1) % 5 == 0 {
                saveStateToDisk()
            }

            if serviceGeneration == expectedGeneration, index < unprocessed.count - 1 {
                try? await Task.sleep(for: scanInterval)
            }
        }

        guard serviceGeneration == expectedGeneration else { return }
        saveStateToDisk()
        let elapsedMilliseconds = (DispatchTime.now().uptimeNanoseconds - scanStart) / 1_000_000
        guard !pausedForBackoff, !pausedForProviderSlow else { return }

        if mode == .automatic, processedCount < unprocessed.count {
            budgetReached = true
            if stoppedReason == "none" {
                stoppedReason = processedCount >= Self.automaticMaxNotesPerScan ? "maxNotes" : "maxDuration"
            }
        }

        if budgetReached {
            updateAIStatus(AIIndexingStatus.completedWithPending.rawValue)
            let remaining = max(0, unprocessed.count - processedCount)
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.batchBudgetExhausted",
                reasonCode: "ai.batchBudgetExhausted",
                durationMs: Double(elapsedMilliseconds),
                counts: [
                    "processedNotes": processedCount,
                    "pendingNotes": remaining,
                    "maxNotesPerAutomaticScan": Self.automaticMaxNotesPerScan
                ],
                generation: expectedGeneration,
                metadata: ["scanMode": mode.rawValue]
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.batchProgress",
                reasonCode: "ai.batchProgress",
                counts: ["processedNotes": processedCount, "pendingNotes": remaining],
                generation: expectedGeneration,
                metadata: ["scanMode": mode.rawValue]
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.scanBudgetReached",
                reasonCode: "ai.scanBudgetReached",
                durationMs: Double(elapsedMilliseconds),
                counts: [
                    "processedNotes": processedCount,
                    "pendingNotes": remaining,
                    "totalNotes": noteURLs.count,
                    "maxNotesPerAutomaticScan": Self.automaticMaxNotesPerScan
                ],
                generation: expectedGeneration,
                metadata: [
                    "status.aiIndexing": AIIndexingStatus.completedWithPending.rawValue,
                    "scanMode": mode.rawValue,
                    "ai.automaticScanStoppedReason": stoppedReason,
                    "ai.maxPerNoteDurationMs": String(automaticMaxPerNoteDurationMs)
                ]
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.scanCompletedPartial",
                reasonCode: "ai.scanCompletedPartial",
                durationMs: Double(elapsedMilliseconds),
                counts: ["processedNotes": processedCount, "pendingNotes": remaining, "totalNotes": noteURLs.count],
                generation: expectedGeneration,
                metadata: [
                    "status.aiIndexing": AIIndexingStatus.completedWithPending.rawValue,
                    "ai.automaticScanStoppedReason": stoppedReason
                ]
            )
            if mode == .automatic, remaining > 0, !isPausedByUser, !isAIBackoffActive() {
                scheduleAutomaticContinuation(
                    pendingNotes: remaining,
                    generation: expectedGeneration,
                    stoppedReason: stoppedReason
                )
            } else {
                SubsystemDiagnostics.record(
                    level: .info,
                    subsystem: .aiIndexing,
                    name: "ai.scanContinuationSkippedReason",
                    reasonCode: "ai.scanContinuationSkippedReason",
                    counts: ["pendingNotes": remaining],
                    generation: expectedGeneration,
                    metadata: [
                        "scanMode": mode.rawValue,
                        "paused": String(isPausedByUser),
                        "backoffActive": String(isAIBackoffActive())
                    ]
                )
            }
        } else {
            updateAIStatus(AIIndexingStatus.idle.rawValue)
            logger.info("Vault scan complete: processed \(processedCount) notes in \(elapsedMilliseconds) ms")
            QuartzDiagnostics.info(
                category: "KnowledgeExtraction",
                "Vault scan complete: processed \(processedCount) notes in \(elapsedMilliseconds) ms"
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.scanCompletedFull",
                reasonCode: "ai.scanCompletedFull",
                durationMs: Double(elapsedMilliseconds),
                counts: ["processedNotes": processedCount, "totalNotes": noteURLs.count],
                generation: expectedGeneration,
                metadata: ["status.aiIndexing": AIIndexingStatus.idle.rawValue]
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "conceptScanCompleted",
                reasonCode: "ai.scanCompleted",
                durationMs: Double(elapsedMilliseconds),
                counts: ["processedNotes": processedCount, "totalNotes": noteURLs.count],
                generation: expectedGeneration,
                metadata: ["status.aiIndexing": AIIndexingStatus.idle.rawValue]
            )
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .quartzConceptScanProgress, object: nil)
        }
    }

    private func scheduleAutomaticContinuation(
        pendingNotes: Int,
        generation: UInt64,
        stoppedReason: String
    ) {
        scanContinuationTask?.cancel()
        let cooldown = automaticContinuationCooldown
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.completedWithPendingAwaitingContinuation",
            reasonCode: "ai.completedWithPendingAwaitingContinuation",
            counts: ["pendingNotes": pendingNotes],
            generation: generation,
            metadata: [
                "status.aiIndexing": AIIndexingStatus.completedWithPending.rawValue,
                "ai.automaticScanStoppedReason": stoppedReason
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.scanContinuationScheduled",
            reasonCode: "ai.scanContinuationScheduled",
            counts: ["pendingNotes": pendingNotes],
            generation: generation,
            metadata: [
                "cooldown": String(describing: cooldown),
                "status.aiIndexing": AIIndexingStatus.completedWithPending.rawValue
            ]
        )
        scanContinuationTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: cooldown)
            guard !Task.isCancelled else { return }
            await self?.startContinuationIfStillPending(expectedGeneration: generation)
        }
    }

    private func startContinuationIfStillPending(expectedGeneration: UInt64) {
        guard serviceGeneration == expectedGeneration else {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.scanContinuationSkippedReason",
                reasonCode: "ai.scanContinuationSkippedReason",
                generation: expectedGeneration,
                metadata: ["reason": "generationChanged"]
            )
            return
        }
        guard !isPausedByUser else {
            recordContinuationSkipped(reason: "paused", generation: expectedGeneration)
            return
        }
        guard !isScanRunning else {
            recordContinuationSkipped(reason: "scanAlreadyRunning", generation: expectedGeneration)
            return
        }
        guard !isAIBackoffActive() else {
            recordContinuationSkipped(reason: "backoffActive", generation: expectedGeneration)
            return
        }
        let classification = classifyPendingNotes(collectMarkdownFiles(in: vaultRootURL), mode: .automatic)
        let pendingNotes = classification.pendingURLs.count
        guard pendingNotes > 0 else {
            recordContinuationSkipped(reason: "noPendingNotes", generation: expectedGeneration)
            return
        }
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.scanContinuationStarted",
            reasonCode: "ai.scanContinuationStarted",
            counts: ["pendingNotes": pendingNotes],
            generation: expectedGeneration,
            metadata: ["scanMode": AIConceptScanMode.automatic.rawValue]
        )
        startVaultScan(mode: .automatic)
    }

    private func recordContinuationSkipped(reason: String, generation: UInt64) {
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.scanContinuationSkippedReason",
            reasonCode: "ai.scanContinuationSkippedReason",
            generation: generation,
            metadata: ["reason": reason]
        )
    }

    // MARK: - Core Extraction

    private enum ExtractionOutcome: Sendable {
        case processed
        case skipped
        case providerSlow
    }

    private struct AIExtractionTimeoutError: Error {}

    private func extractConcepts(
        for noteURL: URL,
        expectedGeneration: UInt64? = nil,
        expectedRevision: UInt64? = nil,
        automaticTimeoutMs: UInt64? = nil
    ) async -> ExtractionOutcome {
        let canonicalNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        guard generationAndRevisionAreCurrent(
            for: canonicalNoteURL,
            expectedGeneration: expectedGeneration,
            expectedRevision: expectedRevision
        ) else { return .skipped }

        let content: String
        // CRITICAL: Use coordinated read to prevent race with iCloud sync
        do {
            content = try CoordinatedFileWriter.shared.readString(from: canonicalNoteURL)
        } catch {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .aiIndexing,
                name: "extractionFailed",
                reasonCode: "ai.failedRead",
                noteBasename: canonicalNoteURL.lastPathComponent,
                metadata: ["error": error.localizedDescription]
            )
            return .skipped
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 50 else {
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: [],
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return .processed
        }

        let inputText = String(trimmed.prefix(3000))

        if let extractionOverride {
            let concepts: [String]
            do {
                concepts = try await runAutomaticExtractionWithTimeoutIfNeeded(
                    timeoutMs: automaticTimeoutMs,
                    noteURL: canonicalNoteURL
                ) {
                    await extractionOverride(inputText)
                }
            } catch is AIExtractionTimeoutError {
                registerProviderSlow(noteURL: canonicalNoteURL, timeoutMs: automaticTimeoutMs ?? 0)
                return .providerSlow
            } catch {
                return .skipped
            }
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: concepts,
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return .processed
        }

        // Per CODEX.md F9: Route through AIExecutionPolicy for consistent circuit breaker/fallback
        if let policy = executionPolicy {
            let concepts: [String]
            do {
                concepts = try await runAutomaticExtractionWithTimeoutIfNeeded(
                    timeoutMs: automaticTimeoutMs,
                    noteURL: canonicalNoteURL
                ) {
                    await policy.extractConcepts(
                        from: inputText,
                        model: nil,
                        systemPrompt: Self.systemPrompt
                    )
                }
            } catch is AIExtractionTimeoutError {
                registerProviderSlow(noteURL: canonicalNoteURL, timeoutMs: automaticTimeoutMs ?? 0)
                return .providerSlow
            } catch {
                return .skipped
            }
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: concepts,
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return .processed
        }

        // Legacy path: direct provider access (for backward compatibility)
        let registry = await AIProviderRegistry.shared
        guard let provider = await registry.selectedProvider, provider.isConfigured else { return .skipped }
        let modelID = await registry.selectedModelID

        do {
            let response = try await runAutomaticExtractionWithTimeoutIfNeeded(
                timeoutMs: automaticTimeoutMs,
                noteURL: canonicalNoteURL
            ) {
                try await provider.chat(
                    messages: [
                        AIMessage(role: .system, content: Self.systemPrompt),
                        AIMessage(role: .user, content: inputText)
                    ],
                    model: modelID,
                    temperature: 0.3
                )
            }

            let concepts = parseConcepts(from: response.content)
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: concepts,
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return .processed
        } catch is AIExtractionTimeoutError {
            registerProviderSlow(noteURL: canonicalNoteURL, timeoutMs: automaticTimeoutMs ?? 0)
            return .providerSlow
        } catch {
            logger.warning("Extraction failed: \(error.localizedDescription)")
            QuartzDiagnostics.warning(
                category: "KnowledgeExtraction",
                "Extraction failed: \(error.localizedDescription)"
            )
            let reasonCode = Self.aiFailureReasonCode(for: error)
            registerAIFailure(reasonCode: reasonCode)
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .aiIndexing,
                name: "extractionFailed",
                reasonCode: reasonCode,
                noteBasename: canonicalNoteURL.lastPathComponent,
                metadata: [
                    "error": error.localizedDescription,
                    "status.aiIndexing": aiFailureStatus ?? "failed",
                    "backoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "none"
                ]
            )
            return .skipped
        }
    }

    private func runAutomaticExtractionWithTimeoutIfNeeded<T: Sendable>(
        timeoutMs: UInt64?,
        noteURL: URL,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let timeoutMs else {
            return try await operation()
        }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
                throw AIExtractionTimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func commitConceptUpdate(
        for noteURL: URL,
        concepts: [String],
        expectedGeneration: UInt64?,
        expectedRevision: UInt64?
    ) async {
        guard generationAndRevisionAreCurrent(
            for: noteURL,
            expectedGeneration: expectedGeneration,
            expectedRevision: expectedRevision
        ) else { return }

        await updateConceptsAndState(for: noteURL, concepts: concepts)
        state.lastSuccessAt = Date()
        if !isAIBackoffActive() {
            state.lastFailureReason = nil
            state.backoffUntil = nil
        }

        if !concepts.isEmpty {
            logger.info("[\(noteURL.lastPathComponent)] \(concepts.joined(separator: ", "))")
        }

        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzConceptsUpdated,
                object: noteURL,
                userInfo: ["vaultRootURL": notificationVaultRootURL]
            )
        }
    }

    /// Updates both the live edge store AND the persisted state atomically.
    private func updateConceptsAndState(for noteURL: URL, concepts: [String]) async {
        let relPath = relativePath(for: noteURL)

        // Update live edge store
        await edgeStore.updateConcepts(for: noteURL, concepts: concepts)

        // Update persisted state — clean old associations, add new
        for (concept, var paths) in state.conceptEdges {
            if paths.remove(relPath) != nil {
                state.conceptEdges[concept] = paths.isEmpty ? nil : paths
            }
        }
        for concept in concepts {
            state.conceptEdges[concept, default: []].insert(relPath)
        }

        state.processedTimestamps[relPath] = fileModificationDate(for: noteURL) ?? Date()
    }

    /// Restores concept edges from the persisted JSON into the live GraphEdgeStore.
    /// Called once at the start of each vault scan.
    private func restoreConceptEdgesFromState(expectedGeneration: UInt64) async {
        guard serviceGeneration == expectedGeneration, !state.conceptEdges.isEmpty else { return }
        let fm = FileManager.default
        logger.info("Restoring \(self.state.conceptEdges.count) concepts from ai_index.json")

        // Build a batch: for each note, collect all its concepts
        var noteConcepts: [URL: [String]] = [:]
        for (concept, relPaths) in state.conceptEdges {
            for relPath in relPaths {
                let noteURL = vaultRootURL.appending(path: relPath)
                guard fm.fileExists(atPath: noteURL.path(percentEncoded: false)) else { continue }
                noteConcepts[noteURL, default: []].append(concept)
            }
        }

        guard serviceGeneration == expectedGeneration else { return }

        // Batch-replace the live store so startup restore order is deterministic.
        await edgeStore.replaceConceptState(with: noteConcepts)

        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzConceptsUpdated,
                object: nil,
                userInfo: ["vaultRootURL": notificationVaultRootURL]
            )
        }
    }

    // MARK: - JSON Parsing

    private func parseConcepts(from response: String) -> [String] {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let s = text.firstIndex(of: "["), let e = text.lastIndex(of: "]") else { return [] }
        guard let data = String(text[s...e]).data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 50 }
            .map { $0.lowercased() }
            .uniqued().sorted()
    }

    // MARK: - File Helpers

    private func collectMarkdownFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var urls: [URL] = []
        for case let url as URL in e where url.pathExtension == "md" { urls.append(url) }
        return urls
    }

    public func classifyPendingNotesForTesting(_ noteURLs: [URL], mode: AIConceptScanMode = .automatic) -> AIIndexingPendingClassification {
        classifyPendingNotes(noteURLs, mode: mode)
    }

    private func classifyPendingNotes(_ noteURLs: [URL], mode: AIConceptScanMode) -> AIIndexingPendingClassification {
        let sortedURLs = noteURLs.sorted { $0.absoluteString < $1.absoluteString }
        guard mode != .manualRebuild else {
            return AIIndexingPendingClassification(
                missingConcepts: sortedURLs.count,
                modifiedNotes: 0,
                failedRetry: 0,
                alreadyCurrent: 0,
                pendingURLs: sortedURLs
            )
        }

        var missing: [URL] = []
        var modified: [URL] = []
        var alreadyCurrent = 0

        for url in sortedURLs {
            let relPath = relativePath(for: url)
            guard let lastProcessed = state.processedTimestamps[relPath] else {
                missing.append(url)
                continue
            }
            guard let mtime = fileModificationDate(for: url) else {
                modified.append(url)
                continue
            }
            if mtime > lastProcessed {
                modified.append(url)
            } else {
                alreadyCurrent += 1
            }
        }

        return AIIndexingPendingClassification(
            missingConcepts: missing.count,
            modifiedNotes: modified.count,
            failedRetry: 0,
            alreadyCurrent: alreadyCurrent,
            pendingURLs: missing + modified
        )
    }

    private func recordPendingClassification(
        _ classification: AIIndexingPendingClassification,
        totalNotes: Int,
        generation: UInt64,
        mode: AIConceptScanMode
    ) {
        let status = classification.totalPending > 0 ? AIIndexingStatus.running.rawValue : AIIndexingStatus.idle.rawValue
        let counts = [
            "pendingNotes": classification.totalPending,
            "totalNotes": totalNotes
        ]
        let metadata = [
            "status.aiIndexing": status,
            "scanMode": mode.rawValue
        ]
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.pendingMissingConcepts",
            reasonCode: "ai.pendingMissingConcepts",
            counts: counts.merging(["missingConcepts": classification.missingConcepts]) { _, new in new },
            generation: generation,
            metadata: metadata
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.pendingModifiedNotes",
            reasonCode: "ai.pendingModifiedNotes",
            counts: counts.merging(["modifiedNotes": classification.modifiedNotes]) { _, new in new },
            generation: generation,
            metadata: metadata
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.pendingFailedRetry",
            reasonCode: "ai.pendingFailedRetry",
            counts: counts.merging(["failedRetry": classification.failedRetry]) { _, new in new },
            generation: generation,
            metadata: metadata
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.skippedAlreadyCurrent",
            reasonCode: "ai.skippedAlreadyCurrent",
            counts: counts.merging(["alreadyCurrent": classification.alreadyCurrent]) { _, new in new },
            generation: generation,
            metadata: metadata
        )
    }

    private func relativePath(for url: URL) -> String {
        let root = vaultRootURL.standardizedFileURL.path(percentEncoded: false)
        let file = url.standardizedFileURL.path(percentEncoded: false)
        guard file.hasPrefix(root) else { return url.lastPathComponent }
        return String(file.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func fileModificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - Disk Persistence

    /// Loads state from `{vault}/.quartz/ai_index.json`.
    private nonisolated static func loadState(from vaultRoot: URL) -> AIIndexState {
        let url = vaultRoot.appending(path: ".quartz").appending(path: "ai_index.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url) else { return AIIndexState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AIIndexState.self, from: data)) ?? AIIndexState()
    }

    /// Writes state to disk atomically.
    private func saveStateToDisk() {
        let url = stateFileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to persist AI concept index: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "KnowledgeExtraction",
                "Failed to persist AI concept index: \(error.localizedDescription)"
            )
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .aiIndexing,
                name: "conceptIndexSaveFailed",
                reasonCode: "ai.conceptIndexFailed",
                metadata: ["error": error.localizedDescription, "indexPath": url.path(percentEncoded: false)]
            )
        }
    }

    private static func aiFailureReasonCode(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("404") { return "ai.http404" }
        if message.contains("timed out") || message.contains("timeout") { return "ai.timeout" }
        if message.contains("network") || message.contains("offline") { return "ai.networkLost" }
        if message.contains("backoff") { return "ai.backoff" }
        return "ai.extractionFailed"
    }

    private func registerAIFailure(reasonCode: String) {
        let backoffSeconds: TimeInterval
        switch reasonCode {
        case "ai.http404":
            aiFailureStatus = "failedConfiguration"
            backoffSeconds = 60 * 60
        case "ai.timeout", "ai.networkLost", "ai.backoff":
            aiFailureStatus = "backoff"
            backoffSeconds = 5 * 60
        default:
            aiFailureStatus = "failed"
            backoffSeconds = 60
        }
        aiBackoffUntil = Date().addingTimeInterval(backoffSeconds)
        lastAIFailureReason = reasonCode
        state.lastStatus = aiFailureStatus
        state.lastFailureReason = reasonCode
        state.lastFailureAt = Date()
        state.backoffUntil = aiBackoffUntil
        saveStateToDisk()
        updateAIStatus(aiFailureStatus ?? "failed", extra: [
            "lastAIFailureReason": reasonCode,
            "aiBackoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "unknown"
        ])
    }

    private func registerProviderSlow(noteURL: URL, timeoutMs: UInt64) {
        let backoffSeconds: TimeInterval = 5 * 60
        aiFailureStatus = AIIndexingStatus.providerSlow.rawValue
        aiBackoffUntil = Date().addingTimeInterval(backoffSeconds)
        lastAIFailureReason = "ai.providerSlow"
        state.lastStatus = aiFailureStatus
        state.lastFailureReason = "ai.providerSlow"
        state.lastFailureAt = Date()
        state.backoffUntil = aiBackoffUntil
        saveStateToDisk()
        updateAIStatus(AIIndexingStatus.providerSlow.rawValue, extra: [
            "lastAIFailureReason": "ai.providerSlow",
            "aiBackoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "unknown"
        ])
        SubsystemDiagnostics.record(
            level: .warning,
            subsystem: .aiIndexing,
            name: "ai.noteTimeout",
            reasonCode: "ai.noteTimeout",
            noteBasename: noteURL.lastPathComponent,
            counts: ["ai.maxPerNoteDurationMs": Int(timeoutMs)],
            metadata: [
                "status.aiIndexing": AIIndexingStatus.providerSlow.rawValue,
                "ai.maxPerNoteDurationMs": String(timeoutMs)
            ]
        )
        SubsystemDiagnostics.record(
            level: .warning,
            subsystem: .aiIndexing,
            name: "ai.providerSlow",
            reasonCode: "ai.providerSlow",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "status.aiIndexing": AIIndexingStatus.providerSlow.rawValue,
                "backoffUntil": aiBackoffUntil.map(Self.iso8601String) ?? "unknown"
            ]
        )
    }

    private func isAIBackoffActive(now: Date = Date()) -> Bool {
        guard let aiBackoffUntil else { return false }
        if aiBackoffUntil > now {
            return true
        }
        self.aiBackoffUntil = nil
        aiFailureStatus = nil
        state.backoffUntil = nil
        let pendingNotes = pendingNoteCountForAutomaticScan()
        let nextStatus: String
        if isPausedByUser {
            nextStatus = AIIndexingStatus.paused.rawValue
        } else if pendingNotes > 0 {
            nextStatus = AIIndexingStatus.retryableIdle.rawValue
        } else {
            nextStatus = AIIndexingStatus.idle.rawValue
        }
        state.lastStatus = nextStatus
        saveStateToDisk()
        updateAIStatus(nextStatus, extra: [
            "aiBackoffUntil": "none",
            "aiBackoffExpired": "true",
            "automaticScanningPaused": String(isPausedByUser),
            "pendingNotes": "\(pendingNotes)",
            "nextAutomaticAction": pendingNotes > 0 && !isPausedByUser ? "retryNowOrScheduleAutomaticScan" : "none"
        ])
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.backoffExpired",
            reasonCode: "ai.backoffExpired",
            counts: ["pendingNotes": pendingNotes],
            metadata: [
                "status.aiIndexing": nextStatus,
                "automaticScanningPaused": String(isPausedByUser)
            ]
        )
        if pendingNotes > 0, !isPausedByUser {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .aiIndexing,
                name: "ai.retryableIdle",
                reasonCode: "ai.retryableIdle",
                counts: ["pendingNotes": pendingNotes],
                metadata: [
                    "status.aiIndexing": AIIndexingStatus.retryableIdle.rawValue,
                    "lastAIFailureReason": state.lastFailureReason ?? lastAIFailureReason ?? "unknown",
                    "nextAutomaticAction": "retryNowOrScheduleAutomaticScan"
                ]
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .aiIndexing,
                name: "ai.noAutomaticScanReason",
                reasonCode: "ai.noAutomaticScanReason",
                counts: ["pendingNotes": pendingNotes],
                metadata: [
                    "reason": "backoffExpiredAwaitingRetryBudget",
                    "status.aiIndexing": AIIndexingStatus.retryableIdle.rawValue
                ]
            )
        }
        return false
    }

    private func pendingNoteCountForAutomaticScan() -> Int {
        let allNotes = collectMarkdownFiles(in: vaultRootURL)
        return classifyPendingNotes(allNotes, mode: .automatic).totalPending
    }

    private func publishPendingBacklogIdle(pendingNotes: Int, reason: String) {
        state.lastStatus = AIIndexingStatus.pendingBacklogIdle.rawValue
        saveStateToDisk()
        updateAIStatus(AIIndexingStatus.pendingBacklogIdle.rawValue, extra: [
            "pendingNotes": "\(pendingNotes)",
            "nextAutomaticAction": "startVaultScanOrRetryNow",
            "noAutomaticScanReason": reason
        ])
        SubsystemDiagnostics.record(
            level: .warning,
            subsystem: .aiIndexing,
            name: "ai.pendingBacklogIdle",
            reasonCode: "ai.pendingBacklogIdle",
            counts: ["pendingNotes": pendingNotes],
            metadata: [
                "status.aiIndexing": AIIndexingStatus.pendingBacklogIdle.rawValue,
                "nextAutomaticAction": "startVaultScanOrRetryNow"
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.noAutomaticScanReason",
            reasonCode: "ai.noAutomaticScanReason",
            counts: ["pendingNotes": pendingNotes],
            metadata: [
                "reason": reason,
                "status.aiIndexing": AIIndexingStatus.pendingBacklogIdle.rawValue
            ]
        )
    }

    private func updateAIStatus(_ status: String, extra: [String: String] = [:]) {
        state.lastStatus = status
        var values = [
            "aiIndexing": status,
            "lastAIIndexingStatus": status,
            "processedNoteCount": String(state.processedTimestamps.count),
            "conceptCount": String(state.conceptEdges.count)
        ]
        for (key, value) in extra {
            values[key] = value
        }
        SubsystemDiagnostics.updateState(subsystem: .aiIndexing, values: values)
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .aiIndexing,
            name: "ai.statusPublished",
            reasonCode: "ai.statusPublished",
            counts: [
                "conceptCount": state.conceptEdges.count,
                "processedNotes": state.processedTimestamps.count
            ],
            metadata: values
        )
    }

    private nonisolated static func publishPersistedAIHealth(_ state: AIIndexState) {
        var values: [String: String] = [
            "lastAIIndexingStatus": state.lastStatus ?? "idle",
            "processedNoteCount": String(state.processedTimestamps.count),
            "conceptCount": String(state.conceptEdges.count)
        ]
        if let reason = state.lastFailureReason {
            values["lastAIFailureReason"] = reason
        }
        if let backoffUntil = state.backoffUntil {
            values["aiBackoffUntil"] = Self.iso8601String(backoffUntil)
            if backoffUntil > Date() {
                values["lastAIIndexingStatus"] = state.lastStatus ?? "backoff"
                SubsystemDiagnostics.record(
                    level: .warning,
                    subsystem: .aiIndexing,
                    name: "persistedBackoffLoaded",
                    reasonCode: state.lastFailureReason ?? "ai.backoff",
                    metadata: values
                )
            }
        }
        SubsystemDiagnostics.updateState(subsystem: .aiIndexing, values: values)
    }

    public nonisolated static func persistedHealthSummary(vaultRootURL: URL) -> [String: String] {
        let state = loadState(from: vaultRootURL)
        var summary: [String: String] = [
            "aiIndex.status": state.lastStatus ?? "idle",
            "aiIndex.processedNotes": String(state.processedTimestamps.count),
            "aiIndex.concepts": String(state.conceptEdges.count)
        ]
        if let reason = state.lastFailureReason {
            summary["aiIndex.lastFailureReason"] = reason
        }
        if let backoffUntil = state.backoffUntil {
            summary["aiIndex.backoffUntil"] = iso8601String(backoffUntil)
        }
        if let lastFailureAt = state.lastFailureAt {
            summary["aiIndex.lastFailureAt"] = iso8601String(lastFailureAt)
        }
        if let lastSuccessAt = state.lastSuccessAt {
            summary["aiIndex.lastSuccessAt"] = iso8601String(lastSuccessAt)
        }
        return summary
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Debounced save for on-save extraction path.
    private func scheduleSave() {
        saveDebouncTask?.cancel()
        saveDebouncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.saveStateToDisk()
        }
    }

    private func currentRevision(for noteURL: URL) -> UInt64 {
        requestedRevisionByURL[CanonicalNoteIdentity.canonicalFileURL(for: noteURL)] ?? 0
    }

    private func generationAndRevisionAreCurrent(
        for noteURL: URL,
        expectedGeneration: UInt64?,
        expectedRevision: UInt64?
    ) -> Bool {
        if let expectedGeneration, serviceGeneration != expectedGeneration {
            return false
        }
        if let expectedRevision, currentRevision(for: noteURL) != expectedRevision {
            return false
        }
        return true
    }

    private nonisolated var isEnabled: Bool {
        KnowledgeAnalysisSettings.aiConceptExtractionEnabled()
    }
}

// MARK: - Helpers

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let quartzConceptsUpdated = Notification.Name("quartzConceptsUpdated")
    static let quartzConceptScanProgress = Notification.Name("quartzConceptScanProgress")
}
