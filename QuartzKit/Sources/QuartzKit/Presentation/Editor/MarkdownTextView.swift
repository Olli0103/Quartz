#if canImport(UIKit)
import UIKit
import SwiftUI
import os

/// TextKit 2 based WYSIWYG Markdown view for iOS/iPadOS.
///
/// Renders Markdown live: headlines large, bold text bold, code monospace,
/// syntax characters (`**`, `#`) are hidden.
public class MarkdownUITextView: UITextView {
    private let markdownRenderer = MarkdownRenderer()
    private let logger = Logger(subsystem: "com.quartz", category: "MarkdownTextView")
    private var isUpdating = false

    public var onTextChange: ((String) -> Void)?

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

    /// Sets the Markdown content and renders it.
    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let attributed = markdownRenderer.render(markdown)
        do {
            let nsAttributed = try NSAttributedString(attributed, including: MarkdownAttributes.self)
            // Save cursor position
            let selectedRange = self.selectedRange
            self.attributedText = nsAttributed
            // Restore cursor (if still valid)
            if selectedRange.location + selectedRange.length <= nsAttributed.length {
                self.selectedRange = selectedRange
            }
        } catch {
            logger.warning("Markdown rendering failed, falling back to plain text: \(error.localizedDescription)")
            self.text = markdown
        }
    }

    /// Returns the raw Markdown text (without formatting).
    public var rawMarkdown: String {
        text ?? ""
    }
}

// MARK: - UITextViewDelegate

extension MarkdownUITextView: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        guard !isUpdating else { return }
        onTextChange?(textView.text ?? "")
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper for the TextKit 2 based MarkdownTextView.
public struct MarkdownTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    var editorFontScale: CGFloat

    public init(text: Binding<String>, editorFontScale: CGFloat = 1.0) {
        self._text = text
        self.editorFontScale = editorFontScale
    }

    public func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView()
        view.onTextChange = { [_text] newText in
            _text.wrappedValue = newText
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

/// TextKit 2 based WYSIWYG Markdown view for macOS.
public class MarkdownNSTextView: NSTextView {
    private let markdownRenderer = MarkdownRenderer()
    private let logger = Logger(subsystem: "com.quartz", category: "MarkdownTextView")
    private var isUpdating = false

    public var onTextChange: ((String) -> Void)?

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
        font = .preferredFont(forTextStyle: .body)
        textContainerInset = NSSize(width: 12, height: 16)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isRichText = true
        usesFontPanel = false
        allowsUndo = true
        delegate = self
    }

    /// Sets the Markdown content and renders it.
    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let attributed = markdownRenderer.render(markdown)
        do {
            let nsAttributed = try NSAttributedString(attributed, including: MarkdownAttributes.self)
            let selectedRanges = self.selectedRanges
            textStorage?.setAttributedString(nsAttributed)
            // Clamp restored ranges to new text length to prevent NSRangeException
            let maxLen = nsAttributed.length
            let clampedRanges = selectedRanges.compactMap { rangeValue -> NSValue? in
                let range = rangeValue.rangeValue
                let loc = min(range.location, maxLen)
                let len = min(range.length, maxLen - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
            self.selectedRanges = clampedRanges.isEmpty ? [NSValue(range: NSRange(location: maxLen, length: 0))] : clampedRanges
        } catch {
            logger.warning("Markdown rendering failed, falling back to plain text: \(error.localizedDescription)")
            self.string = markdown
        }
    }

    /// Returns the raw Markdown text.
    public var rawMarkdown: String {
        string
    }
}

// MARK: - NSTextViewDelegate

extension MarkdownNSTextView: NSTextViewDelegate {
    public func textDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        onTextChange?(string)
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper for the TextKit 2 based MarkdownTextView (macOS).
public struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var editorFontScale: CGFloat

    public init(text: Binding<String>, editorFontScale: CGFloat = 1.0) {
        self._text = text
        self.editorFontScale = editorFontScale
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // Configure TextKit 2 for modern text layout
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        ))
        container.widthTracksTextView = true
        layoutManager.textContainer = container

        let textView = MarkdownNSTextView(frame: .zero, textContainer: container)
        textView.autoresizingMask = [.width, .height]
        textView.onTextChange = { [_text] newText in
            _text.wrappedValue = newText
        }
        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        let baseSize = NSFont.preferredFont(forTextStyle: .body).pointSize
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
