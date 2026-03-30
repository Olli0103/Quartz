import Foundation
import os

/// In-memory search index for the entire vault.
///
/// Built when opening the vault and incrementally updated
/// on changes. Searches frontmatter + body.
/// System-wide discovery uses ``QuartzSpotlightIndexer`` (Core Spotlight), not this type.
public actor VaultSearchIndex {
    /// Indexed entry for a note.
    private struct IndexEntry: Sendable {
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

    private var entries: [URL: IndexEntry] = [:]
    private let vaultProvider: any VaultProviding
    private let logger = Logger(subsystem: "com.quartz", category: "VaultSearchIndex")

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
    public func buildIndex(at root: URL) async throws {
        let tree = try await vaultProvider.loadFileTree(at: root)
        await indexNodes(tree)
    }

    /// Indexes notes from an already loaded file tree (avoids duplicate I/O).
    public func indexFromPreloadedTree(_ nodes: [FileNode]) async {
        await indexNodes(nodes)
    }

    /// Updates the index for a single note.
    public func updateEntry(for url: URL) async {
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
        } catch {
            logger.warning("Could not index note at \(url.lastPathComponent): \(error.localizedDescription)")
            entries.removeValue(forKey: url)
        }
    }

    /// Removes a note from the index.
    public func removeEntry(for url: URL) {
        entries.removeValue(forKey: url)
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

    private func indexNodes(_ nodes: [FileNode]) async {
        let noteURLs = collectNoteURLs(from: nodes)
        let maxConcurrency = 16

        await withTaskGroup(of: Void.self) { group in
            var pending = 0
            for url in noteURLs {
                if pending >= maxConcurrency {
                    await group.next()
                    pending -= 1
                }
                group.addTask {
                    await self.updateEntry(for: url)
                }
                pending += 1
            }
            await group.waitForAll()
        }
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
