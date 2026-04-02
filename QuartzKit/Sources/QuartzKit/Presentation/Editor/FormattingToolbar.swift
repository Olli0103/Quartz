import SwiftUI

/// Markdown formatting actions.
public enum FormattingAction: String, CaseIterable, Sendable {
    case bold, italic, strikethrough, heading, bulletList, numberedList, checkbox
    case code, codeBlock, link, image, blockquote, highlight
    case table, math, footnote, mermaid
    // Heading level actions for HeadingDropdown
    case heading1, heading2, heading3, heading4, heading5, heading6, paragraph

    var icon: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .heading, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: "textformat.size.larger"
        case .paragraph: "paragraph"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .checkbox: "checklist"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "terminal"
        case .link: "link"
        case .image: "photo"
        case .blockquote: "text.quote"
        case .highlight: "highlighter"
        case .table: "tablecells"
        case .math: "function"
        case .footnote: "number"
        case .mermaid: "chart.bar.doc.horizontal"
        }
    }

    /// Keyboard shortcut for help text, e.g. "⌘B".
    var shortcut: String? {
        switch self {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .strikethrough: "⌘⇧X"
        case .heading: "⌘⇧H"
        case .heading1: "⌘1"
        case .heading2: "⌘2"
        case .heading3: "⌘3"
        case .heading4: "⌘4"
        case .heading5: "⌘5"
        case .heading6: "⌘6"
        case .paragraph: "⌘0"
        case .code: "⌘E"
        case .link: "⌘⇧L"
        case .blockquote: "⌘⇧Q"
        default: nil
        }
    }

    var label: String {
        switch self {
        case .bold: String(localized: "Bold", bundle: .module)
        case .italic: String(localized: "Italic", bundle: .module)
        case .strikethrough: String(localized: "Strikethrough", bundle: .module)
        case .heading: String(localized: "Heading", bundle: .module)
        case .heading1: String(localized: "Heading 1", bundle: .module)
        case .heading2: String(localized: "Heading 2", bundle: .module)
        case .heading3: String(localized: "Heading 3", bundle: .module)
        case .heading4: String(localized: "Heading 4", bundle: .module)
        case .heading5: String(localized: "Heading 5", bundle: .module)
        case .heading6: String(localized: "Heading 6", bundle: .module)
        case .paragraph: String(localized: "Paragraph", bundle: .module)
        case .bulletList: String(localized: "Bullet List", bundle: .module)
        case .numberedList: String(localized: "Numbered List", bundle: .module)
        case .checkbox: String(localized: "Checkbox", bundle: .module)
        case .code: String(localized: "Inline Code", bundle: .module)
        case .codeBlock: String(localized: "Code Block", bundle: .module)
        case .link: String(localized: "Link", bundle: .module)
        case .image: String(localized: "Image", bundle: .module)
        case .blockquote: String(localized: "Quote", bundle: .module)
        case .highlight: String(localized: "Highlight", bundle: .module)
        case .table: String(localized: "Table", bundle: .module)
        case .math: String(localized: "Math", bundle: .module)
        case .footnote: String(localized: "Footnote", bundle: .module)
        case .mermaid: String(localized: "Mermaid Diagram", bundle: .module)
        }
    }

    var markdownSyntax: MarkdownSyntax {
        switch self {
        case .bold: .wrap("**")
        case .italic: .wrap("*")
        case .strikethrough: .wrap("~~")
        case .heading: .linePrefix("# ")
        case .heading1: .linePrefix("# ")
        case .heading2: .linePrefix("## ")
        case .heading3: .linePrefix("### ")
        case .heading4: .linePrefix("#### ")
        case .heading5: .linePrefix("##### ")
        case .heading6: .linePrefix("###### ")
        case .paragraph: .removeHeadingPrefix
        case .bulletList: .linePrefix("- ")
        case .numberedList: .linePrefix("1. ")
        case .checkbox: .linePrefix("- [ ] ")
        case .code: .wrap("`")
        case .codeBlock: .block("```\n", "\n```")
        case .link: .template("[", "](url)")
        case .image: .template("![", "](path)")
        case .blockquote: .linePrefix("> ")
        case .highlight: .wrap("==")
        case .table: .insert("| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Cell 1 | Cell 2 | Cell 3 |\n")
        case .math: .wrap("$")
        case .footnote: .template("[^", "]: ")
        case .mermaid: .block("```mermaid\n", "\n```")
        }
    }
}

