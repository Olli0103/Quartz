import Foundation
import CryptoKit
import os

/// Search index for the entire vault with disk persistence.
///
/// On first open, builds the full index from the filesystem and saves to
/// `{vault}/.quartz/search-index.json`. On subsequent opens, loads the
/// cached index if the vault fingerprint matches (no files changed).
/// Incrementally updated on note saves with debounced cache writes.
///
/// System-wide discovery uses ``QuartzSpotlightIndexer`` (Core Spotlight), not this type.
public actor VaultSearchIndex {
    private static let rebuildCheckpointInterval = 32

    public enum BuildSource: String, Sendable {
        case cache
        case rebuild
        case incremental
    }

    /// Indexed entry for a note.
    private struct IndexEntry: Sendable, Codable {
        let url: URL
        let title: String
        let titleLower: String
        /// All tags: frontmatter + inline #tags extracted from body.
        let tags: [String]
        let tagsLower: [String]
        let body: String
        let bodyLower: String
        let modifiedAt: Date
    }

    /// Codable wrapper for persisting the full index to disk.
    private struct CachedIndex: Codable, Sendable {
        let entries: [URL: IndexEntry]
        let fingerprint: String
    }

    private var entries: [URL: IndexEntry] = [:]
    private let vaultProvider: any VaultProviding
    private let logger = Logger(subsystem: "com.quartz", category: "VaultSearchIndex")
    private var lastBuildSource: BuildSource?

    /// Root URL of the current vault (set after buildIndex or loadIndex).
    private var vaultRoot: URL?

    /// Debounce task for cache saves — max one save per 5s window.
    private var saveCacheTask: Task<Void, Never>?
    private var lastCacheSave: Date = .distantPast

    /// Regex for inline `#tag` extraction. Matches `#word` only after whitespace
    /// (never at line start — that's a heading). Captures alphanumeric + underscore + hyphen tags.
    private static let inlineTagRegex = try! NSRegularExpression(
        pattern: #"(?<=\s)#([a-zA-Z][a-zA-Z0-9_-]*)"#,
        options: []
    )

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Builds the complete index for a vault.
    ///
    /// Checks the disk cache first. If the cache fingerprint matches the current
    /// vault state (no files added/removed/modified), loads from cache. Otherwise
    /// rebuilds from the filesystem and saves the new cache.
    public func buildIndex(at root: URL) async throws {
        let tree = try await vaultProvider.loadFileTree(at: root)
        await buildIndex(fromPreloadedTree: tree, at: root)
    }

    /// Builds the search index from an already loaded file tree.
    ///
    /// Reuses the persisted cache when the fingerprint matches, avoiding a second
    /// full-note read on startup after the sidebar tree has already been loaded.
    public func buildIndex(fromPreloadedTree nodes: [FileNode], at root: URL) async {
        await buildIndex(fromPreloadedTree: nodes, at: root, forceRebuild: false)
    }

    /// Forces a rebuild from an already loaded file tree, overwriting any persisted cache.
    public func rebuildIndex(fromPreloadedTree nodes: [FileNode], at root: URL) async {
        await buildIndex(fromPreloadedTree: nodes, at: root, forceRebuild: true)
    }

    /// Indexes notes from an already loaded file tree without cache reuse.
    /// Kept for compatibility with older call sites; prefer `buildIndex(fromPreloadedTree:at:)`.
    public func indexFromPreloadedTree(_ nodes: [FileNode]) async {
        guard let vaultRoot else {
            entries.removeAll(keepingCapacity: true)
            await indexNodes(nodes)
            return
        }
        await buildIndex(fromPreloadedTree: nodes, at: vaultRoot, forceRebuild: true)
    }

    /// Updates the index for a single note.
    public func updateEntry(for url: URL) async {
        await updateEntry(for: url, scheduleSave: true)
    }

    private func updateEntry(for url: URL, scheduleSave: Bool) async {
        do {
            let note = try await vaultProvider.readNote(at: url)
            let title = note.displayName
            let frontmatterTags = note.frontmatter.tags
            let body = note.body

            // Extract inline #tags from body (outside code blocks)
            let inlineTags = Self.extractInlineTags(from: body)

            // Merge frontmatter + inline tags, deduplicated
            var tagSet = Set(frontmatterTags.map { $0.lowercased() })
            var allTags = frontmatterTags
            for tag in inlineTags {
                let lower = tag.lowercased()
                if tagSet.insert(lower).inserted {
                    allTags.append(tag)
                }
            }

            entries[url] = IndexEntry(
                url: url,
                title: title,
                titleLower: title.lowercased(),
                tags: allTags,
                tagsLower: allTags.map { $0.lowercased() },
                body: body,
                bodyLower: body.lowercased(),
                modifiedAt: note.frontmatter.modifiedAt
            )
            if scheduleSave {
                lastBuildSource = .incremental
                scheduleCacheSave()
            }
        } catch {
            logger.warning("Could not index note at \(url.lastPathComponent): \(error.localizedDescription)")
            QuartzDiagnostics.warning(
                category: "VaultSearchIndex",
                "Could not index note at \(url.lastPathComponent): \(error.localizedDescription)"
            )
            entries.removeValue(forKey: url)
        }
    }

    /// Removes a note from the index.
    public func removeEntry(for url: URL) {
        entries.removeValue(forKey: url)
        lastBuildSource = .incremental
        scheduleCacheSave()
    }

    /// Returns all unique tags across the vault, mapped to the note URLs that contain them.
    /// Tags are lowercased for deduplication; the display form uses the first occurrence.
    public func allTags() -> [String: [URL]] {
        var tagMap: [String: [URL]] = [:]
        for entry in entries.values {
            for tag in entry.tags {
                tagMap[tag.lowercased(), default: []].append(entry.url)
            }
        }
        return tagMap
    }

    /// Returns the total number of indexed notes.
    public var entryCount: Int { entries.count }

    /// Source used for the most recent vault-wide build or incremental update.
    public var latestBuildSource: BuildSource? { lastBuildSource }

    /// Searches the index and returns results sorted by relevance.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results to return (default 50).
    public func search(query: String, limit: Int = 50) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let queryLower = query.lowercased()
        let queryTerms = queryLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var results: [SearchResult] = []

        for entry in entries.values {
            var score = 0
            var matchContext: String?

            // Title match (highest priority) – pre-computed lowercase
            if entry.titleLower.contains(queryLower) {
                score += 10
                if entry.titleLower == queryLower {
                    score += 5 // Exact match
                }
            }

            // Tag-Match – pre-computed lowercase
            for tagLower in entry.tagsLower {
                if tagLower.contains(queryLower) {
                    score += 5
                }
            }

            // Body-Match – pre-computed lowercase
            if entry.bodyLower.contains(queryLower) {
                score += 3
                matchContext = extractSearchContext(query: queryLower, in: entry.body)
            }

            // All search terms must be present (AND logic)
            if queryTerms.count > 1 {
                let allTermsFound = queryTerms.allSatisfy { term in
                    entry.titleLower.contains(term) ||
                    entry.tagsLower.contains { $0.contains(term) } ||
                    entry.bodyLower.contains(term)
                }
                if !allTermsFound {
                    score = 0
                }
            }

            if score > 0 {
                results.append(SearchResult(
                    noteURL: entry.url,
                    title: entry.title,
                    score: score,
                    context: matchContext,
                    matchedTags: zip(entry.tags, entry.tagsLower)
                        .filter { $0.1.contains(queryLower) }
                        .map(\.0)
                ))
            }
        }

        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Private

    private func buildIndex(fromPreloadedTree nodes: [FileNode], at root: URL, forceRebuild: Bool) async {
        let started = Date()
        vaultRoot = root
        let noteURLs = collectNoteURLs(from: nodes)
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .indexing,
            name: "searchIndexBuildStarted",
            reasonCode: forceRebuild ? "indexing.searchCacheRebuild" : "indexing.searchBuildStarted",
            vaultName: root.lastPathComponent,
            counts: ["notes": noteURLs.count]
        )
        let fingerprint = Self.computeFingerprint(for: noteURLs)

        if !forceRebuild,
           let cached = loadCache(vaultRoot: root),
           cached.fingerprint == fingerprint {
            entries = cached.entries
            lastBuildSource = .cache
            logger.info("Loaded search index from cache (\(cached.entries.count) entries)")
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .indexing,
                name: "searchIndexCacheHit",
                reasonCode: "indexing.searchCacheHit",
                vaultName: root.lastPathComponent,
                durationMs: Date().timeIntervalSince(started) * 1_000,
                counts: ["indexedNotes": cached.entries.count, "totalNotes": noteURLs.count],
                metadata: ["status.searchIndex": "cacheHit"]
            )
            SubsystemDiagnostics.updateState(
                subsystem: .indexing,
                values: [
                    "searchIndexStatus": "cacheHit",
                    "indexedNotes": String(cached.entries.count),
                    "totalNotes": String(noteURLs.count)
                ]
            )
            return
        }

        entries.removeAll(keepingCapacity: true)
        await indexNodes(nodes)
        lastBuildSource = .rebuild
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .indexing,
            name: "searchIndexRebuilt",
            reasonCode: "indexing.searchCacheRebuild",
            vaultName: root.lastPathComponent,
            durationMs: Date().timeIntervalSince(started) * 1_000,
            counts: ["indexedNotes": entries.count, "totalNotes": noteURLs.count],
            metadata: ["status.searchIndex": "rebuilt", "rebuildReason": forceRebuild ? "forced" : "cache missing or fingerprint mismatch"]
        )
        SubsystemDiagnostics.updateState(
            subsystem: .indexing,
            values: [
                "searchIndexStatus": "rebuilt",
                "indexedNotes": String(entries.count),
                "totalNotes": String(noteURLs.count)
            ]
        )
    }

    private func indexNodes(_ nodes: [FileNode]) async {
        let noteURLs = collectNoteURLs(from: nodes)
        let maxConcurrency = 16
        var completedSinceCheckpoint = 0

        await withTaskGroup(of: Void.self) { group in
            var pending = 0
            for url in noteURLs {
                if pending >= maxConcurrency {
                    await group.next()
                    pending -= 1
                    completedSinceCheckpoint += 1
                    if completedSinceCheckpoint >= Self.rebuildCheckpointInterval {
                        saveCache()
                        completedSinceCheckpoint = 0
                    }
                }
                group.addTask {
                    await self.updateEntry(for: url, scheduleSave: false)
                }
                pending += 1
            }
            while pending > 0 {
                await group.next()
                pending -= 1
                completedSinceCheckpoint += 1
                if completedSinceCheckpoint >= Self.rebuildCheckpointInterval {
                    saveCache()
                    completedSinceCheckpoint = 0
                }
            }
        }

        saveCache()
    }

    private func collectNoteURLs(from nodes: [FileNode]) -> [URL] {
        var urls: [URL] = []
        for node in nodes {
            if node.isNote {
                urls.append(node.url)
            }
            if let children = node.children {
                urls.append(contentsOf: collectNoteURLs(from: children))
            }
        }
        return urls
    }

    /// Extracts inline `#tag` patterns from markdown body text.
    /// Skips tags inside fenced code blocks (``` ... ```).
    private static func extractInlineTags(from body: String) -> [String] {
        // Strip fenced code blocks to avoid matching tags in code
        let codeBlockPattern = try! NSRegularExpression(pattern: #"```[\s\S]*?```"#, options: [])
        let mutableBody = NSMutableString(string: body)
        codeBlockPattern.replaceMatches(
            in: mutableBody,
            range: NSRange(location: 0, length: mutableBody.length),
            withTemplate: ""
        )
        let cleanBody = mutableBody as String

        let nsString = cleanBody as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = inlineTagRegex.matches(in: cleanBody, range: fullRange)

        var tags: [String] = []
        var seen = Set<String>()
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let tagRange = match.range(at: 1)
            let tag = nsString.substring(with: tagRange)
            let lower = tag.lowercased()
            if seen.insert(lower).inserted {
                tags.append(tag)
            }
        }
        return tags
    }

    /// Extracts the context around the first match in the body.
    private func extractSearchContext(query: String, in body: String) -> String {
        // Use case-insensitive search directly on body to avoid string index incompatibility
        guard let range = body.range(of: query, options: .caseInsensitive) else { return "" }

        let lineRange = body.lineRange(for: range)
        let context = String(body[lineRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        return String(context.prefix(120))
    }

    // MARK: - Cache Persistence

    /// Returns the cache file URL for the given vault root.
    private static func cacheURL(for vaultRoot: URL) -> URL {
        vaultRoot
            .appending(path: ".quartz")
            .appending(path: "search-index.json")
    }

    /// Computes a SHA256 fingerprint from note URLs, metadata, and note bytes.
    ///
    /// The content digest is intentionally part of the persisted-cache fingerprint.
    /// Sync and restore tools can preserve modification dates and file sizes while
    /// changing bytes; hashing the raw file stream prevents stale search bodies from
    /// being reused in that case without rebuilding the full parsed search index.
    public static func computeFingerprint(for noteURLs: [URL]) -> String {
        let fm = FileManager.default
        var pairs: [(String, TimeInterval, UInt64, String)] = []
        for url in noteURLs {
            let mtime: TimeInterval
            let fileSize: UInt64
            if let attrs = try? fm.attributesOfItem(atPath: url.path(percentEncoded: false)),
               let date = attrs[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
                if let size = attrs[.size] as? NSNumber {
                    fileSize = size.uint64Value
                } else if let size = attrs[.size] as? UInt64 {
                    fileSize = size
                } else if let size = attrs[.size] as? Int {
                    fileSize = UInt64(max(size, 0))
                } else {
                    fileSize = 0
                }
            } else {
                mtime = 0
                fileSize = 0
            }
            pairs.append((url.absoluteString, mtime, fileSize, contentDigest(for: url)))
        }
        pairs.sort { $0.0 < $1.0 }
        let data = pairs.flatMap { "\($0.0):\($0.1):\($0.2):\($0.3)".utf8 }
        let hash = SHA256.hash(data: Data(data))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func contentDigest(for url: URL) -> String {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var hasher = SHA256()
            while true {
                let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return "unreadable"
        }
    }

    /// Loads the cached index from disk.
    private func loadCache(vaultRoot: URL) -> CachedIndex? {
        let url = Self.cacheURL(for: vaultRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedIndex.self, from: data) else {
            return nil
        }
        return cached
    }

    /// Saves the current index to disk. Called on a debounced schedule.
    public func saveCache() {
        guard let root = vaultRoot else { return }
        let url = Self.cacheURL(for: root)
        let noteURLs = Array(entries.keys)
        let fingerprint = Self.computeFingerprint(for: noteURLs)
        let cached = CachedIndex(entries: entries, fingerprint: fingerprint)

        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cached)
            try data.write(to: url, options: .atomic)
            lastCacheSave = Date()
            logger.debug("Saved search index cache (\(self.entries.count) entries)")
        } catch {
            logger.warning("Failed to save search index cache: \(error.localizedDescription)")
            QuartzDiagnostics.warning(
                category: "VaultSearchIndex",
                "Failed to save search index cache: \(error.localizedDescription)"
            )
        }
    }

    /// Schedules a debounced cache save (max one per 5 seconds).
    private func scheduleCacheSave() {
        saveCacheTask?.cancel()
        let sinceLastSave = Date().timeIntervalSince(lastCacheSave)
        let delay: Duration = sinceLastSave < 5 ? .seconds(5 - sinceLastSave) : .milliseconds(100)

        saveCacheTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.saveCache()
        }
    }

    /// Forces a full rebuild on next `buildIndex` call by deleting the cache file.
    public func invalidateCache() {
        guard let root = vaultRoot else { return }
        let url = Self.cacheURL(for: root)
        try? FileManager.default.removeItem(at: url)
        logger.info("Invalidated search index cache")
    }
}

/// A search result with relevance score.
public struct SearchResult: Identifiable, Sendable {
    public let noteURL: URL
    public let title: String
    public let score: Int
    public let context: String?
    public let matchedTags: [String]
    public var id: URL { noteURL }

    public init(noteURL: URL, title: String, score: Int, context: String?, matchedTags: [String]) {
        self.noteURL = noteURL
        self.title = title
        self.score = score
        self.context = context
        self.matchedTags = matchedTags
    }
}
