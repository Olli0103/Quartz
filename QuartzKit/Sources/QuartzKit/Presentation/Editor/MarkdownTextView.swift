#if canImport(UIKit)
import UIKit
import SwiftUI

/// TextKit 2 basierte WYSIWYG Markdown-View für iOS/iPadOS.
///
/// Rendert Markdown live: Headlines groß, Bold fett, Code monospace,
/// Syntax-Zeichen (`**`, `#`) werden ausgeblendet.
public class MarkdownUITextView: UITextView {
    private let markdownRenderer = MarkdownRenderer()
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

    /// Setzt den Markdown-Inhalt und rendert ihn.
    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let attributed = markdownRenderer.render(markdown)
        let nsAttributed = try? NSAttributedString(attributed, including: MarkdownAttributes.self)

        if let nsAttributed {
            // Cursor-Position merken
            let selectedRange = self.selectedRange
            self.attributedText = nsAttributed
            // Cursor wiederherstellen (falls noch gültig)
            if selectedRange.location + selectedRange.length <= nsAttributed.length {
                self.selectedRange = selectedRange
            }
        } else {
            self.text = markdown
        }
    }

    /// Gibt den rohen Markdown-Text zurück (ohne Formatierung).
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

/// SwiftUI-Wrapper für die TextKit 2 basierte MarkdownTextView.
public struct MarkdownTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    var editorFontScale: CGFloat

    public init(text: Binding<String>, editorFontScale: CGFloat = 1.0) {
        self._text = text
        self.editorFontScale = editorFontScale
    }

    public func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView()
        view.onTextChange = { newText in
            Task { @MainActor in
                text = newText
            }
        }
        return view
    }

    public func updateUIView(_ uiView: MarkdownUITextView, context: Context) {
        let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        uiView.font = .systemFont(ofSize: baseSize * editorFontScale)
        if uiView.rawMarkdown != text {
            uiView.setMarkdown(text)
        }
    }
}

#elseif canImport(AppKit)
import AppKit
import SwiftUI

/// TextKit 2 basierte WYSIWYG Markdown-View für macOS.
public class MarkdownNSTextView: NSTextView {
    private let markdownRenderer = MarkdownRenderer()
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
        isRichText = false
        allowsUndo = true
        delegate = self
    }

    /// Setzt den Markdown-Inhalt und rendert ihn.
    public func setMarkdown(_ markdown: String) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let attributed = markdownRenderer.render(markdown)
        let nsAttributed = try? NSAttributedString(attributed, including: MarkdownAttributes.self)

        if let nsAttributed {
            let selectedRanges = self.selectedRanges
            textStorage?.setAttributedString(nsAttributed)
            self.selectedRanges = selectedRanges
        } else {
            self.string = markdown
        }
    }

    /// Gibt den rohen Markdown-Text zurück.
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

/// SwiftUI-Wrapper für die TextKit 2 basierte MarkdownTextView (macOS).
public struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var editorFontScale: CGFloat

    public init(text: Binding<String>, editorFontScale: CGFloat = 1.0) {
        self._text = text
        self.editorFontScale = editorFontScale
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = MarkdownNSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.onTextChange = { newText in
            Task { @MainActor in
                text = newText
            }
        }
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        let baseSize = NSFont.preferredFont(forTextStyle: .body).pointSize
        textView.font = .systemFont(ofSize: baseSize * editorFontScale)
        if textView.rawMarkdown != text {
            textView.setMarkdown(text)
        }
    }
}
#endif
