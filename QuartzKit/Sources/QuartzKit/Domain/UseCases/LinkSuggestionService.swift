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
        public let matchRange: Range<String.Index>
        public var id: String { noteURL.absoluteString + "\(matchRange.lowerBound)" }
    }

    /// Suggests links for note content based on other notes in the vault.
    public func suggestLinks(
        for content: String,
        currentNoteURL: URL,
        allNotes: [FileNode]
    ) -> [Suggestion] {
        let notes = collectNotes(from: allNotes)
            .filter { $0.url != currentNoteURL }

        let existingLinks = extractExistingLinkTargets(from: content)
        let lowerContent = content.lowercased()
        var suggestions: [Suggestion] = []
        var coveredRanges: [Range<String.Index>] = []

        let sortedNotes = notes.sorted { a, b in
            a.name.count > b.name.count
        }

        for note in sortedNotes {
            let displayName = note.name.replacingOccurrences(of: ".md", with: "")
            guard displayName.count >= 3 else { continue }
            guard !existingLinks.contains(displayName.lowercased()) else { continue }

            let searchTerm = displayName.lowercased()
            var searchStart = lowerContent.startIndex

            while let range = lowerContent.range(of: searchTerm, range: searchStart..<lowerContent.endIndex) {
                let overlaps = coveredRanges.contains { existing in
                    existing.overlaps(range)
                }

                if !overlaps && isWordBoundary(content: lowerContent, range: range) {
                    suggestions.append(Suggestion(
                        noteURL: note.url,
                        noteName: displayName,
                        matchRange: range
                    ))
                    coveredRanges.append(range)
                }

                searchStart = range.upperBound
            }
        }

        return suggestions.sorted { a, b in
            a.matchRange.lowerBound < b.matchRange.lowerBound
        }
    }

    private func isWordBoundary(content: String, range: Range<String.Index>) -> Bool {
        let beforeOK: Bool
        if range.lowerBound == content.startIndex {
            beforeOK = true
        } else {
            let before = content[content.index(before: range.lowerBound)]
            beforeOK = !before.isLetter && !before.isNumber
        }

        let afterOK: Bool
        if range.upperBound == content.endIndex {
            afterOK = true
        } else {
            let after = content[range.upperBound]
            afterOK = !after.isLetter && !after.isNumber
        }

        return beforeOK && afterOK
    }

    private func extractExistingLinkTargets(from content: String) -> Set<String> {
        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        var targets = Set<String>()
        for match in matches {
            if match.numberOfRanges > 1 {
                let target = nsContent.substring(with: match.range(at: 1))
                    .components(separatedBy: "|").first?
                    .components(separatedBy: "#").first ?? ""
                targets.insert(target.lowercased())
            }
        }
        return targets
    }

    private func collectNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote { result.append(node) }
            if let children = node.children {
                result.append(contentsOf: collectNotes(from: children))
            }
        }
        return result
    }
}
