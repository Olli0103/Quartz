import Foundation

/// Suggests wiki links by finding note titles mentioned in the current note's text.
///
/// Scans the vault's file tree for note names that appear as substrings
/// in the current note body (case-insensitive), skipping already-linked targets.
public struct LinkSuggestionService: Sendable {
    public init() {}

    public struct Suggestion: Identifiable, Sendable {
        public let noteURL: URL
        public let noteName: String
        public let matchRange: NSRange
        public let matchedText: String
        /// Short context excerpt around the match, for display in the inspector.
        public let matchContext: String
        public var id: String { "\(noteURL.absoluteString)#\(matchRange.location)-\(matchRange.length)" }
    }

    /// Suggests links for note content based on other notes in the vault.
    public func suggestLinks(
        for content: String,
        currentNoteURL: URL,
        allNotes: [FileNode],
        graphEdgeStore: GraphEdgeStore? = nil
    ) async -> [Suggestion] {
        let catalog = NoteReferenceCatalog(allNotes: allNotes)
        let explicitReferences = await catalog.resolvedExplicitReferences(
            in: content,
            sourceNoteURL: currentNoteURL,
            graphEdgeStore: graphEdgeStore
        )
        let linkedNoteURLs = Set(explicitReferences.map(\.targetNoteURL))
        let explicitLinkRanges = explicitReferences.compactMap(\.matchRange)
        let nsContent = content as NSString
        var suggestions: [Suggestion] = []
        var coveredRanges: [NSRange] = []
        var suggestedNoteURLs: Set<URL> = []

        let sortedNotes = catalog
            .linkInsertionSuggestions(matching: "", excluding: currentNoteURL)
            .filter { !linkedNoteURLs.contains($0.noteURL) }
            .sorted { a, b in
                (a.searchTerms.map(\.count).max() ?? a.noteName.count)
                    > (b.searchTerms.map(\.count).max() ?? b.noteName.count)
            }

        for note in sortedNotes {
            guard !suggestedNoteURLs.contains(note.noteURL) else { continue }

            let sortedTerms = note.searchTerms
                .filter { $0.count >= 3 }
                .sorted { $0.count > $1.count }

            for term in sortedTerms {
                var searchRange = NSRange(location: 0, length: nsContent.length)

                while searchRange.length > 0 {
                    let foundRange = nsContent.range(
                        of: term,
                        options: [.caseInsensitive],
                        range: searchRange
                    )
                    guard foundRange.location != NSNotFound,
                          foundRange.length > 0 else {
                        break
                    }

                    let overlapsExistingSuggestion = coveredRanges.contains { existing in
                        NSIntersectionRange(existing, foundRange).length > 0
                    }
                    let overlapsExplicitLink = explicitLinkRanges.contains { explicitRange in
                        NSIntersectionRange(explicitRange, foundRange).length > 0
                    }

                    if !overlapsExistingSuggestion
                        && !overlapsExplicitLink
                        && isWordBoundary(content: content, range: foundRange) {
                        let contextRange = extractContextRange(in: content, around: foundRange)
                        let context = String(content[contextRange])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")

                        suggestions.append(Suggestion(
                            noteURL: note.noteURL,
                            noteName: note.noteName,
                            matchRange: foundRange,
                            matchedText: nsContent.substring(with: foundRange),
                            matchContext: context
                        ))
                        coveredRanges.append(foundRange)
                        suggestedNoteURLs.insert(note.noteURL)
                        break
                    }

                    let nextLocation = foundRange.location + max(foundRange.length, 1)
                    guard nextLocation <= nsContent.length else { break }
                    searchRange = NSRange(location: nextLocation, length: nsContent.length - nextLocation)
                }
                if suggestedNoteURLs.contains(note.noteURL) {
                    break
                }
            }
        }

        return suggestions.sorted { a, b in
            a.matchRange.location < b.matchRange.location
        }
    }

    private func isWordBoundary(content: String, range: NSRange) -> Bool {
        let nsContent = content as NSString
        let beforeOK: Bool
        if range.location == 0 {
            beforeOK = true
        } else {
            let before = nsContent.substring(with: NSRange(location: range.location - 1, length: 1)).first ?? " "
            beforeOK = !before.isLetter && !before.isNumber
        }

        let afterOK: Bool
        if NSMaxRange(range) >= nsContent.length {
            afterOK = true
        } else {
            let after = nsContent.substring(with: NSRange(location: NSMaxRange(range), length: 1)).first ?? " "
            afterOK = !after.isLetter && !after.isNumber
        }

        return beforeOK && afterOK
    }

    /// Extracts a ~60-char context window around a match range for display.
    private func extractContextRange(in content: String, around range: NSRange) -> Range<String.Index> {
        let nsContent = content as NSString
        let clampedLocation = min(max(range.location, 0), nsContent.length)
        let clampedEnd = min(max(NSMaxRange(range), clampedLocation), nsContent.length)
        guard let lowerBound = Range(NSRange(location: clampedLocation, length: 0), in: content)?.lowerBound,
              let upperBound = Range(NSRange(location: clampedEnd, length: 0), in: content)?.lowerBound else {
            return content.startIndex..<content.startIndex
        }

        let contextChars = 30
        var start = lowerBound
        var end = upperBound

        for _ in 0..<contextChars {
            if start > content.startIndex {
                start = content.index(before: start)
            }
        }
        for _ in 0..<contextChars {
            if end < content.endIndex {
                end = content.index(after: end)
            }
        }

        return start..<end
    }

}
