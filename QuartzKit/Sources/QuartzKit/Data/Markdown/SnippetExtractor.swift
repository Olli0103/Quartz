import Foundation

/// Extracts plain-text snippets from raw markdown content.
///
/// Designed for the preview pipeline: takes an 8KB prefix string (not full file),
/// strips frontmatter and markdown syntax, and returns a 2-3 line plain text snippet.
///
/// Uses simple string operations rather than regex for Swift 6 strict concurrency
/// safety and maximum performance.
public enum SnippetExtractor: Sendable {

    /// Maximum snippet length in characters.
    private static let maxSnippetLength = 200

    /// Maximum number of non-empty lines to include in the snippet.
    private static let maxLines = 3

    /// Extracts a plain-text snippet from a raw markdown string (typically an 8KB prefix).
    ///
    /// - Parameter markdown: Raw markdown text, possibly starting with frontmatter.
    /// - Returns: A plain-text snippet of up to 200 characters / 3 lines.
    public static func extractSnippet(from markdown: String) -> String {
        let body = stripFrontmatter(from: markdown)
        return snippetFromBody(body)
    }

    /// Extracts a snippet from pre-stripped body text (frontmatter already removed).
    public static func snippetFromBody(_ body: String) -> String {
        let stripped = stripMarkdownSyntax(body)
        let lines = stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(maxLines)

        let joined = lines.joined(separator: " ")
        if joined.count <= maxSnippetLength {
            return joined
        }
        // Truncate at word boundary when possible
        let truncated = String(joined.prefix(maxSnippetLength))
        if let lastSpace = truncated.lastIndex(of: " "),
           truncated.distance(from: truncated.startIndex, to: lastSpace) > maxSnippetLength / 2 {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    /// Extracts the first H1 heading from markdown body text, if present.
    /// Used as title fallback when frontmatter has no `title:` field.
    public static func extractFirstHeading(from body: String) -> String? {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let heading = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { return heading }
            }
        }
        return nil
    }

    // MARK: - Frontmatter Stripping

    /// Strips YAML frontmatter delimited by `---` from the beginning of markdown text.
    /// Returns the body text after the closing `---` delimiter.
    static func stripFrontmatter(from text: String) -> String {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else {
            return text
        }
        let dropCount = text.hasPrefix("---\r\n") ? 5 : 4
        let afterOpening = text[text.index(text.startIndex, offsetBy: dropCount)...]
        if let closingRange = afterOpening.range(of: "\n---\n") {
            return String(afterOpening[closingRange.upperBound...])
        }
        if let closingRange = afterOpening.range(of: "\n---\r\n") {
            return String(afterOpening[closingRange.upperBound...])
        }
        // No closing delimiter found — treat entire text as body
        return text
    }

    // MARK: - Markdown Syntax Stripping

