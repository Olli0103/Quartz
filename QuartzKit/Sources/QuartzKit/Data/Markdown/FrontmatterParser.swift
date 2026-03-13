import Foundation

/// Leichtgewichtiger YAML-Frontmatter-Parser.
///
/// Erkennt den `---` Delimiter, extrahiert das YAML und parsed es
/// zu einem `Frontmatter`-Objekt. Round-trip-fähig: der Body bleibt unverändert.
public struct FrontmatterParser: FrontmatterParsing, Sendable {
    public init() {}

    // MARK: - FrontmatterParsing

    public func parse(from rawContent: String) throws -> (frontmatter: Frontmatter, body: String) {
        guard rawContent.hasPrefix("---\n") || rawContent.hasPrefix("---\r\n") else {
            return (Frontmatter(), rawContent)
        }

        let scanner = rawContent.dropFirst(4) // Skip opening "---\n"
        guard let closingRange = scanner.range(of: "\n---\n") ?? scanner.range(of: "\n---\r\n") else {
            return (Frontmatter(), rawContent)
        }

        let yamlString = String(scanner[scanner.startIndex..<closingRange.lowerBound])
        let body = String(scanner[closingRange.upperBound...]).trimmingLeadingNewlines()

        let frontmatter = try parseYAML(yamlString)
        return (frontmatter, body)
    }

    public func serialize(_ frontmatter: Frontmatter) throws -> String {
        var lines: [String] = []

        if let title = frontmatter.title {
            lines.append("title: \(quoteIfNeeded(title))")
        }
        if !frontmatter.tags.isEmpty {
            let tagList = frontmatter.tags.map { quoteIfNeeded($0) }.joined(separator: ", ")
            lines.append("tags: [\(tagList)]")
        }
        if !frontmatter.aliases.isEmpty {
            let aliasList = frontmatter.aliases.map { quoteIfNeeded($0) }.joined(separator: ", ")
            lines.append("aliases: [\(aliasList)]")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lines.append("created: \(formatter.string(from: frontmatter.createdAt))")
        lines.append("modified: \(formatter.string(from: frontmatter.modifiedAt))")

        if let template = frontmatter.template {
            lines.append("template: \(quoteIfNeeded(template))")
        }
        if let ocrText = frontmatter.ocrText, !ocrText.isEmpty {
            lines.append("ocr_text: \(quoteIfNeeded(ocrText))")
        }
        if frontmatter.isEncrypted {
            lines.append("encrypted: true")
        }

        for (key, value) in frontmatter.customFields.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(quoteIfNeeded(value))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private YAML Parsing

    private func parseYAML(_ yaml: String) throws -> Frontmatter {
        var frontmatter = Frontmatter()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Split on first ": " to preserve colons in values (e.g. URLs)
            let key: String
            let rawValue: String
            if let separatorRange = trimmed.range(of: ": ") {
                key = String(trimmed[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                rawValue = String(trimmed[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let colonIndex = trimmed.firstIndex(of: ":") {
                key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            } else {
                continue
            }

            switch key {
            case "title":
                frontmatter.title = unquote(rawValue)
            case "tags":
                frontmatter.tags = parseInlineArray(rawValue)
            case "aliases":
                frontmatter.aliases = parseInlineArray(rawValue)
            case "created":
                if let date = formatter.date(from: rawValue) {
                    frontmatter.createdAt = date
                }
            case "modified":
                if let date = formatter.date(from: rawValue) {
                    frontmatter.modifiedAt = date
                }
            case "template":
                frontmatter.template = unquote(rawValue)
            case "ocr_text":
                frontmatter.ocrText = unquote(rawValue)
            case "encrypted":
                frontmatter.isEncrypted = rawValue == "true"
            default:
                frontmatter.customFields[key] = unquote(rawValue)
            }
        }

        return frontmatter
    }

    /// Parsed eine YAML inline-Array-Syntax: `[tag1, tag2, "tag 3"]`
    private func parseInlineArray(_ value: String) -> [String] {
        var content = value
        if content.hasPrefix("[") { content.removeFirst() }
        if content.hasSuffix("]") { content.removeLast() }

        return content
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { unquote($0) }
            .filter { !$0.isEmpty }
    }

    /// Entfernt umschließende Anführungszeichen.
    private func unquote(_ value: String) -> String {
        var v = value
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v.removeFirst()
            v.removeLast()
        }
        return v
    }

    /// Setzt Anführungszeichen wenn der Wert Sonderzeichen enthält.
    private func quoteIfNeeded(_ value: String) -> String {
        let needsQuoting = value.contains(":") || value.contains("#") ||
            value.contains("[") || value.contains("]") ||
            value.contains(",") || value.contains("\"") ||
            value.contains("'") || value.hasPrefix(" ") || value.hasSuffix(" ")
        return needsQuoting ? "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"" : value
    }
}

// MARK: - String Extension

private extension String {
    func trimmingLeadingNewlines() -> String {
        var result = self
        while result.hasPrefix("\n") || result.hasPrefix("\r\n") {
            if result.hasPrefix("\r\n") {
                result.removeFirst(2)
            } else {
                result.removeFirst()
            }
        }
        return result
    }
}
