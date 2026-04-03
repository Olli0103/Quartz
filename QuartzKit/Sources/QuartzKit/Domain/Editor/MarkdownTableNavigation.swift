import Foundation

// MARK: - Table Navigation Result

/// Result of a table navigation operation (Tab / Shift-Tab within a markdown table).
public struct TableNavigationResult: Equatable, Sendable {
    /// The cursor position to move to (start of the target cell content).
    public let cursorPosition: Int
    /// The selection range to apply (selects the cell content for easy overwriting).
    public let selectionRange: NSRange
    /// If a new row was appended, the replacement info; otherwise `nil`.
    public let newRowInsertion: NewRowInsertion?

    public init(
        cursorPosition: Int,
        selectionRange: NSRange,
        newRowInsertion: NewRowInsertion? = nil
    ) {
        self.cursorPosition = cursorPosition
        self.selectionRange = selectionRange
        self.newRowInsertion = newRowInsertion
    }
}

/// Describes a new row to be inserted at the end of a table.
public struct NewRowInsertion: Equatable, Sendable {
    /// The range in the original text where the new row should be inserted.
    public let insertionPoint: Int
    /// The text of the new row (e.g., `"| | | |\n"`).
    public let rowText: String

    public init(insertionPoint: Int, rowText: String) {
        self.insertionPoint = insertionPoint
        self.rowText = rowText
    }
}

// MARK: - Table Navigation Engine

/// Pure engine for markdown table keyboard navigation.
///
/// Detects whether the cursor is inside a markdown table and handles
/// Tab (next cell) and Shift-Tab (previous cell) navigation.
/// Tab at the last cell of the last row inserts a new empty row.
///
/// This is a pure helper with no UI dependencies, making it easy to test.
public struct MarkdownTableNavigation: Sendable {

    public init() {}

    // MARK: - Public API

    /// Handles a Tab or Shift-Tab key press at the given cursor position.
    ///
    /// - Parameters:
    ///   - text: The current document text.
    ///   - cursorPosition: The cursor position when Tab was pressed.
    ///   - isShiftTab: `true` for Shift-Tab (backward navigation).
    /// - Returns: A `TableNavigationResult` if the cursor is inside a table, or `nil`
    ///   if the cursor is not in a table (caller should insert a literal tab).
    public func handleTab(
        in text: String,
        cursorPosition: Int,
        isShiftTab: Bool
    ) -> TableNavigationResult? {
        let nsText = text as NSString
        let safeCursor = min(max(cursorPosition, 0), nsText.length)

        // 1. Find the current line
        let lineRange = nsText.lineRange(for: NSRange(location: safeCursor, length: 0))
        let currentLine = nsText.substring(with: lineRange)

        // 2. Check if current line is a table row
        guard Self.isTableRow(currentLine) else { return nil }

        // 3. Find the full table extent (all contiguous table lines)
        let tableInfo = findTableExtent(in: nsText, containingLineAt: lineRange)

        // 4. Parse all cells with their positions
        let rows = parseTableRows(in: nsText, tableInfo: tableInfo)
        guard !rows.isEmpty else { return nil }

        // 5. Find the current cell
        guard let currentCell = findCell(at: safeCursor, in: rows) else { return nil }

        // 6. Navigate to the target cell
        if isShiftTab {
            return navigateBackward(from: currentCell, rows: rows, in: nsText, tableInfo: tableInfo)
        } else {
            return navigateForward(from: currentCell, rows: rows, in: nsText, tableInfo: tableInfo)
        }
    }

    // MARK: - Table Line Detection

