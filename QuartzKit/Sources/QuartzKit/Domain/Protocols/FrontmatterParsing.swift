import Foundation

/// Protocol für das Parsen und Serialisieren von YAML-Frontmatter.
public protocol FrontmatterParsing: Sendable {
    /// Extrahiert Frontmatter und Body aus einem rohen Markdown-String.
    func parse(from rawContent: String) throws -> (frontmatter: Frontmatter, body: String)

    /// Serialisiert Frontmatter zurück zu einem YAML-String.
    func serialize(_ frontmatter: Frontmatter) throws -> String
}
