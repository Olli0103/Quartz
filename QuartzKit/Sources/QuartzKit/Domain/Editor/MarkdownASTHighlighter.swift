import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Background AST Parser (120fps Guarantee)

/// Converts swift-markdown `SourceRange` (line:column) to `NSRange`.
/// Column is UTF-8 bytes from line start; we convert to character offset.
private func sourceRangeToNSRange(_ range: SourceRange, in source: String) -> NSRange? {
    let lines = source.components(separatedBy: .newlines)
    guard !lines.isEmpty else { return nil }

    func locationToOffset(_ loc: SourceLocation) -> Int? {
        let lineIdx = loc.line - 1
        guard lineIdx >= 0, lineIdx < lines.count else { return nil }
        var offset = 0
        for i in 0..<lineIdx {
            offset += lines[i].count + 1 // +1 for newline
        }
        let lineContent = lines[lineIdx]
        let colBytes = loc.column - 1
        if colBytes <= 0 { return offset }
        let utf8 = lineContent.utf8
        guard colBytes <= utf8.count else { return offset + lineContent.count }
        let byteIndex = utf8.index(utf8.startIndex, offsetBy: colBytes)
        guard let charIndex = byteIndex.samePosition(in: lineContent) else { return offset }
        return offset + lineContent.distance(from: lineContent.startIndex, to: charIndex)
    }

    guard let start = locationToOffset(range.lowerBound),
          let end = locationToOffset(range.upperBound),
          start <= end, end <= (source as NSString).length else {
        return nil
    }
    return NSRange(location: start, length: end - start)
}

/// Attribute application record for a range.
public struct HighlightSpan: @unchecked Sendable {
    public let range: NSRange
    public let font: PlatformFont
    public let color: PlatformColor?
    public let traits: FontTraits
    public let backgroundColor: PlatformColor?
    public let strikethrough: Bool
    /// When true, only the foreground color is applied (overlays on existing attributes).
    /// Used for muting syntax delimiter characters (e.g., `#`, `**`, `` ` ``).
    public let isOverlay: Bool

    public init(range: NSRange, font: PlatformFont, color: PlatformColor?, traits: FontTraits, backgroundColor: PlatformColor?, strikethrough: Bool, isOverlay: Bool = false) {
        self.range = range
        self.font = font
        self.color = color
        self.traits = traits
        self.backgroundColor = backgroundColor
        self.strikethrough = strikethrough
        self.isOverlay = isOverlay
    }
}

#if canImport(UIKit)
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#endif

#if canImport(UIKit)
public struct FontTraits: Sendable {
    public var bold: Bool
    public var italic: Bool
    public init(bold: Bool, italic: Bool) {
        self.bold = bold
        self.italic = italic
    }
}
#elseif canImport(AppKit)
public struct FontTraits: Sendable {
    public var bold: Bool
    public var italic: Bool
    public init(bold: Bool, italic: Bool) {
        self.bold = bold
        self.italic = italic
    }
}
#endif

