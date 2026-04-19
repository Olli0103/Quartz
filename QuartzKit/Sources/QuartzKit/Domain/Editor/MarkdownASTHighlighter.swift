import Foundation
import Markdown
#if canImport(CoreText)
import CoreText
#endif
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
/// Column is UTF-8 bytes from line start; this resolver pre-indexes line starts
/// once per parse to avoid re-splitting the full document for every AST node.
private struct SourceRangeResolver {
    private struct IndexedLine {
        let content: String
        let utf16Start: Int
    }

    private let totalUTF16Length: Int
    private let lines: [IndexedLine]

    init(source: String) {
        totalUTF16Length = source.utf16.count

        var indexedLines: [IndexedLine] = []
        var lineStart = source.startIndex
        var cursor = source.startIndex
        var utf16Start = 0

        while cursor < source.endIndex {
            let character = source[cursor]
            guard character == "\n" || character == "\r" else {
                cursor = source.index(after: cursor)
                continue
            }

            indexedLines.append(IndexedLine(
                content: String(source[lineStart..<cursor]),
                utf16Start: utf16Start
            ))

            let next = source.index(after: cursor)
            if character == "\r",
               next < source.endIndex,
               source[next] == "\n" {
                utf16Start += 2
                cursor = source.index(after: next)
            } else {
                utf16Start += 1
                cursor = next
            }
            lineStart = cursor
        }

        indexedLines.append(IndexedLine(
            content: String(source[lineStart..<source.endIndex]),
            utf16Start: utf16Start
        ))
        lines = indexedLines
    }

    func nsRange(for range: SourceRange) -> NSRange? {
        guard let start = utf16Offset(for: range.lowerBound),
              let end = utf16Offset(for: range.upperBound),
              start <= end,
              end <= totalUTF16Length else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    private func utf16Offset(for location: SourceLocation) -> Int? {
        let lineIndex = location.line - 1
        guard lineIndex >= 0, lineIndex < lines.count else { return nil }

        let indexedLine = lines[lineIndex]
        let columnBytes = max(location.column - 1, 0)
        guard columnBytes > 0 else { return indexedLine.utf16Start }

        let utf8View = indexedLine.content.utf8
        let clampedBytes = min(columnBytes, utf8View.count)
        let byteIndex = utf8View.index(utf8View.startIndex, offsetBy: clampedBytes)
        guard let stringIndex = byteIndex.samePosition(in: indexedLine.content) else {
            return indexedLine.utf16Start + indexedLine.content.utf16.count
        }

        let utf16Distance = indexedLine.content.utf16.distance(
            from: indexedLine.content.startIndex,
            to: stringIndex
        )
        return indexedLine.utf16Start + utf16Distance
    }
}

/// Attribute application record for a range.
public enum OverlayVisibilityBehavior: Sendable {
    /// Overlay is a stylistic layer only and should never be concealed.
    case alwaysVisible
    /// Overlay represents markdown syntax and should only be visible while the
    /// active selection/caret is inside the associated semantic range.
    case concealWhenInactive(revealRange: NSRange)
}

public enum HighlightSemanticRole: Sendable, Equatable {
    case heading(level: Int)
    case bold
    case italic
    case inlineCode
    case strikethrough
    case blockquote
    case codeBlock
}

public struct HighlightSpan: @unchecked Sendable {
    public let range: NSRange
    public let font: PlatformFont
    public let color: PlatformColor?
    public let traits: FontTraits
    public let backgroundColor: PlatformColor?
    public let strikethrough: Bool
    /// When true, only the foreground color is applied (overlays on existing attributes).
    /// Used for muting syntax delimiter characters and additive styling like wiki links.
    public let isOverlay: Bool
    /// Controls whether the overlay should stay visible or be concealed
    /// unless the active selection is interacting with its semantic token.
    public let overlayVisibilityBehavior: OverlayVisibilityBehavior
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
    /// Semantic role propagated from the markdown parser for higher-level editor state.
    public let semanticRole: HighlightSemanticRole?

