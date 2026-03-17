import Foundation

/// Extrahiert `[[wiki-links]]` aus Markdown-Text.
///
/// Unterstützt:
/// - `[[Note Name]]` – einfacher Link
/// - `[[Note Name|Display Text]]` – Link mit Alias
/// - `[[Note Name#Heading]]` – Link mit Anker
public struct WikiLinkExtractor: Sendable {
    nonisolated(unsafe) private static let pattern = /\[\[([^\]]+)\]\]/

    public init() {}

    /// Extrahiert alle Wiki-Links aus einem Markdown-String.
    public func extractLinks(from markdown: String) -> [WikiLink] {
        var links: [WikiLink] = []

        for match in markdown.matches(of: Self.pattern) {
            let content = String(match.output.1)
            links.append(WikiLink(raw: content))
        }

        return links
    }

    /// Gibt die Ranges aller Wiki-Links im Text zurück.
    public func linkRanges(in text: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        var results: [(Range<String.Index>, WikiLink)] = []

        for match in text.matches(of: Self.pattern) {
            let content = String(match.output.1)
            results.append((match.range, WikiLink(raw: content)))
        }

        return results
    }
}

/// Repräsentiert einen geparsten Wiki-Link.
public struct WikiLink: Sendable, Hashable, Identifiable {
    /// Der vollständige Rohinhalt innerhalb der `[[ ]]`.
    public let raw: String

    /// Der Ziel-Notizenname (ohne Alias und Anker).
    public var target: String {
        var name = raw
        // Alias entfernen
        if let pipeIndex = name.firstIndex(of: "|") {
            name = String(name[name.startIndex..<pipeIndex])
        }
        // Anker entfernen
        if let hashIndex = name.firstIndex(of: "#") {
            name = String(name[name.startIndex..<hashIndex])
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Der Anzeigetext (Alias oder Zielname).
    public var displayText: String {
        if let pipeIndex = raw.firstIndex(of: "|") {
            return String(raw[raw.index(after: pipeIndex)...]).trimmingCharacters(in: .whitespaces)
        }
        return target
    }

    /// Optionaler Heading-Anker.
    public var heading: String? {
        guard let hashIndex = raw.firstIndex(of: "#") else { return nil }
        var anchor = String(raw[raw.index(after: hashIndex)...])
        // Alias nach dem Anker entfernen
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
