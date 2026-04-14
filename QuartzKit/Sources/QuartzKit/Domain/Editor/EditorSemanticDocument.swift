import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum EditorListKind: Sendable, Equatable {
    case bullet(marker: Character)
    case numbered
    case checkbox(checked: Bool, marker: Character)
}

public enum EditorBlockKind: Sendable, Equatable {
    case blank
    case paragraph
    case heading(level: Int)
    case listItem(kind: EditorListKind)
    case blockquote
    case codeFence
    case tableRow(style: QuartzTableRowStyle?)
}

public struct EditorBlockNode: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: EditorBlockKind
    public let range: NSRange
    public let contentRange: NSRange
    public let syntaxRange: NSRange?

    public init(
        id: String,
        kind: EditorBlockKind,
        range: NSRange,
        contentRange: NSRange,
        syntaxRange: NSRange?
    ) {
        self.id = id
        self.kind = kind
        self.range = range
        self.contentRange = contentRange
        self.syntaxRange = syntaxRange
    }
}

public enum EditorInlineTokenKind: Sendable, Equatable {
    case concealableSyntax
    case visibleOverlay
    case wikiLink
    case attachment
}

public struct EditorInlineToken: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: EditorInlineTokenKind
    public let range: NSRange
    public let revealRange: NSRange?
    public let visibleTextRange: NSRange?

    public init(
        id: String,
        kind: EditorInlineTokenKind,
        range: NSRange,
        revealRange: NSRange?,
        visibleTextRange: NSRange?
    ) {
        self.id = id
        self.kind = kind
        self.range = range
        self.revealRange = revealRange
        self.visibleTextRange = visibleTextRange
    }
}

public enum EditorInlineFormatKind: Sendable, Equatable, Hashable {
    case bold
    case italic
    case strikethrough
    case inlineCode
}

public struct EditorInlineFormatRun: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: EditorInlineFormatKind
    public let range: NSRange

    public init(id: String, kind: EditorInlineFormatKind, range: NSRange) {
        self.id = id
        self.kind = kind
        self.range = range
    }
}

public enum EditorTypingContext: Sendable, Equatable {
    case paragraph
    case heading(level: Int)
}

public struct EditorRenderPlan: Sendable {
    public static let empty = EditorRenderPlan(spans: [])

    public let primaryTextSpans: [HighlightSpan]
    public let blockStylingSpans: [HighlightSpan]
    public let inlineStylingSpans: [HighlightSpan]
    public let overlaySpans: [HighlightSpan]
    public let concealmentStylingSpans: [HighlightSpan]
    public let attachmentSpans: [HighlightSpan]

    public init(spans: [HighlightSpan]) {
        let primary = spans.filter { !$0.isOverlay }
        primaryTextSpans = primary
        blockStylingSpans = primary.filter { $0.paragraphStyle != nil || $0.tableRowStyle != nil }
        inlineStylingSpans = primary.filter { $0.paragraphStyle == nil && $0.tableRowStyle == nil }
        overlaySpans = spans.filter { $0.isOverlay }
        concealmentStylingSpans = overlaySpans.filter {
            if case .concealWhenInactive = $0.overlayVisibilityBehavior {
                return true
            }
            return false
        }
        attachmentSpans = spans.filter { $0.attachment != nil }
    }

    public func primarySegments(
        for semanticDocument: EditorSemanticDocument,
        defaultFont: PlatformFont,
        defaultColor: PlatformColor
    ) -> [EditorTextSegment] {
        guard semanticDocument.textLength > 0 else { return [] }

        let orderedPrimarySpans = primaryTextSpans.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }

        var boundaries = Set<Int>([0, semanticDocument.textLength])
        semanticDocument.blocks.forEach { block in
            boundaries.insert(block.range.location)
            boundaries.insert(NSMaxRange(block.range))
        }
        orderedPrimarySpans.forEach { span in
            boundaries.insert(span.range.location)
            boundaries.insert(NSMaxRange(span.range))
        }

