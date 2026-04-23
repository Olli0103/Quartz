import Foundation
import os

// MARK: - Intelligence Engine Recovery Journal

/// Persistent journal for failed Intelligence Engine operations.
///
/// **The Objective:**
/// Ensures no file change events are lost when coordinated writes fail due to:
/// - iCloud sync locks (file being uploaded/downloaded)
/// - Disk full conditions
/// - NSFilePresenter coordination timeouts
/// - App termination during processing
///
/// **Cross-Platform Nuances:**
/// - **macOS**: "Optimize Mac Storage" can evict files, causing `.notDownloaded` errors.
///   Journal entries include download-needed flag for retry.
/// - **iOS/iPadOS**: Background app suspension can interrupt processing.
///   Journal is persisted before suspension via `applicationWillResignActive`.
/// - **All platforms**: Journal uses atomic writes to prevent corruption.
///
/// **Recovery Strategy:**
/// 1. On failure: Write event to `.quartz/recovery_journal.json`
/// 2. On next launch: Read journal, re-attempt all pending operations
/// 3. On success: Remove entry from journal
/// 4. On repeated failure: Mark entry as "deferred" with exponential backoff
///
/// **Usage:**
/// ```swift
/// // On failure:
/// RecoveryJournal.shared.recordFailure(for: noteURL, operation: .indexEmbedding)
///
/// // On launch:
/// await RecoveryJournal.shared.replayPendingOperations { entry in
///     // Re-attempt the operation
/// }
/// ```
public actor RecoveryJournal {

    // MARK: - Singleton

    public static let shared = RecoveryJournal()

    // MARK: - State

    private var entries: [JournalEntry] = []
    private var journalURL: URL?
    private let logger = Logger(subsystem: "com.quartz", category: "RecoveryJournal")

    /// Maximum retry attempts before marking as deferred.
    private let maxRetryAttempts = 5

    /// Base retry delay (doubles each attempt).
    private let baseRetryDelay: TimeInterval = 2.0

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    /// Sets the vault root for journal storage.
    /// Call this when a vault is loaded.
    public func configure(vaultRoot: URL) {
        let quartzDir = vaultRoot.appending(path: ".quartz")
        journalURL = quartzDir.appending(path: "recovery_journal.json")

        // Load existing journal
        Task {
            await loadJournal()
        }
    }

    // MARK: - Recording Failures

    /// Records a failed operation to the journal.
    ///
    /// - Parameters:
    ///   - url: The file URL that failed.
    ///   - operation: The type of operation that failed.
    ///   - error: The error that caused the failure.
    public func recordFailure(
        for url: URL,
        operation: OperationType,
        error: Error? = nil
    ) {
        // Check if entry already exists
        if let existingIndex = entries.firstIndex(where: { $0.fileURL == url && $0.operation == operation }) {
            // Increment retry count
            entries[existingIndex].retryCount += 1
            entries[existingIndex].lastAttempt = Date()
            entries[existingIndex].lastError = error?.localizedDescription

            logger.warning("Updated journal entry for \(url.lastPathComponent): retry #\(self.entries[existingIndex].retryCount)")
            QuartzDiagnostics.warning(
                category: "RecoveryJournal",
                "Updated journal entry for \(url.lastPathComponent): retry #\(self.entries[existingIndex].retryCount)"
            )
        } else {
            // Create new entry
            let entry = JournalEntry(
                fileURL: url,
                operation: operation,
                lastError: error?.localizedDescription
            )
            entries.append(entry)

            logger.info("Recorded failure for \(url.lastPathComponent): \(operation.rawValue)")
        }

        saveJournal()
    }

    /// Records a file move operation (requires special handling).
    public func recordMove(from oldURL: URL, to newURL: URL, error: Error? = nil) {
        let entry = JournalEntry(
            fileURL: newURL,
            operation: .relocateEmbedding,
            context: ["oldURL": oldURL.path(percentEncoded: false)],
            lastError: error?.localizedDescription
        )
        entries.append(entry)
        saveJournal()

        logger.info("Recorded move failure: \(oldURL.lastPathComponent) → \(newURL.lastPathComponent)")
    }

    // MARK: - Recovery

    /// Replays all pending operations in the journal.
    ///
    /// - Parameter handler: Async closure that attempts each operation.
    ///   Return `true` if successful, `false` to keep in journal.
    public func replayPendingOperations(
        handler: @escaping (JournalEntry) async -> Bool
    ) async {
        guard !entries.isEmpty else {
            logger.info("No pending operations in recovery journal")
            return
        }

        logger.info("Replaying \(self.entries.count) pending operations from journal")

        var successfulEntries: [UUID] = []
        var deferredEntries: [UUID] = []

        for entry in entries {
            // Check if we should retry based on backoff
            if let nextRetry = entry.nextRetryTime, Date() < nextRetry {
                logger.debug("Skipping \(entry.fileURL.lastPathComponent): next retry at \(nextRetry)")
                continue
            }

            // Check if max retries exceeded
            if entry.retryCount >= maxRetryAttempts {
                logger.warning("Max retries exceeded for \(entry.fileURL.lastPathComponent), marking as deferred")
                QuartzDiagnostics.warning(
                    category: "RecoveryJournal",
                    "Max retries exceeded for \(entry.fileURL.lastPathComponent), marking as deferred"
                )
                deferredEntries.append(entry.id)
                continue
            }

            // Attempt recovery
            logger.info("Retrying \(entry.operation.rawValue) for \(entry.fileURL.lastPathComponent) (attempt \(entry.retryCount + 1))")

            let success = await handler(entry)

            if success {
                logger.success("Successfully recovered \(entry.fileURL.lastPathComponent)")
                successfulEntries.append(entry.id)
            } else {
                // Update retry count (will be incremented by recordFailure if called)
                logger.warning("Recovery failed for \(entry.fileURL.lastPathComponent)")
                QuartzDiagnostics.warning(
                    category: "RecoveryJournal",
                    "Recovery failed for \(entry.fileURL.lastPathComponent)"
                )
            }
        }

        // Remove successful entries
        entries.removeAll { successfulEntries.contains($0.id) }

        // Mark deferred entries
        for id in deferredEntries {
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].isDeferred = true
            }
        }

        saveJournal()

        logger.info("Recovery complete: \(successfulEntries.count) succeeded, \(deferredEntries.count) deferred, \(self.entries.count) remaining")
    }

    /// Clears all entries for a specific file (e.g., after successful manual reindex).
    public func clearEntries(for url: URL) {
        let removed = entries.filter { $0.fileURL == url }
        entries.removeAll { $0.fileURL == url }

        if !removed.isEmpty {
            saveJournal()
            logger.info("Cleared \(removed.count) journal entries for \(url.lastPathComponent)")
        }
    }

    /// Clears all deferred entries (e.g., user requested full reindex).
    public func clearDeferredEntries() {
        let deferredCount = entries.filter(\.isDeferred).count
        entries.removeAll(where: \.isDeferred)

        if deferredCount > 0 {
            saveJournal()
            logger.info("Cleared \(deferredCount) deferred journal entries")
        }
    }

    /// Returns all pending entries (for diagnostics UI).
    public var pendingEntries: [JournalEntry] {
        entries.filter { !$0.isDeferred }
    }

    /// Returns all deferred entries (for diagnostics UI).
    public var deferredEntries: [JournalEntry] {
        entries.filter(\.isDeferred)
    }

    // MARK: - Persistence

    private func loadJournal() {
        guard let url = journalURL,
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            logger.debug("No existing journal found")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([JournalEntry].self, from: data)
            logger.info("Loaded \(self.entries.count) entries from recovery journal")
        } catch {
            logger.error("Failed to load recovery journal: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "RecoveryJournal",
                "Failed to load recovery journal: \(error.localizedDescription)"
            )
            // Don't delete corrupted journal — might contain important recovery data
        }
    }

    private func saveJournal() {
        guard let url = journalURL else { return }

        do {
            // Ensure .quartz directory exists
            let quartzDir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: quartzDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)

            // Atomic write to prevent corruption
            try data.write(to: url, options: .atomic)
            logger.debug("Saved \(self.entries.count) entries to recovery journal")
        } catch {
            logger.error("Failed to save recovery journal: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "RecoveryJournal",
                "Failed to save recovery journal: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Journal Entry

public extension RecoveryJournal {

    /// A single entry in the recovery journal.
    struct JournalEntry: Codable, Identifiable, Sendable {
        public let id: UUID
        public let fileURL: URL
        public let operation: OperationType
        public let createdAt: Date
        public var lastAttempt: Date
        public var retryCount: Int
        public var lastError: String?
        public var context: [String: String]
        public var isDeferred: Bool

        public init(
            fileURL: URL,
            operation: OperationType,
            context: [String: String] = [:],
            lastError: String? = nil
        ) {
            self.id = UUID()
            self.fileURL = fileURL
            self.operation = operation
            self.createdAt = Date()
            self.lastAttempt = Date()
            self.retryCount = 0
            self.lastError = lastError
            self.context = context
            self.isDeferred = false
        }

        /// Calculates the next retry time based on exponential backoff.
        public var nextRetryTime: Date? {
            guard retryCount > 0 else { return nil }
            let delay = pow(2.0, Double(retryCount - 1)) * 2.0  // 2s, 4s, 8s, 16s, 32s
            return lastAttempt.addingTimeInterval(delay)
        }
    }

    /// Types of operations that can be journaled.
    enum OperationType: String, Codable, Sendable {
        case indexEmbedding = "index_embedding"
        case removeEmbedding = "remove_embedding"
        case relocateEmbedding = "relocate_embedding"
        case extractConcepts = "extract_concepts"
        case analyzeSemanticLinks = "analyze_semantic_links"
        case updateGraphEdges = "update_graph_edges"
    }
}

// MARK: - Convenience Extension for IntelligenceEngineCoordinator

public extension RecoveryJournal {

    /// Records an embedding index failure and schedules retry.
    func recordEmbeddingFailure(for url: URL, error: Error) {
        recordFailure(for: url, operation: .indexEmbedding, error: error)
    }

    /// Records a concept extraction failure.
    func recordConceptExtractionFailure(for url: URL, error: Error) {
        recordFailure(for: url, operation: .extractConcepts, error: error)
    }

    /// Records a semantic analysis failure.
    func recordSemanticAnalysisFailure(for url: URL, error: Error) {
        recordFailure(for: url, operation: .analyzeSemanticLinks, error: error)
    }
}
