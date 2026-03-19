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
        isEditable = true
        delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let viewPoint = gesture.location(in: self)
        guard let container = textContainer else { return }
        let containerPoint = CGPoint(
            x: viewPoint.x - textContainerInset.left,
            y: viewPoint.y - textContainerInset.top
        )
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        guard glyphRect.contains(containerPoint) else { return }
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return }
        guard let attachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? MarkdownCheckboxAttachment else { return }
        isUpdating = true
        defer { isUpdating = false }
        let toggled = attachment.originalMarkdown.contains("[ ]") ? "- [x] " : "- [ ] "
        let newAttachment = MarkdownCheckboxAttachment()
        newAttachment.originalMarkdown = toggled
        textStorage.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: NSAttributedString(attachment: newAttachment))
        _rawMarkdown = reconstructRawMarkdown()
        onTextChange?(_rawMarkdown)
    }

    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        _rawMarkdown = markdown
        let sel = selectedRange
        text = markdown
        // Tables stay as raw markdown on iOS (no attachments) for editable tables.
        #if canImport(UIKit)
        highlighter.applyHighlighting(
            to: textStorage,
            baseFont: font ?? .preferredFont(forTextStyle: .body),
            noteURL: noteURL,
            applyTables: false
        )
        #endif
        let maxLen = textStorage.length
        let loc = min(sel.location, maxLen)
        let len = min(sel.length, maxLen - loc)
        selectedRange = NSRange(location: loc, length: len)
    }

    public var rawMarkdown: String { _rawMarkdown }

    /// If the cursor is in a list line, returns the prefix to insert on Enter (indent + bullet/checkbox).
    private func listContinuationPrefix() -> String? {
        let str = textStorage.string as NSString
        let pos = selectedRange.location
        let lineRange = str.lineRange(for: NSRange(location: pos, length: 0))
        let line = str.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let indent = String(line.prefix(line.count - trimmed.count))

        if trimmed.isEmpty { return nil }

        let bulletPrefixes = ["- ", "* ", "+ "]
        for prefix in bulletPrefixes {
            if trimmed.hasPrefix(prefix) {
                let afterPrefix = String(trimmed.dropFirst(prefix.count))
                if afterPrefix.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
                return indent + prefix
            }
        }

        if trimmed.hasPrefix("- ") && trimmed.count >= 4 {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: 2)
            let third = trimmed[idx]
            if third == "\u{FFFC}" {
                let afterCheckbox = String(trimmed.dropFirst(5))
                if afterCheckbox.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
                return indent + "- [ ] "
            }
            if third == "[" && (trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")) {
                let afterCheckbox = String(trimmed.dropFirst(6))
                if afterCheckbox.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
                return indent + "- [ ] "
            }
        }

        if let match = trimmed.firstMatch(of: /^(\d+)\.\s/) {
            let afterNum = String(trimmed.dropFirst(match.0.count))
            if afterNum.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            return indent + "1. "
        }

        return nil
    }

    func reconstructRawMarkdown() -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return "" }
        textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let imgAttachment = value as? MarkdownImageAttachment {
                result += imgAttachment.originalMarkdown
            } else if let tableAttachment = value as? MarkdownTableAttachment {
                result += tableAttachment.originalMarkdown
            } else if let checkboxAttachment = value as? MarkdownCheckboxAttachment {
                result += checkboxAttachment.originalMarkdown
            } else if let headerAttachment = value as? MarkdownHeaderPrefixAttachment {
                result += headerAttachment.originalMarkdown
            } else if let delimAttachment = value as? MarkdownInlineDelimiterAttachment {
                result += delimAttachment.originalMarkdown
            } else {
                result += self.textStorage.attributedSubstring(from: range).string
            }
        }
        return result
    }
}

