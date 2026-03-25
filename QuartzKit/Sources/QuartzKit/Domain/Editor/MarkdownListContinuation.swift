import Foundation

/// Result of a list continuation operation.
public struct ListContinuationResult: Equatable, Sendable {
    /// The new text after inserting the newline and continuation marker.
    public let newText: String
    /// The new cursor position after the insertion.
    public let newCursorPosition: Int

    /// Range in the original text that should be replaced (for surgical updates).
    public let replacementRange: NSRange
    /// The text to insert at the replacement range (for surgical updates).
    public let insertionText: String

    public init(newText: String, newCursorPosition: Int, replacementRange: NSRange, insertionText: String) {
        self.newText = newText
        self.newCursorPosition = newCursorPosition
        self.replacementRange = replacementRange
        self.insertionText = insertionText
    }

    /// Legacy initializer for compatibility
    public init(newText: String, newCursorPosition: Int) {
        self.newText = newText
        self.newCursorPosition = newCursorPosition
        // Fallback: replace entire document
        self.replacementRange = NSRange(location: 0, length: (newText as NSString).length)
        self.insertionText = newText
    }
}

/// Pure engine for markdown list continuation on newline.
///
/// Detects list markers (bullets, numbers, checkboxes, blockquotes) on the current line
/// and computes the appropriate continuation when the user presses Return.
///
/// This is a pure helper with no UI dependencies, making it easy to test.
public struct MarkdownListContinuation: Sendable {

    public init() {}

    /// Handles a newline insertion at the given cursor position.
    ///
    /// - Parameters:
    ///   - text: The current text content.
    ///   - cursorPosition: The cursor position where newline is being inserted.
    /// - Returns: A `ListContinuationResult` if continuation applies, or `nil` if no list marker was detected.
    public func handleNewline(in text: String, cursorPosition: Int) -> ListContinuationResult? {
        let nsText = text as NSString

        // Clamp cursor position to valid range
        let safeCursor = min(max(cursorPosition, 0), nsText.length)

        // Find the current line range
        let lineRange = nsText.lineRange(for: NSRange(location: safeCursor, length: 0))
        let currentLine = nsText.substring(with: lineRange)

        // Remove trailing newline from current line for analysis
        let lineContent = currentLine.hasSuffix("\n")
            ? String(currentLine.dropLast())
            : currentLine

        // Parse the line for list markers
        guard let marker = parseListMarker(from: lineContent) else {
            return nil
        }

        // Calculate position within the line
        let positionInLine = safeCursor - lineRange.location

        // Check if the line content after the marker is empty (exit list case)
        let contentAfterMarker = marker.contentStart < lineContent.count
            ? String(lineContent.dropFirst(marker.contentStart))
            : ""

        let trimmedContent = contentAfterMarker.trimmingCharacters(in: .whitespaces)

        // If we're at the end of an empty marker line, exit the list
        if trimmedContent.isEmpty && positionInLine >= marker.contentStart {
            return exitList(text: text, lineRange: lineRange, markerLength: marker.fullMarkerLength)
        }

        // Calculate the text before and after cursor within the line
        let textBeforeCursorInLine = String(lineContent.prefix(positionInLine))
        let textAfterCursorInLine = String(lineContent.dropFirst(positionInLine))

        // Build the continuation marker
        let continuationMarker = buildContinuationMarker(for: marker)

        // Build the new text
        let beforeLine = lineRange.location > 0 ? nsText.substring(to: lineRange.location) : ""
        let afterLine = lineRange.location + lineRange.length < nsText.length
            ? nsText.substring(from: lineRange.location + lineRange.length)
            : ""

        // Handle trailing newline in original line
        let lineHadTrailingNewline = currentLine.hasSuffix("\n")

        let newLineContent: String
        let insertionText: String
        if textAfterCursorInLine.isEmpty {
            // Cursor at end of line content
            newLineContent = textBeforeCursorInLine + "\n" + continuationMarker
            insertionText = "\n" + continuationMarker
        } else {
            // Cursor in middle - split the content
            newLineContent = textBeforeCursorInLine + "\n" + continuationMarker + textAfterCursorInLine
            insertionText = "\n" + continuationMarker
        }

        let newText: String
        if lineHadTrailingNewline {
            newText = beforeLine + newLineContent + "\n" + afterLine
        } else {
            newText = beforeLine + newLineContent + afterLine
        }

        // Calculate new cursor position (right after the continuation marker)
        let newCursorPosition = beforeLine.count + textBeforeCursorInLine.count + 1 + continuationMarker.count

        // Surgical replacement: just insert at cursor position
        let replacementRange = NSRange(location: safeCursor, length: 0)

        return ListContinuationResult(
            newText: newText,
            newCursorPosition: newCursorPosition,
            replacementRange: replacementRange,
            insertionText: insertionText
        )
    }

    // MARK: - Private Helpers

    private struct ParsedMarker {
        let indent: String
        let markerType: MarkerType
        let fullMarkerLength: Int
        let contentStart: Int
        let number: Int? // For numbered lists
    }

    private enum MarkerType {
        case bullet(Character) // -, *, +
        case numbered
        case checkbox(checked: Bool, bullet: Character)
        case blockquote(depth: Int)
    }

