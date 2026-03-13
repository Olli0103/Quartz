import Foundation

/// Extrahiert `#tag` Syntax aus Markdown-Text.
///
/// Erkennt Tags im Format `#tagname`, ignoriert Headings (`# `)
/// und Code-Blöcke. Tags dürfen Buchstaben, Zahlen, `-`, `_` und `/` enthalten.
public struct TagExtractor: Sendable {
    /// Pattern: `#` gefolgt von mindestens einem Wort-Zeichen, nicht am Zeilenanfang mit Leerzeichen danach (Heading)
    private static let tagPattern = /(?:^|(?<=\s))#([a-zA-Z\u{00C0}-\u{024F}0-9][a-zA-Z\u{00C0}-\u{024F}0-9_\/\-]*)/

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
    public func tagRanges(in text: String) -> [(range: Range<String.Index>, tag: String)] {
        var results: [(Range<String.Index>, String)] = []

        for match in text.matches(of: Self.tagPattern) {
            let tag = String(match.output.1).lowercased()
            results.append((match.range, tag))
        }

        return results
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
