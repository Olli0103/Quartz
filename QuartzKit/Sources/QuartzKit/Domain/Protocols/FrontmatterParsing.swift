import Foundation

/// Protocol for parsing and serializing YAML frontmatter.
public protocol FrontmatterParsing: Sendable {
    /// Extracts frontmatter and body from a raw Markdown string.
    func parse(from rawContent: String) throws -> (frontmatter: Frontmatter, body: String)

    /// Serializes frontmatter back to a YAML string.
    func serialize(_ frontmatter: Frontmatter) throws -> String
}
