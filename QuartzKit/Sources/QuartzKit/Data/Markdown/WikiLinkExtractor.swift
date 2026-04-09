import Foundation

/// Extracts `[[wiki-links]]` from Markdown text.
///
/// Supports:
/// - `[[Note Name]]` – simple link
/// - `[[Note Name|Display Text]]` – link with alias
/// - `[[Note Name#Heading]]` – link with anchor
public struct WikiLinkExtractor: Sendable {
    /// nonisolated(unsafe) for static Regex — compiled once, immutable, thread-safe.
    nonisolated(unsafe) private static let pattern: Regex<(Substring, Substring)> = /\[\[([^\]]+)\]\]/

    public init() {}

    /// Extracts all wiki links from a Markdown string.
    /// Skips links inside fenced code blocks and inline code.
    public func extractLinks(from markdown: String) -> [WikiLink] {
        let codeRanges = codeBlockRanges(in: markdown)
        var links: [WikiLink] = []

        for match in markdown.matches(of: Self.pattern) {
            // Skip links that fall inside code blocks
            let isInCode = codeRanges.contains { $0.contains(match.range.lowerBound) }
            guard !isInCode else { continue }

            let content = String(match.output.1)
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            links.append(WikiLink(raw: content))
        }

        return links
    }

    /// Returns the ranges of all wiki links in the text.
    public func linkRanges(in text: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        let codeRanges = codeBlockRanges(in: text)
        var results: [(Range<String.Index>, WikiLink)] = []

        for match in text.matches(of: Self.pattern) {
            let isInCode = codeRanges.contains { $0.contains(match.range.lowerBound) }
            guard !isInCode else { continue }

            let content = String(match.output.1)
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            results.append((match.range, WikiLink(raw: content)))
        }

        return results
    }

    // MARK: - Private

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
}

/// Represents a parsed wiki link.
public struct WikiLink: Sendable, Hashable, Identifiable {
    /// The complete raw content inside the `[[ ]]`.
    public let raw: String

    /// The target note name (without alias and anchor).
    public var target: String {
        var name = raw
        // Remove alias
        if let pipeIndex = name.firstIndex(of: "|") {
            name = String(name[name.startIndex..<pipeIndex])
        }
        // Remove anchor
        if let hashIndex = name.firstIndex(of: "#") {
            name = String(name[name.startIndex..<hashIndex])
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// The display text (alias or target name).
    public var displayText: String {
        if let pipeIndex = raw.firstIndex(of: "|") {
            return String(raw[raw.index(after: pipeIndex)...]).trimmingCharacters(in: .whitespaces)
        }
        return target
    }

    /// Optional heading anchor.
    public var heading: String? {
        guard let hashIndex = raw.firstIndex(of: "#") else { return nil }
        var anchor = String(raw[raw.index(after: hashIndex)...])
        // Remove alias after the anchor
        if let pipeIndex = anchor.firstIndex(of: "|") {
            anchor = String(anchor[anchor.startIndex..<pipeIndex])
        }
        return anchor.trimmingCharacters(in: .whitespaces)
    }

    public var id: String { raw }

    public init(raw: String) {
        self.raw = raw
    }
}