/// Actor that parses markdown on a background thread and returns highlight spans.
/// Debouncing and async parsing keep the main thread free for 120fps.
public actor MarkdownASTHighlighter {
    private(set) public var baseFontSize: CGFloat
    public var fontFamily: AppearanceManager.EditorFontFamily = .system
    public var lineSpacing: CGFloat = 1.5
    private var parseTask: Task<[HighlightSpan], Never>?
    private let debounceInterval: UInt64 = 80_000_000 // 80ms in nanoseconds

    /// Maximum document size (characters) before we skip highlighting for performance.
    /// Documents larger than ~500KB of text would cause noticeable lag.
    private static let maxDocumentSize = 500_000

    /// Threshold above which we use a longer debounce interval.
    private static let largeDocumentThreshold = 50_000

    public init(baseFontSize: CGFloat = 14) {
        self.baseFontSize = baseFontSize
    }

    /// Updates font family and line spacing from the main actor.
    public func updateSettings(fontFamily: AppearanceManager.EditorFontFamily, lineSpacing: CGFloat) {
        self.fontFamily = fontFamily
        self.lineSpacing = lineSpacing
    }

    /// Parses markdown and returns highlight spans. Cancels any in-flight parse.
    /// Call from background; result is applied on main thread.
    public func parse(_ markdown: String) async -> [HighlightSpan] {
        parseTask?.cancel()

        // Skip highlighting for very large documents to prevent UI lag
        guard markdown.count < Self.maxDocumentSize else {
            return []
        }

        let task = Task<[HighlightSpan], Never> { [baseFontSize, fontFamily] in
            await Task.yield()
            return Self.parseSync(markdown, baseFontSize: baseFontSize, fontFamily: fontFamily)
        }
        parseTask = task
        return await task.value
    }

    /// Debounced parse: waits `debounceInterval` then parses. Cancels previous.
    /// Uses longer debounce for large documents.
    public func parseDebounced(_ markdown: String) async -> [HighlightSpan] {
        parseTask?.cancel()

        // Adaptive debounce: longer delay for larger documents
        let delay: UInt64 = markdown.count > Self.largeDocumentThreshold
            ? debounceInterval * 2  // 160ms for large docs
            : debounceInterval       // 80ms for normal docs

        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return [] }
        return await parse(markdown)
    }

    private static func parseSync(_ markdown: String, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let doc = Document(parsing: markdown)
        collectSpans(from: doc, in: markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, into: &spans)
        return spans
    }

    private static func collectSpans(from markup: any Markup, in source: String, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily, into spans: inout [HighlightSpan]) {
        if let range = markup.range, let nsRange = sourceRangeToNSRange(range, in: source), nsRange.length > 0 {
            if let heading = markup as? Heading {
                let scale: CGFloat = switch heading.level {
                case 1: 1.7
                case 2: 1.45
                case 3: 1.25
                case 4: 1.12
                default: 1.05
                }
                let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize * scale, weight: .bold)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false))
                let headingText = (source as NSString).substring(with: nsRange)
                if let prefixEnd = headingText.firstIndex(of: " "),
                   headingText.hasPrefix("#") {
                    let prefixLength = headingText.distance(from: headingText.startIndex, to: prefixEnd) + 1
                    let prefixRange = NSRange(location: nsRange.location, length: prefixLength)
                    let mutedColor: PlatformColor
                    #if canImport(UIKit)
                    mutedColor = UIColor.tertiaryLabel
                    #elseif canImport(AppKit)
                    mutedColor = NSColor.tertiaryLabelColor
                    #endif
                    spans.append(HighlightSpan(range: prefixRange, font: font, color: mutedColor, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                }
                return
            }
            if markup is Strong {
                let syntaxLen = 2
                let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize, weight: .bold)
                let mutedColor: PlatformColor
                #if canImport(UIKit)
                mutedColor = UIColor.tertiaryLabel
                #elseif canImport(AppKit)
                mutedColor = NSColor.tertiaryLabelColor
                #endif
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false))
                // Mute opening and closing ** delimiters
                if nsRange.length > syntaxLen * 2 {
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location + nsRange.length - syntaxLen, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                }
                return
            }
            if markup is Emphasis {
                let syntaxLen = 1
                let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize, italic: true)
                let mutedColor: PlatformColor
                #if canImport(UIKit)
                mutedColor = UIColor.tertiaryLabel
                #elseif canImport(AppKit)
                mutedColor = NSColor.tertiaryLabelColor
                #endif
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: true), backgroundColor: nil, strikethrough: false))
                // Mute opening and closing * delimiters
                if nsRange.length > syntaxLen * 2 {
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: false, italic: true), backgroundColor: nil, strikethrough: false, isOverlay: true))
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location + nsRange.length - syntaxLen, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: false, italic: true), backgroundColor: nil, strikethrough: false, isOverlay: true))
                }
                return
            }
            if markup is InlineCode {
                let syntaxLen = 1
                let font = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
                let mutedColor: PlatformColor
                #if canImport(UIKit)
                mutedColor = UIColor.tertiaryLabel
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: UIColor.systemFill, strikethrough: false))
                #elseif canImport(AppKit)
                mutedColor = NSColor.tertiaryLabelColor
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), strikethrough: false))
                #endif
                // Mute backtick delimiters
                if nsRange.length > syntaxLen * 2 {
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: false, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location + nsRange.length - syntaxLen, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: false, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                }
                return
            }
            if markup is CodeBlock {
                let font = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
                #if canImport(UIKit)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: UIColor.systemFill, strikethrough: false))
                #elseif canImport(AppKit)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), strikethrough: false))
                #endif
                return
            }
            if markup is Strikethrough {
                let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)
                let mutedColor: PlatformColor
                let strikeColor: PlatformColor
                #if canImport(UIKit)
                mutedColor = UIColor.tertiaryLabel
                strikeColor = UIColor.secondaryLabel
                #elseif canImport(AppKit)
                mutedColor = NSColor.tertiaryLabelColor
                strikeColor = NSColor.secondaryLabelColor
                #endif
                spans.append(HighlightSpan(range: nsRange, font: font, color: strikeColor, traits: FontTraits(bold: false, italic: false), backgroundColor: nil, strikethrough: true))
                // Mute ~~ delimiters
                let syntaxLen = 2
                if nsRange.length > syntaxLen * 2 {
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: false, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                    spans.append(HighlightSpan(range: NSRange(location: nsRange.location + nsRange.length - syntaxLen, length: syntaxLen), font: font, color: mutedColor, traits: FontTraits(bold: false, italic: false), backgroundColor: nil, strikethrough: false, isOverlay: true))
                }
                return
            }
            if markup is Markdown.Table {
                // Don't override the font or background — keep standard proportional body text.
                // Instead, dim the pipe | and dash - syntax characters so the grid fades away
                // while the cell content stays readable.
                let tableText = (source as NSString).substring(with: nsRange)
                let bodyFont = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)
                let mutedColor: PlatformColor
                #if canImport(UIKit)
                mutedColor = UIColor.quaternaryLabel
                #elseif canImport(AppKit)
                mutedColor = NSColor.quaternaryLabelColor
                #endif

                // Scan for | and - characters within the table range and mute them
                for (i, ch) in tableText.enumerated() {
                    if ch == "|" || ch == "-" {
                        let charRange = NSRange(location: nsRange.location + i, length: 1)
                        spans.append(HighlightSpan(
                            range: charRange,
                            font: bodyFont,
                            color: mutedColor,
                            traits: FontTraits(bold: false, italic: false),
                            backgroundColor: nil,
                            strikethrough: false,
                            isOverlay: true
                        ))
                    }
                }
                // Don't return — let children (cell contents) get their normal inline styling
            }
            if markup is BlockQuote {
                let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize, italic: true)
                let quoteColor: PlatformColor
                #if canImport(UIKit)
                quoteColor = UIColor.secondaryLabel
                #elseif canImport(AppKit)
                quoteColor = NSColor.secondaryLabelColor
                #endif
                spans.append(HighlightSpan(range: nsRange, font: font, color: quoteColor, traits: FontTraits(bold: false, italic: true), backgroundColor: nil, strikethrough: false))
                // Don't recurse into children — blockquote styles the whole range
                return
            }
            if markup is Link {
                let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)
                let linkColor: PlatformColor
                #if canImport(UIKit)
                linkColor = UIColor.systemBlue
                #elseif canImport(AppKit)
                linkColor = NSColor.linkColor
                #endif
                spans.append(HighlightSpan(range: nsRange, font: font, color: linkColor, traits: FontTraits(bold: false, italic: false), backgroundColor: nil, strikethrough: false))
                return
            }
        }
        for child in markup.children {
            collectSpans(from: child, in: source, baseFontSize: baseFontSize, fontFamily: fontFamily, into: &spans)
        }
    }
}
