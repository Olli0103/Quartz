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
public actor KnowledgeExtractionService {
    private let edgeStore: GraphEdgeStore
    private let vaultRootURL: URL
    private let logger = Logger(subsystem: "com.quartz", category: "KnowledgeExtraction")

    // MARK: - Persisted State

    private var state: AIIndexState

    private var stateFileURL: URL {
        vaultRootURL.appending(path: ".quartz").appending(path: "ai_index.json")
    }

    // MARK: - On-Save Debounce

    private var pendingURL: URL?
    private var debounceTask: Task<Void, Never>?

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

    // MARK: - Settings

    private static let enabledKey = "semanticAutoLinkingEnabled"

    private static let systemPrompt = """
    You are an ontology engine for a Second Brain note-taking app. \
    Read the note below and extract the 3-5 most critical underlying concepts. \
    These can be Projects, People, Technologies, or Abstract Ideas. \
    Return ONLY a valid JSON array of strings. Example: ["Project Apollo", "Bhargav", "SwiftUI Architecture"]. \
    Keep each concept concise (1-3 words). Do not include explanations.
    """

    private let scanIntervalSeconds: Double = 2.0

    // MARK: - Init

    public init(edgeStore: GraphEdgeStore, vaultRootURL: URL) {
        self.edgeStore = edgeStore
        self.vaultRootURL = vaultRootURL
        self.state = Self.loadState(from: vaultRootURL)
    }

    // MARK: - On-Save Extraction

    public func scheduleExtraction(for noteURL: URL) {
        guard isEnabled else { return }
        pendingURL = noteURL
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.extractConcepts(for: noteURL)
            await self?.scheduleSave()
        }
    }

    // MARK: - Vault Scan

    public func startVaultScan() {
        guard isEnabled else { return }
        guard !isScanRunning else { return }
        scanTask?.cancel()
        scanTask = Task(priority: .utility) { [weak self] in
            await self?.runVaultScan()
        }
    }

    public func stopVaultScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanRunning = false
        scanProgress = nil
    }

    private func runVaultScan() async {
        isScanRunning = true
        defer {
            isScanRunning = false
            scanProgress = nil
        }

        // Restore concepts from persisted state into the live edge store
        await restoreConceptEdgesFromState()

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
            guard !Task.isCancelled else { break }

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

            await extractConcepts(for: noteURL)

            // Save state every 5 notes (resilient to crashes mid-scan)
            if (index + 1) % 5 == 0 {
                saveStateToDisk()
            }

            if index < unprocessed.count - 1 {
                try? await Task.sleep(for: .seconds(scanIntervalSeconds))
            }
        }

        saveStateToDisk()
        logger.info("Vault scan complete")

        await MainActor.run {
            NotificationCenter.default.post(name: .quartzConceptScanProgress, object: nil)
        }
    }

    // MARK: - Core Extraction

    private func extractConcepts(for noteURL: URL) async {
        let content: String
        do { content = try String(contentsOf: noteURL, encoding: .utf8) } catch { return }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 50 else {
            await updateConceptsAndState(for: noteURL, concepts: [])
            return
        }

        let registry = await AIProviderRegistry.shared
        guard let provider = await registry.selectedProvider, provider.isConfigured else { return }
        let modelID = await registry.selectedModelID

        do {
            let response = try await provider.chat(
                messages: [
                    AIMessage(role: .system, content: Self.systemPrompt),
                    AIMessage(role: .user, content: String(trimmed.prefix(3000)))
                ],
                model: modelID,
                temperature: 0.3
            )

            let concepts = parseConcepts(from: response.content)
            await updateConceptsAndState(for: noteURL, concepts: concepts)

            if !concepts.isEmpty {
                logger.info("[\(noteURL.lastPathComponent)] \(concepts.joined(separator: ", "))")
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .quartzConceptsUpdated, object: noteURL)
            }
        } catch {
            logger.warning("Extraction failed: \(error.localizedDescription)")
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
    private func restoreConceptEdgesFromState() async {
        guard !state.conceptEdges.isEmpty else { return }
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

        // Batch-update the live store
        for (noteURL, concepts) in noteConcepts {
            await edgeStore.updateConcepts(for: noteURL, concepts: concepts)
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

    private nonisolated var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
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