        let sortedBoundaries = boundaries.sorted()
        guard sortedBoundaries.count >= 2 else { return [] }

        var segments: [EditorTextSegment] = []

        for index in 0..<(sortedBoundaries.count - 1) {
            let start = sortedBoundaries[index]
            let end = sortedBoundaries[index + 1]
            guard end > start else { continue }

            let range = NSRange(location: start, length: end - start)
            let block = semanticDocument.block(containing: start)
            var attributes = baseAttributes(
                for: block,
                defaultFont: defaultFont,
                defaultColor: defaultColor
            )

            for span in orderedPrimarySpans where spanCoversRange(span, range: range) {
                mergePrimaryAttributes(into: &attributes, from: span, defaultColor: defaultColor)
            }

            if let last = segments.last,
               NSMaxRange(last.range) == range.location,
               last.blockID == block?.id,
               primaryAttributesEqual(last.attributes, attributes) {
                let mergedRange = NSRange(location: last.range.location, length: last.range.length + range.length)
                segments[segments.count - 1] = EditorTextSegment(
                    range: mergedRange,
                    attributes: attributes,
                    blockID: block?.id
                )
            } else {
                segments.append(EditorTextSegment(range: range, attributes: attributes, blockID: block?.id))
            }
        }

        return segments
    }

    private func baseAttributes(
        for block: EditorBlockNode?,
        defaultFont: PlatformFont,
        defaultColor: PlatformColor
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: defaultColor,
            .backgroundColor: platformClearColor(),
            .strikethroughStyle: 0
        ]

        if case let .tableRow(style?) = block?.kind {
            attributes[.quartzTableRowStyle] = style.rawValue
        }

        return attributes
    }

    private func mergePrimaryAttributes(
        into attributes: inout [NSAttributedString.Key: Any],
        from span: HighlightSpan,
        defaultColor: PlatformColor
    ) {
        attributes[.font] = span.font
        attributes[.foregroundColor] = span.color ?? defaultColor
        attributes[.backgroundColor] = span.backgroundColor ?? platformClearColor()
        attributes[.strikethroughStyle] = span.strikethrough ? 1 : 0
        if let paragraphStyle = span.paragraphStyle {
            attributes[.paragraphStyle] = paragraphStyle
        }
        if let tableRowStyle = span.tableRowStyle {
            attributes[.quartzTableRowStyle] = tableRowStyle.rawValue
        }
    }

    private func spanCoversRange(_ span: HighlightSpan, range: NSRange) -> Bool {
        span.range.location <= range.location && NSMaxRange(span.range) >= NSMaxRange(range)
    }

    private func primaryAttributesEqual(
        _ lhs: [NSAttributedString.Key: Any],
        _ rhs: [NSAttributedString.Key: Any]
    ) -> Bool {
        #if canImport(UIKit)
        if !fontsEqual(lhs[.font] as? UIFont, rhs[.font] as? UIFont) { return false }
        if !colorsEqual(lhs[.foregroundColor] as? UIColor, rhs[.foregroundColor] as? UIColor) { return false }
        if !colorsEqual(lhs[.backgroundColor] as? UIColor, rhs[.backgroundColor] as? UIColor) { return false }
        #elseif canImport(AppKit)
        if !fontsEqual(lhs[.font] as? NSFont, rhs[.font] as? NSFont) { return false }
        if !colorsEqual(lhs[.foregroundColor] as? NSColor, rhs[.foregroundColor] as? NSColor) { return false }
        if !colorsEqual(lhs[.backgroundColor] as? NSColor, rhs[.backgroundColor] as? NSColor) { return false }
        #endif

        let lhsParagraph = lhs[.paragraphStyle] as? NSParagraphStyle
        let rhsParagraph = rhs[.paragraphStyle] as? NSParagraphStyle
        if !(lhsParagraph?.isEqual(rhsParagraph) ?? (rhsParagraph == nil)) { return false }

        if !numberAttributesEqual(lhs[.strikethroughStyle], rhs[.strikethroughStyle]) { return false }
        if !numberAttributesEqual(lhs[.quartzTableRowStyle], rhs[.quartzTableRowStyle]) { return false }
        return true
    }

    #if canImport(UIKit)
    private func fontsEqual(_ a: UIFont?, _ b: UIFont?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.fontName == b.fontName && a.pointSize == b.pointSize
    }

    private func colorsEqual(_ a: UIColor?, _ b: UIColor?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a == b
    }
    #elseif canImport(AppKit)
    private func fontsEqual(_ a: NSFont?, _ b: NSFont?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.fontName == b.fontName && a.pointSize == b.pointSize
    }

    private func colorsEqual(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a == b
    }
    #endif

    private func numberAttributesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs as NSNumber, rhs as NSNumber):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        default:
            return false
        }
    }

    private func platformClearColor() -> PlatformColor {
        #if canImport(UIKit)
        return UIColor.clear
        #elseif canImport(AppKit)
        return NSColor.clear
        #endif
    }
}

