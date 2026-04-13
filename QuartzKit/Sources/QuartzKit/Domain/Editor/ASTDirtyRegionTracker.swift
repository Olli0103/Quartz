import Foundation

// MARK: - AST Dirty Region Tracker

/// Computes paragraph-aligned dirty ranges for incremental AST highlighting.
///
/// Given an edit range and the document text, this utility expands the edit to
/// paragraph boundaries so the highlighter can re-parse only the affected region
/// instead of the entire document.
///
/// **Thread Safety:** All methods are pure functions on `Sendable` inputs — safe
/// to call from any isolation context.
public enum ASTDirtyRegionTracker: Sendable {

    // MARK: - Primary API

    /// Returns the paragraph-aligned range containing the edited region.
    ///
    /// Expands the edit range to include the full paragraphs (newline-delimited lines)
    /// that intersect the edit. This is the minimum range that must be re-parsed.
    ///
    /// - Parameters:
    ///   - text: The full document text *after* the edit.
    ///   - editRange: The range in the post-edit text where changes landed.
    ///                 Typically: `NSRange(location: editStart, length: replacementLength)`.
    /// - Returns: A paragraph-aligned range, or `nil` if the text is empty.
    public static func dirtyRange(
        in text: String,
        editRange: NSRange
    ) -> NSRange? {
        let nsString = text as NSString
        let length = nsString.length
        guard length > 0 else { return nil }

        // Clamp edit range to valid bounds
        let clampedLocation = min(max(editRange.location, 0), length)
        let clampedEnd = min(clampedLocation + max(editRange.length, 0), length)
        let clamped = NSRange(location: clampedLocation, length: clampedEnd - clampedLocation)

        return paragraphRange(in: nsString, covering: clamped)
    }

    /// Returns a dirty range from the pre-edit range and replacement length.
    ///
    /// Converts a `MutationTransaction`'s `editedRange` (pre-edit coordinates)
    /// and `replacementLength` into a post-edit dirty range, then aligns to paragraphs.
    ///
    /// - Parameters:
    ///   - text: The full document text *after* the edit.
    ///   - preEditRange: The range that was replaced (pre-edit coordinates).
    ///   - replacementLength: The length of the replacement text.
    /// - Returns: A paragraph-aligned range in post-edit coordinates, or `nil` if the text is empty.
    public static func dirtyRange(
        in text: String,
        preEditRange: NSRange,
        replacementLength: Int
    ) -> NSRange? {
        // In post-edit coordinates, the changed region starts at preEditRange.location
        // and extends for replacementLength characters.
        let postEditRange = NSRange(
            location: preEditRange.location,
            length: max(replacementLength, 0)
        )
        return dirtyRange(in: text, editRange: postEditRange)
    }

    // MARK: - Expanded Dirty Range

    /// Returns a dirty range with one paragraph of context on each side.
    ///
    /// This is useful for edits that might affect surrounding structure, such as
    /// opening/closing a code fence or changing list indentation levels.
    ///
    /// - Parameters:
    ///   - text: The full document text *after* the edit.
    ///   - editRange: The range in the post-edit text where changes landed.
    /// - Returns: A paragraph-aligned range with ±1 paragraph context, or `nil` if empty.
    public static func expandedDirtyRange(
        in text: String,
        editRange: NSRange
    ) -> NSRange? {
        guard let base = dirtyRange(in: text, editRange: editRange) else {
            return nil
        }
        let nsText = text as NSString
        let expanded = expandByOneParagraph(base, in: nsText)
        return expandMarkdownStructures(in: nsText, covering: expanded)
    }

    /// Expanded variant that accepts pre-edit coordinates.
    public static func expandedDirtyRange(
        in text: String,
        preEditRange: NSRange,
        replacementLength: Int
    ) -> NSRange? {
        guard let base = dirtyRange(
            in: text,
            preEditRange: preEditRange,
            replacementLength: replacementLength
        ) else {
            return nil
        }
        let nsText = text as NSString
        let expanded = expandByOneParagraph(base, in: nsText)
        return expandMarkdownStructures(in: nsText, covering: expanded)
    }

    // MARK: - Code Fence Detection

    /// Returns `true` if the dirty range contains a code fence boundary (`` ``` ``).
    ///
    /// When a code fence boundary is inside the dirty range, the highlighter should
    /// fall back to a full document parse because the fence affects all subsequent content.
    ///
    /// - Parameters:
    ///   - text: The full document text.
    ///   - range: The paragraph-aligned dirty range.
    /// - Returns: `true` if the range contains a code fence delimiter.
    public static func containsCodeFenceBoundary(
        in text: String,
        range: NSRange
    ) -> Bool {
        let nsString = text as NSString
        guard range.location >= 0,
              range.location + range.length <= nsString.length else {
            return false
        }
        let substring = nsString.substring(with: range)
        // Match lines that start with optional whitespace + 3+ backticks or tildes
        return substring.contains("```") || substring.contains("~~~")
    }

