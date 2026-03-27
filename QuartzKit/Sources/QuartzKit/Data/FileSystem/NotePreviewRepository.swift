import Foundation
import os

/// Persistent cache for note preview data.
///
/// Stores `CachedNotePreview` entries in a JSON file at `.quartz/preview-cache.json`
/// inside the vault root. Loaded into memory on vault open for zero-cost reads.
///
/// Actor-isolated for thread safety — the indexer and UI can access it concurrently
/// without data races.
public actor NotePreviewRepository {

    /// Codable cache entry. Everything except `isFavorite` (resolved at query time).
    public struct CachedNotePreview: Codable, Sendable {
        public let url: URL
        public let title: String
        public let modifiedAt: Date
        public let fileSize: Int64
        public let snippet: String
        public let tags: [String]

        public init(
            url: URL,
            title: String,
            modifiedAt: Date,
            fileSize: Int64,
            snippet: String,
            tags: [String]
        ) {
            self.url = url
            self.title = title
            self.modifiedAt = modifiedAt
            self.fileSize = fileSize
            self.snippet = snippet
            self.tags = tags
        }
    }

    private var cache: [URL: CachedNotePreview] = [:]
    private let cacheFileURL: URL
    private let logger = Logger(subsystem: "com.quartz", category: "NotePreviewRepository")

    public init(vaultRoot: URL) {
        let quartzDir = vaultRoot.appending(path: ".quartz")
        self.cacheFileURL = quartzDir.appending(path: "preview-cache.json")
    }

    // MARK: - Persistence

    /// Loads the cache from disk. Called once on vault open.
    /// If the file doesn't exist or is corrupt, starts with an empty cache.
    public func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path(percentEncoded: false)) else {
            logger.info("No preview cache file found; starting fresh.")
            return
        }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let entries = try JSONDecoder().decode([CachedNotePreview].self, from: data)
            cache = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0) })
            logger.info("Loaded \(entries.count) preview cache entries.")
        } catch {
            logger.warning("Failed to load preview cache: \(error.localizedDescription). Starting fresh.")
            cache = [:]
        }
    }

    /// Persists the current cache to disk as JSON.
    public func saveCache() {
        do {
            let dir = cacheFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let entries = Array(cache.values)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            logger.warning("Failed to save preview cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Access

    /// Returns the cached preview for a URL if it exists AND the fingerprint matches.
    /// Returns `nil` if not cached or if the file has been modified since caching.
    public func cachedPreview(for url: URL, modifiedAt: Date, fileSize: Int64) -> CachedNotePreview? {
        guard let entry = cache[url] else { return nil }
        // Fingerprint check: skip re-index if modification date and size match
        guard entry.modifiedAt == modifiedAt, entry.fileSize == fileSize else { return nil }
        return entry
    }

    /// Stores or updates a preview entry.
    public func store(_ preview: CachedNotePreview) {
        cache[preview.url] = preview
    }

    /// Removes the entry for a deleted file.
    public func remove(for url: URL) {
        cache.removeValue(forKey: url)
    }

    /// Returns all cached previews (for bulk list population).
    public func allPreviews() -> [CachedNotePreview] {
        Array(cache.values)
    }

    /// Returns the number of cached entries.
    public var count: Int {
        cache.count
    }
}
