#if canImport(UIKit)
import UIKit
import SwiftUI

public class MarkdownUITextView: UITextView {
    private let highlighter = MarkdownSyntaxHighlighter()
    var isUpdating = false
    private var highlightWorkItem: DispatchWorkItem?
    public var noteURL: URL?
    private var _rawMarkdown: String = ""

    public var onTextChange: ((String) -> Void)?
    public var onSelectionChange: ((NSRange) -> Void)?

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
        textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        autocorrectionType = .default
        autocapitalizationType = .sentences
        allowsEditingTextAttributes = false
        backgroundColor = .clear
        delegate = self
    }

    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        _rawMarkdown = markdown
        let sel = selectedRange
        text = markdown
        undoManager?.disableUndoRegistration()
        highlighter.applyHighlighting(
            to: textStorage,
            baseFont: font ?? .preferredFont(forTextStyle: .body),
            noteURL: noteURL
        )
        undoManager?.enableUndoRegistration()
        let maxLen = textStorage.length
        let loc = min(sel.location, maxLen)
        let len = min(sel.length, maxLen - loc)
        selectedRange = NSRange(location: loc, length: len)
    }

    public var rawMarkdown: String { _rawMarkdown }

    func reconstructRawMarkdown() -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return "" }
        textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let imgAttachment = value as? MarkdownImageAttachment {
                result += imgAttachment.originalMarkdown
            } else {
                result += self.textStorage.attributedSubstring(from: range).string
            }
        }
        return result
    }
}

extension MarkdownUITextView: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        guard !isUpdating else { return }
        _rawMarkdown = reconstructRawMarkdown()
        onTextChange?(_rawMarkdown)
        scheduleHighlight()
    }

    private func scheduleHighlight() {
        highlightWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isUpdating else { return }
            self.isUpdating = true
            let sel = self.selectedRange
            self.undoManager?.disableUndoRegistration()
            self.highlighter.applyHighlighting(
                to: self.textStorage,
                baseFont: self.font ?? .preferredFont(forTextStyle: .body),
                noteURL: self.noteURL
            )
            self.undoManager?.enableUndoRegistration()
            let maxLen = self.textStorage.length
            let loc = min(sel.location, maxLen)
            let len = min(sel.length, maxLen - loc)
            self.selectedRange = NSRange(location: loc, length: len)
            self.isUpdating = false
        }
        highlightWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isUpdating else { return }
        onSelectionChange?(textView.selectedRange)
    }
}

// MARK: - SwiftUI Wrapper (iOS)

public struct MarkdownTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    var editorFontScale: CGFloat
    var noteURL: URL?

    public init(text: Binding<String>, cursorPosition: Binding<NSRange>, editorFontScale: CGFloat = 1.0, noteURL: URL? = nil) {
        self._text = text
        self._cursorPosition = cursorPosition
        self.editorFontScale = editorFontScale
        self.noteURL = noteURL
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView()
        context.coordinator.textView = view
        return view
    }

    public func updateUIView(_ uiView: MarkdownUITextView, context: Context) {
        uiView.noteURL = noteURL

        uiView.onTextChange = { [weak uiView] newText in
            guard uiView?.isUpdating != true else { return }
            self.text = newText
        }
        uiView.onSelectionChange = { newRange in
            self.cursorPosition = newRange
        }

        let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let newFont = UIFont.systemFont(ofSize: baseSize * editorFontScale)
        if uiView.font != newFont { uiView.font = newFont }

        if uiView.rawMarkdown != text {
            uiView.setMarkdown(text)
        }
    }

    public final class Coordinator {
        weak var textView: MarkdownUITextView?
    }
}

#elseif canImport(AppKit)
import AppKit
import SwiftUI

public class MarkdownNSTextView: NSTextView {
    private let highlighter = MarkdownSyntaxHighlighter()
    var isUpdating = false
    private var needsHighlight = false
    public var noteURL: URL?
    private var _rawMarkdown: String = ""

