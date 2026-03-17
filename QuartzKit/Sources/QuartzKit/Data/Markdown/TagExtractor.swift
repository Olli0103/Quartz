import Foundation

/// Extrahiert `#tag` Syntax aus Markdown-Text.
///
/// Erkennt Tags im Format `#tagname`, ignoriert Headings (`# `)
/// und Code-Blöcke. Tags dürfen Buchstaben, Zahlen, `-`, `_` und `/` enthalten.
public struct TagExtractor: Sendable {
    /// Pattern: `#` gefolgt von mindestens einem Wort-Zeichen, nicht am Zeilenanfang mit Leerzeichen danach (Heading)
    private static let tagPattern = /(?:^|\s)#([a-zA-Z\u{00C0}-\u{024F}0-9][a-zA-Z\u{00C0}-\u{024F}0-9_\/\-]*)/

    public init() {}

    /// Extrahiert alle eindeutigen Tags aus einem Markdown-String.
    public func extractTags(from markdown: String) -> [String] {
        // Code-Blöcke entfernen bevor Tags extrahiert werden
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

    /// Gibt die Ranges aller Tags im Text zurück (für Syntax-Highlighting).
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
        // Entferne fenced code blocks (```...```)
        let fencedPattern = /```[\s\S]*?```/
        var cleaned = text.replacing(fencedPattern, with: "")

        // Entferne inline code (`...`)
        let inlinePattern = /`[^`]+`/
        cleaned = cleaned.replacing(inlinePattern, with: "")

        return cleaned
    }
}
