import Foundation

/// Extracts markdown headings (# ## ###) for outline/table of contents.
public struct HeadingExtractor: Sendable {
    /// nonisolated(unsafe) for static Regex — compiled once, immutable, thread-safe.
    nonisolated(unsafe) private static let headingPattern = /^(#{1,6})\s+(.+)$/

    public init() {}

    /// A heading with level (1–6), text, and position information.
    public struct Heading: Sendable, Identifiable {
        public let level: Int
        public let text: String
        /// Character range in the original string (for cursor navigation).
        public let range: Range<String.Index>
        /// UTF-16 offset of the heading start, stored for stable ID generation.
        private let utf16Offset: Int
        public var id: String { "\(level)-\(text)-\(utf16Offset)" }

        public init(level: Int, text: String, range: Range<String.Index>, in source: String) {
            self.level = level
            self.text = text
            self.range = range
            self.utf16Offset = source.utf16.distance(from: source.startIndex, to: range.lowerBound)
        }
    }

    /// Extracts headings from markdown, skipping code blocks.
    /// Includes character ranges for accessibility rotor navigation.
    public func extractHeadings(from markdown: String) -> [Heading] {
        var headings: [Heading] = []
        var inFencedBlock = false
        var fenceChar: Character?
        var currentIndex = markdown.startIndex

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let lineString = String(line)
            let trimmed = lineString.trimmingCharacters(in: .whitespaces)

            // Calculate the range for this line
            let lineStart = currentIndex
            let lineEnd: String.Index
            if let end = markdown.index(lineStart, offsetBy: line.count, limitedBy: markdown.endIndex) {
                lineEnd = end
            } else {
                lineEnd = markdown.endIndex
            }

            // Track fenced code blocks
            if trimmed.hasPrefix("```") {
                let char = trimmed.first
                if !inFencedBlock {
                    inFencedBlock = true
                    fenceChar = char
                } else if char == fenceChar {
                    inFencedBlock = false
                    fenceChar = nil
                }
                // Move to next line (skip newline character)
                if lineEnd < markdown.endIndex {
                    currentIndex = markdown.index(after: lineEnd)
                } else {
                    currentIndex = markdown.endIndex
                }
                continue
            }

            if !inFencedBlock {
                if let match = trimmed.prefixMatch(of: Self.headingPattern) {
                    let level = match.1.count
                    let text = String(match.2).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        headings.append(Heading(level: level, text: text, range: lineStart..<lineEnd, in: markdown))
                    }
                }
            }

            // Move to the next line (skip the newline character)
            if lineEnd < markdown.endIndex {
                currentIndex = markdown.index(after: lineEnd)
            } else {
                currentIndex = markdown.endIndex
            }
        }
        return headings
    }

    /// Legacy method for backwards compatibility - extracts headings without range info.
    public func extractHeadingsSimple(from markdown: String) -> [(level: Int, text: String)] {
        extractHeadings(from: markdown).map { ($0.level, $0.text) }
    }
}