    public init(range: NSRange, font: PlatformFont, color: PlatformColor?, traits: FontTraits, backgroundColor: PlatformColor?, strikethrough: Bool, isOverlay: Bool = false, overlayVisibilityBehavior: OverlayVisibilityBehavior = .alwaysVisible, attachment: NSTextAttachment? = nil, paragraphStyle: NSParagraphStyle? = nil, tableRowStyle: QuartzTableRowStyle? = nil, kern: CGFloat? = nil, wikiLinkTitle: String? = nil, semanticRole: HighlightSemanticRole? = nil) {
        self.range = range
        self.font = font
        self.color = color
        self.traits = traits
        self.backgroundColor = backgroundColor
        self.strikethrough = strikethrough
        self.isOverlay = isOverlay
        self.overlayVisibilityBehavior = overlayVisibilityBehavior
        self.attachment = attachment
        self.paragraphStyle = paragraphStyle
        self.tableRowStyle = tableRowStyle
        self.kern = kern
        self.wikiLinkTitle = wikiLinkTitle
        self.semanticRole = semanticRole
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
    /// Cached source for large-document reuse. Avoids reparsing identical content when
    /// the editor or tests request spans repeatedly without an intervening edit.
    private var cachedMarkdown: String?
    private var parseTask: Task<[HighlightSpan], Never>?
    private let debounceInterval: UInt64 = 150_000_000 // 150ms in nanoseconds

    /// Maximum document size (characters) before we skip full AST highlighting for performance.
    /// Documents larger than ~500KB of text would cause noticeable lag.
    private static let maxDocumentSize = 500_000

    /// Threshold above which we use a longer debounce interval.
    private static let largeDocumentThreshold = 50_000

    /// Threshold above which we use chunked parsing to avoid blocking.
    private static let chunkedParsingThreshold = 100_000
    /// Threshold above which we reuse exact-match parse results to keep steady-state
    /// editor refreshes well under budget for large notes.
    private static let cacheReuseThreshold = 20_000

    /// Size of each chunk for incremental parsing.
    private static let chunkSize = 25_000
    /// Nested list documents beyond this depth are rendered with a lightweight
    /// fallback to avoid parser/visitor stack blowups on pathological input.
    private static let maxSafeListDepth = 24

    private static let semanticMarkdownRegex = try! NSRegularExpression(
        pattern: #"```[\s\S]*?```|\$\$[\s\S]+?\$\$|\[\[[^\]]+\]\]|!\[[^\]]*\]\([^)]*\)|\[[^\]]*\]\([^)]*\)|(?<!\*)\*\*([^\n]+?)\*\*(?!\*)|~~([^~\n]+?)~~|(?<!\*)\*([^*\n]+?)\*(?!\*)|`[^`\n]+`|(?<!\$)\$(?!\$)([^\n]+?)(?<!\$)\$(?!\$)"#
    )
    private static let wikiLinkRegex = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
    private static let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"(?<image>!)?\[(?<label>[^\]]*)\]\((?<destination>[^)]*)\)"#
    )

    public init(baseFontSize: CGFloat = 14) {
        self.baseFontSize = baseFontSize
    }

    /// Synchronous parse entrypoint for very small editor formatting operations where
    /// visible consistency matters more than background scheduling latency.
    static func parseImmediately(
        _ markdown: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?
    ) -> [HighlightSpan] {
        parseSync(
            markdown,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            vaultRootURL: vaultRootURL,
            noteURL: noteURL
        )
    }

    /// Updates font family and line spacing from the main actor.
    public func updateSettings(fontFamily: AppearanceManager.EditorFontFamily, lineSpacing: CGFloat, vaultRootURL: URL? = nil, noteURL: URL? = nil) {
        self.fontFamily = fontFamily
        self.lineSpacing = lineSpacing
        if let vaultRootURL { self.vaultRootURL = vaultRootURL }
        if let noteURL { self.noteURL = noteURL }
        parseTask?.cancel()
        parseTask = nil
        cachedMarkdown = nil
        cachedSpans = []
    }