public struct EditorTextSegment {
    public let range: NSRange
    public let attributes: [NSAttributedString.Key: Any]
    public let blockID: String?

    public init(range: NSRange, attributes: [NSAttributedString.Key: Any], blockID: String? = nil) {
        self.range = range
        self.attributes = attributes
        self.blockID = blockID
    }
}

public struct EditorSemanticDocument: Sendable, Equatable {
    public static let empty = EditorSemanticDocument(textLength: 0, blocks: [], inlineTokens: [], inlineFormats: [])

    public let textLength: Int
    public let blocks: [EditorBlockNode]
    public let inlineTokens: [EditorInlineToken]
    public let inlineFormats: [EditorInlineFormatRun]

    public init(
        textLength: Int,
        blocks: [EditorBlockNode],
        inlineTokens: [EditorInlineToken],
        inlineFormats: [EditorInlineFormatRun]
    ) {
        self.textLength = textLength
        self.blocks = blocks
        self.inlineTokens = inlineTokens
        self.inlineFormats = inlineFormats
    }

    public static func build(markdown: String, spans: [HighlightSpan]) -> EditorSemanticDocument {
        let nsMarkdown = markdown as NSString
        let textLength = nsMarkdown.length
        guard textLength > 0 else { return .empty }

        return EditorSemanticDocument(
            textLength: textLength,
            blocks: buildBlockNodes(spans: spans, nsMarkdown: nsMarkdown),
            inlineTokens: buildInlineTokens(spans: spans, nsMarkdown: nsMarkdown),
            inlineFormats: buildInlineFormats(spans: spans, nsMarkdown: nsMarkdown)
        )
    }

    public func block(containing location: Int) -> EditorBlockNode? {
        guard !blocks.isEmpty else { return nil }
        let clampedLocation = min(max(location, 0), textLength)

        if clampedLocation == textLength,
           let trailingBlank = blocks.last(where: { $0.range.location == textLength && $0.range.length == 0 }) {
            return trailingBlank
        }

        if let block = blocks.first(where: { NSLocationInRange(clampedLocation, $0.range) }) {
            return block
        }

        if clampedLocation == textLength {
            return blocks.last(where: { NSMaxRange($0.range) == textLength })
        }

        return blocks.first(where: {
            $0.range.location <= clampedLocation && clampedLocation <= NSMaxRange($0.range)
        })
    }

    public func typingContext(at location: Int) -> EditorTypingContext {
        guard let block = block(containing: location) else { return .paragraph }
        switch block.kind {
        case let .heading(level):
            return .heading(level: level)
        case .blank, .paragraph, .listItem, .blockquote, .codeFence, .tableRow:
            return .paragraph
        }
    }