    // MARK: - Internals

    /// Expands a range to full paragraph boundaries.
    private static func paragraphRange(
        in nsString: NSString,
        covering range: NSRange
    ) -> NSRange {
        let length = nsString.length

        // Start paragraph: find range of paragraph containing range.location
        let startPara = nsString.lineRange(
            for: NSRange(location: min(range.location, length > 0 ? length - 1 : 0), length: 0)
        )

        // End paragraph: find range of paragraph containing the last character
        let endLocation: Int
        if range.length > 0 {
            endLocation = min(range.location + range.length - 1, length > 0 ? length - 1 : 0)
        } else {
            endLocation = min(range.location, length > 0 ? length - 1 : 0)
        }
        let endPara = nsString.lineRange(
            for: NSRange(location: endLocation, length: 0)
        )

        // Union of start and end paragraph ranges
        let unionStart = startPara.location
        let unionEnd = max(
            startPara.location + startPara.length,
            endPara.location + endPara.length
        )
        return NSRange(location: unionStart, length: unionEnd - unionStart)
    }

    /// Expands a paragraph-aligned range by one paragraph on each side.
    private static func expandByOneParagraph(
        _ range: NSRange,
        in nsString: NSString
    ) -> NSRange {
        let length = nsString.length
        guard length > 0 else { return range }

        var start = range.location
        var end = range.location + range.length

        // Expand backward: if we're not at the start, step back into the previous paragraph
        if start > 0 {
            let prevPara = nsString.lineRange(
                for: NSRange(location: start - 1, length: 0)
            )
            start = prevPara.location
        }

        // Expand forward: if we're not at the end, step into the next paragraph
        if end < length {
            let nextPara = nsString.lineRange(
                for: NSRange(location: min(end, length - 1), length: 0)
            )
            end = nextPara.location + nextPara.length
        }

        return NSRange(location: start, length: end - start)
    }

    /// Expands a dirty range to cover any intersecting markdown table block.
    /// Table edits are line-structural: reparsing only the edited row can drop
    /// the header/divider spans and break incremental table styling parity.
    private static func expandMarkdownStructures(
        in nsString: NSString,
        covering range: NSRange
    ) -> NSRange {
        var expanded = range

        for lineRange in intersectingLineRanges(in: nsString, covering: range) {
            let line = nsString.substring(with: lineRange)
            guard MarkdownTableNavigation.isTableRow(line) else { continue }

            let tableBlock = tableBlockRange(in: nsString, containing: lineRange)
            let start = min(expanded.location, tableBlock.location)
            let end = max(expanded.location + expanded.length, tableBlock.location + tableBlock.length)
            expanded = NSRange(location: start, length: end - start)
        }

        return expanded
    }

    private static func intersectingLineRanges(
        in nsString: NSString,
        covering range: NSRange
    ) -> [NSRange] {
        let length = nsString.length
        guard length > 0 else { return [] }

        let startLocation = min(max(range.location, 0), max(length - 1, 0))
        let endLocation: Int
        if range.length > 0 {
            endLocation = min(range.location + range.length - 1, max(length - 1, 0))
        } else {
            endLocation = startLocation
        }

        let endLine = nsString.lineRange(for: NSRange(location: endLocation, length: 0))
        var cursor = nsString.lineRange(for: NSRange(location: startLocation, length: 0)).location
        var lines: [NSRange] = []

        while cursor < endLine.location + endLine.length {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            lines.append(lineRange)

            let nextCursor = lineRange.location + lineRange.length
            guard nextCursor > cursor else { break }
            cursor = nextCursor
        }

        return lines
    }

    private static func tableBlockRange(
        in nsString: NSString,
        containing lineRange: NSRange
    ) -> NSRange {
        let length = nsString.length
        guard length > 0 else { return lineRange }

        var startLine = lineRange
        while startLine.location > 0 {
            let previousLine = nsString.lineRange(for: NSRange(location: startLine.location - 1, length: 0))
            let previousText = nsString.substring(with: previousLine)
            guard MarkdownTableNavigation.isTableRow(previousText) else { break }
            startLine = previousLine
        }

        var endLine = lineRange
        while endLine.location + endLine.length < length {
            let nextLine = nsString.lineRange(for: NSRange(location: endLine.location + endLine.length, length: 0))
            let nextText = nsString.substring(with: nextLine)
            guard MarkdownTableNavigation.isTableRow(nextText) else { break }
            endLine = nextLine
        }

        let end = endLine.location + endLine.length
        return NSRange(location: startLine.location, length: end - startLine.location)
    }
}
