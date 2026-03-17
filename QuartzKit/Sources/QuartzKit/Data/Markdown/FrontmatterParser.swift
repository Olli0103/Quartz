import Foundation

/// Lightweight YAML frontmatter parser.
///
/// Detects the `---` delimiter, extracts the YAML, and parses it
/// into a `Frontmatter` object. Round-trip capable: the body remains unchanged.
public struct FrontmatterParser: FrontmatterParsing, Sendable {
    // ISO8601DateFormatter is thread-safe (unlike DateFormatter)
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init() {}

    // MARK: - FrontmatterParsing

    public func parse(from rawContent: String) throws -> (frontmatter: Frontmatter, body: String) {
        guard rawContent.hasPrefix("---\n") || rawContent.hasPrefix("---\r\n") else {
            return (Frontmatter(), rawContent)
        }

        let dropCount = rawContent.hasPrefix("---\r\n") ? 5 : 4
        let scanner = rawContent.dropFirst(dropCount) // Skip opening "---\n" or "---\r\n"
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

        lines.append("created: \(Self.isoFormatter.string(from: frontmatter.createdAt))")
        lines.append("modified: \(Self.isoFormatter.string(from: frontmatter.modifiedAt))")

        if let template = frontmatter.template {
            lines.append("template: \(quoteIfNeeded(template))")
        }
        if let ocrText = frontmatter.ocrText, !ocrText.isEmpty {
            lines.append("ocr_text: \(quoteIfNeeded(ocrText))")
        }
        if !frontmatter.linkedNotes.isEmpty {
            let noteList = frontmatter.linkedNotes.map { quoteIfNeeded($0) }.joined(separator: ", ")
            lines.append("linked_notes: [\(noteList)]")
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
                if let date = Self.isoFormatter.date(from: rawValue) {
                    frontmatter.createdAt = date
                }
            case "modified":
                if let date = Self.isoFormatter.date(from: rawValue) {
                    frontmatter.modifiedAt = date
                }
            case "template":
                frontmatter.template = unquote(rawValue)
            case "ocr_text":
                frontmatter.ocrText = unquote(rawValue)
            case "linked_notes":
                frontmatter.linkedNotes = parseInlineArray(rawValue)
            case "encrypted":
                frontmatter.isEncrypted = rawValue == "true"
            default:
                frontmatter.customFields[key] = unquote(rawValue)
            }
        }

        return frontmatter
    }

    /// Parses a YAML inline array syntax: `[tag1, tag2, "tag 3"]`
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

    /// Removes surrounding quotes and processes escape sequences.
    private func unquote(_ value: String) -> String {
        var v = value
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v.removeFirst()
            v.removeLast()
            // Process YAML escape sequences (order matters: \\\\ first to avoid double-replacement)
            v = v.replacingOccurrences(of: "\\\\", with: "\u{0000}") // temp placeholder
            v = v.replacingOccurrences(of: "\\\"", with: "\"")
            v = v.replacingOccurrences(of: "\\'", with: "'")
            v = v.replacingOccurrences(of: "\\n", with: "\n")
            v = v.replacingOccurrences(of: "\\t", with: "\t")
            v = v.replacingOccurrences(of: "\u{0000}", with: "\\") // restore backslash
        }
        return v
    }

    /// Adds quotes if the value contains special characters.
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
