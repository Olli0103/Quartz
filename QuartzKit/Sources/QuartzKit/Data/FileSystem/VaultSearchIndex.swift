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
        let tags: [String]
        let tagsLower: [String]
        let body: String
        let bodyLower: String
        let modifiedAt: Date
    }

    private var entries: [URL: IndexEntry] = [:]
    private let vaultProvider: any VaultProviding
    private let logger = Logger(subsystem: "com.quartz", category: "VaultSearchIndex")

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
            let tags = note.frontmatter.tags
            let body = note.body
            entries[url] = IndexEntry(
                url: url,
                title: title,
                titleLower: title.lowercased(),
                tags: tags,
                tagsLower: tags.map { $0.lowercased() },
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
