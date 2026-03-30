import Foundation
import os

/// Background service that discovers semantic relationships between notes
/// using vector embeddings. Observes `.quartzNoteSaved` notifications and
/// updates `GraphEdgeStore.semanticEdges` with high-confidence matches.
///
/// **Privacy-safe**: All processing happens on-device via `VectorEmbeddingService`.
/// Never alters markdown files — semantic links are stored only in memory.
///
/// **Non-blocking**: Runs all similarity searches on a background thread
/// with debouncing to avoid saturating the CPU during rapid saves.
public actor SemanticLinkService {
    private let embeddingService: VectorEmbeddingService
    private let edgeStore: GraphEdgeStore
    private let vaultRootURL: URL
    private let logger = Logger(subsystem: "com.quartz", category: "SemanticLinkService")

    /// Minimum similarity score to create a semantic link.
    /// 0.82 is a high bar — only genuinely related notes will be linked.
    private let similarityThreshold: Float = 0.82

    /// Maximum number of semantic links per note.
    private let maxRelatedNotes = 5

    /// AppStorage key for the user setting (shared with graph-time semantic linking).
    private static let enabledKey = "semanticAutoLinkingEnabled"

    /// Debounce tracking — URL of the most recently scheduled note.
    private var pendingURL: URL?
    private var debounceTask: Task<Void, Never>?

    public init(
        embeddingService: VectorEmbeddingService,
        edgeStore: GraphEdgeStore,
        vaultRootURL: URL
    ) {
        self.embeddingService = embeddingService
        self.edgeStore = edgeStore
        self.vaultRootURL = vaultRootURL
    }

    /// Schedules a background semantic analysis for the given note URL.
    /// Debounces by 3 seconds — if another save comes in, the timer resets.
    public func scheduleAnalysis(for noteURL: URL) {
        guard isEnabled else { return }

        pendingURL = noteURL
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.runAnalysis()
        }
    }

    /// Runs the semantic similarity search for the pending note.
    private func runAnalysis() async {
        guard let noteURL = pendingURL else { return }
        pendingURL = nil

        let stableID = VectorEmbeddingService.stableNoteID(for: noteURL, vaultRoot: vaultRootURL)

        logger.info("Running semantic analysis for \(noteURL.lastPathComponent)")

        // Find similar notes using the vector index (high threshold)
        let similarIDs = await embeddingService.findSimilarNoteIDs(
            for: stableID,
            limit: maxRelatedNotes,
            threshold: similarityThreshold
        )

        guard !similarIDs.isEmpty else {
            logger.debug("No semantic matches above threshold \(self.similarityThreshold) for \(noteURL.lastPathComponent)")
            // Clear any stale edges for this note
            await edgeStore.updateSemanticConnections(for: noteURL, related: [])
            return
        }

        // Resolve UUIDs back to file URLs
        let resolvedURLs = resolveNoteURLs(from: similarIDs)

        logger.info("Found \(resolvedURLs.count) semantic links for \(noteURL.lastPathComponent)")

        // Update the edge store
        await edgeStore.updateSemanticConnections(for: noteURL, related: resolvedURLs)

        // Post notification so the inspector can refresh
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzSemanticLinksUpdated,
                object: noteURL
            )
        }
    }

    /// Resolves stable note UUIDs to file URLs by scanning the vault directory.
    private func resolveNoteURLs(from noteIDs: [UUID]) -> [URL] {
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

    /// Checks the user setting. Reads from UserDefaults (main-actor safe via synchronous read).
    private nonisolated var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }
}

// MARK: - Notification

public extension Notification.Name {
    /// Posted when semantic links are updated for a note.
    /// `object` is the note URL (`URL`).
    static let quartzSemanticLinksUpdated = Notification.Name("quartzSemanticLinksUpdated")
}