    public func isBlankBlock(at location: Int) -> Bool {
        guard let block = block(containing: location) else { return true }
        if case .blank = block.kind {
            return true
        }
        return false
    }

    public func revealedInlineTokenIDs(for selection: NSRange) -> [String] {
        inlineTokens.compactMap { token in
            guard let revealRange = token.revealRange,
                  selectionTouchesRevealRange(selection, revealRange: revealRange) else {
                return nil
            }
            return token.id
        }
    }

    public func selectionTouchesRevealRange(_ selection: NSRange, revealRange: NSRange) -> Bool {
        guard revealRange.location != NSNotFound,
              revealRange.location >= 0,
              revealRange.length > 0,
              NSMaxRange(revealRange) <= textLength else {
            return false
        }

        let clampedLocation = min(max(selection.location, 0), textLength)
        let clampedLength = min(max(selection.length, 0), max(textLength - clampedLocation, 0))

        if clampedLength == 0 {
            return clampedLocation >= revealRange.location && clampedLocation < NSMaxRange(revealRange)
        }

        return NSIntersectionRange(
            NSRange(location: clampedLocation, length: clampedLength),
            revealRange
        ).length > 0
    }

    public func inlineFormatKinds(at location: Int) -> Set<EditorInlineFormatKind> {
        let clampedLocation = min(max(location, 0), textLength)
        return Set(inlineFormats.compactMap { format in
            guard Self.rangeContainsCaret(format.range, at: clampedLocation, textLength: textLength) else {
                return nil
            }
            return format.kind
        })
    }

    private static func buildBlockNodes(
        spans: [HighlightSpan],
        nsMarkdown: NSString
    ) -> [EditorBlockNode] {
        var blocks: [EditorBlockNode] = []
        var fingerprints: [String: Int] = [:]
        let tableSpans = spans.filter { $0.tableRowStyle != nil }
        var activeCodeFenceMarker: Character?
        var cursor = 0

        while cursor < nsMarkdown.length {
            let fullLineRange = nsMarkdown.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = lineRangeWithoutNewlines(fullLineRange, in: nsMarkdown)
            let line = nsMarkdown.substring(with: contentRange)
            let classification = classifyBlock(
                line: line,
                lineRange: contentRange,
                tableSpans: tableSpans,
                activeCodeFenceMarker: activeCodeFenceMarker
            )
            let fingerprint = "\(classification.kind)|\(classification.normalizedContent)"
            let occurrence = (fingerprints[fingerprint] ?? 0) + 1
            fingerprints[fingerprint] = occurrence

            blocks.append(EditorBlockNode(
                id: "\(fingerprint)#\(occurrence)",
                kind: classification.kind,
                range: fullLineRange,
                contentRange: contentRange,
                syntaxRange: classification.syntaxRange
            ))

            if let fenceMarker = classification.codeFenceMarker {
                if activeCodeFenceMarker == fenceMarker {
                    activeCodeFenceMarker = nil
                } else if activeCodeFenceMarker == nil {
                    activeCodeFenceMarker = fenceMarker
                }
            }

            cursor = NSMaxRange(fullLineRange)
        }

        if hasTrailingLineBreak(nsMarkdown as String) {
            let fingerprint = "\(EditorBlockKind.blank)|"
            let occurrence = (fingerprints[fingerprint] ?? 0) + 1
            fingerprints[fingerprint] = occurrence
            blocks.append(EditorBlockNode(
                id: "\(fingerprint)#\(occurrence)",
                kind: .blank,
                range: NSRange(location: nsMarkdown.length, length: 0),
                contentRange: NSRange(location: nsMarkdown.length, length: 0),
                syntaxRange: nil
            ))
        }

        return blocks
    }

    private static func buildInlineTokens(
        spans: [HighlightSpan],
        nsMarkdown: NSString
    ) -> [EditorInlineToken] {
        var tokens: [EditorInlineToken] = []
        var fingerprints: [String: Int] = [:]

        let ordered = spans.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }

