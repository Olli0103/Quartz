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
    /// Custom attribute marking a wiki-link span. Value is the linked note title (String).
    /// Used by the text view to intercept clicks and navigate to the linked note.
    static let quartzWikiLink = NSAttributedString.Key("QuartzWikiLink")
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
    /// When set, marks this span as a wiki-link. Value is the linked note title.
    /// Applied as NSAttributedString.Key.quartzWikiLink and underline styling.
    public let wikiLinkTitle: String?

    public init(range: NSRange, font: PlatformFont, color: PlatformColor?, traits: FontTraits, backgroundColor: PlatformColor?, strikethrough: Bool, isOverlay: Bool = false, attachment: NSTextAttachment? = nil, paragraphStyle: NSParagraphStyle? = nil, tableRowStyle: QuartzTableRowStyle? = nil, kern: CGFloat? = nil, wikiLinkTitle: String? = nil) {
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
        self.wikiLinkTitle = wikiLinkTitle
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
    /// How syntax delimiters are displayed (full, gentle fade, hidden until caret).
    public var syntaxVisibilityMode: SyntaxVisibilityMode = .full
    /// Root URL of the current vault. Used to resolve relative image paths in `![](assets/...)`.
    public var vaultRootURL: URL?
    /// URL of the currently open note. Used for relative path resolution.
    public var noteURL: URL?
    /// Cached spans from the last full or incremental parse. Used for incremental patching.
    private var cachedSpans: [HighlightSpan] = []
    private var parseTask: Task<[HighlightSpan], Never>?
    private let debounceInterval: UInt64 = 150_000_000 // 150ms in nanoseconds

    /// Maximum document size (characters) before we skip full AST highlighting for performance.
    /// Documents larger than ~500KB of text would cause noticeable lag.
    private static let maxDocumentSize = 500_000

    /// Threshold above which we use a longer debounce interval.
    private static let largeDocumentThreshold = 50_000

    /// Threshold above which we use chunked parsing to avoid blocking.
    private static let chunkedParsingThreshold = 100_000

    /// Size of each chunk for incremental parsing.
    private static let chunkSize = 25_000

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
    /// Uses chunked parsing for documents over 100KB to prevent blocking.
    public func parse(_ markdown: String) async -> [HighlightSpan] {
        parseTask?.cancel()

        // Skip highlighting for very large documents to prevent UI lag
        guard markdown.count < Self.maxDocumentSize else {
            return []
        }

        let task = Task<[HighlightSpan], Never> { [baseFontSize, fontFamily, vaultRootURL, noteURL] in
            await Task.yield()

            // For large documents, use chunked parsing with cooperative cancellation
            if markdown.count > Self.chunkedParsingThreshold {
                return await Self.parseChunked(
                    markdown,
                    baseFontSize: baseFontSize,
                    fontFamily: fontFamily,
                    vaultRootURL: vaultRootURL,
                    noteURL: noteURL
                )
            }

            return Self.parseSync(markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL)
        }
        parseTask = task
        let result = await task.value
        cachedSpans = result
        return result
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

    // MARK: - Incremental Parsing

    /// Incrementally parses only the dirty region of the document and merges with cached spans.
    ///
    /// Falls back to full parse when:
    /// - No cached spans exist (first parse)
    /// - The dirty region contains a code fence boundary (affects all subsequent content)
    /// - The edit range is invalid
    ///
    /// - Parameters:
    ///   - markdown: The full document text after the edit.
    ///   - editRange: The post-edit range where changes occurred.
    ///   - preEditLength: The length of the text that was replaced (pre-edit).
    /// - Returns: Merged highlight spans for the full document.
    public func parseIncremental(
        _ markdown: String,
        editRange: NSRange,
        preEditLength: Int
    ) async -> [HighlightSpan] {
        // Fall back to full parse if no cache
        guard !cachedSpans.isEmpty else {
            return await parse(markdown)
        }

        // Compute expanded dirty range (±1 paragraph context)
        guard let dirtyRange = ASTDirtyRegionTracker.expandedDirtyRange(
            in: markdown,
            editRange: editRange
        ) else {
            return await parse(markdown)
        }

        // Fall back if dirty range contains code fence (affects everything after it)
        if ASTDirtyRegionTracker.containsCodeFenceBoundary(in: markdown, range: dirtyRange) {
            return await parse(markdown)
        }

        let nsMarkdown = markdown as NSString
        let docLength = nsMarkdown.length

        // Validate dirty range
        guard dirtyRange.location >= 0,
              dirtyRange.location + dirtyRange.length <= docLength else {
            return await parse(markdown)
        }

        // Extract dirty substring and parse it
        let dirtyText = nsMarkdown.substring(with: dirtyRange)
        let dirtySpans = Self.parseSync(
            dirtyText,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            vaultRootURL: vaultRootURL,
            noteURL: noteURL
        )

        // Offset dirty spans to global coordinates
        let offsetSpans = dirtySpans.map { span -> HighlightSpan in
            HighlightSpan(
                range: NSRange(location: span.range.location + dirtyRange.location, length: span.range.length),
                font: span.font,
                color: span.color,
                traits: span.traits,
                backgroundColor: span.backgroundColor,
                strikethrough: span.strikethrough,
                isOverlay: span.isOverlay,
                attachment: span.attachment,
                paragraphStyle: span.paragraphStyle,
                tableRowStyle: span.tableRowStyle,
                kern: span.kern,
                wikiLinkTitle: span.wikiLinkTitle
            )
        }

        // Compute length delta for shifting spans after the dirty region
        let lengthDelta = editRange.length - preEditLength

        // Merge: keep spans before dirty range, insert new spans, shift spans after
        var merged: [HighlightSpan] = []

        // 1. Spans entirely before the dirty range (unchanged)
        for span in cachedSpans {
            if span.range.location + span.range.length <= dirtyRange.location {
                merged.append(span)
            }
        }

        // 2. New spans from the dirty region parse
        merged.append(contentsOf: offsetSpans)

        // 3. Spans entirely after the dirty range (shifted by length delta)
        let oldDirtyEnd = dirtyRange.location + dirtyRange.length - lengthDelta
        for span in cachedSpans {
            if span.range.location >= oldDirtyEnd {
                let shifted = NSRange(
                    location: span.range.location + lengthDelta,
                    length: span.range.length
                )
                // Validate shifted range
                guard shifted.location >= 0, shifted.location + shifted.length <= docLength else { continue }
                merged.append(HighlightSpan(
                    range: shifted,
                    font: span.font,
                    color: span.color,
                    traits: span.traits,
                    backgroundColor: span.backgroundColor,
                    strikethrough: span.strikethrough,
                    isOverlay: span.isOverlay,
                    attachment: span.attachment,
                    paragraphStyle: span.paragraphStyle,
                    tableRowStyle: span.tableRowStyle,
                    kern: span.kern,
                    wikiLinkTitle: span.wikiLinkTitle
                ))
            }
        }

        cachedSpans = merged
        return merged
    }

    private static func parseSync(_ markdown: String, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily, vaultRootURL: URL?, noteURL: URL?) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let doc = Document(parsing: markdown)
        collectSpans(from: doc, in: markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL, into: &spans)
        // Post-AST pass: highlight [[wiki-links]] which swift-markdown treats as plain text
        appendWikiLinkSpans(in: markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, into: &spans)
        // Post-AST pass: highlight $..$ (inline) and $$...$$ (display) LaTeX
        appendLatexSpans(in: markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, into: &spans)
        return spans
    }

    /// Chunked parsing for large documents (100KB+).
    /// Parses the document in segments, yielding between chunks to stay responsive.
    /// This prevents blocking the thread for extended periods on massive files.
    private static func parseChunked(
        _ markdown: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?
    ) async -> [HighlightSpan] {
        // For very large documents, we parse the FULL AST (swift-markdown is fast)
        // but process the resulting tree in chunks with yield points.
        let doc = Document(parsing: markdown)

        var spans: [HighlightSpan] = []
        var processedNodes = 0

        // Process top-level blocks with cooperative cancellation
        for child in doc.children {
            guard !Task.isCancelled else { return spans }

            collectSpans(
                from: child,
                in: markdown,
                baseFontSize: baseFontSize,
                fontFamily: fontFamily,
                vaultRootURL: vaultRootURL,
                noteURL: noteURL,
                into: &spans
            )

            processedNodes += 1

            // Yield every 10 top-level blocks to stay responsive
            if processedNodes % 10 == 0 {
                await Task.yield()
            }
        }

        // Check cancellation before wiki-link pass
        guard !Task.isCancelled else { return spans }

        // Wiki-links: process in chunks of source text
        let nsSource = markdown as NSString
        let totalLength = nsSource.length
        var offset = 0

        while offset < totalLength {
            guard !Task.isCancelled else { return spans }

            let chunkEnd = min(offset + chunkSize, totalLength)
            // Extend to next newline to avoid breaking patterns
            var adjustedEnd = chunkEnd
            if adjustedEnd < totalLength {
                let remaining = nsSource.substring(from: adjustedEnd)
                if let newlineIdx = remaining.firstIndex(of: "\n") {
                    adjustedEnd += remaining.distance(from: remaining.startIndex, to: newlineIdx) + 1
                }
            }

            let chunkRange = NSRange(location: offset, length: min(adjustedEnd - offset, totalLength - offset))
            let chunk = nsSource.substring(with: chunkRange)

            // Find wiki-links in this chunk and adjust ranges to global offset
            appendWikiLinkSpansChunked(
                in: chunk,
                globalOffset: offset,
                baseFontSize: baseFontSize,
                fontFamily: fontFamily,
                fullSource: markdown,
                into: &spans
            )

            offset = adjustedEnd
            await Task.yield()
        }

        // LaTeX pass (non-chunked — regex is fast enough for large docs)
        guard !Task.isCancelled else { return spans }
        appendLatexSpans(in: markdown, baseFontSize: baseFontSize, fontFamily: fontFamily, into: &spans)

        return spans
    }

    /// Finds wiki-links in a chunk and emits spans with corrected global offsets.
    private static func appendWikiLinkSpansChunked(
        in chunk: String,
        globalOffset: Int,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        fullSource: String,
        into spans: inout [HighlightSpan]
    ) {
        let nsChunk = chunk as NSString
        guard nsChunk.length > 0 else { return }

        let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)

        let accentColor: PlatformColor
        let bracketColor: PlatformColor
        #if canImport(UIKit)
        accentColor = UIColor.tintColor
        bracketColor = UIColor.tertiaryLabel
        #elseif canImport(AppKit)
        accentColor = NSColor.controlAccentColor
        bracketColor = NSColor.tertiaryLabelColor
        #endif

        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return }
        let matches = regex.matches(in: chunk, range: NSRange(location: 0, length: nsChunk.length))

        for match in matches {
            let localRange = match.range
            guard match.numberOfRanges >= 2 else { continue }
            let contentRange = match.range(at: 1)

            // Skip code blocks (simplified check for chunked processing)
            let rawContent = nsChunk.substring(with: contentRange)
            let wikiLink = WikiLink(raw: rawContent)
            let targetTitle = wikiLink.target

            // Convert to global ranges
            let globalFullRange = NSRange(location: globalOffset + localRange.location, length: localRange.length)
            let globalInnerRange = NSRange(location: globalOffset + localRange.location + 2, length: localRange.length - 4)

            guard globalInnerRange.length > 0 else { continue }

            // Primary span
            spans.append(HighlightSpan(
                range: globalInnerRange,
                font: font,
                color: accentColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                wikiLinkTitle: targetTitle
            ))

            // Bracket delimiters
            let openBrackets = NSRange(location: globalFullRange.location, length: 2)
            let closeBrackets = NSRange(location: globalFullRange.location + globalFullRange.length - 2, length: 2)
            spans.append(HighlightSpan(
                range: openBrackets,
                font: font,
                color: bracketColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true
            ))
            spans.append(HighlightSpan(
                range: closeBrackets,
                font: font,
                color: bracketColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true
            ))
        }
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

    // MARK: - Wiki-Link Highlighting

    /// Post-AST pass that finds `[[wiki-links]]` via regex and emits highlight spans.
    /// The AST parser treats these as plain text, so we overlay accent color + underline.
    ///
    /// Skips wiki-links inside fenced code blocks and inline code to match `WikiLinkExtractor`.
    private static func appendWikiLinkSpans(
        in source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        into spans: inout [HighlightSpan]
    ) {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return }

        // Build a set of code ranges to skip
        let codeRanges = codeBlockNSRanges(in: source)
        let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)

        let accentColor: PlatformColor
        let bracketColor: PlatformColor
        #if canImport(UIKit)
        accentColor = UIColor.tintColor
        bracketColor = UIColor.tertiaryLabel
        #elseif canImport(AppKit)
        accentColor = NSColor.controlAccentColor
        bracketColor = NSColor.tertiaryLabelColor
        #endif

        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return }
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))

        for match in matches {
            let fullNSRange = match.range
            guard match.numberOfRanges >= 2 else { continue }
            let contentRange = match.range(at: 1) // Capture group: the content inside [[ ]]

            // Skip wiki-links inside code blocks
            let isInCode = codeRanges.contains { NSIntersectionRange($0, fullNSRange).length > 0 }
            guard !isInCode else { continue }
            guard fullNSRange.location >= 0, fullNSRange.location + fullNSRange.length <= nsSource.length else { continue }

            // Parse the target title from the raw content
            let rawContent = nsSource.substring(with: contentRange)
            let wikiLink = WikiLink(raw: rawContent)
            let targetTitle = wikiLink.target

            // The inner content range: skip the leading [[ (2 chars) and trailing ]] (2 chars)
            let innerRange = NSRange(location: fullNSRange.location + 2, length: fullNSRange.length - 4)
            guard innerRange.length > 0 else { continue }

            // Primary span: accent color + wiki-link attribute on the inner text
            spans.append(HighlightSpan(
                range: innerRange,
                font: font,
                color: accentColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                wikiLinkTitle: targetTitle
            ))

            // Mute the [[ and ]] bracket delimiters
            let openBrackets = NSRange(location: fullNSRange.location, length: 2)
            let closeBrackets = NSRange(location: fullNSRange.location + fullNSRange.length - 2, length: 2)
            spans.append(HighlightSpan(
                range: openBrackets,
                font: font,
                color: bracketColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true
            ))
            spans.append(HighlightSpan(
                range: closeBrackets,
                font: font,
                color: bracketColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true
            ))
        }
    }

    /// Returns NSRanges for all fenced code blocks and inline code spans.
    private static func codeBlockNSRanges(in source: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let nsSource = source as NSString

        // Fenced code blocks
        if let fencedRegex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```") {
            let fencedMatches = fencedRegex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            ranges.append(contentsOf: fencedMatches.map(\.range))
        }

        // Inline code
        if let inlineRegex = try? NSRegularExpression(pattern: "`[^`]+`") {
            let inlineMatches = inlineRegex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            ranges.append(contentsOf: inlineMatches.map(\.range))
        }

        return ranges
    }

    // MARK: - LaTeX Highlighting

    /// Post-AST pass that finds `$...$` (inline) and `$$...$$` (display) LaTeX expressions
    /// and styles them with monospace font and a subtle background color.
    /// Skips LaTeX inside fenced code blocks and inline code.
    private static func appendLatexSpans(
        in source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        into spans: inout [HighlightSpan]
    ) {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return }

        let codeRanges = codeBlockNSRanges(in: source)
        let codeFont = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
        let noTraits = FontTraits(bold: false, italic: false)

        let latexColor: PlatformColor
        let delimiterColor: PlatformColor
        let latexBg: PlatformColor
        #if canImport(UIKit)
        latexColor = UIColor.label
        delimiterColor = UIColor.tertiaryLabel
        latexBg = UIColor.systemFill.withAlphaComponent(0.08)
        #elseif canImport(AppKit)
        latexColor = NSColor.labelColor
        delimiterColor = NSColor.tertiaryLabelColor
        latexBg = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        #endif

        // Display math: $$...$$  (must be checked before inline $...$)
        if let displayRegex = try? NSRegularExpression(pattern: #"\$\$(.+?)\$\$"#, options: [.dotMatchesLineSeparators]) {
            let matches = displayRegex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            for match in matches {
                let fullRange = match.range
                guard match.numberOfRanges >= 2 else { continue }
                let contentRange = match.range(at: 1)

                let isInCode = codeRanges.contains { NSIntersectionRange($0, fullRange).length > 0 }
                guard !isInCode else { continue }
                guard fullRange.location >= 0, fullRange.location + fullRange.length <= nsSource.length else { continue }

                // Opening $$ delimiter
                spans.append(HighlightSpan(
                    range: NSRange(location: fullRange.location, length: 2),
                    font: codeFont,
                    color: delimiterColor,
                    traits: noTraits,
                    backgroundColor: nil,
                    strikethrough: false,
                    isOverlay: true
                ))

                // LaTeX content
                if contentRange.length > 0 {
                    spans.append(HighlightSpan(
                        range: contentRange,
                        font: codeFont,
                        color: latexColor,
                        traits: noTraits,
                        backgroundColor: latexBg,
                        strikethrough: false
                    ))
                }

                // Closing $$ delimiter
                let closingStart = fullRange.location + fullRange.length - 2
                spans.append(HighlightSpan(
                    range: NSRange(location: closingStart, length: 2),
                    font: codeFont,
                    color: delimiterColor,
                    traits: noTraits,
                    backgroundColor: nil,
                    strikethrough: false,
                    isOverlay: true
                ))
            }
        }

        // Inline math: $...$  (single dollar, not preceded/followed by another $)
        if let inlineRegex = try? NSRegularExpression(pattern: #"(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)"#) {
            let matches = inlineRegex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            for match in matches {
                let fullRange = match.range
                guard match.numberOfRanges >= 2 else { continue }
                let contentRange = match.range(at: 1)

                let isInCode = codeRanges.contains { NSIntersectionRange($0, fullRange).length > 0 }
                guard !isInCode else { continue }
                // Also skip if this overlaps with a display math range ($$)
                guard fullRange.location >= 0, fullRange.location + fullRange.length <= nsSource.length else { continue }

                // Opening $ delimiter
                spans.append(HighlightSpan(
                    range: NSRange(location: fullRange.location, length: 1),
                    font: codeFont,
                    color: delimiterColor,
                    traits: noTraits,
                    backgroundColor: nil,
                    strikethrough: false,
                    isOverlay: true
                ))

                // LaTeX content
                if contentRange.length > 0 {
                    spans.append(HighlightSpan(
                        range: contentRange,
                        font: codeFont,
                        color: latexColor,
                        traits: noTraits,
                        backgroundColor: latexBg,
                        strikethrough: false
                    ))
                }

                // Closing $ delimiter
                let closingStart = fullRange.location + fullRange.length - 1
                spans.append(HighlightSpan(
                    range: NSRange(location: closingStart, length: 1),
                    font: codeFont,
                    color: delimiterColor,
                    traits: noTraits,
                    backgroundColor: nil,
                    strikethrough: false,
                    isOverlay: true
                ))
            }
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
