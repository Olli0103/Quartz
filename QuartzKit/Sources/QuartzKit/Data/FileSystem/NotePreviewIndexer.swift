import Foundation
import os

/// Asynchronous indexer that builds and maintains the note preview cache.
///
/// Reads only a bounded prefix (8KB by default) of each markdown file using `FileHandle`
/// for efficient partial reads. Extracts title, tags, and a 2-3 line plain text snippet
/// without loading full file contents.
///
/// Follows the same concurrency pattern as `VaultSearchIndex`: `TaskGroup` with
/// bounded concurrency (16 parallel tasks), cooperative cancellation, and fingerprint-based
/// skip logic for unchanged files.
///
/// **Integration:** Sits alongside `VaultSearchIndex`, `QuartzSpotlightIndexer`, and
/// `VectorEmbeddingService`. Each indexer serves a different purpose; this one is the
/// fastest because it reads the least data.
public actor NotePreviewIndexer {

    /// Maximum bytes to read from the beginning of a file.
    /// 8KB covers typical frontmatter (200-500 bytes) + first 3-5 paragraphs.
    private static let maxPrefixBytes = 8192

    /// Maximum concurrent file reads during batch indexing.
    private static let maxConcurrency = 16

    private let repository: NotePreviewRepository
    private let frontmatterParser: any FrontmatterParsing
    private let vaultRoot: URL
    private let logger = Logger(subsystem: "com.quartz", category: "NotePreviewIndexer")

    public init(
        vaultRoot: URL,
        repository: NotePreviewRepository,
        frontmatterParser: any FrontmatterParsing
    ) {
        self.vaultRoot = vaultRoot
        self.repository = repository
        self.frontmatterParser = frontmatterParser
    }

    // MARK: - Batch Indexing

    /// Full reindex from a pre-loaded file tree. Called on vault open.
    ///
    /// Uses `TaskGroup` with bounded concurrency to process files in parallel
    /// without overwhelming the system. Unchanged files (matching fingerprint)
    /// are skipped entirely.
    public func indexAll(from tree: [FileNode]) async {
        let noteURLs = Self.collectNoteURLs(from: tree)
        guard !noteURLs.isEmpty else { return }

        logger.info("Indexing \(noteURLs.count) notes for preview cache…")

        var indexed = 0
        var skipped = 0

        await withTaskGroup(of: Bool.self) { group in
            var pending = 0
            for url in noteURLs {
                if pending >= Self.maxConcurrency {
                    if let wasIndexed = await group.next() {
                        if wasIndexed { indexed += 1 } else { skipped += 1 }
                    }
                    pending -= 1
                }
                group.addTask {
                    await self.indexFileIfNeeded(at: url)
                }
                pending += 1
            }
            for await wasIndexed in group {
                if wasIndexed { indexed += 1 } else { skipped += 1 }
            }
        }

        // Persist after full reindex
        await repository.saveCache()
        logger.info("Preview indexing complete: \(indexed) indexed, \(skipped) skipped (unchanged).")
    }

    // MARK: - Incremental Updates

    /// Incrementally index a single file (called from FileWatcher events).
    /// Always re-extracts (no fingerprint skip) since we know the file changed.
    public func indexFile(at url: URL) async {
        guard url.pathExtension.lowercased() == "md" else { return }
        await extractAndStore(at: url)
        await repository.saveCache()
    }

    /// Remove a file from the cache (called on deletion).
    public func removeFile(at url: URL) async {
        await repository.remove(for: url)
        await repository.saveCache()
    }

    // MARK: - Core Extraction

    /// Checks fingerprint and extracts if needed. Returns `true` if extraction happened.
    private func indexFileIfNeeded(at url: URL) async -> Bool {
        guard let (modifiedAt, fileSize) = Self.readFileMetadata(at: url) else { return false }

        // Fingerprint check: skip if unchanged
        if await repository.cachedPreview(for: url, modifiedAt: modifiedAt, fileSize: fileSize) != nil {
            return false
        }

        await extractAndStore(at: url, modifiedAt: modifiedAt, fileSize: fileSize)
        return true
    }

    /// Reads the bounded prefix, extracts metadata + snippet, and stores in the repository.
    private func extractAndStore(at url: URL, modifiedAt: Date? = nil, fileSize: Int64? = nil) async {
        let meta: (Date, Int64)
        if let m = modifiedAt, let s = fileSize {
            meta = (m, s)
        } else if let m = Self.readFileMetadata(at: url) {
            meta = m
        } else {
            return
        }

        guard let prefix = Self.readPrefix(at: url) else { return }

        // Extract frontmatter (title + tags) using the existing parser
        let frontmatter: Frontmatter
        let body: String
        do {
            let result = try frontmatterParser.parse(from: prefix)
            frontmatter = result.frontmatter
            body = result.body
        } catch {
            // If frontmatter parsing fails, treat entire prefix as body
            frontmatter = Frontmatter()
            body = prefix
        }

        // Resolve title: frontmatter → first H1 → filename
        let title = resolveTitle(
            frontmatterTitle: frontmatter.title,
            body: body,
            fileURL: url
        )

        // Extract plain-text snippet from body
        let snippet = SnippetExtractor.snippetFromBody(body)

        let preview = NotePreviewRepository.CachedNotePreview(
            url: url,
            title: title,
            modifiedAt: meta.0,
            fileSize: meta.1,
            snippet: snippet,
            tags: frontmatter.tags
        )
        await repository.store(preview)
    }

    // MARK: - Title Resolution

    /// Priority: frontmatter title → first H1 heading → filename sans extension.
    private func resolveTitle(frontmatterTitle: String?, body: String, fileURL: URL) -> String {
        // 1. Frontmatter title
        if let title = frontmatterTitle, !title.isEmpty {
            return title
        }
        // 2. First H1 heading in body
        if let heading = SnippetExtractor.extractFirstHeading(from: body) {
            return heading
        }
        // 3. Filename without extension
        return fileURL.deletingPathExtension().lastPathComponent
    }

    // MARK: - Bounded File Read

    /// Reads at most `maxPrefixBytes` from the beginning of a file.
    ///
    /// Uses `FileHandle` for efficient partial read — no full file load into memory.
    /// For a 500-note vault, this reads ~4MB total instead of potentially hundreds of MB.
    ///
    /// Handles UTF-8 multibyte edge case: if `String(data:encoding:)` returns nil
    /// (truncated mid-character), retries with 512 fewer bytes.
    private static func readPrefix(at url: URL, maxBytes: Int = maxPrefixBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }

        // Try full prefix first
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        // If it fails (truncated mid-character), try slightly shorter
        let fallbackCount = max(data.count - 512, 0)
        if fallbackCount > 0, let text = String(data: data.prefix(fallbackCount), encoding: .utf8) {
            return text
        }
        return nil
    }

    // MARK: - File Metadata

    /// Reads modification date and file size from URL resource values.
    private static func readFileMetadata(at url: URL) -> (Date, Int64)? {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ]) else { return nil }
        guard let modDate = values.contentModificationDate,
              let size = values.fileSize else { return nil }
        return (modDate, Int64(size))
    }

    // MARK: - Tree Traversal

    /// Recursively collects all note URLs from a file tree.
    private static func collectNoteURLs(from nodes: [FileNode]) -> [URL] {
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
}