public enum MarkdownSyntax: Sendable {
    case wrap(String)
    case linePrefix(String)
    case block(String, String)
    case template(String, String)
    case insert(String)
    case removeHeadingPrefix
}

// MARK: - Formatting Toolbar View

/// Icon and divider sizes – larger on macOS for better legibility.
private var formatBarIconSize: CGFloat {
    #if os(macOS)
    17
    #else
    14
    #endif
}

private var formatBarIconWeight: Font.Weight {
    #if os(macOS)
    .semibold
    #else
    .medium
    #endif
}

private var formatBarDividerHeight: CGFloat {
    #if os(macOS)
    22
    #else
    18
    #endif
}

public struct FormattingToolbar: View {
    let onAction: (FormattingAction) -> Void

    private let primaryActions: [FormattingAction] = [
        .bold, .italic, .strikethrough, .heading, .bulletList, .checkbox, .code, .link
    ]
    private let secondaryActions: [FormattingAction] = [
        .numberedList, .codeBlock, .image, .blockquote, .highlight, .table, .math, .footnote, .mermaid
    ]

    public init(onAction: @escaping (FormattingAction) -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryActions, id: \.self) { action in
                    FormatButton(action: action) {
                        onAction(action)
                    }
                }

                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: formatBarDividerHeight)
                    .padding(.horizontal, 8)

                Menu {
                    ForEach(secondaryActions, id: \.self) { action in
                        Button { onAction(action) } label: {
                            Label(action.label, systemImage: action.icon)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: formatBarIconSize, weight: formatBarIconWeight))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(String(localized: "More formatting options", bundle: .module))
                .help(String(localized: "More formatting options", bundle: .module))
            }
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 44)
    }
}

