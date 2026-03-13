import Foundation

/// In-Memory Suchindex für den gesamten Vault.
///
/// Wird beim Öffnen des Vaults aufgebaut und bei Änderungen
/// inkrementell aktualisiert. Durchsucht Frontmatter + Body.
public actor VaultSearchIndex {
    /// Indizierter Eintrag für eine Notiz.
    private struct IndexEntry: Sendable {
        let url: URL
        let title: String
        let tags: [String]
        let body: String
        let modifiedAt: Date
    }

    private var entries: [URL: IndexEntry] = [:]
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Baut den kompletten Index für einen Vault auf.
    public func buildIndex(at root: URL) async {
        do {
            let tree = try await vaultProvider.loadFileTree(at: root)
            await indexNodes(tree)
        } catch {
            // Index-Aufbau fehlgeschlagen, leerer Index
        }
    }

    /// Aktualisiert den Index für eine einzelne Notiz.
    public func updateEntry(for url: URL) async {
        do {
            let note = try await vaultProvider.readNote(at: url)
            entries[url] = IndexEntry(
                url: url,
                title: note.displayName,
                tags: note.frontmatter.tags,
                body: note.body,
                modifiedAt: note.frontmatter.modifiedAt
            )
        } catch {
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

            // Titel-Match (höchste Priorität)
            if entry.title.lowercased().contains(queryLower) {
                score += 10
                if entry.title.lowercased() == queryLower {
                    score += 5 // Exakter Match
                }
            }

            // Tag-Match
            for tag in entry.tags {
                if tag.lowercased().contains(queryLower) {
                    score += 5
                }
            }

            // Body-Match
            let bodyLower = entry.body.lowercased()
            if bodyLower.contains(queryLower) {
                score += 3
                matchContext = extractSearchContext(query: queryLower, in: entry.body)
            }

            // Alle Suchbegriffe müssen vorkommen (AND-Logik)
            if queryTerms.count > 1 {
                let allTermsFound = queryTerms.allSatisfy { term in
                    entry.title.lowercased().contains(term) ||
                    entry.tags.contains { $0.lowercased().contains(term) } ||
                    bodyLower.contains(term)
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
                    matchedTags: entry.tags.filter { $0.lowercased().contains(queryLower) }
                ))
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Private

    private func indexNodes(_ nodes: [FileNode]) async {
        for node in nodes {
            if node.isNote {
                await updateEntry(for: node.url)
            }
            if let children = node.children {
                await indexNodes(children)
            }
        }
    }

    /// Extrahiert den Kontext um den ersten Treffer im Body.
    private func extractSearchContext(query: String, in body: String) -> String {
        let bodyLower = body.lowercased()
        guard let range = bodyLower.range(of: query) else { return "" }

        let matchStart = body.distance(from: body.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - 40)
        let contextEnd = min(body.count, matchStart + query.count + 60)

        let startIndex = body.index(body.startIndex, offsetBy: contextStart)
        let endIndex = body.index(body.startIndex, offsetBy: contextEnd)

        var context = String(body[startIndex..<endIndex])
            .replacingOccurrences(of: "\n", with: " ")

        if contextStart > 0 { context = "…" + context }
        if contextEnd < body.count { context += "…" }

        return context
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
