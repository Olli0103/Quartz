import Foundation

/// Represents a Markdown document with optional YAML frontmatter.
///
/// Helper struct for reading and writing `.md` files.
public struct MarkdownDocument: Sendable, Equatable {
    public var frontmatter: Frontmatter
    public var body: String

    public init(frontmatter: Frontmatter = Frontmatter(), body: String = "") {
        self.frontmatter = frontmatter
        self.body = body
    }

    /// Creates a `MarkdownDocument` from raw file content.
    public init(rawContent: String, parser: some FrontmatterParsing = FrontmatterParser()) throws {
        let (fm, body) = try parser.parse(from: rawContent)
        self.frontmatter = fm
        self.body = body
    }

    /// Serializes the document back to a raw Markdown string.
    public func toRawContent(serializer: some FrontmatterParsing = FrontmatterParser()) throws -> String {
        let yaml = try serializer.serialize(frontmatter)
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        return "---\n\(yaml)---\n\n\(body)"
    }
}
