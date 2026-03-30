import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Background AST Parser (120fps Guarantee)

// MARK: - Table Row Style (Custom Attribute)

/// Identifies a table row's role for custom background drawing.
/// Stored as a custom `NSAttributedString.Key` so `drawBackground(in:)`
/// can find contiguous table lines and paint uniform-width blocks.
public enum QuartzTableRowStyle: Int, Sendable {
    case header = 0
    case divider = 1
    case bodyEven = 2
    case bodyOdd = 3
}

public extension NSAttributedString.Key {
    /// Custom attribute marking a line as part of a markdown table.
    /// Value is `QuartzTableRowStyle.rawValue` (Int).
    static let quartzTableRowStyle = NSAttributedString.Key("QuartzTableRowStyle")
}

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
    /// When set, an NSTextAttachment is applied to the first character of the range.
    /// Used for inline image rendering — the attachment replaces the `!` character visually.
    public let attachment: NSTextAttachment?
    /// When set, a paragraph style is applied to the range. Used for table spacing.
    public let paragraphStyle: NSParagraphStyle?
    /// When set, marks this span as a table row for custom background drawing.
    public let tableRowStyle: QuartzTableRowStyle?
    /// When set, applies NSAttributedString.Key.kern to the range.
    /// Used for elastic table column alignment.
    public let kern: CGFloat?

    public init(range: NSRange, font: PlatformFont, color: PlatformColor?, traits: FontTraits, backgroundColor: PlatformColor?, strikethrough: Bool, isOverlay: Bool = false, attachment: NSTextAttachment? = nil, paragraphStyle: NSParagraphStyle? = nil, tableRowStyle: QuartzTableRowStyle? = nil, kern: CGFloat? = nil) {
        self.range = range
        self.font = font
        self.color = color
        self.traits = traits
        self.backgroundColor = backgroundColor
        self.strikethrough = strikethrough
        self.isOverlay = isOverlay
        self.attachment = attachment
        self.paragraphStyle = paragraphStyle
        self.tableRowStyle = tableRowStyle
        self.kern = kern
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
    /// Root URL of the current vault. Used to resolve relative image paths in `![](assets/...)`.
    public var vaultRootURL: URL?
    /// URL of the currently open note. Used for relative path resolution.
    public var noteURL: URL?
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
    public func updateSettings(fontFamily: AppearanceManager.EditorFontFamily, lineSpacing: CGFloat, vaultRootURL: URL? = nil, noteURL: URL? = nil) {
        self.fontFamily = fontFamily
        self.lineSpacing = lineSpacing
        if let vaultRootURL { self.vaultRootURL = vaultRootURL }
        if let noteURL { self.noteURL = noteURL }
    }

    /// Parses markdown and returns highlight spans. Cancels any in-flight parse.
    /// Call from background; result is applied on main thread.
    public func parse(_ markdown: String) async -> [HighlightSpan] {
        parseTask?.cancel()

        // Skip highlighting for very large documents to prevent UI lag
        guard markdown.count < Self.maxDocumentSize else {
            return []
        }

        let task = Task<[HighlightSpan], Never> { [baseFontSize, fontFamily, vaultRootURL, noteURL] in
            await Task.yield()
            return Self.parseSync(markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL)
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

    private static func parseSync(_ markdown: String, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily, vaultRootURL: URL?, noteURL: URL?) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let doc = Document(parsing: markdown)
        collectSpans(from: doc, in: markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL, into: &spans)
        return spans
    }

    private static func collectSpans(from markup: any Markup, in source: String, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily, vaultRootURL: URL?, noteURL: URL?, into spans: inout [HighlightSpan]) {
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
                // Rich table rendering: monospaced font, zebra stripes, dynamic kerning
                // for perfect column alignment without mutating the markdown source.
                let monoFont = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
                // NO bold font — all rows use identical monoFont for perfect column alignment.
                // Header is distinguished by background color only (via drawBackground).

                // Monospaced character width — all chars are the same width
                let monoCharWidth: CGFloat = {
                    let attrs: [NSAttributedString.Key: Any] = [.font: monoFont]
                    return ("M" as NSString).size(withAttributes: attrs).width
                }()

                let mutedColor: PlatformColor
                let clearColor: PlatformColor
                #if canImport(UIKit)
                mutedColor = UIColor.tertiaryLabel
                clearColor = UIColor.clear
                #elseif canImport(AppKit)
                mutedColor = NSColor.tertiaryLabelColor
                clearColor = NSColor.clear
                #endif

                // Paragraph styles
                let firstLineParagraph = NSMutableParagraphStyle()
                firstLineParagraph.paragraphSpacingBefore = 8
                firstLineParagraph.paragraphSpacing = 0
                firstLineParagraph.lineSpacing = 2
                firstLineParagraph.headIndent = 0
                firstLineParagraph.firstLineHeadIndent = 0

                let tableParagraph = NSMutableParagraphStyle()
                tableParagraph.paragraphSpacingBefore = 0
                tableParagraph.paragraphSpacing = 0
                tableParagraph.lineSpacing = 2
                tableParagraph.headIndent = 0
                tableParagraph.firstLineHeadIndent = 0

                // --- Phase 1: Parse all lines into cells, compute max column widths ---
                let tableText = (source as NSString).substring(with: nsRange)
                let tableLines = tableText.components(separatedBy: .newlines)

                var parsedRows: [[String]] = []
                for line in tableLines {
                    if line.isEmpty {
                        parsedRows.append([])
                    } else {
                        // Parse ALL rows including the divider — we need cell widths for kerning
                        parsedRows.append(Self.splitTableRow(line))
                    }
                }

                // Max character width per column (skip divider line for width calc)
                var maxColWidths: [Int] = []
                for (lineIdx, cells) in parsedRows.enumerated() {
                    let isDivider = lineIdx == 1 && tableLines.count > 1 && Self.isTableDividerLine(tableLines[lineIdx])
                    if isDivider { continue } // divider dashes don't count toward column width
                    for (colIdx, cell) in cells.enumerated() {
                        if colIdx >= maxColWidths.count {
                            maxColWidths.append(cell.count)
                        } else if cell.count > maxColWidths[colIdx] {
                            maxColWidths[colIdx] = cell.count
                        }
                    }
                }

                // --- Phase 2: Emit spans with dynamic kerning ---
                var lineOffset = nsRange.location
                var bodyRowIndex = 0

                for (lineIdx, line) in tableLines.enumerated() {
                    let lineLength = (line as NSString).length
                    guard lineLength > 0 else {
                        lineOffset += lineLength + 1
                        continue
                    }

                    let hasTrailingNewline = (lineOffset + lineLength) < (nsRange.location + nsRange.length)
                    let spanLength = hasTrailingNewline ? lineLength + 1 : lineLength
                    let lineRange = NSRange(location: lineOffset, length: spanLength)

                    let isDividerLine = lineIdx == 1 && Self.isTableDividerLine(line)
                    let isHeaderLine = lineIdx == 0
                    let paraStyle = lineIdx == 0 ? firstLineParagraph : tableParagraph

                    // --- Primary span (font, paragraph, table row style) ---
                    if isDividerLine {
                        // Divider: ALL text invisible (dashes AND pipes).
                        // drawBackground paints a clean 1px separator line.
                        spans.append(HighlightSpan(
                            range: lineRange, font: monoFont, color: clearColor,
                            traits: FontTraits(bold: false, italic: false),
                            backgroundColor: nil, strikethrough: false,
                            paragraphStyle: paraStyle, tableRowStyle: .divider
                        ))
                    } else if isHeaderLine {
                        // Header: same monoFont (NOT bold) — distinguished by bg color only
                        spans.append(HighlightSpan(
                            range: lineRange, font: monoFont, color: nil,
                            traits: FontTraits(bold: false, italic: false),
                            backgroundColor: nil, strikethrough: false,
                            paragraphStyle: paraStyle, tableRowStyle: .header
                        ))
                    } else {
                        let rowStyle: QuartzTableRowStyle = (bodyRowIndex % 2 == 0) ? .bodyEven : .bodyOdd
                        spans.append(HighlightSpan(
                            range: lineRange, font: monoFont, color: nil,
                            traits: FontTraits(bold: false, italic: false),
                            backgroundColor: nil, strikethrough: false,
                            paragraphStyle: paraStyle, tableRowStyle: rowStyle
                        ))
                        bodyRowIndex += 1
                    }

                    // --- Overlay: dim pipe characters (skip divider — fully invisible) ---
                    if !isDividerLine {
                        for (charIdx, ch) in line.enumerated() {
                            if ch == "|" {
                                spans.append(HighlightSpan(
                                    range: NSRange(location: lineOffset + charIdx, length: 1),
                                    font: monoFont,
                                    color: mutedColor,
                                    traits: FontTraits(bold: false, italic: false),
                                    backgroundColor: nil, strikethrough: false,
                                    isOverlay: true
                                ))
                            }
                        }
                    }

                    // --- Dynamic kerning: stretch cells to align columns ---
                    // Applies to ALL rows including the divider so pipes align vertically.
                    let cells = parsedRows[lineIdx]
                    var scanIdx = 0
                    if line.hasPrefix("|") { scanIdx = 1 }

                    for (colIdx, cell) in cells.enumerated() {
                        guard colIdx < maxColWidths.count else { break }
                        let maxW = maxColWidths[colIdx]
                        let missing = maxW - cell.count

                        if missing > 0, cell.count > 0 {
                            let lastCharInCell = scanIdx + cell.count - 1
                            if lastCharInCell >= 0, lastCharInCell < lineLength {
                                let kernAmount = CGFloat(missing) * monoCharWidth
                                spans.append(HighlightSpan(
                                    range: NSRange(location: lineOffset + lastCharInCell, length: 1),
                                    font: monoFont,
                                    color: nil,
                                    traits: FontTraits(bold: false, italic: false),
                                    backgroundColor: nil, strikethrough: false,
                                    isOverlay: true,
                                    kern: kernAmount
                                ))
                            }
                        }

                        scanIdx += cell.count + 1
                    }

                    lineOffset += lineLength + 1
                }

                return
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
            if let image = markup as? Markdown.Image {
                // Inline image rendering: resolve the relative path, load the image,
                // and produce an attachment span that replaces the raw syntax visually.
                let attachment = resolveImageAttachment(
                    source: image.source,
                    vaultRootURL: vaultRootURL,
                    noteURL: noteURL
                )

                let bodyFont = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)

                if nsRange.length >= 2 {
                    // First character: will be replaced with U+FFFC in applyHighlightSpans.
                    // Use normal body font so the line fragment has room for the image.
                    spans.append(HighlightSpan(
                        range: NSRange(location: nsRange.location, length: 1),
                        font: bodyFont,
                        color: nil,
                        traits: FontTraits(bold: false, italic: false),
                        backgroundColor: nil,
                        strikethrough: false,
                        attachment: attachment
                    ))

                    // Remaining characters: hide the raw `[alt](path)` syntax
                    let invisibleFont = EditorFontFactory.makeFont(family: fontFamily, size: 0.1)
                    let clearColor: PlatformColor
                    #if canImport(UIKit)
                    clearColor = UIColor.clear
                    #elseif canImport(AppKit)
                    clearColor = NSColor.clear
                    #endif

                    spans.append(HighlightSpan(
                        range: NSRange(location: nsRange.location + 1, length: nsRange.length - 1),
                        font: invisibleFont,
                        color: clearColor,
                        traits: FontTraits(bold: false, italic: false),
                        backgroundColor: nil,
                        strikethrough: false
                    ))
                } else {
                    // Edge case: single character image node — just style as link
                    let linkColor: PlatformColor
                    #if canImport(UIKit)
                    linkColor = UIColor.systemBlue
                    #elseif canImport(AppKit)
                    linkColor = NSColor.linkColor
                    #endif
                    spans.append(HighlightSpan(
                        range: nsRange,
                        font: bodyFont,
                        color: linkColor,
                        traits: FontTraits(bold: false, italic: false),
                        backgroundColor: nil,
                        strikethrough: false
                    ))
                }
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
            collectSpans(from: child, in: source, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL, into: &spans)
        }
    }

    // MARK: - Table Helpers

    /// Returns true if the line is a table header divider (e.g., `|---|---|---:|`).
    private static func isTableDividerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // A divider line contains only |, -, :, and spaces
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
            && trimmed.contains("-")
    }

    /// Splits a markdown table row `| A | B | C |` into cell content strings `["A ", "B ", "C "]`.
    /// Preserves internal whitespace exactly as written — the kern calculation uses
    /// the raw character count so the visual width matches.
    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line
        // Strip leading pipe
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        // Strip trailing pipe
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        // Split on | — each segment is one cell's content
        return trimmed.components(separatedBy: "|")
    }

    // MARK: - Image Resolution

    /// Resolves a relative image path to a `ScaledTextAttachment`, or returns nil
    /// if the path is invalid, the file doesn't exist, or the image can't be loaded.
    /// Runs synchronously — acceptable for V1 since images are small local files.
    private static func resolveImageAttachment(
        source: String?,
        vaultRootURL: URL?,
        noteURL: URL?
    ) -> NSTextAttachment? {
        guard let source, !source.isEmpty else { return nil }

        // Skip remote URLs — only render local vault images
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return nil
        }

        // Resolve relative path against the note's directory (or vault root as fallback)
        let baseURL: URL?
        if let noteURL {
            baseURL = noteURL.deletingLastPathComponent()
        } else {
            baseURL = vaultRootURL
        }
        guard let baseURL else { return nil }

        let resolvedURL = baseURL.appendingPathComponent(source).standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedURL.path(percentEncoded: false)) else {
            return nil
        }

        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: resolvedURL) else { return nil }
        let attachment = ScaledTextAttachment()
        attachment.image = image
        return attachment
        #elseif canImport(UIKit)
        guard let image = UIImage(contentsOfFile: resolvedURL.path(percentEncoded: false)) else { return nil }
        let attachment = ScaledTextAttachment()
        attachment.image = image
        return attachment
        #endif
    }
}
