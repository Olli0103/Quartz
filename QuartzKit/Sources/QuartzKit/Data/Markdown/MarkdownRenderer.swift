import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Wandelt einen Markdown-String via `swift-markdown` AST in einen `AttributedString` um.
///
/// Pipeline: `String` → `Document` (AST) → `AttributedString`
/// Unterstützt Headlines, Bold, Italic, Code, Links, Listen, Checkboxen.
public struct MarkdownRenderer: Sendable {
    public init() {}

    /// Konvertiert Markdown-Text zu einem AttributedString für die Darstellung im Editor.
    public func render(_ markdown: String) -> AttributedString {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseSymbolLinks])
        var visitor = AttributedStringVisitor()
        return visitor.visit(document)
    }
}

// MARK: - AST Visitor

/// Traversiert den `swift-markdown` AST und baut einen `AttributedString` auf.
private struct AttributedStringVisitor: MarkupVisitor {
    typealias Result = AttributedString

    private var currentHeadingLevel: Int = 0

    // MARK: - Block Elements

    mutating func defaultVisit(_ markup: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> AttributedString {
        var result = AttributedString()
        for (index, child) in document.children.enumerated() {
            result.append(visit(child))
            if index < document.childCount - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> AttributedString {
        currentHeadingLevel = heading.level
        var result = AttributedString()
        for child in heading.children {
            result.append(visit(child))
        }
        currentHeadingLevel = 0

        // Heading-Stil: Dynamic Type via preferred text styles
        result.markdownHeadingLevel = heading.level
        #if canImport(UIKit)
        let textStyle: UIFont.TextStyle = switch heading.level {
        case 1: .title1
        case 2: .title2
        case 3: .title3
        case 4: .headline
        default: .body
        }
        let baseFont = UIFont.preferredFont(forTextStyle: textStyle)
        result.font = UIFont.boldSystemFont(ofSize: baseFont.pointSize)
        #elseif canImport(AppKit)
        let scaleFactor: CGFloat = switch heading.level {
        case 1: 2.0
        case 2: 1.7
        case 3: 1.4
        case 4: 1.2
        default: 1.0
        }
        let bodySize = NSFont.systemFontSize
        result.font = .boldSystemFont(ofSize: bodySize * scaleFactor)
        #endif

        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> AttributedString {
        var result = AttributedString()
        for child in paragraph.children {
            result.append(visit(child))
        }
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitText(_ text: Text) -> AttributedString {
        AttributedString(text.string)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> AttributedString {
        AttributedString(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> AttributedString {
        AttributedString("\n")
    }

    // MARK: - Inline Elements

    mutating func visitStrong(_ strong: Strong) -> AttributedString {
        var result = AttributedString()
        for child in strong.children {
            result.append(visit(child))
        }
        result.markdownBold = true
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> AttributedString {
        var result = AttributedString()
        for child in emphasis.children {
            result.append(visit(child))
        }
        result.markdownItalic = true
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> AttributedString {
        var result = AttributedString(inlineCode.code)
        result.markdownInlineCode = true
        #if canImport(UIKit)
        let inlineCodeSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        result.font = .monospacedSystemFont(ofSize: inlineCodeSize, weight: .regular)
        #elseif canImport(AppKit)
        result.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        #endif
        return result
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> AttributedString {
        var result = AttributedString(codeBlock.code)
        result.markdownCodeBlock = true
        result.markdownCodeLanguage = codeBlock.language
        #if canImport(UIKit)
        let codeBlockSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        result.font = .monospacedSystemFont(ofSize: codeBlockSize, weight: .regular)
        #elseif canImport(AppKit)
        result.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        #endif
        result.append(AttributedString("\n"))
        return result
    }

    mutating func visitLink(_ link: Markdown.Link) -> AttributedString {
        var result = AttributedString()
        for child in link.children {
            result.append(visit(child))
        }
        if let destination = link.destination, let url = URL(string: destination) {
            result.link = url
        }
        return result
    }

    mutating func visitImage(_ image: Markdown.Image) -> AttributedString {
        let alt = image.plainText
        var result = AttributedString(alt.isEmpty ? "[Image]" : alt)
        result.markdownImageSource = image.source
        return result
    }

    // MARK: - Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> AttributedString {
        var result = AttributedString()
        for child in list.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitOrderedList(_ list: OrderedList) -> AttributedString {
        var result = AttributedString()
        for (index, child) in list.children.enumerated() {
            let number = list.startIndex + UInt(index)
            var prefix = AttributedString("\(number). ")
            prefix.markdownListPrefix = true
            result.append(prefix)
            result.append(visit(child))
        }
        return result
    }

    mutating func visitListItem(_ item: ListItem) -> AttributedString {
        var result = AttributedString()

        // Checkbox-Erkennung
        if let checkbox = item.checkbox {
            let symbol = checkbox == .checked ? "☑ " : "☐ "
            var check = AttributedString(symbol)
            check.markdownCheckbox = checkbox == .checked
            result.append(check)
        } else if item.parent is UnorderedList {
            var bullet = AttributedString("• ")
            bullet.markdownListPrefix = true
            result.append(bullet)
        }

        for child in item.children {
            result.append(visit(child))
        }
        return result
    }

    // MARK: - Block Quote & Thematic Break

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> AttributedString {
        var result = AttributedString()
        for child in blockQuote.children {
            result.append(visit(child))
        }
        result.markdownBlockQuote = true
        return result
    }

    mutating func visitThematicBreak(_ break: ThematicBreak) -> AttributedString {
        var result = AttributedString("———\n")
        result.markdownThematicBreak = true
        return result
    }
}

// MARK: - Custom AttributedString Keys

/// Custom Attribute-Keys für Markdown-Semantik im AttributedString.
/// Werden vom TextKit 2 Renderer genutzt um das Layout zu steuern.
public enum MarkdownHeadingLevelKey: AttributedStringKey {
    public typealias Value = Int
    public static let name = "markdownHeadingLevel"
}

public enum MarkdownBoldKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownBold"
}

public enum MarkdownItalicKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownItalic"
}

public enum MarkdownInlineCodeKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownInlineCode"
}

public enum MarkdownCodeBlockKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownCodeBlock"
}

public enum MarkdownCodeLanguageKey: AttributedStringKey {
    public typealias Value = String
    public static let name = "markdownCodeLanguage"
}

public enum MarkdownCheckboxKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownCheckbox"
}

public enum MarkdownListPrefixKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownListPrefix"
}

public enum MarkdownBlockQuoteKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownBlockQuote"
}

public enum MarkdownThematicBreakKey: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "markdownThematicBreak"
}

public enum MarkdownImageSourceKey: AttributedStringKey {
    public typealias Value = String
    public static let name = "markdownImageSource"
}

// MARK: - AttributeScope

public struct MarkdownAttributes: AttributeScope {
    public let markdownHeadingLevel: MarkdownHeadingLevelKey
    public let markdownBold: MarkdownBoldKey
    public let markdownItalic: MarkdownItalicKey
    public let markdownInlineCode: MarkdownInlineCodeKey
    public let markdownCodeBlock: MarkdownCodeBlockKey
    public let markdownCodeLanguage: MarkdownCodeLanguageKey
    public let markdownCheckbox: MarkdownCheckboxKey
    public let markdownListPrefix: MarkdownListPrefixKey
    public let markdownBlockQuote: MarkdownBlockQuoteKey
    public let markdownThematicBreak: MarkdownThematicBreakKey
    public let markdownImageSource: MarkdownImageSourceKey
    public let foundation: AttributeScopes.FoundationAttributes
}

public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<MarkdownAttributes, T>
    ) -> T {
        self[T.self]
    }
}
