import Foundation

/// Extracts `#tag` syntax from Markdown text.
///
/// Recognizes tags in the format `#tagname`, ignores headings (`# `)
/// and code blocks. Tags may contain letters, digits, `-`, `_` and `/`.
public struct TagExtractor: Sendable {
    /// Pattern: `#` followed by at least one Unicode letter or digit.
    /// Uses Unicode properties (\p{L}, \p{N}) to support CJK, Arabic, Cyrillic, etc.
    nonisolated(unsafe) private static let tagPattern = /(?:^|\s)#([\p{L}\p{N}][\p{L}\p{N}_\/\-]*)/

    public init() {}

    /// Extracts all unique tags from a Markdown string.
    public func extractTags(from markdown: String) -> [String] {
        // Remove code blocks before extracting tags
        let cleaned = removeCodeBlocks(from: markdown)

        var tags: [String] = []
        var seen: Set<String> = []

        for match in cleaned.matches(of: Self.tagPattern) {
            let tag = String(match.output.1).lowercased()
            if !seen.contains(tag) {
                seen.insert(tag)
                tags.append(tag)
            }
        }

        return tags
    }

    /// Returns the ranges of all tags in the text (for syntax highlighting).
    /// Strips code blocks first to avoid highlighting tags inside code.
    public func tagRanges(in text: String) -> [(range: Range<String.Index>, tag: String)] {
        // Build a set of code block ranges to skip
        let codeBlockRanges = codeBlockRanges(in: text)
        var results: [(Range<String.Index>, String)] = []

        for match in text.matches(of: Self.tagPattern) {
            // Skip tags that fall inside code blocks
            let isInCodeBlock = codeBlockRanges.contains { codeRange in
                codeRange.contains(match.range.lowerBound)
            }
            guard !isInCodeBlock else { continue }

            let tag = String(match.output.1).lowercased()
            results.append((match.range, tag))
        }

        return results
    }

    private func codeBlockRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        // Fenced code blocks
        let fencedPattern = /```[\s\S]*?```/
        for match in text.matches(of: fencedPattern) {
            ranges.append(match.range)
        }

        // Inline code
        let inlinePattern = /`[^`]+`/
        for match in text.matches(of: inlinePattern) {
            ranges.append(match.range)
        }

        return ranges
    }

    private func removeCodeBlocks(from text: String) -> String {
        // Remove fenced code blocks (```...```)
        let fencedPattern = /```[\s\S]*?```/
        var cleaned = text.replacing(fencedPattern, with: "")

        // Remove inline code (`...`)
        let inlinePattern = /`[^`]+`/
        cleaned = cleaned.replacing(inlinePattern, with: "")

        return cleaned
    }
}