/// Individual formatting button with explicit hover + press visual feedback.
private struct FormatButton: View {
    let action: FormattingAction
    let onTap: () -> Void
    @Environment(\.appearanceManager) private var appearance
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: action.icon)
            .font(.system(size: formatBarIconSize, weight: formatBarIconWeight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isPressed ? appearance.accentColor : isHovered ? .primary : .secondary)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in isHovered = hovering }
            .onTapGesture {
                QuartzFeedback.selection()
                onTap()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityLabel(action.label)
            .help(helpText)
    }

    private var helpText: String {
        if let shortcut = action.shortcut {
            return "\(action.label) (\(shortcut))"
        }
        return action.label
    }

    private var backgroundColor: Color {
        if isPressed { return appearance.accentColor.opacity(0.2) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}

// MARK: - Surgical Format Edit

/// Describes a surgical text edit for formatting — no full-text replacement needed.
/// Used by `EditorSession.applyFormatting` to pipe through `applyExternalEdit`.
public struct MarkdownFormatEdit: Sendable {
    /// The range in the original text to replace.
    public let range: NSRange
    /// The replacement string.
    public let replacement: String
    /// Where to place the cursor after the edit.
    public let cursorAfter: NSRange

    public init(range: NSRange, replacement: String, cursorAfter: NSRange) {
        self.range = range
        self.replacement = replacement
        self.cursorAfter = cursorAfter
    }
}

// MARK: - Formatting State

/// Tracks which formatting markers are active at the current cursor position.
/// Used to highlight active toolbar buttons (e.g., Bold button appears pressed when cursor is inside **...**).
public struct FormattingState: Equatable, Sendable {
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var isStrikethrough: Bool = false
    public var isCode: Bool = false
    public var headingLevel: Int = 0  // 0 = no heading, 1-6 = H1-H6

    public static let empty = FormattingState()

    public init(isBold: Bool = false, isItalic: Bool = false, isStrikethrough: Bool = false, isCode: Bool = false, headingLevel: Int = 0) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough
        self.isCode = isCode
        self.headingLevel = headingLevel
    }

    /// Detects formatting state at a given cursor position in markdown text.
    public static func detect(in text: String, at cursorLocation: Int) -> FormattingState {
        let nsText = text as NSString
        guard cursorLocation >= 0, cursorLocation <= nsText.length else { return .empty }

        // Detect heading level from current line
        let lineRange = nsText.lineRange(for: NSRange(location: min(cursorLocation, max(0, nsText.length - 1)), length: 0))
        let line = nsText.substring(with: lineRange)
        var headingLevel = 0
        let trimmedLine = line.trimmingCharacters(in: .newlines)
        if trimmedLine.hasPrefix("#") {
            var level = 0
            for ch in trimmedLine {
                if ch == "#" { level += 1 } else { break }
            }
            let afterHashes = String(trimmedLine.dropFirst(level))
            if level >= 1 && level <= 6 && (afterHashes.isEmpty || afterHashes.hasPrefix(" ")) {
                headingLevel = level
            }
        }

        // Detect inline formatting by scanning for markers around cursor
        let isBold = isWrapped(in: nsText, at: cursorLocation, marker: "**")
        let isItalic = isWrappedSingle(in: nsText, at: cursorLocation, marker: "*", doubleMarker: "**")
        let isStrikethrough = isWrapped(in: nsText, at: cursorLocation, marker: "~~")
        let isCode = isWrapped(in: nsText, at: cursorLocation, marker: "`")

        return FormattingState(
            isBold: isBold,
            isItalic: isItalic,
            isStrikethrough: isStrikethrough,
            isCode: isCode,
            headingLevel: headingLevel
        )
    }

    /// Checks if cursor position is between two instances of `marker` on the same line.
    private static func isWrapped(in text: NSString, at cursor: Int, marker: String) -> Bool {
        let lineRange = text.lineRange(for: NSRange(location: min(cursor, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        let localCursor = cursor - lineRange.location

        // Find marker before cursor
        guard let beforeRange = (line as NSString).range(of: marker, options: .backwards,
                range: NSRange(location: 0, length: min(localCursor, (line as NSString).length))).toOptional(),
              beforeRange.location != NSNotFound else { return false }

        // Find marker after cursor
        let searchStart = localCursor
        let searchLen = (line as NSString).length - searchStart
        guard searchLen > 0 else { return false }
        let afterRange = (line as NSString).range(of: marker,
                range: NSRange(location: searchStart, length: searchLen))
        return afterRange.location != NSNotFound
    }

    /// Detects single * italic (not inside ** bold).
    private static func isWrappedSingle(in text: NSString, at cursor: Int, marker: String, doubleMarker: String) -> Bool {
        // If already bold, check for triple *** (bold+italic)
        let lineRange = text.lineRange(for: NSRange(location: min(cursor, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        let localCursor = cursor - lineRange.location
        let nsLine = line as NSString

        // Count marker occurrences before and after cursor
        var beforeCount = 0
        var i = 0
        while i < localCursor && i < nsLine.length {
            if nsLine.character(at: i) == Character(marker).asciiValue.map(UInt16.init) ?? 0 {
                beforeCount += 1
            }
            i += 1
        }

        var afterCount = 0
        i = localCursor
        while i < nsLine.length {
            if nsLine.character(at: i) == Character(marker).asciiValue.map(UInt16.init) ?? 0 {
                afterCount += 1
            }
            i += 1
        }

        // Odd counts on both sides suggest italic (single marker pair)
        return beforeCount % 2 == 1 && afterCount % 2 == 1
    }
}

private extension NSRange {
    func toOptional() -> NSRange? {
        location == NSNotFound ? nil : self
    }
}

// MARK: - Markdown Text Formatting Logic

public struct MarkdownFormatter: Sendable {
    public init() {}

    /// Computes a surgical edit descriptor for a formatting action.
    /// Returns `nil` if the action doesn't modify the text.
    /// Uses NSString ranges throughout for emoji/multibyte safety.
    public func surgicalEdit(
        _ action: FormattingAction,
        in text: String,
        selectedRange: NSRange
    ) -> MarkdownFormatEdit? {
        let nsText = text as NSString
        let selectedText = nsText.substring(with: selectedRange)

        switch action.markdownSyntax {
        case .wrap(let marker):
            return surgicalWrap(marker, text: nsText, selection: selectedRange, selectedText: selectedText)
        case .linePrefix(let prefix):
            return surgicalLinePrefix(prefix, text: nsText, selection: selectedRange)
        case .block(let open, let close):
            let replacement = "\(open)\(selectedText)\(close)"
            return MarkdownFormatEdit(
                range: selectedRange,
                replacement: replacement,
                cursorAfter: NSRange(location: selectedRange.location + (open as NSString).length, length: (selectedText as NSString).length)
            )
        case .template(let before, let after):
            let replacement = "\(before)\(selectedText)\(after)"
            let cursorLoc: Int
            if selectedText.isEmpty {
                cursorLoc = selectedRange.location + (before as NSString).length
            } else {
                cursorLoc = selectedRange.location + (replacement as NSString).length
            }
            return MarkdownFormatEdit(
                range: selectedRange,
                replacement: replacement,
                cursorAfter: NSRange(location: cursorLoc, length: 0)
            )
        case .insert(let raw):
            return MarkdownFormatEdit(
                range: selectedRange,
                replacement: raw,
                cursorAfter: NSRange(location: selectedRange.location + (raw as NSString).length, length: 0)
            )
        case .removeHeadingPrefix:
            return surgicalRemoveHeading(text: nsText, selection: selectedRange)
        }
    }

    private func surgicalWrap(_ marker: String, text: NSString, selection: NSRange, selectedText: String) -> MarkdownFormatEdit {
        let mLen = (marker as NSString).length

        // Case 1: Selection is INSIDE markers — markers are adjacent to selection
        // e.g., **|word|** where | marks selection bounds
        let beforeStart = selection.location - mLen
        let afterEnd = selection.location + selection.length
        let hasBefore = beforeStart >= 0 && text.substring(with: NSRange(location: beforeStart, length: mLen)) == marker
        let hasAfter = afterEnd + mLen <= text.length && text.substring(with: NSRange(location: afterEnd, length: mLen)) == marker

        if hasBefore && hasAfter {
            // Toggle OFF: remove markers around selection, keep inner text
            let removeRange = NSRange(location: beforeStart, length: selection.length + mLen * 2)
            return MarkdownFormatEdit(
                range: removeRange,
                replacement: selectedText,
                cursorAfter: NSRange(location: beforeStart, length: (selectedText as NSString).length)
            )
        }

        // Case 2: Selection INCLUDES the markers
        // e.g., |**word**| where | marks selection bounds
        let selStr = selectedText as NSString
        if selStr.length >= mLen * 2 {
            let startsWithMarker = selStr.substring(to: mLen) == marker
            let endsWithMarker = selStr.substring(from: selStr.length - mLen) == marker
            if startsWithMarker && endsWithMarker {
                // Toggle OFF: strip markers from selected text
                let innerText = selStr.substring(with: NSRange(location: mLen, length: selStr.length - mLen * 2))
                return MarkdownFormatEdit(
                    range: selection,
                    replacement: innerText,
                    cursorAfter: NSRange(location: selection.location, length: (innerText as NSString).length)
                )
            }
        }

        // Toggle ON: wrap selection in markers
        let replacement = "\(marker)\(selectedText)\(marker)"
        return MarkdownFormatEdit(
            range: selection,
            replacement: replacement,
            cursorAfter: NSRange(location: selection.location + mLen, length: (selectedText as NSString).length)
        )
    }

    private func surgicalLinePrefix(_ prefix: String, text: NSString, selection: NSRange) -> MarkdownFormatEdit {
        let lineRange = text.lineRange(for: selection)
        let line = text.substring(with: lineRange)

        let headingPrefixPattern = /^#{1,6}\s/
        if prefix.hasPrefix("#"), let match = line.prefixMatch(of: headingPrefixPattern) {
            let existingPrefix = String(line[match.range])
            let trimmedLine = String(line[match.range.upperBound...])

            // If the existing heading prefix matches the requested one, toggle OFF
            if existingPrefix == prefix {
                return MarkdownFormatEdit(
                    range: lineRange,
                    replacement: trimmedLine,
                    cursorAfter: NSRange(location: lineRange.location, length: 0)
                )
            }

            // Otherwise, replace with the new heading level
            let newLine = prefix + trimmedLine
            let prefixDiff = (prefix as NSString).length - match.range.upperBound.utf16Offset(in: line)
            return MarkdownFormatEdit(
                range: lineRange,
                replacement: newLine,
                cursorAfter: NSRange(location: selection.location + prefixDiff, length: 0)
            )
        }

        let prefixLen = (prefix as NSString).length
        if line.hasPrefix(prefix) {
            let newLine = String(line.dropFirst(prefix.count))
            return MarkdownFormatEdit(
                range: lineRange,
                replacement: newLine,
                cursorAfter: NSRange(location: max(selection.location - prefixLen, lineRange.location), length: 0)
            )
        } else {
            let newLine = prefix + line
            return MarkdownFormatEdit(
                range: lineRange,
                replacement: newLine,
                cursorAfter: NSRange(location: selection.location + prefixLen, length: 0)
            )
        }
    }

    /// Strips ALL line-level formatting: headings (#), bullets (- * +), numbers (1.), checkboxes (- [ ]), blockquotes (>).
    private func surgicalRemoveHeading(text: NSString, selection: NSRange) -> MarkdownFormatEdit? {
        let lineRange = text.lineRange(for: selection)
        let line = text.substring(with: lineRange)
        let trimmedLine = line.trimmingCharacters(in: .newlines)

        // Try each prefix pattern in order of specificity
        let patterns: [(check: (String) -> Int?, label: String)] = [
            // Checkboxes: - [ ] or - [x]
            ({ line in
                if line.hasPrefix("- [ ] ") { return 6 }
                if line.hasPrefix("- [x] ") { return 6 }
                if line.hasPrefix("- [X] ") { return 6 }
                return nil
            }, "checkbox"),
            // Headings: # through ######
            ({ line in
                guard line.hasPrefix("#") else { return nil }
                var count = 0
                for ch in line { if ch == "#" { count += 1 } else { break } }
                guard count >= 1, count <= 6 else { return nil }
                let rest = String(line.dropFirst(count))
                if rest.hasPrefix(" ") { return count + 1 }
                if rest.isEmpty { return count }
                return nil
            }, "heading"),
            // Blockquotes: > or > text
            ({ line in
                if line.hasPrefix("> ") { return 2 }
                if line == ">" || line.hasPrefix(">\n") { return 1 }
                return nil
            }, "blockquote"),
            // Unordered lists: - * +
            ({ line in
                for prefix in ["- ", "* ", "+ "] {
                    if line.hasPrefix(prefix) { return prefix.count }
                }
                return nil
            }, "bullet"),
            // Ordered lists: 1. 2. 10. etc
            ({ line in
                var i = line.startIndex
                while i < line.endIndex && line[i].isNumber { i = line.index(after: i) }
                guard i > line.startIndex, i < line.endIndex, line[i] == "." else { return nil }
                let afterDot = line.index(after: i)
                guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
                return line.distance(from: line.startIndex, to: line.index(after: afterDot))
            }, "ordered"),
        ]

        for (check, _) in patterns {
            if let prefixLen = check(trimmedLine) {
                let newLine = String(trimmedLine.dropFirst(prefixLen))
                // Preserve trailing newline if the original line had one
                let suffix = line.hasSuffix("\n") ? "\n" : ""
                let replacement = newLine + suffix
                return MarkdownFormatEdit(
                    range: lineRange,
                    replacement: replacement,
                    cursorAfter: NSRange(location: max(selection.location - prefixLen, lineRange.location), length: 0)
                )
            }
        }

        return nil
    }

    // MARK: - Legacy Full-Text API (kept for backward compatibility)

    public func apply(
        _ action: FormattingAction,
        to text: String,
        selectedRange: NSRange
    ) -> (text: String, newSelection: NSRange) {
        let nsText = text as NSString
        let selectedText = nsText.substring(with: selectedRange)

        switch action.markdownSyntax {
        case .wrap(let marker):
            return applyWrap(marker, text: text, selection: selectedRange, selectedText: selectedText)
        case .linePrefix(let prefix):
            return applyLinePrefix(prefix, text: text, selection: selectedRange)
        case .block(let open, let close):
            let replacement = "\(open)\(selectedText)\(close)"
            let newText = nsText.replacingCharacters(in: selectedRange, with: replacement)
            return (newText, NSRange(location: selectedRange.location + open.count, length: selectedText.count))
        case .template(let before, let after):
            let replacement = "\(before)\(selectedText)\(after)"
            let newText = nsText.replacingCharacters(in: selectedRange, with: replacement)
            if selectedText.isEmpty {
                return (newText, NSRange(location: selectedRange.location + before.count, length: 0))
            } else {
                return (newText, NSRange(location: selectedRange.location + before.count + selectedText.count + after.count, length: 0))
            }
        case .insert(let raw):
            let newText = nsText.replacingCharacters(in: selectedRange, with: raw)
            return (newText, NSRange(location: selectedRange.location + raw.count, length: 0))
        case .removeHeadingPrefix:
            return removeHeadingPrefix(text: text, selection: selectedRange)
        }
    }

    private func applyWrap(_ marker: String, text: String, selection: NSRange, selectedText: String) -> (String, NSRange) {
        let nsText = text as NSString
        let mLen = (marker as NSString).length

        // Case 1: Selection is INSIDE markers
        let beforeStart = selection.location - mLen
        let afterEnd = selection.location + selection.length
        let hasBefore = beforeStart >= 0 && nsText.substring(with: NSRange(location: beforeStart, length: mLen)) == marker
        let hasAfter = afterEnd + mLen <= nsText.length && nsText.substring(with: NSRange(location: afterEnd, length: mLen)) == marker

        if hasBefore && hasAfter {
            let removeRange = NSRange(location: beforeStart, length: selection.length + mLen * 2)
            let newText = nsText.replacingCharacters(in: removeRange, with: selectedText)
            return (newText, NSRange(location: beforeStart, length: (selectedText as NSString).length))
        }

        // Case 2: Selection INCLUDES the markers
        let selStr = selectedText as NSString
        if selStr.length >= mLen * 2 {
            let startsWithMarker = selStr.substring(to: mLen) == marker
            let endsWithMarker = selStr.substring(from: selStr.length - mLen) == marker
            if startsWithMarker && endsWithMarker {
                let innerText = selStr.substring(with: NSRange(location: mLen, length: selStr.length - mLen * 2))
                let newText = nsText.replacingCharacters(in: selection, with: innerText)
                return (newText, NSRange(location: selection.location, length: (innerText as NSString).length))
            }
        }

        // Toggle ON
        let replacement = "\(marker)\(selectedText)\(marker)"
        let newText = nsText.replacingCharacters(in: selection, with: replacement)
        return (newText, NSRange(location: selection.location + mLen, length: (selectedText as NSString).length))
    }

    private func applyLinePrefix(_ prefix: String, text: String, selection: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: selection)
        let line = nsText.substring(with: lineRange)

        // For heading prefixes, check existing heading
        let headingPrefixPattern = /^#{1,6}\s/
        if prefix.hasPrefix("#"), let match = line.prefixMatch(of: headingPrefixPattern) {
            let existingPrefix = String(line[match.range])
            let trimmedLine = String(line[match.range.upperBound...])

            // If the existing heading prefix matches the requested one, toggle OFF
            if existingPrefix == prefix {
                let newText = nsText.replacingCharacters(in: lineRange, with: trimmedLine)
                return (newText, NSRange(location: lineRange.location, length: 0))
            }

            // Otherwise, replace with the new heading level
            let newLine = prefix + trimmedLine
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            let prefixDiff = prefix.count - match.range.upperBound.utf16Offset(in: line)
            return (newText, NSRange(location: selection.location + prefixDiff, length: 0))
        }

        if line.hasPrefix(prefix) {
            let newLine = String(line.dropFirst(prefix.count))
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            return (newText, NSRange(location: max(selection.location - prefix.count, lineRange.location), length: 0))
        } else {
            let newLine = prefix + line
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            return (newText, NSRange(location: selection.location + prefix.count, length: 0))
        }
    }

    private func removeHeadingPrefix(text: String, selection: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        // Use the surgical version and apply its result
        if let edit = surgicalRemoveHeading(text: nsText, selection: selection) {
            let newText = nsText.replacingCharacters(in: edit.range, with: edit.replacement)
            return (newText, edit.cursorAfter)
        }
        return (text, selection)
    }
}