    public var onTextChange: ((String) -> Void)?
    public var onSelectionChange: ((NSRange) -> Void)?

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
        textContainerInset = NSSize(width: 40, height: 28)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isRichText = true
        usesFontPanel = false
        usesRuler = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        drawsBackground = false
        delegate = self
    }

    /// Sets the text and applies full highlighting. Used for external updates (load, format bar).
    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        _rawMarkdown = markdown
        let prevRanges = selectedRanges
        string = markdown
        undoManager?.disableUndoRegistration()
        highlighter.applyHighlighting(
            to: textStorage!,
            baseFont: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            noteURL: noteURL
        )
        undoManager?.enableUndoRegistration()
        let maxLen = textStorage?.length ?? 0
        let clamped = prevRanges.compactMap { rv -> NSValue? in
            let r = rv.rangeValue
            let loc = min(r.location, maxLen)
            let len = min(r.length, maxLen - loc)
            return NSValue(range: NSRange(location: loc, length: len))
        }
        selectedRanges = clamped.isEmpty ? [NSValue(range: NSRange(location: maxLen, length: 0))] : clamped
    }

    /// Sets the cursor position without triggering text change callbacks.
    public func setCursorPosition(_ range: NSRange) {
        let maxLen = textStorage?.length ?? 0
        let loc = min(range.location, maxLen)
        let len = min(range.length, maxLen - loc)
        let clamped = NSRange(location: loc, length: len)
        guard selectedRange() != clamped else { return }
        isUpdating = true
        setSelectedRange(clamped)
        isUpdating = false
    }

    public var rawMarkdown: String { _rawMarkdown }

    func reconstructRawMarkdown() -> String {
        guard let storage = textStorage else { return _rawMarkdown }
        var result = ""
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return "" }
        storage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let imgAttachment = value as? MarkdownImageAttachment {
                result += imgAttachment.originalMarkdown
            } else {
                result += storage.attributedSubstring(from: range).string
            }
        }
        return result
    }

    public override func didChangeText() {
        super.didChangeText()
        guard !isUpdating else { return }
        _rawMarkdown = reconstructRawMarkdown()
        onTextChange?(_rawMarkdown)
        scheduleHighlight()
    }

    private var highlightWorkItem: DispatchWorkItem?

    private func scheduleHighlight() {
        highlightWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isUpdating else { return }
            self.isUpdating = true
            let sel = self.selectedRanges
            self.undoManager?.disableUndoRegistration()
            self.highlighter.applyHighlighting(
                to: self.textStorage!,
                baseFont: self.font ?? .systemFont(ofSize: NSFont.systemFontSize),
                noteURL: self.noteURL
            )
            self.undoManager?.enableUndoRegistration()
            let maxLen = self.textStorage?.length ?? 0
            let clamped = sel.compactMap { rv -> NSValue? in
                let r = rv.rangeValue
                let loc = min(r.location, maxLen)
                let len = min(r.length, maxLen - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
            self.selectedRanges = clamped.isEmpty
                ? [NSValue(range: NSRange(location: maxLen, length: 0))]
                : clamped
            self.isUpdating = false
        }
        highlightWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
        if !isUpdating, !flag, let first = ranges.first {
            onSelectionChange?(first.rangeValue)
        }
    }
}

extension MarkdownNSTextView: NSTextViewDelegate {}

// MARK: - SwiftUI Wrapper (macOS)

public struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    var editorFontScale: CGFloat
    var noteURL: URL?

    public init(text: Binding<String>, cursorPosition: Binding<NSRange>, editorFontScale: CGFloat = 1.0, noteURL: URL? = nil) {
        self._text = text
        self._cursorPosition = cursorPosition
        self.editorFontScale = editorFontScale
        self.noteURL = noteURL
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

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

        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }

        textView.noteURL = noteURL

        // CRITICAL: Always refresh closures so they write to the CURRENT bindings.
        textView.onTextChange = { [weak textView] newText in
            guard textView?.isUpdating != true else { return }
            self.text = newText
        }
        textView.onSelectionChange = { newRange in
            self.cursorPosition = newRange
        }

        let baseSize = NSFont.systemFontSize
        let scaledSize = baseSize * editorFontScale
        let newFont = NSFont.systemFont(ofSize: scaledSize)
        if textView.font?.pointSize != scaledSize {
            textView.font = newFont
        }

        if textView.rawMarkdown != text {
            textView.setMarkdown(text)
        }
    }

    public final class Coordinator {
        weak var textView: MarkdownNSTextView?
    }
}
#endif

// MARK: - Image Attachment

final class MarkdownImageAttachment: NSTextAttachment {
    /// The original markdown text (e.g. `![alt](path)`) this attachment replaced.
    /// Used to reconstruct the raw markdown when the user edits.
    var originalMarkdown: String = ""
}

// MARK: - Syntax Highlighter

struct MarkdownSyntaxHighlighter: Sendable {
    #if canImport(UIKit)
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
    typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
    typealias PlatformImage = NSImage
    #endif

    func applyHighlighting(to storage: NSTextStorage, baseFont: PlatformFont, noteURL: URL? = nil) {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 4

        storage.addAttribute(.font, value: baseFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: PlatformColor.labelColor, range: fullRange)
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)

