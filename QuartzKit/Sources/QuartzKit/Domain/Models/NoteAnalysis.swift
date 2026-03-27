import Foundation

/// Document statistics for the inspector panel.
public struct NoteStats: Sendable, Equatable {
    public let wordCount: Int
    public let characterCount: Int
    /// Estimated reading time in minutes (rounded up, 238 WPM average).
    public let readingTimeMinutes: Int

    public static let empty = NoteStats(wordCount: 0, characterCount: 0, readingTimeMinutes: 0)

    public init(wordCount: Int, characterCount: Int, readingTimeMinutes: Int) {
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.readingTimeMinutes = readingTimeMinutes
    }
}

/// A heading extracted from markdown for the Table of Contents.
public struct HeadingItem: Identifiable, Sendable {
    /// Stable identity from HeadingExtractor.
    public let id: String
    /// Heading level (1-6).
    public let level: Int
    /// Heading text without `#` markers.
    public let text: String
    /// UTF-16 character offset in the document for scroll-to navigation.
    public let characterOffset: Int

    public init(id: String, level: Int, text: String, characterOffset: Int) {
        self.id = id
        self.level = level
        self.text = text
        self.characterOffset = characterOffset
    }
}

/// Combined analysis result from `MarkdownAnalysisService`.
public struct NoteAnalysis: Sendable {
    public let headings: [HeadingItem]
    public let stats: NoteStats

    public static let empty = NoteAnalysis(headings: [], stats: .empty)

    public init(headings: [HeadingItem], stats: NoteStats) {
        self.headings = headings
        self.stats = stats
    }
}
