import Foundation
import os

/// In-Memory Suchindex für den gesamten Vault.
///
/// Wird beim Öffnen des Vaults aufgebaut und bei Änderungen
/// inkrementell aktualisiert. Durchsucht Frontmatter + Body.
public actor VaultSearchIndex {
    /// Indizierter Eintrag für eine Notiz.
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

    /// Baut den kompletten Index für einen Vault auf.
    public func buildIndex(at root: URL) async throws {
        let tree = try await vaultProvider.loadFileTree(at: root)
        await indexNodes(tree)
    }

    /// Indexiert Notizen aus einem bereits geladenen Dateibaum (vermeidet doppeltes I/O).
    public func indexFromPreloadedTree(_ nodes: [FileNode]) async {
        await indexNodes(nodes)
    }

    /// Aktualisiert den Index für eine einzelne Notiz.
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

    /// Entfernt eine Notiz aus dem Index.
    public func removeEntry(for url: URL) {
        entries.removeValue(forKey: url)
    }

    /// Durchsucht den Index und gibt Ergebnisse zurück, sortiert nach Relevanz.
    public func search(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let queryLower = query.lowercased()
        let queryTerms = queryLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var results: [SearchResult] = []

        for entry in entries.values {
            var score = 0
            var matchContext: String?

            // Titel-Match (höchste Priorität) – pre-computed lowercase
            if entry.titleLower.contains(queryLower) {
                score += 10
                if entry.titleLower == queryLower {
                    score += 5 // Exakter Match
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

            // Alle Suchbegriffe müssen vorkommen (AND-Logik)
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

        return results.sorted { $0.score > $1.score }
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

    /// Extrahiert den Kontext um den ersten Treffer im Body.
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

/// Ein Suchergebnis mit Relevanz-Score.
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
