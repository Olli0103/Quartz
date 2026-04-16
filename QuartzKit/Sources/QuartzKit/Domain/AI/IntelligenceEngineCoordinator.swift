import Foundation
import os

public final class IntelligenceEngineNotificationSource: @unchecked Sendable {}

/// Unified coordinator for the Intelligence Engine subsystems.
///
/// Bridges file system events (NSFilePresenter, iCloud sync) to all AI services:
/// - VectorEmbeddingService (embeddings)
/// - SemanticLinkService (relationship discovery)
/// - KnowledgeExtractionService (concept extraction)
///
/// **Thread Safety**: All file reads use `CoordinatedFileWriter` to prevent
/// race conditions with iCloud sync operations.
///
/// **Non-blocking**: Heavy operations run on background tasks, never MainActor.
public actor IntelligenceEngineCoordinator {

    // MARK: - Dependencies

    private weak var embeddingService: VectorEmbeddingService?
    private weak var semanticService: SemanticLinkService?
    private weak var extractionService: KnowledgeExtractionService?
    private let vaultRootURL: URL
    private let logger = Logger(subsystem: "com.quartz", category: "IntelligenceEngine")

    // MARK: - Status Tracking

    /// Current status of the Intelligence Engine (observable by UI).
    public private(set) var status: IntelligenceEngineStatus = .idle

    /// Stable notification sender for coordinator-specific observers.
    /// UI can continue observing all status changes with `object: nil`;
    /// tests can use this to avoid cross-coordinator noise.
    public nonisolated let statusNotificationSource = IntelligenceEngineNotificationSource()

    /// Detailed progress for each subsystem.
    public private(set) var subsystemProgress: SubsystemProgress = .init()

    /// nonisolated(unsafe) for deinit access — Swift 6 deinit is nonisolated.
    /// Safe: @MainActor @Observable class; observers only removed in deinit.
    nonisolated(unsafe) private var observerTokens: [Any] = []

    // MARK: - Debouncing

    /// Pending file URLs to process (deduplicated).
    private var pendingURLs: Set<URL> = []

    /// Debounce task for batching rapid file changes.
    private var debounceTask: Task<Void, Never>?

    /// Debounce interval for batching changes.
    private let debounceInterval: Duration = .seconds(2)

    // MARK: - Init

    public init(
        embeddingService: VectorEmbeddingService?,
        semanticService: SemanticLinkService?,
        extractionService: KnowledgeExtractionService?,
        vaultRootURL: URL
    ) {
        self.embeddingService = embeddingService
        self.semanticService = semanticService
        self.extractionService = extractionService
        self.vaultRootURL = vaultRootURL
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Event Wiring

    /// Starts observing file system events. Call once after initialization.
    public func startObserving() {
        // Remove any existing observers
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()

        // 1. NSFilePresenter changes (iCloud sync, external edits)
        let presenterToken = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { await self?.handleFileChange(at: url, source: .filePresenter) }
        }
        observerTokens.append(presenterToken)

        // 2. NSFilePresenter move events
        let moveToken = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterDidMove,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let oldURL = userInfo["oldURL"] as? URL,
                  let newURL = userInfo["newURL"] as? URL else { return }
            Task { await self?.handleFileMove(from: oldURL, to: newURL) }
        }
        observerTokens.append(moveToken)

        // 3. NSFilePresenter delete events
        let deleteToken = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterWillDelete,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { await self?.handleFileDeletion(at: url) }
        }
        observerTokens.append(deleteToken)

        // 4. Editor saves (legacy path, still needed for immediate updates)
        let saveToken = NotificationCenter.default.addObserver(
            forName: .quartzNoteSaved,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { await self?.handleFileChange(at: url, source: .editorSave) }
        }
        observerTokens.append(saveToken)

        logger.info("IntelligenceEngineCoordinator started observing file events")
    }

    /// Stops observing file system events and cancels any pending batch work.
    public func stopObserving() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingURLs.removeAll()

        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()

        status = .idle
    }

    // MARK: - Event Handlers

    /// Handles file content changes from any source.
    private func handleFileChange(at url: URL, source: ChangeSource) {
        guard url.pathExtension.lowercased() == "md" else { return }

        logger.debug("File change detected: \(url.lastPathComponent) (source: \(String(describing: source)))")

        // Add to pending set and debounce
        pendingURLs.insert(url)
        scheduleProcessing()
    }

    /// Handles file moves/renames.
    private func handleFileMove(from oldURL: URL, to newURL: URL) {
        guard newURL.pathExtension.lowercased() == "md" else { return }

        logger.info("File moved: \(oldURL.lastPathComponent) → \(newURL.lastPathComponent)")

        Task.detached(priority: .utility) { [embeddingService, vaultRootURL] in
            guard let embedding = embeddingService else { return }

            // Remove old embeddings
            let oldID = VectorEmbeddingService.stableNoteID(for: oldURL, vaultRoot: vaultRootURL)
            await embedding.removeNote(oldID)

            // Index at new location with coordinated read
            let newID = VectorEmbeddingService.stableNoteID(for: newURL, vaultRoot: vaultRootURL)
            if let content = try? CoordinatedFileWriter.shared.readString(from: newURL) {
                try? await embedding.indexNote(noteID: newID, content: content)
                try? await embedding.saveIndex()
            }
        }
    }

    /// Handles file deletions.
    private func handleFileDeletion(at url: URL) {
        guard url.pathExtension.lowercased() == "md" else { return }

        logger.info("File deleted: \(url.lastPathComponent)")

        Task.detached(priority: .utility) { [embeddingService, vaultRootURL] in
            guard let embedding = embeddingService else { return }
            let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRootURL)
            await embedding.removeNote(stableID)
            try? await embedding.saveIndex()
        }
    }

    // MARK: - Batch Processing

    /// Schedules debounced processing of pending file changes.
    private func scheduleProcessing() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.processPendingChanges()
        }
    }

    /// Processes all pending file changes in a batch.
    private func processPendingChanges() async {
        let urls = pendingURLs
        pendingURLs.removeAll()

        guard !urls.isEmpty else { return }

        logger.info("Processing \(urls.count) file changes")

        // Update status
        status = .indexing(progress: 0, total: urls.count)
        await postStatusUpdate()

        var processed = 0
        for url in urls {
            guard !Task.isCancelled else { break }

            await processFile(at: url)

            processed += 1
            status = .indexing(progress: processed, total: urls.count)
            await postStatusUpdate()
        }

        // Run semantic analysis after all embeddings are updated
        status = .analyzing
        await postStatusUpdate()

        for url in urls {
            await semanticService?.scheduleAnalysis(for: url)
            await extractionService?.scheduleExtraction(for: url)
        }

        status = .idle
        await postStatusUpdate()

        logger.info("Completed processing \(urls.count) file changes")
    }

    /// Processes a single file with coordinated read.
    private func processFile(at url: URL) async {
        guard let embedding = embeddingService else { return }

        // CRITICAL: Use coordinated read to prevent race with iCloud
        guard let content = try? CoordinatedFileWriter.shared.readString(from: url) else {
            logger.warning("Failed to read file: \(url.lastPathComponent)")
            return
        }

        guard !content.isEmpty else { return }

        let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRootURL)

        do {
            try await embedding.indexNote(noteID: stableID, content: content)
            try await embedding.saveIndex()
        } catch {
            logger.error("Failed to index note: \(error.localizedDescription)")
        }
    }

    // MARK: - Status Notifications

    /// Posts a status update notification for UI observers.
    private func postStatusUpdate() async {
        let currentStatus = status
        let notificationSource = statusNotificationSource
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzIntelligenceEngineStatusChanged,
                object: notificationSource,
                userInfo: ["status": currentStatus]
            )
        }
    }
}

