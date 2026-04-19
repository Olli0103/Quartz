import Foundation

/// Shared interpretation of note references for editor suggestions, backlinks,
/// and explicit wiki-link resolution.
///
/// This keeps linked references and unlinked mentions on one explicit reference model:
/// each textual reference resolves to a canonical note URL before the caller
/// decides whether it is linked, unlinked, or navigable.
public struct NoteReferenceCatalog: Sendable {
    public struct NoteReference: Identifiable, Sendable, Equatable {
        public let noteURL: URL
        public let noteName: String
        public let searchTerms: [String]

        public var id: URL { noteURL }

        public var insertableTarget: String {
            noteName
        }
    }

    private let notes: [NoteReference]
    private let notesByURL: [URL: NoteReference]
    private let fallbackTargets: [String: URL]

    public init(allNotes: [FileNode]) {
        let collected = Self.collectNotes(from: allNotes).map(Self.makeReference(for:))
        let deduplicated = Self.deduplicateReferences(collected)
        self.notes = deduplicated.sorted {
            $0.noteName.localizedCaseInsensitiveCompare($1.noteName) == .orderedAscending
        }
        self.notesByURL = Dictionary(uniqueKeysWithValues: notes.map { ($0.noteURL, $0) })
        self.fallbackTargets = Self.buildFallbackTargets(from: notes)
    }

    public var allNoteURLs: [URL] {
        notes.map(\.noteURL)
    }

    public func suggestion(for noteURL: URL) -> NoteReference? {
        notesByURL[CanonicalNoteIdentity.canonicalFileURL(for: noteURL)]
    }

    public func linkInsertionSuggestions(
        matching query: String,
        excluding currentNoteURL: URL?
    ) -> [NoteReference] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = Self.normalize(trimmedQuery)

        let filtered = notes.filter { reference in
            guard reference.noteURL != currentNoteURL else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return reference.searchTerms.contains {
                let normalizedTerm = Self.normalize($0)
                return normalizedTerm.hasPrefix(normalizedQuery) || normalizedTerm.contains(normalizedQuery)
            }
        }

