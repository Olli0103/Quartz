import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Walks the swift-markdown AST and produces a richly-styled `NSAttributedString`
/// suitable for PDF rendering (via CTFramesetter) and RTF export.
///
/// Uses print-friendly styling: explicit black text, system fonts at fixed sizes,
/// proper paragraph spacing for headings and lists.
struct RichAttributedStringBuilder: MarkupVisitor {
    typealias Result = NSMutableAttributedString

    /// Base body font size for export.
    static let bodySize: CGFloat = 12
    static let titleSize: CGFloat = 22
    static let h1Size: CGFloat = 20
    static let h2Size: CGFloat = 17
    static let h3Size: CGFloat = 14
    static let h4Size: CGFloat = 12
    static let codeSize: CGFloat = 10.5

    private var listDepth = 0
    private var orderedListCounters: [Int] = []
    private var isInOrderedList = false

    // MARK: - Public Entry Point

    /// Renders markdown text into an `NSAttributedString` with print-ready styling.
    static func build(markdown text: String, title: String) -> NSAttributedString {
        let document = Document(parsing: text, options: [.parseBlockDirectives])
        var visitor = RichAttributedStringBuilder()

        // Title
        let titleStr = NSMutableAttributedString(
            string: title + "\n\n",
            attributes: [
                .font: Self.boldFont(size: titleSize),
                .foregroundColor: Self.textColor,
                .paragraphStyle: Self.paragraphStyle(spacingAfter: 8)
            ]
        )

        let body = visitor.visit(document)
        titleStr.append(body)
        return titleStr
    }

    // MARK: - Block Elements

