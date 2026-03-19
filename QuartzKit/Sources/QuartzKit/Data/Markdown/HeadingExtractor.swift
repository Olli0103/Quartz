import Foundation

/// Extracts markdown headings (# ## ###) for outline/table of contents.
public struct HeadingExtractor: Sendable {
    nonisolated(unsafe) private static let headingPattern = /^(#{1,6})\s+(.+)$/

    public init() {}

    /// A heading with level (1–6) and text.
    public struct Heading: Sendable, Identifiable {
        public let level: Int
        public let text: String
        public var id: String { "\(level)-\(text)" }
    }

    /// Extracts headings from markdown, skipping code blocks.
    public func extractHeadings(from markdown: String) -> [Heading] {
        var headings: [Heading] = []
        var inFencedBlock = false
        var fenceChar: Character?
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)

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
                continue
            }
            guard !inFencedBlock else { continue }

            if let match = trimmed.prefixMatch(of: Self.headingPattern) {
                let level = match.1.count
                let text = String(match.2).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    headings.append(Heading(level: level, text: text))
                }
            }
        }
        return headings
    }
}
