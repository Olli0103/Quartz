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

    public init() {}
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
    private var isScanRunning = false
    public private(set) var scanProgress: ScanProgress?
    private var saveDebouncTask: Task<Void, Never>?

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
        extractionOverride: (@Sendable (String) async -> [String])? = nil
    ) {
        self.edgeStore = edgeStore
        self.vaultRootURL = vaultRootURL
        self.executionPolicy = executionPolicy
        self.debounceInterval = debounceInterval
        self.scanInterval = scanInterval
        self.extractionOverride = extractionOverride
        self.state = Self.loadState(from: vaultRootURL)
    }

    // MARK: - On-Save Extraction

    public func scheduleExtraction(for noteURL: URL) {
        guard isEnabled else { return }
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        pendingURLs.insert(canonicalURL)
        requestedRevisionByURL[canonicalURL, default: 0] &+= 1
        debounceTask?.cancel()
        let generation = serviceGeneration
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.runPendingExtractions(expectedGeneration: generation)
        }
    }

    // MARK: - Vault Scan

    public func startVaultScan() {
        guard isEnabled else { return }
        guard !isScanRunning else { return }
        scanTask?.cancel()
        let generation = serviceGeneration
        scanTask = Task(priority: .utility) { [weak self] in
            await self?.runVaultScan(expectedGeneration: generation)
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
        hasRestoredPersistedConceptsForCurrentGeneration = false
    }

    private func runPendingExtractions(expectedGeneration: UInt64) async {
        guard serviceGeneration == expectedGeneration else { return }

        let urls = pendingURLs.sorted(by: { $0.absoluteString < $1.absoluteString })
        pendingURLs.removeAll(keepingCapacity: true)

        for noteURL in urls {
            guard serviceGeneration == expectedGeneration else { break }
            let revision = currentRevision(for: noteURL)
            await extractConcepts(
                for: noteURL,
                expectedGeneration: expectedGeneration,
                expectedRevision: revision
            )
        }

        guard serviceGeneration == expectedGeneration else { return }
        scheduleSave()
    }

    private func runVaultScan(expectedGeneration: UInt64) async {
        guard serviceGeneration == expectedGeneration else { return }
        isScanRunning = true
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
        guard !noteURLs.isEmpty else { return }

        let unprocessed = noteURLs.filter { url in
            let relPath = relativePath(for: url)
            guard let lastProcessed = state.processedTimestamps[relPath] else { return true }
            guard let mtime = fileModificationDate(for: url) else { return true }
            return mtime > lastProcessed
        }

        guard !unprocessed.isEmpty else {
            logger.info("Vault scan: all \(noteURLs.count) notes already indexed")
            return
        }

        logger.info("Vault scan: \(unprocessed.count)/\(noteURLs.count) need processing")

        for (index, noteURL) in unprocessed.enumerated() {
            guard !Task.isCancelled, serviceGeneration == expectedGeneration else { break }

            scanProgress = ScanProgress(
                current: index + 1,
                total: unprocessed.count,
                currentNote: noteURL.deletingPathExtension().lastPathComponent
            )

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .quartzConceptScanProgress,
                    object: nil,
                    userInfo: ["current": index + 1, "total": unprocessed.count,
                               "note": noteURL.deletingPathExtension().lastPathComponent]
                )
            }

            let revision = currentRevision(for: noteURL)
            await extractConcepts(
                for: noteURL,
                expectedGeneration: expectedGeneration,
                expectedRevision: revision
            )

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
        logger.info("Vault scan complete")

        await MainActor.run {
            NotificationCenter.default.post(name: .quartzConceptScanProgress, object: nil)
        }
    }

    // MARK: - Core Extraction

    private func extractConcepts(
        for noteURL: URL,
        expectedGeneration: UInt64? = nil,
        expectedRevision: UInt64? = nil
    ) async {
        let canonicalNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: noteURL)
        guard generationAndRevisionAreCurrent(
            for: canonicalNoteURL,
            expectedGeneration: expectedGeneration,
            expectedRevision: expectedRevision
        ) else { return }

        let content: String
        // CRITICAL: Use coordinated read to prevent race with iCloud sync
        do { content = try CoordinatedFileWriter.shared.readString(from: canonicalNoteURL) } catch { return }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 50 else {
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: [],
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return
        }

        let inputText = String(trimmed.prefix(3000))

        if let extractionOverride {
            let concepts = await extractionOverride(inputText)
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: concepts,
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return
        }

        // Per CODEX.md F9: Route through AIExecutionPolicy for consistent circuit breaker/fallback
        if let policy = executionPolicy {
            let concepts = await policy.extractConcepts(
                from: inputText,
                model: nil,
                systemPrompt: Self.systemPrompt
            )
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: concepts,
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
            return
        }

        // Legacy path: direct provider access (for backward compatibility)
        let registry = await AIProviderRegistry.shared
        guard let provider = await registry.selectedProvider, provider.isConfigured else { return }
        let modelID = await registry.selectedModelID

        do {
            let response = try await provider.chat(
                messages: [
                    AIMessage(role: .system, content: Self.systemPrompt),
                    AIMessage(role: .user, content: inputText)
                ],
                model: modelID,
                temperature: 0.3
            )

            let concepts = parseConcepts(from: response.content)
            await commitConceptUpdate(
                for: canonicalNoteURL,
                concepts: concepts,
                expectedGeneration: expectedGeneration,
                expectedRevision: expectedRevision
            )
        } catch {
            logger.warning("Extraction failed: \(error.localizedDescription)")
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
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
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