    mutating func defaultVisit(_ markup: any Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in document.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in heading.children {
            result.append(visit(child))
        }
        result.append(NSAttributedString(string: "\n"))

        let fontSize: CGFloat = switch heading.level {
        case 1: Self.h1Size
        case 2: Self.h2Size
        case 3: Self.h3Size
        default: Self.h4Size
        }

        let range = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .font: Self.boldFont(size: fontSize),
            .foregroundColor: Self.textColor,
            .paragraphStyle: Self.paragraphStyle(spacingBefore: 16, spacingAfter: 4)
        ], range: range)

        return result
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in paragraph.children {
            result.append(visit(child))
        }
        result.append(NSAttributedString(string: "\n"))

        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.paragraphStyle, value: Self.paragraphStyle(spacingAfter: 6), range: range)

        return result
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in blockQuote.children {
            result.append(visit(child))
        }

        let range = NSRange(location: 0, length: result.length)
        let style = Self.paragraphStyle(headIndent: 20, firstLineIndent: 20, spacingAfter: 6)
        result.addAttributes([
            .foregroundColor: Self.secondaryTextColor,
            .paragraphStyle: style
        ], range: range)

        return result
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let result = NSMutableAttributedString(
            string: code + "\n\n",
            attributes: [
                .font: Self.monoFont(size: Self.codeSize),
                .foregroundColor: Self.textColor,
                .paragraphStyle: Self.paragraphStyle(headIndent: 12, firstLineIndent: 12, spacingAfter: 8)
            ]
        )
        return result
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(
            string: "\n\n",
            attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: Self.secondaryTextColor
            ]
        )
        return result
    }

    // MARK: - Tables (rendered as monospaced aligned text)

    mutating func visitTable(_ table: Markdown.Table) -> NSMutableAttributedString {
        // Completely hijack table rendering — do NOT call visit() on children.
        // Extract all cell strings into a 2D array, then build an aligned monospaced grid.
        var rows: [[String]] = []
        var columnCount = 0

        for child in table.children {
            if let head = child as? Markdown.Table.Head {
                // Head cells are direct children of Table.Head
                var headerCells: [String] = []
                for cell in head.children {
                    headerCells.append(extractPlainText(from: cell))
                }
                if !headerCells.isEmpty {
                    columnCount = max(columnCount, headerCells.count)
                    rows.append(headerCells)
                }
            } else if let body = child as? Markdown.Table.Body {
                for row in body.children {
                    var rowCells: [String] = []
                    // Body contains Table.Row, each Row contains Table.Cell
                    for cell in row.children {
                        rowCells.append(extractPlainText(from: cell))
                    }
                    if !rowCells.isEmpty {
                        columnCount = max(columnCount, rowCells.count)
                        rows.append(rowCells)
                    }
                }
            }
        }

        guard !rows.isEmpty, columnCount > 0 else {
            return NSMutableAttributedString(string: "\n")
        }

        // Normalize: pad each row to have the same number of columns
        for i in rows.indices {
            while rows[i].count < columnCount {
                rows[i].append("")
            }
        }

        // Calculate max character width per column (min 3 for readability)
        var colWidths = [Int](repeating: 3, count: columnCount)
        for row in rows {
            for (col, cell) in row.enumerated() {
                colWidths[col] = max(colWidths[col], cell.count)
            }
        }

        // Build the padded ASCII grid
        var tableText = ""
        for (rowIndex, row) in rows.enumerated() {
            var line = "| "
            for (col, cell) in row.enumerated() {
                line += cell.padding(toLength: colWidths[col], withPad: " ", startingAt: 0)
                line += " | "
            }
            tableText += line.trimmingCharacters(in: .whitespaces) + "\n"

            // Separator after header row
            if rowIndex == 0 {
                var sep = "| "
                for col in 0..<columnCount {
                    sep += String(repeating: "-", count: colWidths[col])
                    sep += " | "
                }
                tableText += sep.trimmingCharacters(in: .whitespaces) + "\n"
            }
        }
        tableText += "\n"

        // Return as a single monospaced attributed string — no child traversal
        return NSMutableAttributedString(
            string: tableText,
            attributes: [
                .font: Self.monoFont(size: Self.codeSize),
                .foregroundColor: Self.textColor,
                .paragraphStyle: Self.paragraphStyle(spacingAfter: 8)
            ]
        )
    }

    mutating func visitTableHead(_ head: Markdown.Table.Head) -> NSMutableAttributedString {
        // Handled by visitTable
        NSMutableAttributedString()
    }

    mutating func visitTableBody(_ body: Markdown.Table.Body) -> NSMutableAttributedString {
        // Handled by visitTable
        NSMutableAttributedString()
    }

    mutating func visitTableRow(_ row: Markdown.Table.Row) -> NSMutableAttributedString {
        // Handled by visitTable
        NSMutableAttributedString()
    }

    mutating func visitTableCell(_ cell: Markdown.Table.Cell) -> NSMutableAttributedString {
        // Handled by visitTable
        NSMutableAttributedString()
    }

    /// Extracts plain text from a markup node (strips formatting).
    private func extractPlainText(from markup: any Markup) -> String {
        var text = ""
        for child in markup.children {
            if let t = child as? Markdown.Text {
                text += t.string
            } else if let code = child as? InlineCode {
                text += code.code
            } else if let strong = child as? Strong {
                text += extractPlainText(from: strong)
            } else if let em = child as? Emphasis {
                text += extractPlainText(from: em)
            } else {
                text += extractPlainText(from: child)
            }
        }
        return text
    }

    // MARK: - Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSMutableAttributedString {
        listDepth += 1
        let saved = isInOrderedList
        isInOrderedList = false
        let result = NSMutableAttributedString()
        for child in list.children {
            result.append(visit(child))
        }
        isInOrderedList = saved
        listDepth -= 1
        return result
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSMutableAttributedString {
        listDepth += 1
        let saved = isInOrderedList
        isInOrderedList = true
        orderedListCounters.append(0)
        let result = NSMutableAttributedString()
        for child in list.children {
            result.append(visit(child))
        }
        orderedListCounters.removeLast()
        isInOrderedList = saved
        listDepth -= 1
        return result
    }

    mutating func visitListItem(_ listItem: ListItem) -> NSMutableAttributedString {
        let indent = CGFloat(listDepth) * 20

        let bullet: String
        if let checkbox = listItem.checkbox {
            bullet = checkbox == .checked ? "  ☑ " : "  ☐ "
        } else if isInOrderedList, !orderedListCounters.isEmpty {
            orderedListCounters[orderedListCounters.count - 1] += 1
            bullet = "  \(orderedListCounters.last!). "
        } else {
            bullet = "  • "
        }

        let result = NSMutableAttributedString(
            string: bullet,
            attributes: [
                .font: Self.bodyFont(size: Self.bodySize),
                .foregroundColor: Self.textColor
            ]
        )

        for child in listItem.children {
            result.append(visit(child))
        }

        let range = NSRange(location: 0, length: result.length)
        let style = Self.paragraphStyle(headIndent: indent + 20, firstLineIndent: indent)
        result.addAttribute(.paragraphStyle, value: style, range: range)

        return result
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text.string,
            attributes: [
                .font: Self.bodyFont(size: Self.bodySize),
                .foregroundColor: Self.textColor
            ]
        )
    }

    mutating func visitStrong(_ strong: Strong) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in strong.children { result.append(visit(child)) }
        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: Self.boldFont(size: Self.bodySize), range: range)
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in emphasis.children { result.append(visit(child)) }
        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: Self.italicFont(size: Self.bodySize), range: range)
        return result
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in strikethrough.children { result.append(visit(child)) }
        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: inlineCode.code,
            attributes: [
                .font: Self.monoFont(size: Self.codeSize),
                .foregroundColor: Self.textColor
            ]
        )
    }

    mutating func visitLink(_ link: Markdown.Link) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children { result.append(visit(child)) }
        if let dest = link.destination, let url = URL(string: dest) {
            let range = NSRange(location: 0, length: result.length)
            result.addAttribute(.link, value: url, range: range)
        }
        return result
    }

    mutating func visitImage(_ image: Markdown.Image) -> NSMutableAttributedString {
        let alt = image.plainText.isEmpty ? "Image" : image.plainText
        return NSMutableAttributedString(
            string: "[\(alt)]",
            attributes: [
                .font: Self.italicFont(size: Self.bodySize),
                .foregroundColor: Self.secondaryTextColor
            ]
        )
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSMutableAttributedString {
        NSMutableAttributedString(string: " ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSMutableAttributedString {
        NSMutableAttributedString(string: "\n")
    }

    // MARK: - Font Helpers

    #if canImport(UIKit)
    private static var textColor: UIColor { .black }
    private static var secondaryTextColor: UIColor { .darkGray }
    private static func bodyFont(size: CGFloat) -> UIFont { .systemFont(ofSize: size) }
    private static func boldFont(size: CGFloat) -> UIFont { .boldSystemFont(ofSize: size) }
    private static func italicFont(size: CGFloat) -> UIFont { .italicSystemFont(ofSize: size) }
    private static func monoFont(size: CGFloat) -> UIFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    #elseif canImport(AppKit)
    private static var textColor: NSColor { .black }
    private static var secondaryTextColor: NSColor { .darkGray }
    private static func bodyFont(size: CGFloat) -> NSFont { .systemFont(ofSize: size) }
    private static func boldFont(size: CGFloat) -> NSFont { .boldSystemFont(ofSize: size) }
    private static func italicFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    }
    private static func monoFont(size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    #endif

    // MARK: - Paragraph Style Helper

    private static func paragraphStyle(
        headIndent: CGFloat = 0,
        firstLineIndent: CGFloat = 0,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 4
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineIndent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineSpacing = 2
        return style
    }
}