        for span in ordered {
            let kind: EditorInlineTokenKind
            let revealRange: NSRange?

            if span.attachment != nil {
                kind = .attachment
                revealRange = nil
            } else if span.wikiLinkTitle != nil {
                kind = .wikiLink
                if case let .concealWhenInactive(range) = span.overlayVisibilityBehavior {
                    revealRange = clamp(range, textLength: nsMarkdown.length)
                } else {
                    revealRange = nil
                }
            } else if span.isOverlay {
                switch span.overlayVisibilityBehavior {
                case .alwaysVisible:
                    kind = .visibleOverlay
                    revealRange = nil
                case let .concealWhenInactive(range):
                    kind = .concealableSyntax
                    revealRange = clamp(range, textLength: nsMarkdown.length)
                }
            } else {
                continue
            }

            let clampedRange = clamp(span.range, textLength: nsMarkdown.length)
            let surface = clampedRange.length > 0 ? nsMarkdown.substring(with: clampedRange) : ""
            let fingerprint = "\(kind)|\(surface)|\(revealRange?.location ?? -1):\(revealRange?.length ?? 0)"
            let occurrence = (fingerprints[fingerprint] ?? 0) + 1
            fingerprints[fingerprint] = occurrence

            tokens.append(EditorInlineToken(
                id: "\(fingerprint)#\(occurrence)",
                kind: kind,
                range: clampedRange,
                revealRange: revealRange,
                visibleTextRange: clampedRange.length > 0 ? clampedRange : nil
            ))
        }