extension MarkdownUITextView: UITextViewDelegate {
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n" else { return true }
        guard let prefix = listContinuationPrefix() else { return true }
        // Intercept: insert newline + prefix ourselves
        guard let storage = textView.textStorage else { return true }
        let nsContent = storage.string as NSString
        let insertRange = NSRange(location: range.location, length: range.length)
        let replacement = "\n" + prefix
        storage.replaceCharacters(in: insertRange, with: replacement)
        textView.selectedRange = NSRange(location: range.location + replacement.count, length: 0)
        _rawMarkdown = reconstructRawMarkdown()
        onTextChange?(_rawMarkdown)
        scheduleHighlight()
        return false
    }

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
            defer { self.isUpdating = false }
            let sel = self.selectedRange
            // No table attachments on iOS – tables stay as editable raw markdown.
            self.highlighter.applyHighlighting(
                to: self.textStorage,
                baseFont: self.font ?? .preferredFont(forTextStyle: .body),
                noteURL: self.noteURL,
                applyTables: false
            )
            let maxLen = self.textStorage.length
            let loc = min(sel.location, maxLen)
            let len = min(sel.length, maxLen - loc)
            self.selectedRange = NSRange(location: loc, length: len)
        }
        highlightWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        highlightWorkItem?.cancel()
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let sel = selectedRange
        highlighter.applyHighlighting(
            to: textStorage,
            baseFont: font ?? .preferredFont(forTextStyle: .body),
            noteURL: noteURL,
            applyTables: false
        )
        let maxLen = textStorage.length
        let loc = min(sel.location, maxLen)
        let len = min(sel.length, maxLen - loc)
        selectedRange = NSRange(location: loc, length: len)
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
            context.coordinator.lastContentFromEditor = newText
            self.text = newText
        }
        uiView.onSelectionChange = { newRange in
            self.cursorPosition = newRange
        }

        let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let newFont = UIFont.systemFont(ofSize: baseSize * editorFontScale)
        if uiView.font != newFont { uiView.font = newFont }

        // Only apply external updates (load, format bar). Skip when the change came from our own editor
        // to avoid overwriting user input when SwiftUI delivers stale binding values.
        if text == context.coordinator.lastContentFromEditor {
            return
        }
        if uiView.rawMarkdown != text {
            uiView.setMarkdown(text)
            context.coordinator.lastContentFromEditor = text
        }
    }

    public final class Coordinator {
        weak var textView: MarkdownUITextView?
        var lastContentFromEditor: String?
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
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }
        string = markdown
        highlighter.applyHighlighting(
            to: textStorage!,
            baseFont: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            noteURL: noteURL,
            applyTables: false
        )
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
            } else if let tableAttachment = value as? MarkdownTableAttachment {
                result += tableAttachment.originalMarkdown
            } else if let checkboxAttachment = value as? MarkdownCheckboxAttachment {
                result += checkboxAttachment.originalMarkdown
            } else if let headerAttachment = value as? MarkdownHeaderPrefixAttachment {
                result += headerAttachment.originalMarkdown
            } else if let delimAttachment = value as? MarkdownInlineDelimiterAttachment {
                result += delimAttachment.originalMarkdown
            } else {
                result += storage.attributedSubstring(from: range).string
            }
        }
        return result
    }

    public override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let layoutManager = layoutManager, let textContainer = textContainer, let storage = textStorage else {
            super.mouseDown(with: event)
            return
        }
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height
        )
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphRect.contains(containerPoint) else {
            super.mouseDown(with: event)
            return
        }
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length,
              let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? MarkdownCheckboxAttachment else {
            super.mouseDown(with: event)
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        let toggled = attachment.originalMarkdown.contains("[ ]") ? "- [x] " : "- [ ] "
        let newAttachment = MarkdownCheckboxAttachment()
        newAttachment.originalMarkdown = toggled
        storage.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: NSAttributedString(attachment: newAttachment))
        _rawMarkdown = reconstructRawMarkdown()
        onTextChange?(_rawMarkdown)
    }

    public override func didChangeText() {
        super.didChangeText()
        guard !isUpdating else { return }
        _rawMarkdown = reconstructRawMarkdown()
        onTextChange?(_rawMarkdown)
        scheduleHighlight()
    }

    /// If the cursor is in a list line, returns the prefix to insert on Enter (indent + bullet/checkbox).
    /// Returns nil if not in a list or if the line is empty (user should exit list).
    private func listContinuationPrefix() -> String? {
        guard let storage = textStorage else { return nil }
        let str = storage.string as NSString
        let pos = selectedRange().location
        let lineRange = str.lineRange(for: NSRange(location: pos, length: 0))
        let line = str.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let indent = String(line.prefix(line.count - trimmed.count))

        // Empty bullet: exit list
        if trimmed.isEmpty { return nil }

        let bulletPrefixes = ["- ", "* ", "+ "]
        for prefix in bulletPrefixes {
            if trimmed.hasPrefix(prefix) {
                let afterPrefix = String(trimmed.dropFirst(prefix.count))
                if afterPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                    return nil // Empty bullet, exit list
                }
                return indent + prefix
            }
        }

        // Checkbox: "- [ ] ", "- [x] ", or "- " + attachment + " "
        if trimmed.hasPrefix("- ") && trimmed.count >= 4 {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: 2)
            let third = trimmed[idx]
            if third == "\u{FFFC}" {
                let afterCheckbox = String(trimmed.dropFirst(5)) // "- " + attachment + " "
                if afterCheckbox.trimmingCharacters(in: .whitespaces).isEmpty {
                    return nil
                }
                return indent + "- [ ] "
            }
            if third == "[" && (trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")) {
                let afterCheckbox = String(trimmed.dropFirst(6))
                if afterCheckbox.trimmingCharacters(in: .whitespaces).isEmpty {
                    return nil
                }
                return indent + "- [ ] "
            }
        }

        // Numbered list
        if let match = trimmed.firstMatch(of: /^(\d+)\.\s/) {
            let afterNum = String(trimmed.dropFirst(match.0.count))
            if afterNum.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
            return indent + "1. "
        }

        return nil
    }

    public override func insertNewline(_ sender: Any?) {
        if let prefix = listContinuationPrefix() {
            insertText("\n" + prefix, replacementRange: selectedRange())
            return
        }
        super.insertNewline(sender)
    }

    private var highlightWorkItem: DispatchWorkItem?

    private func scheduleHighlight() {
        highlightWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isUpdating else { return }
            self.isUpdating = true
            defer { self.isUpdating = false }
            let sel = self.selectedRanges
            self.undoManager?.disableUndoRegistration()
            defer { self.undoManager?.enableUndoRegistration() }
            self.highlighter.applyHighlighting(
                to: self.textStorage!,
                baseFont: self.font ?? .systemFont(ofSize: NSFont.systemFontSize),
                noteURL: self.noteURL,
                applyTables: false
            )
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
        }
        highlightWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            highlightWorkItem?.cancel()
            guard !isUpdating else { return result }
            isUpdating = true
            defer { isUpdating = false }
            let sel = selectedRanges
            undoManager?.disableUndoRegistration()
            defer { undoManager?.enableUndoRegistration() }
            highlighter.applyHighlighting(
                to: textStorage!,
                baseFont: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                noteURL: noteURL,
                applyTables: false
            )
            let maxLen = textStorage?.length ?? 0
            let clamped = sel.compactMap { rv -> NSValue? in
                let r = rv.rangeValue
                let loc = min(r.location, maxLen)
                let len = min(r.length, maxLen - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
            selectedRanges = clamped.isEmpty
                ? [NSValue(range: NSRange(location: maxLen, length: 0))]
                : clamped
        }
        return result
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

/// Attachment for rendered Markdown tables. Stores original markdown for round-trip.
final class MarkdownTableAttachment: NSTextAttachment {
    var originalMarkdown: String = ""
}

/// Attachment for GFM task list checkboxes. Renders ☐/☑, stores original markdown for round-trip.
final class MarkdownCheckboxAttachment: NSTextAttachment {
    /// Original markdown: `- [ ] ` or `- [x] ` (GFM task list syntax).
    var originalMarkdown: String = ""
    var isChecked: Bool { originalMarkdown.contains("[x]") || originalMarkdown.contains("[X]") }

    #if canImport(UIKit)
    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        let ptSize = (textContainer?.layoutManager?.textStorage?.attribute(.font, at: charIndex, effectiveRange: nil) as? UIFont)?.pointSize ?? 17
        return renderCheckboxImage(size: max(18, ptSize * 1.1))
    }
    #elseif canImport(AppKit)
    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        let ptSize = (textContainer?.layoutManager?.textStorage?.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont)?.pointSize ?? NSFont.systemFontSize
        return renderCheckboxImage(size: max(18, ptSize * 1.1))
    }
    #endif

    #if canImport(UIKit)
    private func renderCheckboxImage(size: CGFloat) -> UIImage? {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { ctx in
            if isChecked {
                UIColor.systemGreen.setFill()
                let path = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 4)
                path.fill()
                UIColor.white.setStroke()
                path.lineWidth = 2
                path.stroke()
                let checkPath = UIBezierPath()
                checkPath.move(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.5))
                checkPath.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.7))
                checkPath.addLine(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.3))
                UIColor.white.setStroke()
                checkPath.lineWidth = 2
                checkPath.lineCapStyle = .round
                checkPath.lineJoinStyle = .round
                checkPath.stroke()
            } else {
                UIColor.systemGray3.setStroke()
                let path = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 4)
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }
    #elseif canImport(AppKit)
    private func renderCheckboxImage(size: CGFloat) -> NSImage? {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = NSImage(size: rect.size)
        image.lockFocus()
        defer { image.unlockFocus() }
        if isChecked {
            NSColor.systemGreen.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            NSColor.white.setStroke()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            path.stroke()
            let checkPath = NSBezierPath()
            checkPath.move(to: NSPoint(x: rect.width * 0.2, y: rect.height * 0.5))
            checkPath.line(to: NSPoint(x: rect.width * 0.4, y: rect.height * 0.7))
            checkPath.line(to: NSPoint(x: rect.width * 0.8, y: rect.height * 0.3))
            NSColor.white.setStroke()
            checkPath.lineWidth = 2
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            checkPath.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            path.stroke()
        }
        return image
    }
    #endif

    override var bounds: CGRect {
        get {
            let size: CGFloat = 20
            #if canImport(UIKit)
            return CGRect(x: 0, y: -4, width: size, height: size)
            #else
            return CGRect(x: 0, y: -4, width: size, height: size)
            #endif
        }
        set { }
    }
}

