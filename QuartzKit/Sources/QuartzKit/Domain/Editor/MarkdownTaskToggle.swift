import Foundation

// MARK: - Task Toggle Result

/// Result of toggling a task checkbox in markdown text.
public struct TaskToggleResult: Equatable, Sendable {
    /// The range in the original text to replace.
    public let replacementRange: NSRange
    /// The replacement text (e.g., `"[x]"` or `"[ ]"`).
    public let replacementText: String
    /// The new checked state after toggle.
    public let isChecked: Bool
    /// The cursor position after the toggle (unchanged).
    public let cursorPosition: Int

    public init(replacementRange: NSRange, replacementText: String, isChecked: Bool, cursorPosition: Int) {
        self.replacementRange = replacementRange
        self.replacementText = replacementText
        self.isChecked = isChecked
        self.cursorPosition = cursorPosition
    }
}

// MARK: - Task Toggle Engine

/// Pure engine for toggling markdown task checkboxes.
///
/// Detects `- [ ]` and `- [x]` patterns and flips the checkbox state.
/// Supports single-line toggle and cascading toggle to nested children.
///
/// This is a pure helper with no UI dependencies, making it easy to test.
public struct MarkdownTaskToggle: Sendable {

    public init() {}

    // MARK: - Single Toggle

    /// Toggles the task checkbox on the line containing the given cursor position.
    ///
    /// - Parameters:
    ///   - text: The current document text.
    ///   - cursorPosition: The cursor position (or line position to toggle).
    /// - Returns: A `TaskToggleResult` if the line has a checkbox, or `nil`.
    public func toggle(in text: String, at cursorPosition: Int) -> TaskToggleResult? {
        let nsText = text as NSString
        let safeCursor = min(max(cursorPosition, 0), nsText.length)

        let lineRange = nsText.lineRange(for: NSRange(location: safeCursor, length: 0))
        let line = nsText.substring(with: lineRange)

        guard let checkbox = findCheckbox(in: line) else { return nil }

        let newState = !checkbox.isChecked
        let checkboxRange = NSRange(
            location: lineRange.location + checkbox.bracketOffset,
            length: 3 // "[ ]" or "[x]"
        )
        let replacement = newState ? "[x]" : "[ ]"

        return TaskToggleResult(
            replacementRange: checkboxRange,
            replacementText: replacement,
            isChecked: newState,
            cursorPosition: safeCursor
        )
    }

    // MARK: - Cascade Toggle

    /// Toggles the task checkbox on the current line and cascades to nested children.
    ///
    /// Children are identified by having a greater indentation level than the toggled line.
    /// The cascade stops when a line with equal or lesser indentation is encountered.
    ///
    /// - Parameters:
    ///   - text: The current document text.
    ///   - cursorPosition: The cursor position on the parent task line.
    /// - Returns: An array of `TaskToggleResult`s (parent + children), or `nil` if no checkbox.
    public func toggleWithChildren(in text: String, at cursorPosition: Int) -> [TaskToggleResult]? {
        let nsText = text as NSString
        let safeCursor = min(max(cursorPosition, 0), nsText.length)

        let lineRange = nsText.lineRange(for: NSRange(location: safeCursor, length: 0))
        let line = nsText.substring(with: lineRange)

        guard let parentCheckbox = findCheckbox(in: line) else { return nil }

        let parentIndent = leadingWhitespaceCount(in: line)
        let newState = !parentCheckbox.isChecked
        let replacement = newState ? "[x]" : "[ ]"

        var results: [TaskToggleResult] = []

        // Toggle parent
        let parentRange = NSRange(
            location: lineRange.location + parentCheckbox.bracketOffset,
            length: 3
        )
        results.append(TaskToggleResult(
            replacementRange: parentRange,
            replacementText: replacement,
            isChecked: newState,
            cursorPosition: safeCursor
        ))

        // Scan forward for children (lines with greater indentation that have checkboxes)
        var scanPos = lineRange.location + lineRange.length
        while scanPos < nsText.length {
            let childLineRange = nsText.lineRange(for: NSRange(location: scanPos, length: 0))
            let childLine = nsText.substring(with: childLineRange)

            let childIndent = leadingWhitespaceCount(in: childLine)
            let trimmed = childLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // Stop at empty lines or lines with equal/lesser indentation
            if trimmed.isEmpty {
                // Skip blank lines within nested content
                scanPos = childLineRange.location + childLineRange.length
                continue
            }
            if childIndent <= parentIndent {
                break
            }

            // Toggle child checkbox if present
            if let childCheckbox = findCheckbox(in: childLine) {
                let childRange = NSRange(
                    location: childLineRange.location + childCheckbox.bracketOffset,
                    length: 3
                )
                results.append(TaskToggleResult(
                    replacementRange: childRange,
                    replacementText: replacement,
                    isChecked: newState,
                    cursorPosition: safeCursor
                ))
            }

            scanPos = childLineRange.location + childLineRange.length
        }

        return results.isEmpty ? nil : results
    }

    // MARK: - Checkbox Detection

    /// Information about a detected checkbox within a line.
    struct CheckboxInfo {
        /// Offset from the start of the line to the `[` character.
        let bracketOffset: Int
        /// Whether the checkbox is currently checked.
        let isChecked: Bool
    }

    /// Finds a task checkbox in a line (e.g., `- [ ]` or `- [x]`).
    func findCheckbox(in line: String) -> CheckboxInfo? {
        // Match patterns like: "- [ ]", "- [x]", "- [X]", "* [ ]", "* [x]", "1. [ ]", etc.
        // with optional leading whitespace
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

        // List marker: -, *, +, or ordered (1., 2., etc.)
        var afterMarker: Substring
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            afterMarker = trimmed.dropFirst(2)
        } else if let dotIndex = trimmed.firstIndex(of: "."),
                  trimmed[trimmed.startIndex..<dotIndex].allSatisfy(\.isNumber),
                  trimmed.index(after: dotIndex) < trimmed.endIndex,
                  trimmed[trimmed.index(after: dotIndex)] == " " {
            afterMarker = trimmed[trimmed.index(dotIndex, offsetBy: 2)...]
        } else {
            return nil
        }

        // Check for [ ] or [x] or [X]
        if afterMarker.hasPrefix("[ ] ") || afterMarker.hasPrefix("[ ]\n") || afterMarker == "[ ]" {
            let offset = line.count - afterMarker.count
            return CheckboxInfo(bracketOffset: offset, isChecked: false)
        }

        if afterMarker.hasPrefix("[x] ") || afterMarker.hasPrefix("[x]\n") || afterMarker == "[x]" ||
           afterMarker.hasPrefix("[X] ") || afterMarker.hasPrefix("[X]\n") || afterMarker == "[X]" {
            let offset = line.count - afterMarker.count
            return CheckboxInfo(bracketOffset: offset, isChecked: true)
        }

        return nil
    }

    /// Counts leading whitespace characters (spaces and tabs).
    private func leadingWhitespaceCount(in line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 4 } // Tab = 4 spaces equivalent
            else { break }
        }
        return count
    }
}