        return filtered.sorted { lhs, rhs in
            let lhsScore = matchScore(for: lhs, query: normalizedQuery)
            let rhsScore = matchScore(for: rhs, query: normalizedQuery)
            if lhsScore == rhsScore {
                return lhs.noteName.localizedCaseInsensitiveCompare(rhs.noteName) == .orderedAscending
            }
            return lhsScore > rhsScore
        }
    }

    public func resolvedExplicitLinkTargets(
        in content: String,
        sourceNoteURL: URL,
        graphEdgeStore: GraphEdgeStore?
    ) async -> Set<URL> {
        Set(await resolvedExplicitReferences(
            in: content,
            sourceNoteURL: sourceNoteURL,
            graphEdgeStore: graphEdgeStore
        ).map(\.targetNoteURL))
    }

    public func resolvedExplicitReferences(
        in content: String,
        sourceNoteURL: URL,
        graphEdgeStore: GraphEdgeStore?,
        using extractor: WikiLinkExtractor = WikiLinkExtractor()
    ) async -> [ExplicitNoteReference] {
        let canonicalSourceNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceNoteURL)
        let nsContent = content as NSString
        var references: [ExplicitNoteReference] = []
        for (range, link) in extractor.linkRanges(in: content) {
            let nsRange = NSRange(range, in: content)
            guard let resolvedURL = await resolveExplicitLinkTarget(link.target, graphEdgeStore: graphEdgeStore) else {
                continue
            }

            let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: resolvedURL)
            guard let noteReference = noteReference(for: canonicalURL) else { continue }

            let lineRange = trimmedLineRange(containing: nsRange, in: nsContent)
            let context = nsContent.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")

            references.append(
                ExplicitNoteReference(
                    sourceNoteURL: canonicalSourceNoteURL,
                    targetNoteURL: noteReference.noteURL,
                    targetNoteName: noteReference.noteName,
                    insertableTarget: noteReference.insertableTarget,
                    rawLinkText: link.raw,
                    rawTargetText: link.target,
                    displayText: link.displayText,
                    headingFragment: link.heading,
                    matchRange: nsRange,
                    lineRange: lineRange,
                    context: context
                )
            )
        }

        return references.sorted { lhs, rhs in
            let lhsLocation = lhs.matchRange?.location ?? Int.max
            let rhsLocation = rhs.matchRange?.location ?? Int.max
            if lhsLocation == rhsLocation {
                return lhs.targetNoteName.localizedCaseInsensitiveCompare(rhs.targetNoteName) == .orderedAscending
            }
            return lhsLocation < rhsLocation
        }
    }

    public func resolveExplicitLinkTarget(
        _ target: String,
        graphEdgeStore: GraphEdgeStore?
    ) async -> URL? {
        if let resolved = fallbackResolve(target) {
            return resolved
        }
        if let graphEdgeStore,
           let resolved = await graphEdgeStore.resolveTitle(target) {
            return resolved
        }
        return nil
    }

    public func noteReference(for url: URL) -> NoteReference? {
        notesByURL[CanonicalNoteIdentity.canonicalFileURL(for: url)]
    }

    private func fallbackResolve(_ target: String) -> URL? {
        let normalizedTarget = Self.normalize(target)
        if let exact = fallbackTargets[normalizedTarget] {
            return exact
        }

        let hyphenVariant = normalizedTarget.replacingOccurrences(of: "-", with: " ")
        if hyphenVariant != normalizedTarget, let resolved = fallbackTargets[hyphenVariant] {
            return resolved
        }

        return nil
    }

    private func matchScore(for reference: NoteReference, query: String) -> Int {
        guard !query.isEmpty else { return 0 }

        for term in reference.searchTerms {
            let normalized = Self.normalize(term)
            if normalized == query { return 3 }
            if normalized.hasPrefix(query) { return 2 }
            if normalized.contains(query) { return 1 }
        }

        return 0
    }

    private static func collectNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote {
                result.append(node)
            }
            if let children = node.children {
                result.append(contentsOf: collectNotes(from: children))
            }
        }
        return result
    }

    private static func makeReference(for note: FileNode) -> NoteReference {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: note.url)
        let displayName = note.name.replacingOccurrences(of: ".md", with: "")
        var searchTerms: [String] = [displayName]
        if let title = note.frontmatter?.title, !title.isEmpty {
            searchTerms.append(title)
        }
        if let aliases = note.frontmatter?.aliases {
            searchTerms.append(contentsOf: aliases.filter { !$0.isEmpty })
        }
        searchTerms = Array(NSOrderedSet(array: searchTerms)) as? [String] ?? searchTerms

        return NoteReference(
            noteURL: canonicalURL,
            noteName: displayName,
            searchTerms: searchTerms
        )
    }

    private static func deduplicateReferences(_ references: [NoteReference]) -> [NoteReference] {
        var mergedByURL: [URL: NoteReference] = [:]

        for reference in references {
            let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: reference.noteURL)
            if let existing = mergedByURL[canonicalURL] {
                let mergedTerms = Array(NSOrderedSet(array: existing.searchTerms + reference.searchTerms)) as? [String]
                    ?? (existing.searchTerms + reference.searchTerms)
                mergedByURL[canonicalURL] = NoteReference(
                    noteURL: canonicalURL,
                    noteName: existing.noteName,
                    searchTerms: mergedTerms
                )
            } else {
                mergedByURL[canonicalURL] = NoteReference(
                    noteURL: canonicalURL,
                    noteName: reference.noteName,
                    searchTerms: reference.searchTerms
                )
            }
        }

        return Array(mergedByURL.values)
    }

    private static func buildFallbackTargets(from notes: [NoteReference]) -> [String: URL] {
        var lookup: [String: URL] = [:]

        for note in notes {
            for term in note.searchTerms {
                let normalized = normalize(term)
                if lookup[normalized] == nil {
                    lookup[normalized] = note.noteURL
                }
            }

            let pathWithoutExtension = note.noteURL.deletingPathExtension().path(percentEncoded: false)
            let components = pathWithoutExtension.split(separator: "/").map(String.init)
            for startIndex in 0..<components.count {
                let suffix = components[startIndex...].joined(separator: "/")
                let normalizedSuffix = normalize(suffix)
                if lookup[normalizedSuffix] == nil {
                    lookup[normalizedSuffix] = note.noteURL
                }
            }
        }

        return lookup
    }

    private static func normalize(_ text: String) -> String {
        GraphIdentityResolver.normalize(text)
    }

    private func trimmedLineRange(containing range: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let safeLocation = min(max(range.location, 0), max(text.length - 1, 0))
        let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))

        var trimmedLength = lineRange.length
        while trimmedLength > 0 {
            let scalar = text.character(at: lineRange.location + trimmedLength - 1)
            if scalar == 10 || scalar == 13 {
                trimmedLength -= 1
            } else {
                break
            }
        }

        return NSRange(location: lineRange.location, length: trimmedLength)
    }
}