    private func parseListMarker(from line: String) -> ParsedMarker? {
        // Extract leading whitespace
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let afterIndent = String(line.dropFirst(indent.count))

        // Try blockquote first: > or > >
        if let blockquoteResult = parseBlockquote(afterIndent, indent: indent) {
            return blockquoteResult
        }

        // Try checkbox: - [ ] or - [x] or * [ ] etc.
        if let checkboxResult = parseCheckbox(afterIndent, indent: indent) {
            return checkboxResult
        }

        // Try numbered list: 1. or 12.
        if let numberedResult = parseNumbered(afterIndent, indent: indent) {
            return numberedResult
        }

        // Try bullet: - or * or +
        if let bulletResult = parseBullet(afterIndent, indent: indent) {
            return bulletResult
        }

        return nil
    }

    private func parseBlockquote(_ text: String, indent: String) -> ParsedMarker? {
        var depth = 0
        var remaining = text
        var totalMarkerLength = indent.count

        while remaining.hasPrefix(">") {
            depth += 1
            remaining = String(remaining.dropFirst())
            totalMarkerLength += 1

            // Skip optional space after >
            if remaining.hasPrefix(" ") {
                remaining = String(remaining.dropFirst())
                totalMarkerLength += 1
            }
        }

        guard depth > 0 else { return nil }

        return ParsedMarker(
            indent: indent,
            markerType: .blockquote(depth: depth),
            fullMarkerLength: totalMarkerLength,
            contentStart: totalMarkerLength,
            number: nil
        )
    }

    private func parseCheckbox(_ text: String, indent: String) -> ParsedMarker? {
        // Pattern: (- or * or +) followed by space, then [ ] or [x] or [X]
        guard text.count >= 5 else { return nil }

        let chars = Array(text)
        guard (chars[0] == "-" || chars[0] == "*" || chars[0] == "+"),
              chars[1] == " ",
              chars[2] == "[",
              (chars[3] == " " || chars[3] == "x" || chars[3] == "X"),
              chars[4] == "]" else {
            return nil
        }

        let checked = chars[3] == "x" || chars[3] == "X"
        let bullet = chars[0]

        // Check for space after ]
        let hasSpaceAfter = text.count > 5 && chars[5] == " "
        let markerLength = indent.count + (hasSpaceAfter ? 6 : 5)

        return ParsedMarker(
            indent: indent,
            markerType: .checkbox(checked: checked, bullet: bullet),
            fullMarkerLength: markerLength,
            contentStart: markerLength,
            number: nil
        )
    }

    private func parseNumbered(_ text: String, indent: String) -> ParsedMarker? {
        // Pattern: one or more digits followed by . and space
        var numberStr = ""
        var idx = text.startIndex

        while idx < text.endIndex && text[idx].isNumber {
            numberStr.append(text[idx])
            idx = text.index(after: idx)
        }

        guard !numberStr.isEmpty,
              idx < text.endIndex,
              text[idx] == "." else {
            return nil
        }

        idx = text.index(after: idx)

        // Check for space after .
        guard idx < text.endIndex && text[idx] == " " else {
            return nil
        }

        let number = Int(numberStr) ?? 1
        let markerLength = indent.count + numberStr.count + 2 // "N. "

        return ParsedMarker(
            indent: indent,
            markerType: .numbered,
            fullMarkerLength: markerLength,
            contentStart: markerLength,
            number: number
        )
    }

    private func parseBullet(_ text: String, indent: String) -> ParsedMarker? {
        // Pattern: - or * or + followed by space
        guard text.count >= 2 else { return nil }

        let first = text.first!
        guard (first == "-" || first == "*" || first == "+"),
              text.dropFirst().first == " " else {
            return nil
        }

        return ParsedMarker(
            indent: indent,
            markerType: .bullet(first),
            fullMarkerLength: indent.count + 2,
            contentStart: indent.count + 2,
            number: nil
        )
    }

    private func buildContinuationMarker(for marker: ParsedMarker) -> String {
        switch marker.markerType {
        case .bullet(let char):
            return marker.indent + String(char) + " "

        case .numbered:
            let nextNumber = (marker.number ?? 1) + 1
            return marker.indent + "\(nextNumber). "

        case .checkbox(_, let bullet):
            // Always continue with unchecked checkbox
            return marker.indent + String(bullet) + " [ ] "

        case .blockquote(let depth):
            return marker.indent + String(repeating: "> ", count: depth)
        }
    }

    private func exitList(text: String, lineRange: NSRange, markerLength: Int) -> ListContinuationResult {
        let nsText = text as NSString

        // Remove the marker from the current line and add a blank line
        let beforeLine = lineRange.location > 0 ? nsText.substring(to: lineRange.location) : ""
        let afterLine = lineRange.location + lineRange.length < nsText.length
            ? nsText.substring(from: lineRange.location + lineRange.length)
            : ""

        let newText = beforeLine + "\n" + afterLine
        let newCursorPosition = beforeLine.count + 1

        // Surgical replacement: replace the entire current line with just a newline
        let replacementRange = lineRange
        let insertionText = "\n"

        return ListContinuationResult(
            newText: newText,
            newCursorPosition: newCursorPosition,
            replacementRange: replacementRange,
            insertionText: insertionText
        )
    }
}
