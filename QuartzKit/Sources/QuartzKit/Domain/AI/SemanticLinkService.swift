import Foundation
import os

/// Background service that discovers note-to-note related-note similarity
/// using vector embeddings and updates `GraphEdgeStore.semanticEdges`.
///
/// **Privacy-safe**: All processing happens on-device via `VectorEmbeddingService`.
/// Never alters markdown files — related-note similarity results are stored only in memory.
///
/// **Non-blocking**: Runs all similarity searches on a background thread
/// with debouncing to avoid saturating the CPU during rapid saves.
public actor SemanticLinkService {
    private let embeddingService: VectorEmbeddingService
    private let edgeStore: GraphEdgeStore
    private let vaultRootURL: URL
    private let debounceInterval: Duration
    private let similaritySearchOverride: (@Sendable (UUID, Int, Float) async -> [UUID])?
    private let noteURLResolverOverride: (@Sendable ([UUID]) -> [URL])?
    private let logger = Logger(subsystem: "com.quartz", category: "SemanticLinkService")

    /// Minimum similarity score to create a related-note similarity edge.
    /// 0.82 is a high bar — only genuinely related notes will be linked.
    private let similarityThreshold: Float = 0.82

    /// Maximum number of related notes per note.
    private let maxRelatedNotes = 5

    /// Debounce tracking — all note URLs currently queued for analysis.
    private var pendingURLs: Set<URL> = []
    private var debounceTask: Task<Void, Never>?
    private var serviceGeneration: UInt64 = 0
    private var requestedRevisionByURL: [URL: UInt64] = [:]

    public init(
        embeddingService: VectorEmbeddingService,
        edgeStore: GraphEdgeStore,
        vaultRootURL: URL,
        debounceInterval: Duration = .seconds(3),
        similaritySearchOverride: (@Sendable (UUID, Int, Float) async -> [UUID])? = nil,
        noteURLResolverOverride: (@Sendable ([UUID]) -> [URL])? = nil
    ) {
        self.embeddingService = embeddingService
        self.edgeStore = edgeStore
        self.vaultRootURL = vaultRootURL
        self.debounceInterval = debounceInterval
        self.similaritySearchOverride = similaritySearchOverride
        self.noteURLResolverOverride = noteURLResolverOverride
    }

    /// Schedules a background semantic analysis for the given note URL.
    /// Debounces batched note updates and supersedes stale requests for the same note.
    public func scheduleAnalysis(for noteURL: URL) {
        guard isEnabled else { return }

        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        pendingURLs.insert(canonicalURL)
        requestedRevisionByURL[canonicalURL, default: 0] &+= 1
        debounceTask?.cancel()
        let generation = serviceGeneration
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.runPendingAnalyses(expectedGeneration: generation)
        }
    }

    /// Cancels queued work and prevents suspended older analyses from applying
    /// after a vault switch or relaunch supersedes this service instance.
    public func invalidatePendingWork() {
        serviceGeneration &+= 1
        pendingURLs.removeAll(keepingCapacity: false)
        debounceTask?.cancel()
        debounceTask = nil
    }

    public func handleNoteDeletion(at noteURL: URL) async {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        pendingURLs.remove(canonicalURL)
        requestedRevisionByURL[canonicalURL, default: 0] &+= 1
        await edgeStore.removeSemanticConnections(for: canonicalURL)

        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzRelatedNotesUpdated,
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
        await edgeStore.removeSemanticConnections(for: canonicalOldURL)
        scheduleAnalysis(for: canonicalNewURL)

        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzRelatedNotesUpdated,
                object: canonicalNewURL,
                userInfo: ["vaultRootURL": notificationVaultRootURL]
            )
        }
    }

    private func runPendingAnalyses(expectedGeneration: UInt64) async {
        guard serviceGeneration == expectedGeneration else { return }

        let urls = pendingURLs.sorted(by: { $0.absoluteString < $1.absoluteString })
        pendingURLs.removeAll(keepingCapacity: true)

        for noteURL in urls {
            guard serviceGeneration == expectedGeneration else { break }
            let revision = requestedRevisionByURL[noteURL] ?? 0
            await runAnalysis(for: noteURL, expectedGeneration: expectedGeneration, expectedRevision: revision)
        }
    }

    /// Runs the semantic similarity search for one note if the request is still current.
    private func runAnalysis(
        for noteURL: URL,
        expectedGeneration: UInt64,
        expectedRevision: UInt64
    ) async {
        guard serviceGeneration == expectedGeneration,
              currentRevision(for: noteURL) == expectedRevision else { return }

        let stableID = VectorEmbeddingService.stableNoteID(for: noteURL, vaultRoot: vaultRootURL)

        logger.info("Running related-note similarity analysis for \(noteURL.lastPathComponent)")

        // Find similar notes using the vector index (high threshold)
        let similarIDs: [UUID]
        if let similaritySearchOverride {
            similarIDs = await similaritySearchOverride(stableID, maxRelatedNotes, similarityThreshold)
        } else {
            similarIDs = await embeddingService.findSimilarNoteIDs(
                for: stableID,
                limit: maxRelatedNotes,
                threshold: similarityThreshold
            )
        }

        guard serviceGeneration == expectedGeneration,
              currentRevision(for: noteURL) == expectedRevision else { return }

        guard !similarIDs.isEmpty else {
            logger.debug("No related-note similarity matches above threshold \(self.similarityThreshold) for \(noteURL.lastPathComponent)")
            // Clear any stale edges for this note
            await edgeStore.updateSemanticConnections(for: noteURL, related: [])
            let notificationVaultRootURL = vaultRootURL
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .quartzRelatedNotesUpdated,
                    object: noteURL,
                    userInfo: ["vaultRootURL": notificationVaultRootURL]
                )
            }
            return
        }

        // Resolve UUIDs back to file URLs
        let resolvedURLs = resolveNoteURLs(from: similarIDs)

        guard serviceGeneration == expectedGeneration,
              currentRevision(for: noteURL) == expectedRevision else { return }

        logger.info("Found \(resolvedURLs.count) related notes for \(noteURL.lastPathComponent)")

        // Update the edge store
        await edgeStore.updateSemanticConnections(for: noteURL, related: resolvedURLs)

        // Post notification so the inspector can refresh
        let notificationVaultRootURL = vaultRootURL
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzRelatedNotesUpdated,
                object: noteURL,
                userInfo: ["vaultRootURL": notificationVaultRootURL]
            )
        }
    }

    /// Resolves stable note UUIDs to file URLs by scanning the vault directory.
    private func resolveNoteURLs(from noteIDs: [UUID]) -> [URL] {
        if let noteURLResolverOverride {
            return noteURLResolverOverride(noteIDs)
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var idToURL: [UUID: URL] = [:]
        let targetSet = Set(noteIDs)

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRootURL)
            if targetSet.contains(stableID) {
                idToURL[stableID] = url
            }
            // Early exit if we found all targets
            if idToURL.count == targetSet.count { break }
        }

        // Maintain the similarity ordering from the input
        return noteIDs.compactMap { idToURL[$0] }
    }

    private func currentRevision(for noteURL: URL) -> UInt64 {
        requestedRevisionByURL[CanonicalNoteIdentity.canonicalFileURL(for: noteURL)] ?? 0
    }

    /// Checks the user setting. Reads from UserDefaults (main-actor safe via synchronous read).
    private nonisolated var isEnabled: Bool {
        KnowledgeAnalysisSettings.relatedNotesSimilarityEnabled()
    }
}

// MARK: - Notification

public extension Notification.Name {
    /// Posted when related-note similarity is updated for a note.
    /// `object` is the note URL (`URL`).
    static let quartzRelatedNotesUpdated = Notification.Name("quartzRelatedNotesUpdated")
    /// Backwards-compatible alias kept while older tests and code paths transition.
    static let quartzSemanticLinksUpdated = quartzRelatedNotesUpdated
}
