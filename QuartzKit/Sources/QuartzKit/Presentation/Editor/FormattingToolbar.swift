import SwiftUI

/// Source-neutral markdown formatting model.
/// This file defines formatting actions and surgical edit generation only.
/// Input-path-specific selection and responder recovery belong in `EditorSession`.

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

extension FormattingAction {
    var prefersRecoveredExpandedSelection: Bool {
        switch self {
        case .bold, .italic, .strikethrough, .code, .link, .image, .highlight, .math, .footnote:
            return true
        case .heading, .bulletList, .numberedList, .checkbox, .codeBlock, .blockquote, .table, .mermaid,
                .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .paragraph:
            return false
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
    static let exposesFootnoteAction = false
    static let primaryActions: [FormattingAction] = [
        .bold, .italic, .strikethrough, .heading, .bulletList, .checkbox, .code, .link
    ]
    static let secondaryActions: [FormattingAction] = [
        .numberedList, .codeBlock, .image, .blockquote, .highlight, .table, .math, .mermaid
    ]

    let onAction: (FormattingAction) -> Void

    public init(onAction: @escaping (FormattingAction) -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.primaryActions, id: \.self) { action in
                    FormatButton(action: action) {
                        onAction(action)
                    }
                }

                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: formatBarDividerHeight)
                    .padding(.horizontal, 8)

                Menu {
                    ForEach(Self.secondaryActions, id: \.self) { action in
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
            .accessibilityInputLabels([Text(action.label)])
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
    /// Whether applying this edit should mutate the markdown text.
    public let changesText: Bool

    public init(range: NSRange, replacement: String, cursorAfter: NSRange, changesText: Bool = true) {
        self.range = range
        self.replacement = replacement
        self.cursorAfter = cursorAfter
        self.changesText = changesText
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
    public var isBulletList: Bool = false
    public var isNumberedList: Bool = false
    public var isCheckbox: Bool = false
    public var isBlockquote: Bool = false
    public var isCodeBlock: Bool = false
    public var headingLevel: Int = 0  // 0 = no heading, 1-6 = H1-H6

    public static let empty = FormattingState()

    public init(
        isBold: Bool = false,
        isItalic: Bool = false,
        isStrikethrough: Bool = false,
        isCode: Bool = false,
        isBulletList: Bool = false,
        isNumberedList: Bool = false,
        isCheckbox: Bool = false,
        isBlockquote: Bool = false,
        isCodeBlock: Bool = false,
        headingLevel: Int = 0
    ) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough
        self.isCode = isCode
        self.isBulletList = isBulletList
        self.isNumberedList = isNumberedList
        self.isCheckbox = isCheckbox
        self.isBlockquote = isBlockquote
        self.isCodeBlock = isCodeBlock
        self.headingLevel = headingLevel
    }

    public var hasActiveHeading: Bool { headingLevel > 0 }
    public var hasActiveOverflowStyle: Bool { isNumberedList || isBlockquote || isCodeBlock }

    public func isActive(_ action: FormattingAction) -> Bool {
        switch action {
        case .bold:
            return isBold
        case .italic:
            return isItalic
        case .strikethrough:
            return isStrikethrough
        case .code:
            return isCode
        case .bulletList:
            return isBulletList
        case .numberedList:
            return isNumberedList
        case .checkbox:
            return isCheckbox
        case .blockquote:
            return isBlockquote
        case .codeBlock:
            return isCodeBlock
        case .heading1:
            return headingLevel == 1
        case .heading2:
            return headingLevel == 2
        case .heading3:
            return headingLevel == 3
        case .heading4:
            return headingLevel == 4
        case .heading5:
            return headingLevel == 5
        case .heading6:
            return headingLevel == 6
        case .heading:
            return hasActiveHeading
        case .paragraph:
            return !hasActiveHeading && !isBulletList && !isNumberedList && !isCheckbox && !isBlockquote && !isCodeBlock
        case .link, .image, .highlight, .table, .math, .footnote, .mermaid:
            return false
        }
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
        let blockState = blockState(in: nsText, at: cursorLocation)

        return FormattingState(
            isBold: isBold,
            isItalic: isItalic,
            isStrikethrough: isStrikethrough,
            isCode: isCode,
            isBulletList: blockState.isBulletList,
            isNumberedList: blockState.isNumberedList,
            isCheckbox: blockState.isCheckbox,
            isBlockquote: blockState.isBlockquote,
            isCodeBlock: blockState.isCodeBlock,
            headingLevel: headingLevel
        )
    }

    /// Prefers semantic editor state, but falls back to lightweight markdown heuristics
    /// while highlight spans are still catching up after a live edit.
    public static func detect(
        in text: String,
        semanticDocument: EditorSemanticDocument,
        at cursorLocation: Int
    ) -> FormattingState {
        let fallback = detect(in: text, at: cursorLocation)
        guard semanticDocument.textLength > 0 else { return fallback }

        let headingLevel: Int
        switch semanticDocument.typingContext(at: cursorLocation) {
        case let .heading(level):
            headingLevel = level
        case .paragraph:
            headingLevel = fallback.headingLevel
        }

        let inlineKinds = semanticDocument.inlineFormatKinds(at: cursorLocation)
        let semanticBlockState = blockState(in: semanticDocument, at: cursorLocation)
        return FormattingState(
            isBold: inlineKinds.contains(.bold) || fallback.isBold,
            isItalic: inlineKinds.contains(.italic) || fallback.isItalic,
            isStrikethrough: inlineKinds.contains(.strikethrough) || fallback.isStrikethrough,
            isCode: inlineKinds.contains(.inlineCode) || fallback.isCode,
            isBulletList: semanticBlockState.isBulletList || fallback.isBulletList,
            isNumberedList: semanticBlockState.isNumberedList || fallback.isNumberedList,
            isCheckbox: semanticBlockState.isCheckbox || fallback.isCheckbox,
            isBlockquote: semanticBlockState.isBlockquote || fallback.isBlockquote,
            isCodeBlock: semanticBlockState.isCodeBlock || fallback.isCodeBlock,
            headingLevel: headingLevel
        )
    }

    private static func blockState(in semanticDocument: EditorSemanticDocument, at cursorLocation: Int) -> FormattingState {
        guard let block = semanticDocument.block(containing: cursorLocation) else { return .empty }
        switch block.kind {
        case let .listItem(kind):
            switch kind {
            case .bullet:
                return FormattingState(isBulletList: true)
            case .numbered:
                return FormattingState(isNumberedList: true)
            case .checkbox:
                return FormattingState(isCheckbox: true)
            }
        case .blockquote:
            return FormattingState(isBlockquote: true)
        case .codeFence:
            return FormattingState(isCodeBlock: true)
        case .blank, .paragraph, .heading, .tableRow:
            return .empty
        }
    }

    private static func blockState(in text: NSString, at cursorLocation: Int) -> FormattingState {
        let lineRange = text.lineRange(for: NSRange(location: min(cursorLocation, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        let trimmedLine = line.trimmingCharacters(in: .newlines)

        if isInsideCodeFence(in: text as String, at: cursorLocation) {
            return FormattingState(isCodeBlock: true)
        }

        if trimmedLine.range(of: #"^\s*>\s?"#, options: .regularExpression) != nil {
            return FormattingState(isBlockquote: true)
        }

        if trimmedLine.range(of: #"^\s*[-+*]\s+\[( |x|X)\]\s+"#, options: .regularExpression) != nil {
            return FormattingState(isCheckbox: true)
        }

        if trimmedLine.range(of: #"^\s*\d+[.)]\s+"#, options: .regularExpression) != nil {
            return FormattingState(isNumberedList: true)
        }

        if trimmedLine.range(of: #"^\s*[-+*]\s+"#, options: .regularExpression) != nil {
            return FormattingState(isBulletList: true)
        }

        return .empty
    }

    private static func isInsideCodeFence(in text: String, at cursorLocation: Int) -> Bool {
        var activeFence: Character?
        let nsText = text as NSString
        var cursor = 0

        while cursor < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = NSRange(location: lineRange.location, length: max(lineRange.length - trailingNewlineLength(of: nsText, in: lineRange), 0))
            let line = nsText.substring(with: contentRange)
            let marker = codeFenceMarker(in: line)

            if cursorLocation >= lineRange.location && cursorLocation <= NSMaxRange(lineRange) {
                return activeFence != nil || marker != nil
            }

            if let marker {
                if activeFence == marker {
                    activeFence = nil
                } else if activeFence == nil {
                    activeFence = marker
                }
            }

            cursor = NSMaxRange(lineRange)
        }

        return activeFence != nil && cursorLocation >= nsText.length
    }

    private static func trailingNewlineLength(of text: NSString, in lineRange: NSRange) -> Int {
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

    private static func codeFenceMarker(in line: String) -> Character? {
        let trimmedLeading = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmedLeading.hasPrefix("```") { return "`" }
        if trimmedLeading.hasPrefix("~~~") { return "~" }
        return nil
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
    private static let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"(?<image>!)?\[(?<label>[^\]]*)\]\((?<destination>[^)]*)\)"#
    )

    public init() {}

    /// Computes a surgical edit descriptor for a formatting action.
    /// Returns `nil` if the action doesn't modify the text.
    /// Uses NSString ranges throughout for emoji/multibyte safety.
    public func surgicalEdit(
        _ action: FormattingAction,
        in text: String,
        selectedRange: NSRange,
        semanticDocument: EditorSemanticDocument? = nil
    ) -> MarkdownFormatEdit? {
        let nsText = text as NSString
        let selectedText = nsText.substring(with: selectedRange)

        switch action.markdownSyntax {
        case .wrap(let marker):
            return surgicalWrap(marker, text: nsText, selection: selectedRange, selectedText: selectedText)
        case .linePrefix(let prefix):
            if let edit = semanticLinePrefix(
                for: action,
                targetPrefix: prefix,
                text: nsText,
                selection: selectedRange,
                semanticDocument: semanticDocument
            ) {
                return edit
            }
            return surgicalLinePrefix(prefix, text: nsText, selection: selectedRange)
        case .block(let open, let close):
            if let edit = semanticCodeFenceEdit(
                for: action,
                open: open,
                close: close,
                text: nsText,
                selection: selectedRange,
                semanticDocument: semanticDocument
            ) {
                return edit
            }
            if let edit = structuredFenceInsertEdit(
                for: action,
                open: open,
                close: close,
                text: nsText,
                selection: selectedRange
            ) {
                return edit
            }
            if let edit = lineAwareBlockEdit(
                open: open,
                close: close,
                text: nsText,
                selection: selectedRange
            ) {
                return edit
            }
            let replacement = "\(open)\(selectedText)\(close)"
            return MarkdownFormatEdit(
                range: selectedRange,
                replacement: replacement,
                cursorAfter: NSRange(location: selectedRange.location + (open as NSString).length, length: (selectedText as NSString).length)
            )
        case .template(let before, let after):
            if let selectionOnlyEdit = selectionOnlyTemplateEdit(
                for: action,
                text: nsText,
                selection: selectedRange
            ) {
                return selectionOnlyEdit
            }
            let replacement = "\(before)\(selectedText)\(after)"
            return MarkdownFormatEdit(
                range: selectedRange,
                replacement: replacement,
                cursorAfter: templateCursorRange(
                    for: action,
                    selectedRange: selectedRange,
                    selectedText: selectedText,
                    before: before,
                    after: after
                )
            )
        case .insert(let raw):
            if let edit = structuredInsertEdit(
                for: action,
                raw: raw,
                text: nsText,
                selection: selectedRange
            ) {
                return edit
            }
            return MarkdownFormatEdit(
                range: selectedRange,
                replacement: raw,
                cursorAfter: NSRange(location: selectedRange.location + (raw as NSString).length, length: 0)
            )
        case .removeHeadingPrefix:
            if let edit = semanticCodeFenceEdit(
                for: action,
                open: nil,
                close: nil,
                text: nsText,
                selection: selectedRange,
                semanticDocument: semanticDocument
            ) {
                return edit
            }
            if let edit = semanticLinePrefix(
                for: action,
                targetPrefix: nil,
                text: nsText,
                selection: selectedRange,
                semanticDocument: semanticDocument
            ) {
                return edit
            }
            return surgicalRemoveHeading(text: nsText, selection: selectedRange)
        }
    }

    private func selectionOnlyTemplateEdit(
        for action: FormattingAction,
        text: NSString,
        selection: NSRange
    ) -> MarkdownFormatEdit? {
        guard action == .link || action == .image else { return nil }
        guard text.length > 0 else { return nil }

        let fullRange = NSRange(location: 0, length: text.length)
        let matches = Self.markdownLinkRegex.matches(in: text as String, range: fullRange)

        for match in matches {
            let matchRange = match.range
            guard selectionIntersects(selection, candidate: matchRange) else { continue }

            let imageRange = match.range(withName: "image")
            let isImage = imageRange.location != NSNotFound
            guard (action == .image) == isImage else { continue }

            let destinationRange = match.range(withName: "destination")
            guard destinationRange.location != NSNotFound else { continue }

            return MarkdownFormatEdit(
                range: selection,
                replacement: text.substring(with: selection),
                cursorAfter: destinationRange,
                changesText: false
            )
        }

        return nil
    }

    private func selectionIntersects(_ selection: NSRange, candidate: NSRange) -> Bool {
        guard candidate.location != NSNotFound, candidate.length > 0 else { return false }

        if selection.length == 0 {
            return selection.location >= candidate.location && selection.location <= NSMaxRange(candidate)
        }

        return NSIntersectionRange(selection, candidate).length > 0
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

    private func semanticCodeFenceEdit(
        for action: FormattingAction,
        open: String?,
        close: String?,
        text: NSString,
        selection: NSRange,
        semanticDocument: EditorSemanticDocument?
    ) -> MarkdownFormatEdit? {
        guard let semanticDocument,
              semanticDocument.textLength > 0,
              let fencedRegion = semanticCodeFenceRegion(
                in: text,
                selection: selection,
                semanticDocument: semanticDocument
              ) else {
            return nil
        }

        let desiredMode: SemanticFenceMode?
        switch action {
        case .codeBlock:
            desiredMode = .plain
        case .mermaid:
            desiredMode = .mermaid
        case .paragraph:
            desiredMode = nil
        default:
            return nil
        }

        let openLineBreakLength = max(fencedRegion.open.range.length - fencedRegion.open.contentRange.length, 0)
        let closeLineBreakLength = max(fencedRegion.close.range.length - fencedRegion.close.contentRange.length, 0)
        let innerContentRange = NSRange(
            location: NSMaxRange(fencedRegion.open.range),
            length: max(fencedRegion.close.range.location - NSMaxRange(fencedRegion.open.range), 0)
        )
        let innerContent = text.substring(with: innerContentRange)
        let replacement: String
        let newInnerContentStart: Int

        if let desiredMode {
            let openingLine = openingFenceLine(for: desiredMode) + repeatedLineBreak(length: openLineBreakLength)
            let closingLine = closingFenceLine() + repeatedLineBreak(length: closeLineBreakLength)
            replacement = openingLine + innerContent + closingLine
            newInnerContentStart = fencedRegion.open.range.location + (openingLine as NSString).length

            if fencedRegion.mode == desiredMode {
                return MarkdownFormatEdit(
                    range: fencedRegion.enclosingRange,
                    replacement: innerContent,
                    cursorAfter: semanticCodeFenceCursorAfter(
                        selection: selection,
                        oldInnerContentStart: NSMaxRange(fencedRegion.open.range),
                        oldInnerContentLength: innerContentRange.length,
                        newInnerContentStart: fencedRegion.open.range.location,
                        newInnerContentLength: innerContentRange.length
                    )
                )
            }
        } else {
            replacement = innerContent
            newInnerContentStart = fencedRegion.open.range.location
        }

        return MarkdownFormatEdit(
            range: fencedRegion.enclosingRange,
            replacement: replacement,
            cursorAfter: semanticCodeFenceCursorAfter(
                selection: selection,
                oldInnerContentStart: NSMaxRange(fencedRegion.open.range),
                oldInnerContentLength: innerContentRange.length,
                newInnerContentStart: newInnerContentStart,
                newInnerContentLength: innerContentRange.length
            )
        )
    }

    private func lineAwareBlockEdit(
        open: String,
        close: String,
        text: NSString,
        selection: NSRange
    ) -> MarkdownFormatEdit? {
        guard selection.length > 0 else { return nil }

        let affectedRange = text.lineRange(for: selection)
        guard affectedRange.length > 0 else { return nil }

        let selectedLines = text.substring(with: affectedRange)
        let replacement = "\(open)\(selectedLines)\(close)"
        let openLength = (open as NSString).length

        return MarkdownFormatEdit(
            range: affectedRange,
            replacement: replacement,
            cursorAfter: NSRange(location: affectedRange.location + openLength, length: (selectedLines as NSString).length)
        )
    }

    private func structuredFenceInsertEdit(
        for action: FormattingAction,
        open: String,
        close: String,
        text: NSString,
        selection: NSRange
    ) -> MarkdownFormatEdit? {
        guard selection.length == 0 else { return nil }
        guard action == .codeBlock || action == .mermaid else { return nil }

        let affectedRange = text.lineRange(for: selection)
        guard affectedRange.length > 0 else { return nil }

        let contentRange = NSRange(
            location: affectedRange.location,
            length: max(affectedRange.length - trailingLineBreakLength(in: text, lineRange: affectedRange), 0)
        )
        let lineContent = text.substring(with: contentRange)
        let lineIsBlank = lineContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let insertionLocation: Int
        let replacement: String
        let openLength = (open as NSString).length
        let cursorLocation: Int

        if lineIsBlank {
            insertionLocation = selection.location
            replacement = "\(open)\(close)"
            cursorLocation = insertionLocation + openLength
        } else {
            insertionLocation = NSMaxRange(affectedRange)
            let needsLeadingNewline = insertionLocation > 0
                && (insertionLocation > text.length || text.character(at: insertionLocation - 1) != 10)
                && (insertionLocation > text.length || text.character(at: insertionLocation - 1) != 13)
            replacement = (needsLeadingNewline ? "\n" : "") + open + close
            cursorLocation = insertionLocation + (needsLeadingNewline ? 1 : 0) + openLength
        }

        return MarkdownFormatEdit(
            range: NSRange(location: insertionLocation, length: 0),
            replacement: replacement,
            cursorAfter: NSRange(location: cursorLocation, length: 0)
        )
    }

    private func structuredInsertEdit(
        for action: FormattingAction,
        raw: String,
        text: NSString,
        selection: NSRange
    ) -> MarkdownFormatEdit? {
        guard action == .table, selection.length == 0 else { return nil }

        let lineRange = text.lineRange(for: selection)
        let contentRange = NSRange(
            location: lineRange.location,
            length: max(lineRange.length - trailingLineBreakLength(in: text, lineRange: lineRange), 0)
        )
        let lineContent = text.substring(with: contentRange)
        let lineIsBlank = lineContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let insertionRange: NSRange
        let previousLineIsNonBlank: Bool
        let nextLineIsNonBlank: Bool

        if lineIsBlank {
            insertionRange = lineRange
            if lineRange.location > 0 {
                let previousLine = text.lineRange(for: NSRange(location: max(lineRange.location - 1, 0), length: 0))
                let previousContentRange = NSRange(
                    location: previousLine.location,
                    length: max(previousLine.length - trailingLineBreakLength(in: text, lineRange: previousLine), 0)
                )
                previousLineIsNonBlank = !text.substring(with: previousContentRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            } else {
                previousLineIsNonBlank = false
            }

            let nextLineLocation = NSMaxRange(lineRange)
            if nextLineLocation < text.length {
                let nextLine = text.lineRange(for: NSRange(location: nextLineLocation, length: 0))
                let nextContentRange = NSRange(
                    location: nextLine.location,
                    length: max(nextLine.length - trailingLineBreakLength(in: text, lineRange: nextLine), 0)
                )
                nextLineIsNonBlank = !text.substring(with: nextContentRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            } else {
                nextLineIsNonBlank = false
            }
        } else {
            insertionRange = NSRange(location: NSMaxRange(lineRange), length: 0)
            previousLineIsNonBlank = true

            let nextLineLocation = NSMaxRange(lineRange)
            if nextLineLocation < text.length {
                let nextLine = text.lineRange(for: NSRange(location: nextLineLocation, length: 0))
                let nextContentRange = NSRange(
                    location: nextLine.location,
                    length: max(nextLine.length - trailingLineBreakLength(in: text, lineRange: nextLine), 0)
                )
                nextLineIsNonBlank = !text.substring(with: nextContentRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            } else {
                nextLineIsNonBlank = false
            }
        }

        let leadingSeparator = previousLineIsNonBlank ? "\n" : ""
        let trailingSeparator = nextLineIsNonBlank ? "\n" : ""
        let replacement = leadingSeparator + raw + trailingSeparator
        let replacementNSString = replacement as NSString
        let firstColumnRange = replacementNSString.range(of: "Column 1")
        let cursorLocation: Int
        if firstColumnRange.location != NSNotFound {
            cursorLocation = insertionRange.location + firstColumnRange.location
        } else {
            cursorLocation = insertionRange.location + replacementNSString.length
        }

        return MarkdownFormatEdit(
            range: insertionRange,
            replacement: replacement,
            cursorAfter: NSRange(location: cursorLocation, length: 0)
        )
    }

    private func templateCursorRange(
        for action: FormattingAction,
        selectedRange: NSRange,
        selectedText: String,
        before: String,
        after: String
    ) -> NSRange {
        let beforeLength = (before as NSString).length
        let selectedLength = (selectedText as NSString).length

        if selectedText.isEmpty {
            return NSRange(location: selectedRange.location + beforeLength, length: 0)
        }

        switch action {
        case .link:
            return NSRange(location: selectedRange.location + beforeLength + selectedLength + 2, length: 3)
        case .image:
            return NSRange(location: selectedRange.location + beforeLength + selectedLength + 2, length: 4)
        case .footnote:
            return NSRange(
                location: selectedRange.location + beforeLength + selectedLength + (after as NSString).length,
                length: 0
            )
        default:
            return NSRange(
                location: selectedRange.location + beforeLength + selectedLength + (after as NSString).length,
                length: 0
            )
        }
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

    private func semanticLinePrefix(
        for action: FormattingAction,
        targetPrefix: String?,
        text: NSString,
        selection: NSRange,
        semanticDocument: EditorSemanticDocument?
    ) -> MarkdownFormatEdit? {
        guard let semanticDocument,
              semanticDocument.textLength > 0 else {
            return nil
        }

        if isMultilineSelection(selection, in: text) {
            return semanticMultilineLinePrefix(
                for: action,
                targetPrefix: targetPrefix,
                text: text,
                selection: selection,
                semanticDocument: semanticDocument
            )
        }

        let lineRange = text.lineRange(for: selection)
        let anchorLocation = min(selection.location, max(text.length - 1, 0))
        let anchorLineRange = text.lineRange(for: NSRange(location: anchorLocation, length: 0))
        guard NSEqualRanges(lineRange, anchorLineRange),
              let block = semanticDocument.block(containing: lineRange.location),
              block.range.location == lineRange.location,
              supportsSemanticLineTransition(block.kind) else {
            return nil
        }

        if targetPrefix == nil, block.syntaxRange == nil {
            return nil
        }

        let trailingNewlineLength = trailingLineBreakLength(in: text, lineRange: lineRange)
        let contentRange = NSRange(
            location: lineRange.location,
            length: max(lineRange.length - trailingNewlineLength, 0)
        )
        let lineContent = text.substring(with: contentRange)
        let leadingWhitespaceLength = leadingWhitespaceLength(in: lineContent)
        let leadingWhitespace = (lineContent as NSString).substring(to: leadingWhitespaceLength)

        let existingContentStart = existingContentStart(
            for: block,
            lineRange: lineRange,
            contentRange: contentRange,
            leadingWhitespaceLength: leadingWhitespaceLength
        )
        let bodyRange = NSRange(
            location: existingContentStart,
            length: max(NSMaxRange(contentRange) - existingContentStart, 0)
        )
        let body = text.substring(with: bodyRange)

        let effectivePrefix: String
        if matchesSemanticBlock(action: action, blockKind: block.kind) {
            effectivePrefix = ""
        } else {
            effectivePrefix = targetPrefix ?? ""
        }

        let replacementContent = leadingWhitespace + effectivePrefix + body
        let newlineSuffix = trailingNewlineLength > 0
            ? text.substring(with: NSRange(location: NSMaxRange(contentRange), length: trailingNewlineLength))
            : ""
        let replacement = replacementContent + newlineSuffix

        let previousContentStart = existingContentStart
        let bodyOffset = max(selection.location - previousContentStart, 0)
        let newContentStart = lineRange.location + leadingWhitespaceLength + (effectivePrefix as NSString).length
        let clampedBodyOffset = min(bodyOffset, (body as NSString).length)
        let cursorLocation = newContentStart + clampedBodyOffset

        return MarkdownFormatEdit(
            range: lineRange,
            replacement: replacement,
            cursorAfter: NSRange(location: cursorLocation, length: 0)
        )
    }

    private func semanticMultilineLinePrefix(
        for action: FormattingAction,
        targetPrefix: String?,
        text: NSString,
        selection: NSRange,
        semanticDocument: EditorSemanticDocument
    ) -> MarkdownFormatEdit? {
        let affectedRange = text.lineRange(for: selection)
        guard affectedRange.length > 0 else { return nil }

        var cursor = affectedRange.location
        var replacement = ""
        var mappings: [SemanticLineMapping] = []

        while cursor < NSMaxRange(affectedRange) {
            let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = NSRange(
                location: lineRange.location,
                length: max(lineRange.length - trailingLineBreakLength(in: text, lineRange: lineRange), 0)
            )
            let lineContent = text.substring(with: contentRange)
            let leadingWhitespaceLength = leadingWhitespaceLength(in: lineContent)
            let leadingWhitespace = (lineContent as NSString).substring(to: leadingWhitespaceLength)
            let newlineSuffix = text.substring(with: NSRange(
                location: NSMaxRange(contentRange),
                length: lineRange.length - contentRange.length
            ))
            let block = semanticDocument.block(containing: lineRange.location)

            let originalLine = text.substring(with: lineRange)
            let lineReplacement: String
            let oldBodyStart: Int
            let oldBodyEnd = NSMaxRange(contentRange)
            let newBodyStart: Int
            let newBodyEnd: Int
            let newLineStart = affectedRange.location + (replacement as NSString).length

            if let block,
               block.range.location == lineRange.location,
               supportsSemanticLineTransition(block.kind),
               !(block.kind == .blank && action != .paragraph) {
                let existingContentStart = existingContentStart(
                    for: block,
                    lineRange: lineRange,
                    contentRange: contentRange,
                    leadingWhitespaceLength: leadingWhitespaceLength
                )
                let bodyRange = NSRange(
                    location: existingContentStart,
                    length: max(NSMaxRange(contentRange) - existingContentStart, 0)
                )
                let body = text.substring(with: bodyRange)
                let effectivePrefix: String
                if matchesSemanticBlock(action: action, blockKind: block.kind) {
                    effectivePrefix = ""
                } else {
                    effectivePrefix = targetPrefix ?? ""
                }
                lineReplacement = leadingWhitespace + effectivePrefix + body + newlineSuffix
                oldBodyStart = existingContentStart
                newBodyStart = newLineStart + leadingWhitespaceLength + (effectivePrefix as NSString).length
                newBodyEnd = newBodyStart + (body as NSString).length
            } else {
                lineReplacement = originalLine
                oldBodyStart = lineRange.location + leadingWhitespaceLength
                newBodyStart = newLineStart + leadingWhitespaceLength
                newBodyEnd = newBodyStart + max(contentRange.length - leadingWhitespaceLength, 0)
            }

            replacement += lineReplacement
            mappings.append(SemanticLineMapping(
                oldLineRange: lineRange,
                oldBodyStart: oldBodyStart,
                oldBodyEnd: oldBodyEnd,
                newLineRange: NSRange(location: newLineStart, length: (lineReplacement as NSString).length),
                newBodyStart: newBodyStart,
                newBodyEnd: newBodyEnd
            ))

            cursor = NSMaxRange(lineRange)
        }

        let original = text.substring(with: affectedRange)
        guard replacement != original else { return nil }

        let selectionStart = mapMultilineSelectionPosition(
            selection.location,
            mappings: mappings,
            affectedRange: affectedRange
        )
        let selectionEnd = mapMultilineSelectionPosition(
            selection.location + selection.length,
            mappings: mappings,
            affectedRange: affectedRange
        )

        return MarkdownFormatEdit(
            range: affectedRange,
            replacement: replacement,
            cursorAfter: NSRange(
                location: selectionStart,
                length: max(selectionEnd - selectionStart, 0)
            )
        )
    }

    private func supportsSemanticLineTransition(_ kind: EditorBlockKind) -> Bool {
        switch kind {
        case .blank, .paragraph, .heading, .listItem, .blockquote:
            return true
        case .codeFence, .tableRow:
            return false
        }
    }

    private func matchesSemanticBlock(action: FormattingAction, blockKind: EditorBlockKind) -> Bool {
        switch (action, blockKind) {
        case (.heading, .heading(level: 1)), (.heading1, .heading(level: 1)):
            return true
        case (.heading2, .heading(level: 2)):
            return true
        case (.heading3, .heading(level: 3)):
            return true
        case (.heading4, .heading(level: 4)):
            return true
        case (.heading5, .heading(level: 5)):
            return true
        case (.heading6, .heading(level: 6)):
            return true
        case (.bulletList, .listItem(kind: .bullet)):
            return true
        case (.numberedList, .listItem(kind: .numbered)):
            return true
        case (.checkbox, .listItem(kind: .checkbox)):
            return true
        case (.blockquote, .blockquote):
            return true
        default:
            return false
        }
    }

    private func existingContentStart(
        for block: EditorBlockNode,
        lineRange: NSRange,
        contentRange: NSRange,
        leadingWhitespaceLength: Int
    ) -> Int {
        if let syntaxRange = block.syntaxRange,
           syntaxRange.location >= lineRange.location,
           NSMaxRange(syntaxRange) <= NSMaxRange(contentRange) {
            return NSMaxRange(syntaxRange)
        }
        return lineRange.location + leadingWhitespaceLength
    }

    private func leadingWhitespaceLength(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.utf16.count
    }

    private func trailingLineBreakLength(in text: NSString, lineRange: NSRange) -> Int {
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

    private func isMultilineSelection(_ selection: NSRange, in text: NSString) -> Bool {
        guard selection.length > 0, text.length > 0 else { return false }
        let endLocation = min(selection.location + selection.length - 1, max(text.length - 1, 0))
        let startLine = text.lineRange(for: NSRange(location: min(selection.location, max(text.length - 1, 0)), length: 0))
        let endLine = text.lineRange(for: NSRange(location: endLocation, length: 0))
        return !NSEqualRanges(startLine, endLine)
    }

    private func mapMultilineSelectionPosition(
        _ position: Int,
        mappings: [SemanticLineMapping],
        affectedRange: NSRange
    ) -> Int {
        guard let mapping = mappings.first(where: {
            position >= $0.oldLineRange.location && position <= NSMaxRange($0.oldLineRange)
        }) ?? mappings.last else {
            return position
        }

        if position <= mapping.oldBodyStart {
            return mapping.newBodyStart
        }

        if position <= mapping.oldBodyEnd {
            let offset = min(position - mapping.oldBodyStart, mapping.newBodyEnd - mapping.newBodyStart)
            return mapping.newBodyStart + offset
        }

        let trailingOffset = min(
            position - mapping.oldBodyEnd,
            NSMaxRange(mapping.newLineRange) - mapping.newBodyEnd
        )
        return mapping.newBodyEnd + trailingOffset
    }

    private func semanticCodeFenceRegion(
        in text: NSString,
        selection: NSRange,
        semanticDocument: EditorSemanticDocument
    ) -> SemanticCodeFenceRegion? {
        let location = min(selection.location, max(text.length - 1, 0))
        guard let block = semanticDocument.block(containing: location),
              case .codeFence = block.kind,
              let blockIndex = semanticDocument.blocks.firstIndex(where: { $0.id == block.id }) else {
            return nil
        }

        let fenceMarkerIndices = semanticDocument.blocks.indices.filter { index in
            let candidate = semanticDocument.blocks[index]
            if case .codeFence = candidate.kind {
                return candidate.syntaxRange != nil
            }
            return false
        }

        guard let pairStart = stride(from: 0, to: fenceMarkerIndices.count, by: 2).first(where: { pairStart in
            let openIndex = fenceMarkerIndices[pairStart]
            guard pairStart + 1 < fenceMarkerIndices.count else { return false }
            let closeIndex = fenceMarkerIndices[pairStart + 1]
            return openIndex <= blockIndex && blockIndex <= closeIndex
        }) else {
            return nil
        }

        let openIndex = fenceMarkerIndices[pairStart]
        let closeIndex = fenceMarkerIndices[pairStart + 1]
        let openBlock = semanticDocument.blocks[openIndex]
        let closeBlock = semanticDocument.blocks[closeIndex]
        let openingContent = text.substring(with: openBlock.contentRange)

        return SemanticCodeFenceRegion(
            open: openBlock,
            close: closeBlock,
            enclosingRange: NSRange(
                location: openBlock.range.location,
                length: NSMaxRange(closeBlock.range) - openBlock.range.location
            ),
            mode: semanticFenceMode(for: openingContent)
        )
    }

    private func semanticFenceMode(for openingContent: String) -> SemanticFenceMode {
        let trimmed = openingContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("```mermaid") {
            return .mermaid
        }
        return .plain
    }

    private func openingFenceLine(for mode: SemanticFenceMode) -> String {
        switch mode {
        case .plain:
            return "```"
        case .mermaid:
            return "```mermaid"
        }
    }

    private func closingFenceLine() -> String {
        "```"
    }

    private func repeatedLineBreak(length: Int) -> String {
        guard length > 0 else { return "" }
        return String(repeating: "\n", count: length)
    }

    private func semanticCodeFenceCursorAfter(
        selection: NSRange,
        oldInnerContentStart: Int,
        oldInnerContentLength: Int,
        newInnerContentStart: Int,
        newInnerContentLength: Int
    ) -> NSRange {
        let oldInnerContentEnd = oldInnerContentStart + oldInnerContentLength
        let newInnerContentEnd = newInnerContentStart + newInnerContentLength

        if selection.location <= oldInnerContentStart {
            return NSRange(location: newInnerContentStart, length: 0)
        }

        if selection.location >= oldInnerContentEnd {
            return NSRange(location: newInnerContentEnd, length: 0)
        }

        let bodyOffset = min(selection.location - oldInnerContentStart, newInnerContentLength)
        return NSRange(location: newInnerContentStart + bodyOffset, length: 0)
    }

    private enum SemanticFenceMode {
        case plain
        case mermaid
    }

    private struct SemanticCodeFenceRegion {
        let open: EditorBlockNode
        let close: EditorBlockNode
        let enclosingRange: NSRange
        let mode: SemanticFenceMode
    }

    private struct SemanticLineMapping {
        let oldLineRange: NSRange
        let oldBodyStart: Int
        let oldBodyEnd: Int
        let newLineRange: NSRange
        let newBodyStart: Int
        let newBodyEnd: Int
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
        selectedRange: NSRange,
        semanticDocument: EditorSemanticDocument? = nil
    ) -> (text: String, newSelection: NSRange) {
        let nsText = text as NSString
        if let edit = surgicalEdit(
            action,
            in: text,
            selectedRange: selectedRange,
            semanticDocument: semanticDocument
        ) {
            let newText = nsText.replacingCharacters(in: edit.range, with: edit.replacement)
            return (newText, edit.cursorAfter)
        }
        return (text, selectedRange)
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