/// Invisible attachment for header prefix. Hides `# ` etc. while preserving round-trip.
/// Uses minimal width (4pt) to preserve spacing before heading text.
final class MarkdownHeaderPrefixAttachment: NSTextAttachment {
    var originalMarkdown: String = ""

    override var bounds: CGRect {
        get { CGRect(x: 0, y: 0, width: 4, height: 0) }
        set { }
    }
}

/// Zero-width attachment for inline delimiters (** * `). Hides syntax while preserving round-trip.
final class MarkdownInlineDelimiterAttachment: NSTextAttachment {
    var originalMarkdown: String = ""

    override var bounds: CGRect {
        get { CGRect(x: 0, y: 0, width: 0, height: 0) }
        set { }
    }
}

// MARK: - Syntax Highlighter

struct MarkdownSyntaxHighlighter: Sendable {
    #if canImport(UIKit)
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
    typealias PlatformImage = UIImage
    /// Gold/orange accent for markdown syntax (#, -, >) per design.
    private static let syntaxAccentColor = UIColor(red: 0.91, green: 0.64, blue: 0.23, alpha: 1.0)
    #elseif canImport(AppKit)
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
    typealias PlatformImage = NSImage
    #endif

    func applyHighlighting(to storage: NSTextStorage, baseFont: PlatformFont, noteURL: URL? = nil, applyTables: Bool = true) {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 4

        storage.addAttribute(.font, value: baseFont, range: fullRange)
        #if canImport(UIKit)
        storage.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        #elseif canImport(AppKit)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        #endif
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)

