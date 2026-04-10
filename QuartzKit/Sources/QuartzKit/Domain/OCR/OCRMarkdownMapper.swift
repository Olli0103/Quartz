#if canImport(Vision) && canImport(PencilKit)
import Foundation
import CoreGraphics

/// Maps OCR text observations (with bounding boxes) into structured Markdown.
///
/// Detects headings, bullet lists, numbered lists, and tables using
/// bounding box geometry and text pattern analysis.
///
/// - Linear: OLL-41 (OCR-to-Markdown mapping engine)
public actor OCRMarkdownMapper {

    // MARK: - Configuration

    /// Height ratio above median to classify as heading.
    private let headingHeightFactor: CGFloat = 1.4

    /// Tolerance for column alignment detection.
    private let columnAlignmentTolerance: CGFloat = 0.03

    /// Minimum rows to classify a group as a table.
    private let minimumTableRows = 3

    // MARK: - Types

    enum BlockType {
        case heading(level: Int)
        case bulletItem
        case numberedItem(index: Int)
        case tableRow(cells: [String])
        case paragraph
    }

    struct ClassifiedBlock {
        let text: String
        let type: BlockType
        let boundingBox: CGRect
        let confidence: Float
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Maps observations to structured Markdown.
    public func mapToMarkdown(_ observations: [HandwritingOCRService.TextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        let blocks = classifyBlocks(observations)
        return renderMarkdown(blocks)
    }

    /// Convenience: maps an OCRResult to Markdown.
    public func mapToMarkdown(_ result: HandwritingOCRService.OCRResult) -> String {
        mapToMarkdown(result.observations)
    }

    // MARK: - Classification

    private func classifyBlocks(_ observations: [HandwritingOCRService.TextObservation]) -> [ClassifiedBlock] {
        guard !observations.isEmpty else { return [] }

        // Sort by Y descending (top of page first in Vision coordinates)
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        // Compute median line height for heading detection
        let heights = sorted.map(\.boundingBox.height).filter { $0 > 0 }
        let medianHeight = heights.isEmpty ? 0 : heights.sorted()[heights.count / 2]

        var blocks: [ClassifiedBlock] = []

        for obs in sorted {
            let type = classifySingle(obs, medianHeight: medianHeight)
            blocks.append(ClassifiedBlock(
                text: obs.text.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                boundingBox: obs.boundingBox,
                confidence: obs.confidence
            ))
        }

        // Post-process: detect table regions
        return detectTables(in: blocks)
    }

    private func classifySingle(
        _ obs: HandwritingOCRService.TextObservation,
        medianHeight: CGFloat
    ) -> BlockType {
        let text = obs.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for bullet patterns
        if let bulletType = detectBullet(text) {
            return bulletType
        }

        // Check for heading based on bounding box height
        if medianHeight > 0 && obs.boundingBox.height > 0 {
            let heightRatio = obs.boundingBox.height / medianHeight
            if heightRatio >= headingHeightFactor * 1.5 {
                return .heading(level: 1)
            } else if heightRatio >= headingHeightFactor {
                return .heading(level: 2)
            }
        }

        return .paragraph
    }

    private func detectBullet(_ text: String) -> BlockType? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Unordered bullets
        for prefix in ["- ", "* ", "• ", "‣ ", "◦ "] {
            if trimmed.hasPrefix(prefix) {
                return .bulletItem
            }
        }

        // Numbered items
        if let match = trimmed.range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) {
            let numStr = trimmed[trimmed.startIndex..<match.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            if let num = Int(numStr) {
                return .numberedItem(index: num)
            }
            // Fallback: extract number from matched prefix
            let prefix = String(trimmed[match])
            let digits = prefix.filter(\.isNumber)
            if let num = Int(digits) {
                return .numberedItem(index: num)
            }
        }

        return nil
    }

    // MARK: - Table Detection

    private func detectTables(in blocks: [ClassifiedBlock]) -> [ClassifiedBlock] {
        guard blocks.count >= minimumTableRows else { return blocks }

        var result = blocks
        var i = 0

        while i < result.count {
            guard case .paragraph = result[i].type else {
                i += 1
                continue
            }

            var runEnd = i + 1
            while runEnd < result.count {
                if case .paragraph = result[runEnd].type {
                    runEnd += 1
                } else {
                    break
                }
            }

            let runLength = runEnd - i
            if runLength >= minimumTableRows {
                let runBlocks = Array(result[i..<runEnd])
                if let tableBlocks = tryParseAsTable(runBlocks) {
                    result.replaceSubrange(i..<runEnd, with: tableBlocks)
                    i += tableBlocks.count
                    continue
                }
            }

            i += 1
        }

        return result
    }

    private func tryParseAsTable(_ blocks: [ClassifiedBlock]) -> [ClassifiedBlock]? {
        let splitRows = blocks.map { block -> [String] in
            let text = block.text
            let tabCells = text.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if tabCells.count >= 2 { return tabCells }

            let spaceCells = text.components(separatedBy: "   ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if spaceCells.count >= 2 { return spaceCells }

            return [text]
        }

        let columnCounts = splitRows.map(\.count)
        let maxCols = columnCounts.max() ?? 0

        guard maxCols >= 2 else { return nil }

        let consistentRows = columnCounts.filter { abs($0 - maxCols) <= 1 }.count
        guard consistentRows >= blocks.count - 1 else { return nil }

        return zip(blocks, splitRows).map { block, cells in
            ClassifiedBlock(
                text: block.text,
                type: .tableRow(cells: cells),
                boundingBox: block.boundingBox,
                confidence: block.confidence
            )
        }
    }

    // MARK: - Rendering

    private func renderMarkdown(_ blocks: [ClassifiedBlock]) -> String {
        var lines: [String] = []
        var inTable = false
        var tableColumnCount = 0

        for block in blocks {
            switch block.type {
            case .heading(let level):
                if inTable { inTable = false }
                let prefix = String(repeating: "#", count: level)
                lines.append("")
                lines.append("\(prefix) \(block.text)")
                lines.append("")

            case .bulletItem:
                if inTable { inTable = false }
                let text = stripBulletPrefix(block.text)
                lines.append("- \(text)")

            case .numberedItem(let index):
                if inTable { inTable = false }
                let text = stripNumberedPrefix(block.text)
                lines.append("\(index). \(text)")

            case .tableRow(let cells):
                let paddedCells = padCells(cells, to: max(tableColumnCount, cells.count))
                let row = "| " + paddedCells.joined(separator: " | ") + " |"

                if !inTable {
                    inTable = true
                    tableColumnCount = cells.count
                    lines.append("")
                    lines.append(row)
                    let separator = "| " + paddedCells.map { String(repeating: "-", count: max($0.count, 3)) }.joined(separator: " | ") + " |"
                    lines.append(separator)
                } else {
                    lines.append(row)
                }

            case .paragraph:
                if inTable { inTable = false }
                lines.append("")
                lines.append(block.text)
            }
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    // MARK: - Helpers

    private func stripBulletPrefix(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "• ", "‣ ", "◦ "] {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count))
                break
            }
        }
        return t
    }

    private func stripNumberedPrefix(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        if let range = t.range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) {
            t = String(t[range.upperBound...])
        }
        return t
    }

    private func padCells(_ cells: [String], to count: Int) -> [String] {
        var padded = cells
        while padded.count < count {
            padded.append("")
        }
        return padded
    }
}
#endif
