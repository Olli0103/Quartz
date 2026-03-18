#if canImport(UIKit)
import UIKit
import SwiftUI
import os

/// Plain-text Markdown editor for iOS with live syntax highlighting.
/// Keeps all markdown syntax visible (like Obsidian / iA Writer) so the
/// round-trip is lossless.
public class MarkdownUITextView: UITextView {
    private let highlighter = MarkdownSyntaxHighlighter()
    private var isUpdating = false

    public var onTextChange: (@Sendable (String) -> Void)?
    public var onSelectionChange: (@Sendable (NSRange) -> Void)?

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        autocorrectionType = .default
        autocapitalizationType = .sentences
        allowsEditingTextAttributes = false
        delegate = self
    }

    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let selectedRange = self.selectedRange
        text = markdown
        highlighter.applyHighlighting(to: textStorage, baseFont: font ?? .preferredFont(forTextStyle: .body))
        if selectedRange.location + selectedRange.length <= (text ?? "").count {
            self.selectedRange = selectedRange
        }
    }

    public var rawMarkdown: String {
        text ?? ""
    }
}

extension MarkdownUITextView: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        guard !isUpdating else { return }
        isUpdating = true
        let sel = selectedRange
        highlighter.applyHighlighting(to: textStorage, baseFont: font ?? .preferredFont(forTextStyle: .body))
        selectedRange = sel
        isUpdating = false
        onTextChange?(textView.text ?? "")
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isUpdating else { return }
        onSelectionChange?(textView.selectedRange)
    }
}

// MARK: - SwiftUI Wrapper

public struct MarkdownTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    var editorFontScale: CGFloat

    public init(text: Binding<String>, cursorPosition: Binding<NSRange>, editorFontScale: CGFloat = 1.0) {
        self._text = text
        self._cursorPosition = cursorPosition
        self.editorFontScale = editorFontScale
    }

    public func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView()
        view.onTextChange = { [_text] newText in
            _text.wrappedValue = newText
        }
        view.onSelectionChange = { [_cursorPosition] range in
            _cursorPosition.wrappedValue = range
        }
        return view
    }

    public func updateUIView(_ uiView: MarkdownUITextView, context: Context) {
        let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let newFont = UIFont.systemFont(ofSize: baseSize * editorFontScale)
        if uiView.font != newFont {
            uiView.font = newFont
        }
        if uiView.rawMarkdown != text && !uiView.isFirstResponder {
            uiView.setMarkdown(text)
        }
    }
}

#elseif canImport(AppKit)
import AppKit
import SwiftUI
import os

/// Plain-text Markdown editor for macOS with live syntax highlighting.
/// Keeps all markdown syntax visible so the round-trip is lossless.
public class MarkdownNSTextView: NSTextView {
    private let highlighter = MarkdownSyntaxHighlighter()
    private var isUpdating = false

    public var onTextChange: (@Sendable (String) -> Void)?
    public var onSelectionChange: (@Sendable (NSRange) -> Void)?

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textContainerInset = NSSize(width: 16, height: 16)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isRichText = false
        usesFontPanel = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        delegate = self
    }

    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let ranges = selectedRanges
        string = markdown
        highlighter.applyHighlighting(to: textStorage!, baseFont: font ?? .systemFont(ofSize: NSFont.systemFontSize))
        let maxLen = string.count
        let clamped = ranges.compactMap { rv -> NSValue? in
            let r = rv.rangeValue
            let loc = min(r.location, maxLen)
            let len = min(r.length, maxLen - loc)
            return NSValue(range: NSRange(location: loc, length: len))
        }
        selectedRanges = clamped.isEmpty ? [NSValue(range: NSRange(location: maxLen, length: 0))] : clamped
    }

    public var rawMarkdown: String { string }

    public override func didChangeText() {
        super.didChangeText()
        guard !isUpdating else { return }
        isUpdating = true
        let sel = selectedRanges
        highlighter.applyHighlighting(to: textStorage!, baseFont: font ?? .systemFont(ofSize: NSFont.systemFontSize))
        selectedRanges = sel
        isUpdating = false
        onTextChange?(string)
    }

    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !isUpdating, !stillSelectingFlag, let first = ranges.first {
            onSelectionChange?(first.rangeValue)
        }
    }
}

extension MarkdownNSTextView: NSTextViewDelegate {}

// MARK: - SwiftUI Wrapper

public struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    var editorFontScale: CGFloat

    public init(text: Binding<String>, cursorPosition: Binding<NSRange>, editorFontScale: CGFloat = 1.0) {
        self._text = text
        self._cursorPosition = cursorPosition
        self.editorFontScale = editorFontScale
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = MarkdownNSTextView(frame: scrollView.contentView.bounds)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.onTextChange = { [_text] newText in
            _text.wrappedValue = newText
        }
        textView.onSelectionChange = { [_cursorPosition] range in
            _cursorPosition.wrappedValue = range
        }

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        let baseSize = NSFont.systemFontSize
        let newFont = NSFont.systemFont(ofSize: baseSize * editorFontScale)
        if textView.font != newFont {
            textView.font = newFont
        }
        if textView.rawMarkdown != text && textView.window?.firstResponder !== textView {
            textView.setMarkdown(text)
        }
    }
}
#endif

// MARK: - Syntax Highlighter

