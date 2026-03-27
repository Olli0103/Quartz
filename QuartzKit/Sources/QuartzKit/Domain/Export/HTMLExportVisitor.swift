import Foundation
import Markdown

/// Walks the swift-markdown AST and emits a self-contained HTML document.
///
/// Produces a clean, semantic HTML5 file with the `HTMLStylesheet` CSS
/// embedded inline. Supports headings, paragraphs, bold, italic, strikethrough,
/// links, images, code (inline + block), lists (ordered, unordered, checkbox),
/// blockquotes, thematic breaks, and tables.
struct HTMLExportVisitor: MarkupVisitor {
    typealias Result = String

    private var listCounter: [Int] = [] // stack for ordered list numbering

    // MARK: - Full Document

    /// Renders the complete HTML document with embedded CSS.
    static func render(markdown text: String, title: String, metadata: ExportMetadata? = nil) -> String {
        let document = Document(parsing: text, options: [.parseBlockDirectives])
        var visitor = HTMLExportVisitor()
        let bodyHTML = visitor.visit(document)

        var metaHTML = ""
        if let meta = metadata {
            var parts: [String] = []
            if let date = meta.modifiedAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .long
                parts.append(formatter.string(from: date))
            }
            if !meta.tags.isEmpty {
                parts.append(meta.tags.map { "#\($0)" }.joined(separator: " "))
            }
            if !parts.isEmpty {
                metaHTML = "<p class=\"quartz-meta\">\(Self.escape(parts.joined(separator: " &middot; ")))</p>"
            }
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>\(Self.escape(title))</title>
          <style>\(HTMLStylesheet.css)</style>
        </head>
        <body>
          <article class="quartz-export">
            <h1 class="quartz-title">\(Self.escape(title))</h1>
            \(metaHTML)
            \(bodyHTML)
          </article>
        </body>
        </html>
        """
    }

    // MARK: - Block Elements

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined(separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(heading.level, 6)
        let content = heading.children.map { visit($0) }.joined()
        return "<h\(level)>\(content)</h\(level)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = paragraph.children.map { visit($0) }.joined()
        return "<p>\(content)</p>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let content = blockQuote.children.map { visit($0) }.joined(separator: "\n")
        return "<blockquote>\(content)</blockquote>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language ?? ""
        let langAttr = lang.isEmpty ? "" : " class=\"language-\(Self.escape(lang))\""
        return "<pre><code\(langAttr)>\(Self.escape(codeBlock.code.trimmingCharacters(in: .newlines)))</code></pre>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>"
    }

    // MARK: - Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        let items = list.children.map { visit($0) }.joined(separator: "\n")
        return "<ul>\n\(items)\n</ul>"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        listCounter.append(0)
        let items = list.children.map { visit($0) }.joined(separator: "\n")
        listCounter.removeLast()
        return "<ol>\n\(items)\n</ol>"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        if !listCounter.isEmpty {
            listCounter[listCounter.count - 1] += 1
        }

        let content = listItem.children.map { visit($0) }.joined()

        // Check for checkbox
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li><input type=\"checkbox\" disabled\(checked)> \(content)</li>"
        }

        return "<li>\(content)</li>"
    }

    // MARK: - Tables

    mutating func visitTable(_ table: Markdown.Table) -> String {
        let content = table.children.map { visit($0) }.joined(separator: "\n")
        return "<table>\(content)</table>"
    }

    mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> String {
        let cells = tableHead.children.map { child -> String in
            let content = child.children.map { visit($0) }.joined()
            return "<th>\(content)</th>"
        }
        return "<thead><tr>\(cells.joined())</tr></thead>"
    }

    mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> String {
        let rows = tableBody.children.map { visit($0) }.joined(separator: "\n")
        return "<tbody>\(rows)</tbody>"
    }

    mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> String {
        let cells = tableRow.children.map { child -> String in
            let content = child.children.map { visit($0) }.joined()
            return "<td>\(content)</td>"
        }
        return "<tr>\(cells.joined())</tr>"
    }

    mutating func visitTableCell(_ cell: Markdown.Table.Cell) -> String {
        cell.children.map { visit($0) }.joined()
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> String {
        Self.escape(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(strong.children.map { visit($0) }.joined())</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(emphasis.children.map { visit($0) }.joined())</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(strikethrough.children.map { visit($0) }.joined())</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(Self.escape(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let content = link.children.map { visit($0) }.joined()
        let href = link.destination.map { Self.escape($0) } ?? ""
        return "<a href=\"\(href)\">\(content)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let alt = Self.escape(image.plainText)
        let src = image.source.map { Self.escape($0) } ?? ""
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>" }

    // MARK: - Helpers

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