        return tokens
    }

    private static func buildInlineFormats(
        spans: [HighlightSpan],
        nsMarkdown: NSString
    ) -> [EditorInlineFormatRun] {
        var formats: [EditorInlineFormatRun] = []
        var fingerprints: [String: Int] = [:]

        let ordered = spans.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }

        for span in ordered {
            let kind: EditorInlineFormatKind
            switch span.semanticRole {
            case .bold?:
                kind = .bold
            case .italic?:
                kind = .italic
            case .strikethrough?:
                kind = .strikethrough
            case .inlineCode?:
                kind = .inlineCode
            default:
                continue
            }

            let clampedRange = clamp(span.range, textLength: nsMarkdown.length)
            guard clampedRange.length > 0 else { continue }
            let surface = nsMarkdown.substring(with: clampedRange)
            let fingerprint = "\(kind)|\(surface)"
            let occurrence = (fingerprints[fingerprint] ?? 0) + 1
            fingerprints[fingerprint] = occurrence

            formats.append(EditorInlineFormatRun(
                id: "\(fingerprint)#\(occurrence)",
                kind: kind,
                range: clampedRange
            ))
        }

        return formats
    }

    private static func classifyBlock(
        line: String,
        lineRange: NSRange,
        tableSpans: [HighlightSpan],
        activeCodeFenceMarker: Character?
    ) -> (kind: EditorBlockKind, syntaxRange: NSRange?, normalizedContent: String, codeFenceMarker: Character?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (.blank, nil, "", nil)
        }

        if let fenceMarker = codeFenceMarker(in: line) {
            return (.codeFence, codeFenceSyntaxRange(in: line, globalLocation: lineRange.location), trimmed, fenceMarker)
        }

        if activeCodeFenceMarker != nil {
            return (.codeFence, nil, trimmed, nil)
        }

        if let level = headingLevel(in: line),
           let syntaxRange = headingSyntaxRange(in: line, globalLocation: lineRange.location, level: level) {
            return (.heading(level: level), syntaxRange, trimmed, nil)
        }

        if let (kind, syntaxRange) = listKindAndSyntaxRange(in: line, globalLocation: lineRange.location) {
            return (.listItem(kind: kind), syntaxRange, trimmed, nil)
        }

        if let syntaxRange = blockquoteSyntaxRange(in: line, globalLocation: lineRange.location) {
            return (.blockquote, syntaxRange, trimmed, nil)
        }

        if let style = tableSpans.first(where: { NSIntersectionRange($0.range, lineRange).length > 0 })?.tableRowStyle {
            return (.tableRow(style: style), nil, trimmed, nil)
        }

        return (.paragraph, nil, trimmed, nil)
    }

    private static func lineRangeWithoutNewlines(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let scalar = text.character(at: range.location + length - 1)
            if scalar == 10 || scalar == 13 {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
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

    private static func listKindAndSyntaxRange(in line: String, globalLocation: Int) -> (EditorListKind, NSRange)? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        if let checkboxRegex = try? NSRegularExpression(pattern: #"^\s*([-+*])\s+\[( |x|X)\]\s+"#),
           let match = checkboxRegex.firstMatch(in: line, range: fullRange) {
            let markerRange = match.range(at: 1)
            let checkedRange = match.range(at: 2)
            let marker = markerRange.location != NSNotFound
                ? Character(nsLine.substring(with: markerRange))
                : "-"
            let checkedToken = checkedRange.location != NSNotFound
                ? nsLine.substring(with: checkedRange)
                : " "
            return (
                .checkbox(checked: checkedToken.lowercased() == "x", marker: marker),
                NSRange(location: globalLocation + match.range.location, length: match.range.length)
            )
        }

        if let numberedRegex = try? NSRegularExpression(pattern: #"^\s*\d+[.)]\s+"#),
           let match = numberedRegex.firstMatch(in: line, range: fullRange) {
            return (
                .numbered,
                NSRange(location: globalLocation + match.range.location, length: match.range.length)
            )
        }

        if let bulletRegex = try? NSRegularExpression(pattern: #"^\s*([-+*])\s+"#),
           let match = bulletRegex.firstMatch(in: line, range: fullRange) {
            let markerRange = match.range(at: 1)
            let marker = markerRange.location != NSNotFound
                ? Character(nsLine.substring(with: markerRange))
                : "-"
            return (
                .bullet(marker: marker),
                NSRange(location: globalLocation + match.range.location, length: match.range.length)
            )
        }

        return nil
    }

    private static func blockquoteSyntaxRange(in line: String, globalLocation: Int) -> NSRange? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let regex = try? NSRegularExpression(pattern: #"^\s*>\s?"#),
              let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }
        return NSRange(location: globalLocation + match.range.location, length: match.range.length)
    }

    private static func codeFenceMarker(in line: String) -> Character? {
        let trimmedLeading = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmedLeading.hasPrefix("```") { return "`" }
        if trimmedLeading.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func codeFenceSyntaxRange(in line: String, globalLocation: Int) -> NSRange {
        let nsLine = line as NSString
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
        let markerCharacter = codeFenceMarker(in: line) ?? "`"
        var markerLength = 0
        while leadingWhitespace + markerLength < nsLine.length {
            let scalar = nsLine.character(at: leadingWhitespace + markerLength)
            if scalar == markerCharacter.asciiValue.map(UInt16.init) ?? 0 {
                markerLength += 1
            } else {
                break
            }
        }
        return NSRange(location: globalLocation + leadingWhitespace, length: max(markerLength, 3))
    }

    private static func clamp(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(range.location, 0), textLength)
        let length = min(max(range.length, 0), max(textLength - location, 0))
        return NSRange(location: location, length: length)
    }

    private static func rangeContainsCaret(_ range: NSRange, at location: Int, textLength: Int) -> Bool {
        guard range.location != NSNotFound, range.length > 0 else { return false }
        if location == textLength, location > 0 {
            return NSLocationInRange(location - 1, range)
        }
        return NSLocationInRange(location, range)
    }

    private static func hasTrailingLineBreak(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last == "\n" || last == "\r"
    }
}
