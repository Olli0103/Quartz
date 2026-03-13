import Foundation

/// Repräsentiert ein Markdown-Dokument mit optionalem YAML-Frontmatter.
///
/// Hilfsstruct für das Einlesen und Schreiben von `.md` Dateien.
public struct MarkdownDocument: Sendable, Equatable {
    public var frontmatter: Frontmatter
    public var body: String

    public init(frontmatter: Frontmatter = Frontmatter(), body: String = "") {
        self.frontmatter = frontmatter
        self.body = body
    }

    /// Erstellt ein `MarkdownDocument` aus rohem Dateiinhalt.
    public init(rawContent: String, parser: some FrontmatterParsing = FrontmatterParser()) throws {
        let (fm, body) = try parser.parse(from: rawContent)
        self.frontmatter = fm
        self.body = body
    }

    /// Serialisiert das Dokument zurück zu einem rohen Markdown-String.
    public func toRawContent(serializer: some FrontmatterParsing = FrontmatterParser()) throws -> String {
        let yaml = try serializer.serialize(frontmatter)
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        return "---\n\(yaml)---\n\n\(body)"
    }
}