        let nsText = text as NSString

        nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = nsText.substring(with: lineRange)
            self.highlightLine(line, range: lineRange, in: storage, baseFont: baseFont)
        }

        applyInlinePatterns(to: storage, text: nsText, fullRange: fullRange, baseFont: baseFont)

        // Image attachments replace text, so they must run last (in reverse order).
        if let noteURL {
            applyImageAttachments(to: storage, text: nsText, noteURL: noteURL)
        }

        storage.endEditing()
    }

    private func highlightLine(_ line: String, range: NSRange, in storage: NSTextStorage, baseFont: PlatformFont) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

        if let match = trimmed.prefixMatch(of: /^(#{1,6})\s/) {
            let level = match.1.count
            let scale: CGFloat = switch level {
            case 1: 1.7
            case 2: 1.45
            case 3: 1.25
            case 4: 1.12
            default: 1.05
            }
            let headingFont = PlatformFont.systemFont(ofSize: baseFont.pointSize * scale, weight: .bold)
            storage.addAttribute(.font, value: headingFont, range: range)

            let headingParagraph = NSMutableParagraphStyle()
            headingParagraph.lineSpacing = 4
            headingParagraph.paragraphSpacingBefore = level <= 2 ? 10 : 6
            headingParagraph.paragraphSpacing = level <= 2 ? 6 : 4
            storage.addAttribute(.paragraphStyle, value: headingParagraph, range: range)

            let prefixLen = line.distance(from: line.startIndex, to: line.firstIndex(of: "#")!) + match.0.count
            let prefixRange = NSRange(location: range.location, length: min(prefixLen, range.length))
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: prefixRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: prefixRange)
            #endif
            return
        }

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

        let listPrefixPatterns: [String] = ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ "]
        for prefix in listPrefixPatterns {
            if String(trimmed).hasPrefix(prefix) {
                let offset = line.count - trimmed.count
                let prefixRange = NSRange(location: range.location + offset, length: min(prefix.count, range.length - offset))
                #if canImport(UIKit)
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: prefixRange)
                #elseif canImport(AppKit)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
                #endif
                break
            }
        }

        if let numMatch = String(trimmed).prefixMatch(of: /^\d+\.\s/) {
            let offset = line.count - trimmed.count
            let prefixRange = NSRange(location: range.location + offset, length: min(numMatch.0.count, range.length - offset))
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: prefixRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
            #endif
        }

        let lineStr = String(trimmed)
        if lineStr.hasPrefix("|") && lineStr.hasSuffix("|") {
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: range)
            if lineStr.contains("---") && lineStr.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "|", with: "").allSatisfy({ $0 == "-" }) {
                #if canImport(UIKit)
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: range)
                #elseif canImport(AppKit)
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
                #endif
            } else {
                #if canImport(UIKit)
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
                #elseif canImport(AppKit)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                #endif
            }
        }

        if trimmed.hasPrefix("```mermaid") || trimmed.hasPrefix("``` Mermaid") {
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: range)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: range)
            #endif
        }
    }

    private func applyInlinePatterns(to storage: NSTextStorage, text: NSString, fullRange: NSRange, baseFont: PlatformFont) {
        applyRegex(#"\*\*(.+?)\*\*"#, to: storage, text: text, range: fullRange) { matchRange in
            let boldFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: matchRange)
        }
        applyRegex(#"__(.+?)__"#, to: storage, text: text, range: fullRange) { matchRange in
            let boldFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: matchRange)
        }

        applyRegex(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, to: storage, text: text, range: fullRange) { matchRange in
            let italicFont = baseFont.withTraits(.italic)
            storage.addAttribute(.font, value: italicFont, range: matchRange)
        }

        applyRegex(#"`([^`]+)`"#, to: storage, text: text, range: fullRange) { matchRange in
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: matchRange)
            #if canImport(UIKit)
            storage.addAttribute(.backgroundColor, value: UIColor.systemFill, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: matchRange)
            #endif
        }

        applyRegex(#"```[\s\S]*?```"#, to: storage, text: text, range: fullRange) { matchRange in
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: matchRange)
            #if canImport(UIKit)
            storage.addAttribute(.backgroundColor, value: UIColor.systemFill, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: matchRange)
            #endif
        }

        applyRegex(#"\[([^\]]+)\]\(([^)]+)\)"#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.link, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: matchRange)
            #endif
        }

        applyRegex(#"~~(.+?)~~"#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: matchRange)
            #endif
        }

        applyRegex(#"\$\$[\s\S]+?\$\$"#, to: storage, text: text, range: fullRange) { matchRange in
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: matchRange)
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: matchRange)
            storage.addAttribute(.backgroundColor, value: UIColor.systemPurple.withAlphaComponent(0.08), range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: matchRange)
            storage.addAttribute(.backgroundColor, value: NSColor.systemPurple.withAlphaComponent(0.08), range: matchRange)
            #endif
        }

        applyRegex(#"(?<!\$)\$(?!\$)([^$\n]+)\$(?!\$)"#, to: storage, text: text, range: fullRange) { matchRange in
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: matchRange)
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: matchRange)
            storage.addAttribute(.backgroundColor, value: UIColor.systemPurple.withAlphaComponent(0.08), range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: matchRange)
            storage.addAttribute(.backgroundColor, value: NSColor.systemPurple.withAlphaComponent(0.08), range: matchRange)
            #endif
        }

        applyRegex(#"\[\^[^\]]+\]"#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.systemTeal, range: matchRange)
            storage.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .medium), range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: matchRange)
            storage.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .medium), range: matchRange)
            #endif
        }

        applyRegex(#"\[\^[^\]]+\]:\s*.+"#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: matchRange)
            storage.addAttribute(.font, value: baseFont.withTraits(.italic), range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: matchRange)
            storage.addAttribute(.font, value: baseFont.withTraits(.italic), range: matchRange)
            #endif
        }
    }

    // MARK: - Inline Image Rendering

    /// Finds `![alt](path)` patterns and replaces them with inline image attachments.
    /// Matches are processed in reverse so earlier ranges stay valid after each replacement.
    private func applyImageAttachments(to storage: NSTextStorage, text: NSString, noteURL: URL) {
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = cachedRegex(imagePattern) else { return }

        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        let noteDir = noteURL.deletingLastPathComponent()

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }

            let fullMatchRange = match.range(at: 0)
            let pathRange = match.range(at: 2)

            guard let pathSwiftRange = Range(pathRange, in: text as String) else { continue }
            let imagePath = String((text as String)[pathSwiftRange])

            if imagePath.hasPrefix("http://") || imagePath.hasPrefix("https://") { continue }

            let decodedPath = imagePath.removingPercentEncoding ?? imagePath
            let imageURL = URL(fileURLWithPath: decodedPath, relativeTo: noteDir).standardizedFileURL

            guard let image = Self.cachedImage(at: imageURL) else { continue }

            let attachment = MarkdownImageAttachment()
            attachment.originalMarkdown = text.substring(with: fullMatchRange)

            #if canImport(UIKit)
            let maxWidth: CGFloat = 300
            #elseif canImport(AppKit)
            let maxWidth: CGFloat = 500
            #endif

            let imageSize = image.size
            if imageSize.width > maxWidth {
                let ratio = maxWidth / imageSize.width
                attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: imageSize.height * ratio)
            } else {
                attachment.bounds = CGRect(origin: .zero, size: imageSize)
            }

            attachment.image = image

            let attrString = NSAttributedString(attachment: attachment)
            storage.replaceCharacters(in: fullMatchRange, with: attrString)
        }
    }

    // MARK: - Image Cache

    private static nonisolated(unsafe) var imageCache: [String: PlatformImage] = [:]
    private static let imageCacheLock = NSLock()

    private static func cachedImage(at url: URL) -> PlatformImage? {
        let key = url.path(percentEncoded: false)

        imageCacheLock.lock()
        if let cached = imageCache[key] {
            imageCacheLock.unlock()
            return cached
        }
        imageCacheLock.unlock()

        guard FileManager.default.fileExists(atPath: key) else { return nil }

        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: key) else { return nil }
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        #endif

        imageCacheLock.lock()
        if imageCache.count > 100 { imageCache.removeAll() }
        imageCache[key] = image
        imageCacheLock.unlock()

        return image
    }

    // MARK: - Regex Helpers

    private static nonisolated(unsafe) var regexCache: [String: NSRegularExpression] = [:]
    private static let regexLock = NSLock()

    private func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        Self.regexLock.lock()
        defer { Self.regexLock.unlock() }
        if let cached = Self.regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        Self.regexCache[pattern] = regex
        return regex
    }

    private func applyRegex(_ pattern: String, to storage: NSTextStorage, text: NSString, range: NSRange, handler: (NSRange) -> Void) {
        guard let regex = cachedRegex(pattern) else { return }
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
            return NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
        }
    }
}
#endif