    /// Strips common markdown syntax to produce plain text.
    ///
    /// Uses line-by-line string operations for maximum performance and
    /// Swift 6 strict concurrency safety (no Regex stored properties).
    static func stripMarkdownSyntax(_ text: String) -> String {
        var lines: [String] = []
        var inCodeBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Toggle fenced code blocks (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }

            // Skip horizontal rules (---, ***, ___)
            if isHorizontalRule(trimmed) { continue }

            // Strip line-level syntax and collect
            let stripped = stripLineSyntax(trimmed)
            if !stripped.isEmpty {
                lines.append(stripped)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Strips markdown syntax from a single line of text.
    private static func stripLineSyntax(_ line: String) -> String {
        var result = line

        // Strip heading markers (# through ######)
        if result.hasPrefix("#") {
            var i = result.startIndex
            while i < result.endIndex, result[i] == "#" { i = result.index(after: i) }
            if i < result.endIndex, result[i] == " " {
                result = String(result[result.index(after: i)...])
            }
        }

        // Strip blockquote markers (> at start)
        if result.hasPrefix("> ") {
            result = String(result.dropFirst(2))
        } else if result == ">" {
            result = ""
        }

        // Strip unordered list markers (-, *, + followed by space)
        result = stripListMarker(result)

        // Strip ordered list markers (1. 2. etc)
        result = stripOrderedListMarker(result)

        // Strip checkbox markers
        if result.hasPrefix("[x] ") || result.hasPrefix("[ ] ") {
            result = String(result.dropFirst(4))
        }

        // Strip inline formatting
        result = stripInlineFormatting(result)

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Strips unordered list markers (-, *, +) at the start of a line.
    private static func stripListMarker(_ line: String) -> String {
        guard let first = line.first, (first == "-" || first == "*" || first == "+") else {
            return line
        }
        let rest = line.dropFirst()
        guard rest.first == " " else { return line }
        return String(rest.dropFirst())
    }

    /// Strips ordered list markers (1. 2. 10. etc) at the start of a line.
    private static func stripOrderedListMarker(_ line: String) -> String {
        var i = line.startIndex
        while i < line.endIndex, line[i].isNumber { i = line.index(after: i) }
        guard i > line.startIndex, i < line.endIndex, line[i] == "." else { return line }
        let afterDot = line.index(after: i)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return line }
        return String(line[line.index(after: afterDot)...])
    }

    /// Strips inline markdown formatting: bold, italic, strikethrough, code, links, images.
    private static func stripInlineFormatting(_ text: String) -> String {
        var result = text

        // Remove images ![alt](url) — remove entirely
        result = removePattern(from: result, open: "![", midDelim: "](", close: ")", keepContent: false)

        // Remove links [text](url) — keep link text
        result = removePattern(from: result, open: "[", midDelim: "](", close: ")", keepContent: true)

        // Remove bold ** and __
        result = removeDelimitedContent(from: result, delimiter: "**")
        result = removeDelimitedContent(from: result, delimiter: "__")

        // Remove strikethrough ~~
        result = removeDelimitedContent(from: result, delimiter: "~~")

        // Remove inline code backticks (single)
        result = removeDelimitedContent(from: result, delimiter: "`")

        // Remove remaining single * and _ markers (italic)
        // Simple approach: remove isolated markers
        result = removeSingleCharDelimiter(from: result, char: "*")
        result = removeSingleCharDelimiter(from: result, char: "_")

        return result
    }

    /// Removes paired delimiters (e.g., ** ... **) keeping the content between them.
    private static func removeDelimitedContent(from text: String, delimiter: String) -> String {
        guard text.contains(delimiter) else { return text }
        var result = text
        while let openRange = result.range(of: delimiter) {
            let afterOpen = openRange.upperBound
            guard afterOpen < result.endIndex else { break }
            let searchRange = afterOpen..<result.endIndex
            guard let closeRange = result.range(of: delimiter, range: searchRange) else { break }
            // Keep content between delimiters, remove the delimiters
            let content = String(result[afterOpen..<closeRange.lowerBound])
            result = result.replacingCharacters(
                in: openRange.lowerBound..<closeRange.upperBound,
                with: content
            )
        }
        return result
    }

    /// Removes [text](url) or ![text](url) patterns.
    /// If `keepContent` is true, keeps the text portion; otherwise removes entirely.
    private static func removePattern(
        from text: String,
        open: String,
        midDelim: String,
        close: String,
        keepContent: Bool
    ) -> String {
        guard text.contains(open) else { return text }
        var result = text
        while let openRange = result.range(of: open) {
            let afterOpen = openRange.upperBound
            guard let midRange = result.range(of: midDelim, range: afterOpen..<result.endIndex) else { break }
            guard let closeRange = result.range(of: close, range: midRange.upperBound..<result.endIndex) else { break }

            if keepContent {
                let content = String(result[afterOpen..<midRange.lowerBound])
                result = result.replacingCharacters(
                    in: openRange.lowerBound..<closeRange.upperBound,
                    with: content
                )
            } else {
                result = result.replacingCharacters(
                    in: openRange.lowerBound..<closeRange.upperBound,
                    with: ""
                )
            }
        }
        return result
    }

    /// Removes isolated single-character delimiters (* or _) used for italic.
    private static func removeSingleCharDelimiter(from text: String, char: Character) -> String {
        guard text.contains(char) else { return text }
        let chars = Array(text)
        var indicesToRemove: [Int] = []

        var i = 0
        while i < chars.count {
            if chars[i] == char {
                // Find the matching closing delimiter
                var j = i + 1
                while j < chars.count, chars[j] != char { j += 1 }
                if j < chars.count, j > i + 1 {
                    // Found a pair — mark both for removal
                    indicesToRemove.append(i)
                    indicesToRemove.append(j)
                    i = j + 1
                    continue
                }
            }
            i += 1
        }

        guard !indicesToRemove.isEmpty else { return text }
        let removeSet = Set(indicesToRemove)
        return String(chars.enumerated().compactMap { removeSet.contains($0.offset) ? nil : $0.element })
    }

    /// Checks if a trimmed line is a horizontal rule (---, ***, ___).
    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let chars = Set(trimmed.filter { !$0.isWhitespace })
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }
}