    /// Parses markdown and returns highlight spans. Cancels any in-flight parse.
    /// Call from background; result is applied on main thread.
    /// Uses chunked parsing for documents over 100KB to prevent blocking.
    public func parse(_ markdown: String) async -> [HighlightSpan] {
        // Skip highlighting for very large documents to prevent UI lag
        guard markdown.count < Self.maxDocumentSize else {
            cachedMarkdown = markdown
            cachedSpans = []
            return []
        }

        if markdown.count >= Self.cacheReuseThreshold,
           cachedMarkdown == markdown,
           !cachedSpans.isEmpty {
            return cachedSpans
        }

        parseTask?.cancel()

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
        parseTask = nil
        cachedMarkdown = markdown
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
                overlayVisibilityBehavior: Self.offsetOverlayVisibilityBehavior(
                    span.overlayVisibilityBehavior,
                    by: dirtyRange.location
                ),
                attachment: span.attachment,
                paragraphStyle: span.paragraphStyle,
                tableRowStyle: span.tableRowStyle,
                kern: span.kern,
                wikiLinkTitle: span.wikiLinkTitle,
                semanticRole: span.semanticRole
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
                    overlayVisibilityBehavior: Self.shiftedOverlayVisibilityBehavior(
                        span.overlayVisibilityBehavior,
                        by: lengthDelta
                    ),
                    attachment: span.attachment,
                    paragraphStyle: span.paragraphStyle,
                    tableRowStyle: span.tableRowStyle,
                    kern: span.kern,
                    wikiLinkTitle: span.wikiLinkTitle,
                    semanticRole: span.semanticRole
                ))
            }
        }

        cachedMarkdown = markdown
        let sortedMerged = Self.sortSpans(merged)
        cachedSpans = sortedMerged
        return sortedMerged
    }

    private static func parseSync(_ markdown: String, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily, vaultRootURL: URL?, noteURL: URL?) -> [HighlightSpan] {
        if exceedsSafeListDepth(in: markdown) {
            return parseWithoutAST(
                markdown,
                baseFontSize: baseFontSize,
                fontFamily: fontFamily,
                vaultRootURL: vaultRootURL,
                noteURL: noteURL
            )
        }

        var spans: [HighlightSpan] = []
        let doc = Document(parsing: markdown)
        let resolver = SourceRangeResolver(source: markdown)
        collectSpans(from: doc, in: markdown, resolver: resolver, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL, into: &spans)
        appendHeadingSpans(
            in: markdown,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            into: &spans
        )
        let semanticScan = scanSemanticMarkdown(
            in: markdown,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            vaultRootURL: vaultRootURL,
            noteURL: noteURL
        )
        spans.append(contentsOf: semanticScan.spans)
        appendBlockquoteSpans(
            in: markdown,
            fencedCodeRanges: semanticScan.fencedCodeRanges,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            into: &spans
        )
        return sortSpans(spans)
    }

    private static func parseWithoutAST(
        _ markdown: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?
    ) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        appendHeadingSpans(
            in: markdown,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            into: &spans
        )
        let semanticScan = scanSemanticMarkdown(
            in: markdown,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            vaultRootURL: vaultRootURL,
            noteURL: noteURL
        )
        spans.append(contentsOf: semanticScan.spans)
        appendBlockquoteSpans(
            in: markdown,
            fencedCodeRanges: semanticScan.fencedCodeRanges,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            into: &spans
        )
        return sortSpans(spans)
    }

    private static func exceedsSafeListDepth(in markdown: String) -> Bool {
        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.isEmpty else { continue }

            let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
            let trimmed = line.dropFirst(leadingWhitespace.count)
            guard isListMarkerPrefix(trimmed) else { continue }

            var depth = 0
            for character in leadingWhitespace {
                depth += character == "\t" ? 2 : 1
            }

            if depth / 2 >= maxSafeListDepth {
                return true
            }
        }

        return false
    }

    private static func isListMarkerPrefix<S: StringProtocol>(_ line: S) -> Bool {
        guard let first = line.first else { return false }
        if first == "-" || first == "*" || first == "+" {
            return line.dropFirst().first == " "
        }

        var iterator = line.makeIterator()
        var sawDigit = false
        while let character = iterator.next(), character.isNumber {
            sawDigit = true
        }

        guard sawDigit else { return false }
        let remainder = line.drop { $0.isNumber }
        guard remainder.first == "." else { return false }
        return remainder.dropFirst().first == " "
    }

    /// Chunked parsing for large documents (100KB+).
    /// The previous top-level child walk reused subtree-local `SourceRange` values
    /// against the full-document resolver, which corrupted heading ranges on long
    /// existing notes after open/reopen. Until a document-global chunk walker exists,
    /// large-note correctness must reuse the same authoritative full-document parse.
    private static func parseChunked(
        _ markdown: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?
    ) async -> [HighlightSpan] {
        await Task.yield()
        guard !Task.isCancelled else { return [] }
        let spans = parseSync(
            markdown,
            baseFontSize: baseFontSize,
            fontFamily: fontFamily,
            vaultRootURL: vaultRootURL,
            noteURL: noteURL
        )
        guard !Task.isCancelled else { return [] }
        return spans
    }

    private static func collectSpans(from markup: any Markup, in source: String, resolver: SourceRangeResolver, baseFontSize: CGFloat, fontFamily: AppearanceManager.EditorFontFamily, vaultRootURL: URL?, noteURL: URL?, into spans: inout [HighlightSpan]) {
        if let range = markup.range, let nsRange = resolver.nsRange(for: range), nsRange.length > 0 {
            if markup is Heading {
                // Heading source ranges drift in existing multiline documents.
                // A line-based pass injects canonical heading spans for load, reopen,
                // and edit-time rendering.
                return
            }
            if markup is Strong { return }
            if markup is Emphasis { return }
            if markup is InlineCode {
                // Inline markdown semantics are emitted by the unified semantic scan
                // after the AST walk so render authority stays in one pipeline.
                return
            }
            if markup is CodeBlock {
                // Code block source ranges drift in live multiline documents. The
                // unified semantic scan injects the canonical block ranges.
                return
            }
            if markup is Strikethrough { return }
            if markup is Markdown.Table {
                let tableRange = expandedTableRange(in: source, around: nsRange)
                // Rich table rendering: monospaced font, zebra stripes, dynamic kerning
                // for perfect column alignment without mutating the markdown source.
                let monoFont = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
                // NO bold font — all rows use identical monoFont for perfect column alignment.
                // Header is distinguished by background color only (via drawBackground).

                // Monospaced character width — all chars are the same width
                let monoCharWidth = monospacedCharacterWidth(for: monoFont)

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
                let tableText = (source as NSString).substring(with: tableRange)
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
                var lineOffset = tableRange.location
                var bodyRowIndex = 0

                for (lineIdx, line) in tableLines.enumerated() {
                    let lineLength = (line as NSString).length
                    guard lineLength > 0 else {
                        lineOffset += lineLength + 1
                        continue
                    }

                    let hasTrailingNewline = (lineOffset + lineLength) < (tableRange.location + tableRange.length)
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
                        let rowRevealRange = lineRange
                        for (charIdx, ch) in line.enumerated() {
                            if ch == "|" {
                                spans.append(HighlightSpan(
                                    range: NSRange(location: lineOffset + charIdx, length: 1),
                                    font: monoFont,
                                    color: mutedColor,
                                    traits: FontTraits(bold: false, italic: false),
                                    backgroundColor: nil, strikethrough: false,
                                    isOverlay: true,
                                    overlayVisibilityBehavior: .concealWhenInactive(revealRange: rowRevealRange)
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
                // Blockquote source ranges can drift in multiline documents.
                // A line-based semantic pass injects canonical blockquote spans.
                return
            }
            if markup is Markdown.Image {
                // Markdown image nodes show the same paragraph-local source range drift as
                // links and emphasis. The unified semantic scan injects canonical image spans.
                return
            }
            if markup is Link {
                // Markdown Link source ranges have shown the same paragraph-local drift as
                // emphasis/strong nodes in multiline documents. The unified semantic scan
                // injects canonical link spans instead of trusting the AST range here.
                return
            }
        }
        for child in markup.children {
            collectSpans(from: child, in: source, resolver: resolver, baseFontSize: baseFontSize, fontFamily: fontFamily, vaultRootURL: vaultRootURL, noteURL: noteURL, into: &spans)
        }
    }

    private static func appendHeadingSpans(
        in source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        into spans: inout [HighlightSpan]
    ) {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return }

        let mutedColor: PlatformColor
        #if canImport(UIKit)
        mutedColor = UIColor.tertiaryLabel
        #elseif canImport(AppKit)
        mutedColor = NSColor.tertiaryLabelColor
        #endif

        var cursor = 0
        while cursor < nsSource.length {
            let fullLineRange = nsSource.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = lineRangeWithoutNewlines(fullLineRange, in: nsSource)
            let line = nsSource.substring(with: contentRange)

            if let level = headingLevel(in: line),
               let syntaxRange = headingSyntaxRange(in: line, globalLocation: contentRange.location, level: level) {
                let scale = EditorTypography.headingScale(for: level)
                let font = EditorFontFactory.makeFont(
                    family: fontFamily,
                    size: baseFontSize * scale,
                    weight: .bold
                )

                spans.append(HighlightSpan(
                    range: contentRange,
                    font: font,
                    color: nil,
                    traits: FontTraits(bold: true, italic: false),
                    backgroundColor: nil,
                    strikethrough: false,
                    semanticRole: .heading(level: level)
                ))
                spans.append(HighlightSpan(
                    range: syntaxRange,
                    font: font,
                    color: mutedColor,
                    traits: FontTraits(bold: true, italic: false),
                    backgroundColor: nil,
                    strikethrough: false,
                    isOverlay: true,
                    overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullLineRange)
                ))
            }

            cursor = NSMaxRange(fullLineRange)
        }
    }

    private static func monospacedCharacterWidth(for font: PlatformFont) -> CGFloat {
        let ctFont = font as CTFont
        var character: UniChar = 77 // "M"
        var glyph: CGGlyph = 0

        if CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) {
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
            if advance.width.isFinite, advance.width > 0 {
                return advance.width
            }
        }

        #if canImport(AppKit)
        let fallbackWidth = font.maximumAdvancement.width
        #else
        let fallbackWidth = font.pointSize * 0.6
        #endif

        return max(fallbackWidth, 1)
    }

    private static func headingLevel(in line: String) -> Int? {
        let trimmedLeading = line.drop(while: { $0 == " " || $0 == "\t" })
        var level = 0
        for character in trimmedLeading {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level) else { return nil }
        let remainder = trimmedLeading.dropFirst(level)
        guard remainder.isEmpty || remainder.first == " " else { return nil }
        return level
    }

    private static func headingSyntaxRange(in line: String, globalLocation: Int, level: Int) -> NSRange? {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
        let remainingLength = max(line.utf16.count - leadingWhitespace, 0)
        guard remainingLength > 0 else { return nil }
        return NSRange(location: globalLocation + leadingWhitespace, length: min(level + 1, remainingLength))
    }

    private static func lineRangeWithoutNewlines(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let scalar = text.character(at: range.location + length - 1)
            if scalar == 0x0A || scalar == 0x0D {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
    }

    private static func expandedTableRange(in source: String, around range: NSRange) -> NSRange {
        let nsSource = source as NSString
        let length = nsSource.length
        guard length > 0 else { return range }

        let safeLocation = min(max(range.location, 0), max(length - 1, 0))
        let seedLine = nsSource.lineRange(for: NSRange(location: safeLocation, length: 0))
        let seedText = nsSource.substring(with: seedLine)
        guard MarkdownTableNavigation.isTableRow(seedText) else { return range }

        var startLine = seedLine
        while startLine.location > 0 {
            let previousLine = nsSource.lineRange(for: NSRange(location: startLine.location - 1, length: 0))
            let previousText = nsSource.substring(with: previousLine)
            guard MarkdownTableNavigation.isTableRow(previousText) else { break }
            startLine = previousLine
        }

        var endLine = seedLine
        while endLine.location + endLine.length < length {
            let nextLine = nsSource.lineRange(for: NSRange(location: endLine.location + endLine.length, length: 0))
            let nextText = nsSource.substring(with: nextLine)
            guard MarkdownTableNavigation.isTableRow(nextText) else { break }
            endLine = nextLine
        }

        let end = endLine.location + endLine.length
        return NSRange(location: startLine.location, length: end - startLine.location)
    }

    private struct SemanticScanResult {
        var spans: [HighlightSpan]
        var fencedCodeRanges: [NSRange]

        static let empty = SemanticScanResult(spans: [], fencedCodeRanges: [])
    }

    private enum SemanticTokenKind {
        case fencedCode
        case displayMath
        case wikiLink
        case image
        case markdownLink
        case strong
        case strikethrough
        case emphasis
        case inlineCode
        case inlineMath
    }

    private static func scanSemanticMarkdown(
        in source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?
    ) -> SemanticScanResult {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return .empty }

        let semanticMatches = semanticMarkdownRegex.matches(
            in: source,
            range: NSRange(location: 0, length: nsSource.length)
        )

        var spans: [HighlightSpan] = []
        var fencedCodeRanges: [NSRange] = []

        for match in semanticMatches {
            let fullRange = match.range
            guard fullRange.location != NSNotFound,
                  fullRange.length > 0,
                  NSMaxRange(fullRange) <= nsSource.length else {
                continue
            }

            let token = nsSource.substring(with: fullRange)
            guard let kind = semanticTokenKind(for: token) else { continue }

            switch kind {
            case .fencedCode:
                fencedCodeRanges.append(fullRange)
                appendCodeBlockSpan(
                    fullRange: fullRange,
                    baseFontSize: baseFontSize,
                    into: &spans
                )
            case .displayMath:
                appendMathSpans(
                    fullRange: fullRange,
                    delimiterLength: 2,
                    baseFontSize: baseFontSize,
                    into: &spans
                )
            case .wikiLink:
                appendWikiLinkSemanticSpans(
                    fullRange: fullRange,
                    source: source,
                    baseFontSize: baseFontSize,
                    fontFamily: fontFamily,
                    into: &spans
                )
            case .image, .markdownLink:
                appendMarkdownLinkSemanticSpans(
                    token: token,
                    fullRange: fullRange,
                    source: source,
                    baseFontSize: baseFontSize,
                    fontFamily: fontFamily,
                    vaultRootURL: vaultRootURL,
                    noteURL: noteURL,
                    into: &spans
                )
            case .strong:
                appendDelimitedSemanticSpans(
                    fullRange: fullRange,
                    baseFont: EditorFontFactory.makeFont(
                        family: fontFamily,
                        size: baseFontSize,
                        weight: .bold
                    ),
                    syntaxLength: 2,
                    traits: FontTraits(bold: true, italic: false),
                    semanticRole: .bold,
                    textColor: nil,
                    strikethrough: false,
                    into: &spans
                )
            case .strikethrough:
                let strikeColor: PlatformColor
                #if canImport(UIKit)
                strikeColor = UIColor.secondaryLabel
                #elseif canImport(AppKit)
                strikeColor = NSColor.secondaryLabelColor
                #endif
                appendDelimitedSemanticSpans(
                    fullRange: fullRange,
                    baseFont: EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize),
                    syntaxLength: 2,
                    traits: FontTraits(bold: false, italic: false),
                    semanticRole: .strikethrough,
                    textColor: strikeColor,
                    strikethrough: true,
                    into: &spans
                )
            case .emphasis:
                appendDelimitedSemanticSpans(
                    fullRange: fullRange,
                    baseFont: EditorFontFactory.makeFont(
                        family: fontFamily,
                        size: baseFontSize,
                        italic: true
                    ),
                    syntaxLength: 1,
                    traits: FontTraits(bold: false, italic: true),
                    semanticRole: .italic,
                    textColor: nil,
                    strikethrough: false,
                    into: &spans
                )
            case .inlineCode:
                appendInlineCodeSpan(
                    fullRange: fullRange,
                    baseFontSize: baseFontSize,
                    into: &spans
                )
            case .inlineMath:
                appendMathSpans(
                    fullRange: fullRange,
                    delimiterLength: 1,
                    baseFontSize: baseFontSize,
                    into: &spans
                )
            }
        }

        return SemanticScanResult(spans: spans, fencedCodeRanges: fencedCodeRanges)
    }

    private static func semanticTokenKind(for token: String) -> SemanticTokenKind? {
        if token.hasPrefix("```") { return .fencedCode }
        if token.hasPrefix("$$") { return .displayMath }
        if token.hasPrefix("[[") { return .wikiLink }
        if token.hasPrefix("![") { return .image }
        if token.hasPrefix("[") { return .markdownLink }
        if token.hasPrefix("**") { return .strong }
        if token.hasPrefix("~~") { return .strikethrough }
        if token.hasPrefix("`") { return .inlineCode }
        if token.hasPrefix("$") { return .inlineMath }
        if token.hasPrefix("*") { return .emphasis }
        return nil
    }

    private static func appendWikiLinkSemanticSpans(
        fullRange: NSRange,
        source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        into spans: inout [HighlightSpan]
    ) {
        let nsSource = source as NSString
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

        let localRange = NSRange(location: 0, length: fullRange.length)
        guard let match = wikiLinkRegex.firstMatch(
            in: nsSource.substring(with: fullRange),
            range: localRange
        ), match.numberOfRanges >= 2 else {
            return
        }

        let contentRange = match.range(at: 1)
        let rawContent = nsSource.substring(with: NSRange(
            location: fullRange.location + contentRange.location,
            length: contentRange.length
        ))
        let wikiLink = WikiLink(raw: rawContent)
        let targetTitle = wikiLink.target
        let innerRange = NSRange(location: fullRange.location + 2, length: max(fullRange.length - 4, 0))
        guard innerRange.length > 0 else { return }

        spans.append(HighlightSpan(
            range: innerRange,
            font: font,
            color: accentColor,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: nil,
            strikethrough: false,
            isOverlay: true,
            overlayVisibilityBehavior: .alwaysVisible,
            wikiLinkTitle: targetTitle
        ))

        let openBrackets = NSRange(location: fullRange.location, length: 2)
        let closeBrackets = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
        for syntaxRange in [openBrackets, closeBrackets] {
            spans.append(HighlightSpan(
                range: syntaxRange,
                font: font,
                color: bracketColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullRange)
            ))
        }
    }

    private static func appendMarkdownLinkSemanticSpans(
        token: String,
        fullRange: NSRange,
        source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?,
        into spans: inout [HighlightSpan]
    ) {
        let nsToken = token as NSString
        let localFullRange = NSRange(location: 0, length: nsToken.length)
        guard let match = markdownLinkRegex.firstMatch(in: token, range: localFullRange) else {
            return
        }

        let imageRange = match.range(withName: "image")
        let labelLocalRange = match.range(withName: "label")
        let destinationLocalRange = match.range(withName: "destination")
        guard labelLocalRange.location != NSNotFound,
              destinationLocalRange.location != NSNotFound else {
            return
        }

        let labelRange = NSRange(
            location: fullRange.location + labelLocalRange.location,
            length: labelLocalRange.length
        )
        let destinationRange = NSRange(
            location: fullRange.location + destinationLocalRange.location,
            length: destinationLocalRange.length
        )

        if imageRange.location != NSNotFound {
            appendMarkdownImageSemanticSpans(
                fullRange: fullRange,
                labelRange: labelRange,
                destinationRange: destinationRange,
                source: source,
                baseFontSize: baseFontSize,
                fontFamily: fontFamily,
                vaultRootURL: vaultRootURL,
                noteURL: noteURL,
                into: &spans
            )
            return
        }

        let linkFont = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)

        let linkColor: PlatformColor
        let mutedColor: PlatformColor
        #if canImport(UIKit)
        linkColor = UIColor.systemBlue
        mutedColor = UIColor.tertiaryLabel
        #elseif canImport(AppKit)
        linkColor = NSColor.linkColor
        mutedColor = NSColor.tertiaryLabelColor
        #endif

        spans.append(HighlightSpan(
            range: labelRange,
            font: linkFont,
            color: linkColor,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: nil,
            strikethrough: false
        ))

        let openingBracketRange = NSRange(location: fullRange.location, length: 1)
        let middleSyntaxRange = NSRange(location: NSMaxRange(labelRange), length: 2)
        let closingParenRange = NSRange(location: NSMaxRange(destinationRange), length: 1)

        for syntaxRange in [openingBracketRange, middleSyntaxRange, destinationRange, closingParenRange] {
            guard syntaxRange.length > 0 else { continue }
            spans.append(HighlightSpan(
                range: syntaxRange,
                font: linkFont,
                color: mutedColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullRange)
            ))
        }
    }

    private static func appendMarkdownImageSemanticSpans(
        fullRange: NSRange,
        labelRange: NSRange,
        destinationRange: NSRange,
        source: String,
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        vaultRootURL: URL?,
        noteURL: URL?,
        into spans: inout [HighlightSpan]
    ) {
        let bodyFont = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize)
        let mutedColor: PlatformColor
        let accentColor: PlatformColor
        let clearColor: PlatformColor
        #if canImport(UIKit)
        mutedColor = UIColor.tertiaryLabel
        accentColor = UIColor.systemBlue
        clearColor = UIColor.clear
        #elseif canImport(AppKit)
        mutedColor = NSColor.tertiaryLabelColor
        accentColor = NSColor.linkColor
        clearColor = NSColor.clear
        #endif

        let destination = (source as NSString).substring(with: destinationRange)
        if let attachment = resolveImageAttachment(
            source: destination,
            vaultRootURL: vaultRootURL,
            noteURL: noteURL
        ) {
            spans.append(HighlightSpan(
                range: NSRange(location: fullRange.location, length: 1),
                font: bodyFont,
                color: nil,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                attachment: attachment
            ))

            if fullRange.length > 1 {
                let invisibleFont = EditorFontFactory.makeFont(family: fontFamily, size: 0.1)
                spans.append(HighlightSpan(
                    range: NSRange(location: fullRange.location + 1, length: fullRange.length - 1),
                    font: invisibleFont,
                    color: clearColor,
                    traits: FontTraits(bold: false, italic: false),
                    backgroundColor: nil,
                    strikethrough: false
                ))
            }
            return
        }

        spans.append(HighlightSpan(
            range: labelRange,
            font: bodyFont,
            color: accentColor,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: nil,
            strikethrough: false
        ))

        let openingSyntaxRange = NSRange(location: fullRange.location, length: 2)
        let middleSyntaxRange = NSRange(location: NSMaxRange(labelRange), length: 2)
        let closingParenRange = NSRange(location: NSMaxRange(destinationRange), length: 1)

        for syntaxRange in [openingSyntaxRange, middleSyntaxRange, destinationRange, closingParenRange] {
            guard syntaxRange.length > 0 else { continue }
            spans.append(HighlightSpan(
                range: syntaxRange,
                font: bodyFont,
                color: mutedColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullRange)
            ))
        }
    }

    private static func appendDelimitedSemanticSpans(
        fullRange: NSRange,
        baseFont: PlatformFont,
        syntaxLength: Int,
        traits: FontTraits,
        semanticRole: HighlightSemanticRole,
        textColor: PlatformColor?,
        strikethrough: Bool,
        into spans: inout [HighlightSpan]
    ) {
        let mutedColor: PlatformColor
        #if canImport(UIKit)
        mutedColor = UIColor.tertiaryLabel
        #elseif canImport(AppKit)
        mutedColor = NSColor.tertiaryLabelColor
        #endif

        guard fullRange.length > syntaxLength * 2 else { return }

        spans.append(HighlightSpan(
            range: fullRange,
            font: baseFont,
            color: textColor,
            traits: traits,
            backgroundColor: nil,
            strikethrough: strikethrough,
            semanticRole: semanticRole
        ))

        let openingDelimiter = NSRange(location: fullRange.location, length: syntaxLength)
        let closingDelimiter = NSRange(
            location: fullRange.location + fullRange.length - syntaxLength,
            length: syntaxLength
        )

        for delimiterRange in [openingDelimiter, closingDelimiter] {
            spans.append(HighlightSpan(
                range: delimiterRange,
                font: baseFont,
                color: mutedColor,
                traits: traits,
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullRange)
            ))
        }
    }

    private static func appendInlineCodeSpan(
        fullRange: NSRange,
        baseFontSize: CGFloat,
        into spans: inout [HighlightSpan]
    ) {
        let font = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
        let mutedColor: PlatformColor
        let backgroundColor: PlatformColor
        #if canImport(UIKit)
        mutedColor = UIColor.tertiaryLabel
        backgroundColor = UIColor.systemFill
        #elseif canImport(AppKit)
        mutedColor = NSColor.tertiaryLabelColor
        backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15)
        #endif

        spans.append(HighlightSpan(
            range: fullRange,
            font: font,
            color: nil,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: backgroundColor,
            strikethrough: false,
            semanticRole: .inlineCode
        ))

        guard fullRange.length > 2 else { return }
        let openingDelimiter = NSRange(location: fullRange.location, length: 1)
        let closingDelimiter = NSRange(location: NSMaxRange(fullRange) - 1, length: 1)
        for delimiterRange in [openingDelimiter, closingDelimiter] {
            spans.append(HighlightSpan(
                range: delimiterRange,
                font: font,
                color: mutedColor,
                traits: FontTraits(bold: false, italic: false),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullRange)
            ))
        }
    }

    private static func appendCodeBlockSpan(
        fullRange: NSRange,
        baseFontSize: CGFloat,
        into spans: inout [HighlightSpan]
    ) {
        let font = EditorFontFactory.makeCodeFont(size: baseFontSize * 0.9)
        let backgroundColor: PlatformColor
        #if canImport(UIKit)
        backgroundColor = UIColor.systemFill
        #elseif canImport(AppKit)
        backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15)
        #endif

        spans.append(HighlightSpan(
            range: fullRange,
            font: font,
            color: nil,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: backgroundColor,
            strikethrough: false,
            semanticRole: .codeBlock
        ))
    }

    private static func appendBlockquoteSpans(
        in source: String,
        fencedCodeRanges: [NSRange],
        baseFontSize: CGFloat,
        fontFamily: AppearanceManager.EditorFontFamily,
        into spans: inout [HighlightSpan]
    ) {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return }

        let font = EditorFontFactory.makeFont(family: fontFamily, size: baseFontSize, italic: true)
        let quoteColor: PlatformColor
        let mutedColor: PlatformColor
        #if canImport(UIKit)
        quoteColor = UIColor.secondaryLabel
        mutedColor = UIColor.tertiaryLabel
        #elseif canImport(AppKit)
        quoteColor = NSColor.secondaryLabelColor
        mutedColor = NSColor.tertiaryLabelColor
        #endif

        var cursor = 0
        while cursor < nsSource.length {
            let lineRange = nsSource.lineRange(for: NSRange(location: cursor, length: 0))
            let trailingBreakLength = trailingLineBreakLengthStatic(in: nsSource, lineRange: lineRange)
            let contentRange = NSRange(
                location: lineRange.location,
                length: max(lineRange.length - trailingBreakLength, 0)
            )
            let line = nsSource.substring(with: contentRange)
            defer { cursor = NSMaxRange(lineRange) }

            if fencedCodeRanges.contains(where: { NSIntersectionRange($0, lineRange).length > 0 }) {
                continue
            }

            let leadingWhitespaceLength = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let trimmed = (line as NSString).substring(from: leadingWhitespaceLength)
            guard trimmed.hasPrefix(">") else { continue }

            spans.append(HighlightSpan(
                range: lineRange,
                font: font,
                color: quoteColor,
                traits: FontTraits(bold: false, italic: true),
                backgroundColor: nil,
                strikethrough: false,
                semanticRole: .blockquote
            ))

            let syntaxLength = trimmed.hasPrefix("> ") ? 2 : 1
            spans.append(HighlightSpan(
                range: NSRange(location: lineRange.location + leadingWhitespaceLength, length: syntaxLength),
                font: font,
                color: mutedColor,
                traits: FontTraits(bold: false, italic: true),
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: lineRange)
            ))
        }
    }

    private static func trailingLineBreakLengthStatic(in text: NSString, lineRange: NSRange) -> Int {
        var length = 0
        while length < lineRange.length {
            let scalar = text.character(at: lineRange.location + lineRange.length - length - 1)
            if scalar == 10 || scalar == 13 {
                length += 1
            } else {
                break
            }
        }
        return length
    }

    private static func sortSpans(_ spans: [HighlightSpan]) -> [HighlightSpan] {
        spans.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                if lhs.range.length == rhs.range.length {
                    return lhs.isOverlay && !rhs.isOverlay
                }
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func appendMathSpans(
        fullRange: NSRange,
        delimiterLength: Int,
        baseFontSize: CGFloat,
        into spans: inout [HighlightSpan]
    ) {
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

        guard fullRange.length > delimiterLength * 2 else { return }
        let contentRange = NSRange(
            location: fullRange.location + delimiterLength,
            length: fullRange.length - delimiterLength * 2
        )

        let openingDelimiter = NSRange(location: fullRange.location, length: delimiterLength)
        let closingDelimiter = NSRange(
            location: NSMaxRange(fullRange) - delimiterLength,
            length: delimiterLength
        )

        for delimiterRange in [openingDelimiter, closingDelimiter] {
            spans.append(HighlightSpan(
                range: delimiterRange,
                font: codeFont,
                color: delimiterColor,
                traits: noTraits,
                backgroundColor: nil,
                strikethrough: false,
                isOverlay: true,
                overlayVisibilityBehavior: .concealWhenInactive(revealRange: fullRange)
            ))
        }

        spans.append(HighlightSpan(
            range: contentRange,
            font: codeFont,
            color: latexColor,
            traits: noTraits,
            backgroundColor: latexBg,
            strikethrough: false
        ))
    }

    private static func offsetOverlayVisibilityBehavior(
        _ behavior: OverlayVisibilityBehavior,
        by offset: Int
    ) -> OverlayVisibilityBehavior {
        switch behavior {
        case .alwaysVisible:
            return .alwaysVisible
        case let .concealWhenInactive(revealRange):
            return .concealWhenInactive(revealRange: NSRange(
                location: revealRange.location + offset,
                length: revealRange.length
            ))
        }
    }

    private static func shiftedOverlayVisibilityBehavior(
        _ behavior: OverlayVisibilityBehavior,
        by delta: Int
    ) -> OverlayVisibilityBehavior {
        switch behavior {
        case .alwaysVisible:
            return .alwaysVisible
        case let .concealWhenInactive(revealRange):
            return .concealWhenInactive(revealRange: NSRange(
                location: revealRange.location + delta,
                length: revealRange.length
            ))
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