/// Applies visual styling to raw markdown text while preserving all syntax characters.
/// Handles headings, bold, italic, code, lists, blockquotes, and links.
struct MarkdownSyntaxHighlighter: Sendable {
    #if canImport(UIKit)
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
    #elseif canImport(AppKit)
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
    #endif

    func applyHighlighting(to storage: NSTextStorage, baseFont: PlatformFont) {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()
        // Reset to base style
        storage.addAttribute(.font, value: baseFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: PlatformColor.labelColor, range: fullRange)

        let nsText = text as NSString

        // Process line by line for line-level syntax
        nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = nsText.substring(with: lineRange)
            self.highlightLine(line, range: lineRange, in: storage, baseFont: baseFont)
        }

        // Inline patterns across the whole text
        applyInlinePatterns(to: storage, text: nsText, fullRange: fullRange, baseFont: baseFont)

        storage.endEditing()
    }

    private func highlightLine(_ line: String, range: NSRange, in storage: NSTextStorage, baseFont: PlatformFont) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

        // Headings: # through ######
        if let match = trimmed.prefixMatch(of: /^(#{1,6})\s/) {
            let level = match.1.count
            let scale: CGFloat = switch level {
            case 1: 1.8
            case 2: 1.5
            case 3: 1.3
            case 4: 1.15
            default: 1.05
            }
            let headingFont = PlatformFont.systemFont(ofSize: baseFont.pointSize * scale, weight: .bold)
            storage.addAttribute(.font, value: headingFont, range: range)

            // Style the # prefix more subtly
            let prefixLen = line.distance(from: line.startIndex, to: line.firstIndex(of: "#")!) + match.0.count
            let prefixRange = NSRange(location: range.location, length: prefixLen)
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: prefixRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: prefixRange)
            #endif
            return
        }

        // Blockquote: > text
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            #endif
            let italicFont = PlatformFont.systemFont(ofSize: baseFont.pointSize).withTraits(.italic)
            storage.addAttribute(.font, value: italicFont, range: range)
            return
        }

        // Horizontal rule: ---, ***, ___
        let hrTrimmed = trimmed.trimmingCharacters(in: .whitespaces)
        if hrTrimmed.count >= 3, hrTrimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }),
           Set(hrTrimmed).count == 1 {
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: range)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            #endif
            return
        }

        // List bullets and checkboxes: dim the prefix
        let listPrefixPatterns: [String] = ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ "]
        for prefix in listPrefixPatterns {
            if String(trimmed).hasPrefix(prefix) {
                let offset = line.count - trimmed.count
                let prefixRange = NSRange(location: range.location + offset, length: prefix.count)
                #if canImport(UIKit)
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: prefixRange)
                #elseif canImport(AppKit)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
                #endif
                break
            }
        }

        // Numbered list: 1. , 2. , etc.
        if let numMatch = String(trimmed).prefixMatch(of: /^\d+\.\s/) {
            let offset = line.count - trimmed.count
            let prefixRange = NSRange(location: range.location + offset, length: numMatch.0.count)
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: prefixRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
            #endif
        }
    }

    private func applyInlinePatterns(to storage: NSTextStorage, text: NSString, fullRange: NSRange, baseFont: PlatformFont) {
        // Bold: **text** or __text__
        applyRegex(#"\*\*(.+?)\*\*"#, to: storage, text: text, range: fullRange) { matchRange in
            let boldFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: matchRange)
        }
        applyRegex(#"__(.+?)__"#, to: storage, text: text, range: fullRange) { matchRange in
            let boldFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: matchRange)
        }

        // Italic: *text* or _text_ (but not ** or __)
        applyRegex(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, to: storage, text: text, range: fullRange) { matchRange in
            let italicFont = baseFont.withTraits(.italic)
            storage.addAttribute(.font, value: italicFont, range: matchRange)
        }

        // Inline code: `text`
        applyRegex(#"`([^`]+)`"#, to: storage, text: text, range: fullRange) { matchRange in
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: matchRange)
            #if canImport(UIKit)
            storage.addAttribute(.backgroundColor, value: UIColor.systemFill, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: matchRange)
            #endif
        }

        // Code blocks: ```...```
        applyRegex(#"```[\s\S]*?```"#, to: storage, text: text, range: fullRange) { matchRange in
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: matchRange)
            #if canImport(UIKit)
            storage.addAttribute(.backgroundColor, value: UIColor.systemFill, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: matchRange)
            #endif
        }

        // Links: [text](url)
        applyRegex(#"\[([^\]]+)\]\(([^)]+)\)"#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.link, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: matchRange)
            #endif
        }
    }

    private func applyRegex(_ pattern: String, to storage: NSTextStorage, text: NSString, range: NSRange, handler: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        regex.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            handler(matchRange)
        }
    }
}

// MARK: - Font Traits Helper

#if canImport(UIKit)
private extension UIFont {
    enum Trait { case italic }
    func withTraits(_ trait: Trait) -> UIFont {
        switch trait {
        case .italic:
            if let descriptor = fontDescriptor.withSymbolicTraits(.traitItalic) {
                return UIFont(descriptor: descriptor, size: pointSize)
            }
            return self
        }
    }
}
#elseif canImport(AppKit)
private extension NSFont {
    enum Trait { case italic }
    func withTraits(_ trait: Trait) -> NSFont {
        switch trait {
        case .italic:
            let manager = NSFontManager.shared
            return manager.convert(self, toHaveTrait: .italicFontMask)
        }
    }
}

#endif
