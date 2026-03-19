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
struct HighlightSpan: Sendable {
    let range: NSRange
    let font: PlatformFont
    let color: PlatformColor?
    let traits: FontTraits
    let backgroundColor: PlatformColor?
    let strikethrough: Bool
}

#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

#if canImport(UIKit)
struct FontTraits {
    var bold: Bool
    var italic: Bool
}
#elseif canImport(AppKit)
struct FontTraits {
    var bold: Bool
    var italic: Bool
}
#endif

/// Actor that parses markdown on a background thread and returns highlight spans.
/// Debouncing and async parsing keep the main thread free for 120fps.
public actor MarkdownASTHighlighter {
    private let baseFontSize: CGFloat
    private var parseTask: Task<[HighlightSpan], Never>?
    private let debounceInterval: UInt64 = 80_000_000 // 80ms in nanoseconds

    public init(baseFontSize: CGFloat = 14) {
        self.baseFontSize = baseFontSize
    }

    /// Parses markdown and returns highlight spans. Cancels any in-flight parse.
    /// Call from background; result is applied on main thread.
    public func parse(_ markdown: String) async -> [HighlightSpan] {
        parseTask?.cancel()
        let task = Task<[HighlightSpan], Never> { [baseFontSize] in
            await Task.yield()
            return Self.parseSync(markdown, baseFontSize: baseFontSize)
        }
        parseTask = task
        return await task.value
    }

    /// Debounced parse: waits `debounceInterval` then parses. Cancels previous.
    public func parseDebounced(_ markdown: String) async -> [HighlightSpan] {
        parseTask?.cancel()
        try? await Task.sleep(nanoseconds: debounceInterval)
        guard !Task.isCancelled else { return [] }
        return await parse(markdown)
    }

    private static func parseSync(_ markdown: String, baseFontSize: CGFloat) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let doc = Document(parsing: markdown)
        collectSpans(from: doc, in: markdown, baseFontSize: baseFontSize, into: &spans)
        return spans
    }

    private static func collectSpans(from markup: any Markup, in source: String, baseFontSize: CGFloat, into spans: inout [HighlightSpan]) {
        if let range = markup.range, let nsRange = sourceRangeToNSRange(range, in: source), nsRange.length > 0 {
            if let heading = markup as? Heading {
                let scale: CGFloat = switch heading.level {
                case 1: 1.7
                case 2: 1.45
                case 3: 1.25
                case 4: 1.12
                default: 1.05
                }
                #if canImport(UIKit)
                let font = UIFont.systemFont(ofSize: baseFontSize * scale, weight: .bold)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false))
                #elseif canImport(AppKit)
                let font = NSFont.systemFont(ofSize: baseFontSize * scale, weight: .bold)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false))
                #endif
                return
            }
            if markup is Strong {
                #if canImport(UIKit)
                let font = UIFont.systemFont(ofSize: baseFontSize, weight: .bold)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false))
                #elseif canImport(AppKit)
                let font = NSFont.systemFont(ofSize: baseFontSize, weight: .bold)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: true, italic: false), backgroundColor: nil, strikethrough: false))
                #endif
                return
            }
            if markup is Emphasis {
                #if canImport(UIKit)
                let font = UIFont.italicSystemFont(ofSize: baseFontSize)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: true), backgroundColor: nil, strikethrough: false))
                #elseif canImport(AppKit)
                let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: true), backgroundColor: nil, strikethrough: false))
                #endif
                return
            }
            if markup is InlineCode {
                #if canImport(UIKit)
                let font = UIFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: UIColor.systemFill, strikethrough: false))
                #elseif canImport(AppKit)
                let font = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), strikethrough: false))
                #endif
                return
            }
            if markup is CodeBlock {
                #if canImport(UIKit)
                let font = UIFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: UIColor.systemFill, strikethrough: false))
                #elseif canImport(AppKit)
                let font = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
                spans.append(HighlightSpan(range: nsRange, font: font, color: nil, traits: FontTraits(bold: false, italic: false), backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), strikethrough: false))
                #endif
                return
            }
        }
        for child in markup.children {
            collectSpans(from: child, in: source, baseFontSize: baseFontSize, into: &spans)
        }
    }
}