        let nsText = text as NSString

        nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = nsText.substring(with: lineRange)
            self.highlightLine(line, range: lineRange, in: storage, baseFont: baseFont)
        }

        applyInlinePatterns(to: storage, text: nsText, fullRange: fullRange, baseFont: baseFont)
        applyInlineDelimiterAttachments(to: storage, baseFont: baseFont)

        // Attachments replace text; each uses current storage (order matters for range validity).
        applyCheckboxAttachments(to: storage, baseFont: baseFont)
        applyListPrefixAttachments(to: storage)
        applyHeaderPrefixAttachments(to: storage)
        if applyTables {
            applyTableAttachments(to: storage, text: storage.string as NSString, baseFont: baseFont)
        }
        if let noteURL {
            applyImageAttachments(to: storage, text: storage.string as NSString, noteURL: noteURL)
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
            storage.addAttribute(.foregroundColor, value: Self.syntaxAccentColor, range: prefixRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: prefixRange)
            #endif
            return
        }

        if trimmed.hasPrefix("> ") || trimmed == ">" {
            let lineStr = String(trimmed)
            // Callouts: > [!NOTE], > [!WARNING], etc.
            if let calloutMatch = lineStr.prefixMatch(of: /^>\s*\[!([A-Z]+)\]/) {
                let calloutType = String(calloutMatch.1).uppercased()
                #if canImport(UIKit)
                let calloutColor: UIColor = switch calloutType {
                case "NOTE", "INFO": .systemBlue
                case "TIP", "HINT": .systemGreen
                case "IMPORTANT": .systemOrange
                case "WARNING", "CAUTION": .systemOrange
                case "DANGER", "ERROR": .systemRed
                default: .secondaryLabel
                }
                storage.addAttribute(.foregroundColor, value: calloutColor, range: range)
                storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold), range: range)
                let bgColor = calloutColor.withAlphaComponent(0.12)
                storage.addAttribute(.backgroundColor, value: bgColor, range: range)
                #elseif canImport(AppKit)
                let calloutColor: NSColor = switch calloutType {
                case "NOTE", "INFO": .systemBlue
                case "TIP", "HINT": .systemGreen
                case "IMPORTANT": .systemOrange
                case "WARNING", "CAUTION": .systemOrange
                case "DANGER", "ERROR": .systemRed
                default: .secondaryLabelColor
                }
                storage.addAttribute(.foregroundColor, value: calloutColor, range: range)
                storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold), range: range)
                storage.addAttribute(.backgroundColor, value: calloutColor.withAlphaComponent(0.12), range: range)
                #endif
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = 4
                paragraph.paragraphSpacing = 4
                paragraph.headIndent = 12
                paragraph.firstLineHeadIndent = 12
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            } else {
                // Regular blockquote
                #if canImport(UIKit)
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
                storage.addAttribute(.backgroundColor, value: UIColor.tertiarySystemFill, range: range)
                #elseif canImport(AppKit)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: range)
                #endif
                let italicFont = PlatformFont.systemFont(ofSize: baseFont.pointSize).withTraits(.italic)
                storage.addAttribute(.font, value: italicFont, range: range)
                let paragraph = NSMutableParagraphStyle()
                paragraph.headIndent = 12
                paragraph.firstLineHeadIndent = 12
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
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
                let indentLevel = line.count - trimmed.count
                let offset = indentLevel
                let prefixRange = NSRange(location: range.location + offset, length: min(prefix.count, range.length - offset))
                #if canImport(UIKit)
                storage.addAttribute(.foregroundColor, value: Self.syntaxAccentColor, range: prefixRange)
                #elseif canImport(AppKit)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
                #endif
                if indentLevel > 0 {
                    let indent = CGFloat(indentLevel) * (baseFont.pointSize * 0.6)
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineSpacing = 4
                    paragraph.paragraphSpacing = 4
                    paragraph.headIndent = indent
                    paragraph.firstLineHeadIndent = indent
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
                }
                break
            }
        }

        if let numMatch = String(trimmed).prefixMatch(of: /^\d+\.\s/) {
            let indentLevel = line.count - trimmed.count
            let offset = indentLevel
            let prefixRange = NSRange(location: range.location + offset, length: min(numMatch.0.count, range.length - offset))
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: Self.syntaxAccentColor, range: prefixRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: prefixRange)
            #endif
            if indentLevel > 0 {
                let indent = CGFloat(indentLevel) * (baseFont.pointSize * 0.6)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4
                paragraph.paragraphSpacing = 4
                paragraph.headIndent = indent
                paragraph.firstLineHeadIndent = indent
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
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

        if trimmed.hasPrefix("```") {
            let langLine = String(trimmed)
            #if canImport(UIKit)
            if langLine.hasPrefix("```mermaid") || langLine.hasPrefix("``` Mermaid") {
                storage.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: range)
            } else if langLine.hasPrefix("```swift") || langLine.hasPrefix("``` Swift") {
                storage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: range)
            } else if langLine.hasPrefix("```python") || langLine.hasPrefix("```py ") {
                storage.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
            } else if langLine.hasPrefix("```javascript") || langLine.hasPrefix("```js ") {
                storage.addAttribute(.foregroundColor, value: UIColor.systemYellow, range: range)
            } else if langLine.hasPrefix("```json") {
                storage.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: range)
            }
            #elseif canImport(AppKit)
            if langLine.hasPrefix("```mermaid") || langLine.hasPrefix("``` Mermaid") {
                storage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: range)
            } else if langLine.hasPrefix("```swift") || langLine.hasPrefix("``` Swift") {
                storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
            } else if langLine.hasPrefix("```python") || langLine.hasPrefix("```py ") {
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            } else if langLine.hasPrefix("```javascript") || langLine.hasPrefix("```js ") {
                storage.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: range)
            } else if langLine.hasPrefix("```json") {
                storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: range)
            }
            #endif
        }
    }

    /// Replaces ** * ` delimiters with zero-width attachments and applies styling to content.
    private func applyInlineDelimiterAttachments(to storage: NSTextStorage, baseFont: PlatformFont) {
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        struct Match { let fullRange: NSRange; let delimLen: Int; let markdown: String; let style: InlineStyle }
        enum InlineStyle { case bold, italic, code }
        var matches: [Match] = []

        applyRegexWithCapture(#"\*\*(.+?)\*\*"#, to: text, range: fullRange) { r, _ in
            matches.append(Match(fullRange: r, delimLen: 2, markdown: "**", style: .bold))
        }
        applyRegexWithCapture(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, to: text, range: fullRange) { r, _ in
            matches.append(Match(fullRange: r, delimLen: 1, markdown: "*", style: .italic))
        }
        applyRegexWithCapture(#"`([^`]+)`"#, to: text, range: fullRange) { r, _ in
            matches.append(Match(fullRange: r, delimLen: 1, markdown: "`", style: .code))
        }

        for m in matches.sorted(by: { $0.fullRange.location > $1.fullRange.location }) {
            let closeRange = NSRange(location: m.fullRange.location + m.fullRange.length - m.delimLen, length: m.delimLen)
            let openRange = NSRange(location: m.fullRange.location, length: m.delimLen)
            let att = MarkdownInlineDelimiterAttachment()
            att.originalMarkdown = m.markdown
            storage.replaceCharacters(in: closeRange, with: NSAttributedString(attachment: att))
            let att2 = MarkdownInlineDelimiterAttachment()
            att2.originalMarkdown = m.markdown
            storage.replaceCharacters(in: openRange, with: NSAttributedString(attachment: att2))
            let contentRange = NSRange(location: openRange.location + 1, length: m.fullRange.length - 2 * m.delimLen)
            guard contentRange.length > 0 else { continue }
            switch m.style {
            case .bold:
                storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold), range: contentRange)
            case .italic:
                storage.addAttribute(.font, value: baseFont.withTraits(.italic), range: contentRange)
            case .code:
                storage.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular), range: contentRange)
                #if canImport(UIKit)
                storage.addAttribute(.backgroundColor, value: UIColor.systemFill, range: contentRange)
                #elseif canImport(AppKit)
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: contentRange)
                #endif
            }
        }
    }

    private func applyRegexWithCapture(_ pattern: String, to text: NSString, range: NSRange, handler: (NSRange, NSRange) -> Void) {
        guard let regex = cachedRegex(pattern) else { return }
        regex.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2 else { return }
            let contentRange = m.range(at: 1)
            guard contentRange.location != NSNotFound else { return }
            handler(m.range, contentRange)
        }
    }

    private func applyInlinePatterns(to storage: NSTextStorage, text: NSString, fullRange: NSRange, baseFont: PlatformFont) {
        // Bold __...__ (no delimiter hiding for __ to avoid conflict with italic _)
        applyRegex(#"__(.+?)__"#, to: storage, text: text, range: fullRange) { matchRange in
            let boldFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: matchRange)
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

        // Wiki links [[Note]] or [[Note|Alias]] or [[Note#Heading]]
        applyRegex(#"\[\[([^\]]+)\]\]"#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: matchRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: matchRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            #endif
        }

        // Highlight ==text== (GFM-style)
        applyRegex(#"==(.+?)=="#, to: storage, text: text, range: fullRange) { matchRange in
            #if canImport(UIKit)
            storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.4), range: matchRange)
            #elseif canImport(AppKit)
            storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), range: matchRange)
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

    // MARK: - Checkbox Attachments (GFM Task Lists)

    /// Replaces `- [ ] ` and `- [x] ` with checkbox attachments. Processes in reverse order.
    private func applyCheckboxAttachments(to storage: NSTextStorage, baseFont: PlatformFont) {
        let text = storage.string as NSString
        var matches: [(range: NSRange, prefix: String)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let prefixPatterns = ["- [ ] ", "- [x] ", "- [X] "]
            for prefix in prefixPatterns {
                if String(trimmed).hasPrefix(prefix) {
                    let offset = line.count - trimmed.count
                    let prefixRange = NSRange(location: lineRange.location + offset, length: prefix.count)
                    matches.append((prefixRange, String(prefix)))
                    break
                }
            }
        }
        for match in matches.reversed() {
            let isChecked = match.prefix.contains("[x]") || match.prefix.contains("[X]")
            let attachment = MarkdownCheckboxAttachment()
            attachment.originalMarkdown = match.prefix
            let attrString = NSAttributedString(attachment: attachment)
            storage.replaceCharacters(in: match.range, with: attrString)
            if isChecked {
                let contentStart = match.range.location + 1
                let searchRange = NSRange(location: contentStart, length: max(0, storage.length - contentStart))
                let lineEnd = (storage.string as NSString).rangeOfCharacter(from: .newlines, range: searchRange).location
                let contentLength = (lineEnd == NSNotFound ? storage.length : lineEnd) - contentStart
                let contentRange = NSRange(location: contentStart, length: contentLength)
                if contentRange.length > 0 {
                    #if canImport(UIKit)
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: contentRange)
                    #elseif canImport(AppKit)
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: contentRange)
                    #endif
                }
            }
        }
    }

    // MARK: - List Prefix Attachments (Hide - * + at line start)

    /// Replaces bullet list prefixes (- * +) with zero-width attachments. Runs after checkboxes.
    private func applyListPrefixAttachments(to storage: NSTextStorage) {
        let text = storage.string as NSString
        var matches: [(range: NSRange, prefix: String)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let bulletPrefixes = ["- ", "* ", "+ "]
            for prefix in bulletPrefixes {
                if String(trimmed).hasPrefix(prefix) {
                    let offset = line.count - trimmed.count
                    let prefixRange = NSRange(location: lineRange.location + offset, length: prefix.count)
                    matches.append((prefixRange, String(prefix)))
                    break
                }
            }
        }
        for match in matches.reversed() {
            let att = MarkdownInlineDelimiterAttachment()
            att.originalMarkdown = match.prefix
            storage.replaceCharacters(in: match.range, with: NSAttributedString(attachment: att))
        }
    }

    // MARK: - Header Prefix Attachments (Hide # Symbols)

    /// Replaces `# ` through `###### ` with zero-width attachments. Processes in reverse order.
    private func applyHeaderPrefixAttachments(to storage: NSTextStorage) {
        let text = storage.string as NSString
        var matches: [(range: NSRange, prefix: String)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if let match = String(trimmed).prefixMatch(of: /^(#{1,6})\s/) {
                let offset = line.count - trimmed.count
                let prefixLen = match.0.count
                let prefixRange = NSRange(location: lineRange.location + offset, length: min(prefixLen, lineRange.length - offset))
                let prefix = text.substring(with: prefixRange)
                matches.append((prefixRange, prefix))
            }
        }
        for match in matches.reversed() {
            let attachment = MarkdownHeaderPrefixAttachment()
            attachment.originalMarkdown = match.prefix
            let attrString = NSAttributedString(attachment: attachment)
            storage.replaceCharacters(in: match.range, with: attrString)
        }
    }

    // MARK: - Table Rendering

    /// Parses Markdown table syntax into rows of cells.
    private func parseTable(_ tableMarkdown: String) -> [[String]]? {
        let lines = tableMarkdown.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        var rows: [[String]] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { return nil }
            let inner = trimmed.dropFirst().dropLast()
            let cells = inner.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            rows.append(cells)
        }
        return rows
    }

    /// Applies only table attachments. Used on iOS when deferring to avoid NSUndoManager crash.
    func applyTableAttachmentsOnly(to storage: NSTextStorage, baseFont: PlatformFont) {
        let text = storage.string as NSString
        applyTableAttachments(to: storage, text: text, baseFont: baseFont)
    }

    /// Finds Markdown table blocks and replaces them with rendered table attachments.
    private func applyTableAttachments(to storage: NSTextStorage, text: NSString, baseFont: PlatformFont) {
        let fullText = text as String
        let tablePattern = #"((?:\|[^\n]+\|\n?)+)"#
        guard let regex = cachedRegex(tablePattern) else { return }

        let matches = regex.matches(in: fullText, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: fullText) else { continue }
            let tableMarkdown = String(fullText[matchRange])
            guard let rows = parseTable(tableMarkdown), rows.count >= 2,
                  rows.allSatisfy({ $0.count == rows[0].count }) else { continue }

            let attachment = MarkdownTableAttachment()
            attachment.originalMarkdown = tableMarkdown

            let image = Self.renderTableToImage(rows: rows, baseFont: baseFont)
            attachment.image = image
            let cellHeight: CGFloat = 28
            let tableHeight = CGFloat(rows.count) * cellHeight
            attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width, height: tableHeight)

            let attrString = NSAttributedString(attachment: attachment)
            storage.replaceCharacters(in: match.range, with: attrString)
        }
    }

    private static func renderTableToImage(rows: [[String]], baseFont: PlatformFont) -> PlatformImage {
        let cellPadding: CGFloat = 12
        let cellHeight: CGFloat = 28
        var colWidths: [CGFloat] = Array(repeating: 60, count: rows[0].count)
        for row in rows {
            for (c, cell) in row.enumerated() where c < colWidths.count {
                let size = (cell as NSString).size(withAttributes: [.font: baseFont])
                colWidths[c] = max(colWidths[c], size.width + cellPadding * 2)
            }
        }
        let totalWidth = colWidths.reduce(0, +)
        let totalHeight = CGFloat(rows.count) * cellHeight

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext

            for (r, row) in rows.enumerated() {
                let isHeader = (r == 0)
                let isSeparator = (r == 1 && row.allSatisfy { $0.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces).isEmpty })
                var x: CGFloat = 0
                for (c, cell) in row.enumerated() where c < colWidths.count {
                    let rect = CGRect(x: x, y: CGFloat(r) * cellHeight, width: colWidths[c], height: cellHeight)
                    if isSeparator {
                        UIColor.tertiaryLabel.withAlphaComponent(0.3).setFill()
                        cgContext.fill(rect)
                    } else {
                        (isHeader ? UIColor.secondarySystemFill : UIColor.systemBackground).setFill()
                        cgContext.fill(rect)
                    }
                    if !isSeparator {
                        let attr: [NSAttributedString.Key: Any] = [
                            .font: isHeader ? UIFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold) : baseFont,
                            .foregroundColor: UIColor.label
                        ]
                        let drawRect = rect.insetBy(dx: cellPadding, dy: 4)
                        (cell as NSString).draw(in: drawRect, withAttributes: attr)
                    }
                    UIColor.separator.setStroke()
                    cgContext.setLineWidth(0.5)
                    cgContext.stroke(rect)
                    x += colWidths[c]
                }
            }
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .medium

        NSColor.textBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)).fill()

        for (r, row) in rows.enumerated() {
            let isHeader = (r == 0)
            let isSeparator = (r == 1 && row.allSatisfy { $0.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces).isEmpty })
            var x: CGFloat = 0
            for (c, cell) in row.enumerated() where c < colWidths.count {
                let rect = NSRect(x: x, y: totalHeight - CGFloat(r + 1) * cellHeight, width: colWidths[c], height: cellHeight)
                if isSeparator {
                    NSColor.tertiaryLabelColor.withAlphaComponent(0.3).setFill()
                    NSBezierPath(rect: rect).fill()
                } else {
                    (isHeader ? NSColor.controlBackgroundColor : NSColor.textBackgroundColor).setFill()
                    NSBezierPath(rect: rect).fill()
                }
                if !isSeparator {
                    let attr: [NSAttributedString.Key: Any] = [
                        .font: isHeader ? NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold) : baseFont,
                        .foregroundColor: NSColor.labelColor
                    ]
                    let drawRect = rect.insetBy(dx: cellPadding, dy: 4)
                    (cell as NSString).draw(in: drawRect, withAttributes: attr)
                }
                NSColor.separatorColor.setStroke()
                NSBezierPath.defaultLineWidth = 0.5
                NSBezierPath(rect: rect).stroke()
                x += colWidths[c]
            }
        }
        #endif

        return image
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