// MARK: - Supporting Types

public extension IntelligenceEngineCoordinator {

    /// Source of a file change event.
    enum ChangeSource: String, Sendable {
        case filePresenter = "NSFilePresenter"
        case editorSave = "EditorSave"
        case iCloudSync = "iCloudSync"
    }

    /// Progress tracking for each subsystem.
    struct SubsystemProgress: Sendable {
        public var embeddingProgress: (current: Int, total: Int)?
        public var semanticProgress: (current: Int, total: Int)?
        public var extractionProgress: (current: Int, total: Int)?

        public init(
            embeddingProgress: (current: Int, total: Int)? = nil,
            semanticProgress: (current: Int, total: Int)? = nil,
            extractionProgress: (current: Int, total: Int)? = nil
        ) {
            self.embeddingProgress = embeddingProgress
            self.semanticProgress = semanticProgress
            self.extractionProgress = extractionProgress
        }
    }
}

// MARK: - Intelligence Engine Status

/// Unified status enum for the Intelligence Engine.
/// Observable by InspectorStore and SidebarViewModel for UI display.
public enum IntelligenceEngineStatus: Sendable, Equatable {
    /// Engine is idle, all data is current.
    case idle

    /// Indexing embeddings for notes.
    case indexing(progress: Int, total: Int)

    /// Running semantic analysis (link discovery).
    case analyzing

    /// Extracting AI concepts from notes.
    case extracting(progress: Int, total: Int, currentNote: String)

    /// All operations complete, data is fresh.
    case complete

    /// An error occurred during processing.
    case error(message: String)

    /// Human-readable description for UI display.
    public var displayText: String {
        switch self {
        case .idle:
            return String(localized: "Intelligence Engine ready", bundle: .module)
        case .indexing(let progress, let total):
            return String(localized: "Indexing \(progress)/\(total) notes…", bundle: .module)
        case .analyzing:
            return String(localized: "Discovering relationships…", bundle: .module)
        case .extracting(let progress, let total, _):
            return String(localized: "Extracting concepts \(progress)/\(total)…", bundle: .module)
        case .complete:
            return String(localized: "Intelligence up to date", bundle: .module)
        case .error(let message):
            return String(localized: "Error: \(message)", bundle: .module)
        }
    }

    /// Whether the engine is actively processing.
    public var isActive: Bool {
        switch self {
        case .idle, .complete, .error:
            return false
        case .indexing, .analyzing, .extracting:
            return true
        }
    }

    /// Progress fraction (0.0–1.0) for active states.
    public var progressFraction: Double? {
        switch self {
        case .indexing(let progress, let total):
            return total > 0 ? Double(progress) / Double(total) : nil
        case .extracting(let progress, let total, _):
            return total > 0 ? Double(progress) / Double(total) : nil
        default:
            return nil
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when the Intelligence Engine status changes.
    /// `userInfo["status"]` contains `IntelligenceEngineStatus`.
    static let quartzIntelligenceEngineStatusChanged = Notification.Name("quartzIntelligenceEngineStatusChanged")
}
