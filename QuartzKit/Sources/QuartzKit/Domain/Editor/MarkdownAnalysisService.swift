import Foundation

/// Background actor that extracts structural information from markdown text.
///
/// Produces `NoteAnalysis` containing headings (for ToC) and document statistics
/// (word count, character count, reading time). Runs on a background thread
/// to keep the main thread free for editing.
///
/// Separate from `MarkdownASTHighlighter` which produces `HighlightSpan`s for rendering.
/// This service produces semantic data for the inspector UI.
public actor MarkdownAnalysisService {
    private let headingExtractor = HeadingExtractor()

    /// Average adult silent reading speed (Brysbaert, 2019).
    private static let wordsPerMinute = 238

    public init() {}

    /// Analyzes markdown text and returns headings + stats.
    /// Safe to call from any thread — runs on this actor's executor.
    public func analyze(_ text: String) -> NoteAnalysis {
        let headings = extractHeadingItems(from: text)
        let stats = computeStats(from: text)
        return NoteAnalysis(headings: headings, stats: stats)
    }

    // MARK: - Headings

    private func extractHeadingItems(from text: String) -> [HeadingItem] {
        let rawHeadings = headingExtractor.extractHeadings(from: text)
        return rawHeadings.map { heading in
            let utf16Offset = text.utf16.distance(
                from: text.startIndex,
                to: heading.range.lowerBound
            )
            return HeadingItem(
                id: heading.id,
                level: heading.level,
                text: heading.text,
                characterOffset: utf16Offset
            )
        }
    }

    // MARK: - Stats

    private func computeStats(from text: String) -> NoteStats {
        let wordCount = countWords(in: text)
        let characterCount = text.count
        let readingTime = max(1, Int(ceil(Double(wordCount) / Double(Self.wordsPerMinute))))

        return NoteStats(
            wordCount: wordCount,
            characterCount: characterCount,
            readingTimeMinutes: readingTime
        )
    }

    private func countWords(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