    /// Returns `true` if the line looks like a markdown table row.
    /// A table row starts and ends with `|` (after trimming whitespace).
    public static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3
    }

    /// Returns `true` if the line is a table divider row (e.g., `|---|---|`).
    public static func isDividerRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { return false }
        // Strip pipes and check: only dashes, colons, spaces, pipes
        let inner = trimmed.dropFirst().dropLast()
        return inner.contains("-") &&
            inner.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0 == " " }
    }

    // MARK: - Table Extent

    /// Information about a contiguous table block.
    struct TableInfo {
        /// The range of the entire table in the document.
        let range: NSRange
        /// Line ranges for each row in the table.
        let lineRanges: [NSRange]
    }

    /// Finds all contiguous table lines around the line at `lineRange`.
    private func findTableExtent(
        in nsText: NSString,
        containingLineAt lineRange: NSRange
    ) -> TableInfo {
        var lineRanges: [NSRange] = [lineRange]
        let length = nsText.length

        // Scan backward
        var scanPos = lineRange.location
        while scanPos > 0 {
            let prevLineRange = nsText.lineRange(for: NSRange(location: scanPos - 1, length: 0))
            let prevLine = nsText.substring(with: prevLineRange)
            guard Self.isTableRow(prevLine) else { break }
            lineRanges.insert(prevLineRange, at: 0)
            scanPos = prevLineRange.location
        }

        // Scan forward
        var endPos = lineRange.location + lineRange.length
        while endPos < length {
            let nextLineRange = nsText.lineRange(for: NSRange(location: endPos, length: 0))
            let nextLine = nsText.substring(with: nextLineRange)
            guard Self.isTableRow(nextLine) else { break }
            lineRanges.append(nextLineRange)
            endPos = nextLineRange.location + nextLineRange.length
        }

        let tableStart = lineRanges.first!.location
        let tableEnd = lineRanges.last!.location + lineRanges.last!.length
        return TableInfo(
            range: NSRange(location: tableStart, length: tableEnd - tableStart),
            lineRanges: lineRanges
        )
    }

    // MARK: - Cell Parsing

    /// A single cell in the table with its document-relative position.
    struct CellInfo {
        /// Row index in the table (0 = header, 1 = divider, 2+ = body).
        let row: Int
        /// Column index (0-based).
        let column: Int
        /// The range of the cell content (between pipes, trimmed of leading/trailing space).
        let contentRange: NSRange
        /// Whether this row is a divider row.
        let isDivider: Bool
    }

    /// Parses all cells in the table with their document-relative positions.
    private func parseTableRows(in nsText: NSString, tableInfo: TableInfo) -> [CellInfo] {
        var cells: [CellInfo] = []

        for (rowIndex, lineRange) in tableInfo.lineRanges.enumerated() {
            let line = nsText.substring(with: lineRange)
            let isDivider = Self.isDividerRow(line)

            // Find pipe positions within the line
            let pipePositions = findPipePositions(in: line)
            guard pipePositions.count >= 2 else { continue }

            // Each cell is between consecutive pipes
            for col in 0..<(pipePositions.count - 1) {
                let cellStart = pipePositions[col] + 1 // after the pipe
                let cellEnd = pipePositions[col + 1]   // before the next pipe
                guard cellEnd > cellStart else { continue }

                let cellContent = String(line[line.index(line.startIndex, offsetBy: cellStart)..<line.index(line.startIndex, offsetBy: cellEnd)])

                // Trim leading/trailing spaces to get content range
                let trimmedStart = cellContent.prefix(while: { $0 == " " }).count
                let trimmedEnd = cellContent.reversed().prefix(while: { $0 == " " }).count
                let contentLength = max(cellEnd - cellStart - trimmedStart - trimmedEnd, 0)

                let docLocation = lineRange.location + cellStart + trimmedStart
                cells.append(CellInfo(
                    row: rowIndex,
                    column: col,
                    contentRange: NSRange(location: docLocation, length: contentLength),
                    isDivider: isDivider
                ))
            }
        }

        return cells
    }

    /// Finds the indices of all `|` characters in a line.
    private func findPipePositions(in line: String) -> [Int] {
        var positions: [Int] = []
        for (i, ch) in line.enumerated() {
            if ch == "|" {
                positions.append(i)
            }
        }
        return positions
    }

    /// Finds the cell containing the given cursor position.
    private func findCell(at cursor: Int, in cells: [CellInfo]) -> CellInfo? {
        // First try to find a cell whose content range contains the cursor
        for cell in cells where !cell.isDivider {
            let cellStart = cell.contentRange.location
            let cellEnd = cell.contentRange.location + cell.contentRange.length
            if cursor >= cellStart && cursor <= cellEnd {
                return cell
            }
        }

        // If cursor is between pipes but outside trimmed content (in the spaces),
        // find the cell on the same row nearest to the cursor
        for cell in cells where !cell.isDivider {
            // Expand check to include the spaces around content (pipe to pipe)
            let expandedStart = cell.contentRange.location - 1 // includes leading space
            let expandedEnd = cell.contentRange.location + cell.contentRange.length + 1
            if cursor >= expandedStart && cursor <= expandedEnd {
                return cell
            }
        }

        // Last resort: find the cell on the same line
        for cell in cells where !cell.isDivider {
            // Check by comparing what line the cursor is on
            if cursor >= cell.contentRange.location - cell.column - 2 &&
               cursor < cell.contentRange.location + cell.contentRange.length + 2 {
                return cell
            }
        }

        return nil
    }

    // MARK: - Navigation

    /// Navigate forward (Tab): move to next cell, or insert new row at end.
    private func navigateForward(
        from current: CellInfo,
        rows: [CellInfo],
        in nsText: NSString,
        tableInfo: TableInfo
    ) -> TableNavigationResult {
        // Find navigable cells (skip divider rows), sorted by row then column
        let navigable = rows.filter { !$0.isDivider }
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }

        guard let currentIndex = navigable.firstIndex(where: {
            $0.row == current.row && $0.column == current.column
        }) else {
            // Fallback: select first navigable cell
            if let first = navigable.first {
                return makeResult(for: first)
            }
            return makeResult(for: current)
        }

        let nextIndex = currentIndex + 1

        if nextIndex < navigable.count {
            // Move to next cell
            return makeResult(for: navigable[nextIndex])
        } else {
            // At the last cell — insert a new row
            return insertNewRow(after: tableInfo, columnCount: columnCount(in: navigable), in: nsText)
        }
    }

    /// Navigate backward (Shift-Tab): move to previous cell.
    private func navigateBackward(
        from current: CellInfo,
        rows: [CellInfo],
        in nsText: NSString,
        tableInfo: TableInfo
    ) -> TableNavigationResult {
        let navigable = rows.filter { !$0.isDivider }
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }

        guard let currentIndex = navigable.firstIndex(where: {
            $0.row == current.row && $0.column == current.column
        }) else {
            if let first = navigable.first {
                return makeResult(for: first)
            }
            return makeResult(for: current)
        }

        if currentIndex > 0 {
            return makeResult(for: navigable[currentIndex - 1])
        } else {
            // Already at first cell — stay put
            return makeResult(for: current)
        }
    }

    /// Creates a navigation result that selects a cell's content.
    private func makeResult(for cell: CellInfo) -> TableNavigationResult {
        TableNavigationResult(
            cursorPosition: cell.contentRange.location,
            selectionRange: cell.contentRange
        )
    }

    /// Inserts a new empty row at the end of the table.
    private func insertNewRow(
        after tableInfo: TableInfo,
        columnCount: Int,
        in nsText: NSString
    ) -> TableNavigationResult {
        let cols = max(columnCount, 1)

        // Build the new row: "| | | |\n"
        var row = "|"
        for _ in 0..<cols {
            row += "   |"
        }
        row += "\n"

        let insertionPoint = tableInfo.range.location + tableInfo.range.length

        // The first cell in the new row will be at:
        // insertionPoint + 2 (after "| ")
        let firstCellStart = insertionPoint + 2
        let firstCellLength = 1 // single space for content

        return TableNavigationResult(
            cursorPosition: firstCellStart,
            selectionRange: NSRange(location: firstCellStart, length: firstCellLength),
            newRowInsertion: NewRowInsertion(
                insertionPoint: insertionPoint,
                rowText: row
            )
        )
    }

    /// Counts the number of columns based on the maximum column index.
    private func columnCount(in cells: [CellInfo]) -> Int {
        guard let maxCol = cells.map(\.column).max() else { return 1 }
        return maxCol + 1
    }
}
