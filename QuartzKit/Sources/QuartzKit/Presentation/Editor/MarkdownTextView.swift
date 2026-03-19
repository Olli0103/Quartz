import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Live Markdown Editor (Pillar 1: TextKit + AST)

/// Production-ready markdown editor using UITextView (iOS) / NSTextView (macOS) with
/// live AST-based syntax highlighting via swift-markdown. Parsing runs on a background
/// Actor with 80ms debounce; attributes are applied on the main thread for 120fps.
///
/// **Performance:** No full AST parse on every keystroke. Debounced async pipeline keeps
/// the main thread free for ProMotion scrolling and typing.
public struct MarkdownTextViewRepresentable: View {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    var editorFontScale: CGFloat
    var noteURL: URL?

    public init(
        text: Binding<String>,
        cursorPosition: Binding<NSRange>,
        editorFontScale: CGFloat = 1.0,
        noteURL: URL? = nil
    ) {
        self._text = text
        self._cursorPosition = cursorPosition
        self.editorFontScale = editorFontScale
        self.noteURL = noteURL
    }

    public var body: some View {
        #if os(iOS)
        MarkdownTextView_iOS(
            text: $text,
            cursorPosition: $cursorPosition,
            baseFontSize: baseFontSize,
            editorFontScale: editorFontScale
        )
        #elseif os(macOS)
        MarkdownTextView_macOS(
            text: $text,
            cursorPosition: $cursorPosition,
            baseFontSize: baseFontSize,
            editorFontScale: editorFontScale
        )
        #else
        TextEditor(text: $text)
            .onChange(of: text) { _, _ in cursorPosition = NSRange(location: text.count, length: 0) }
        #endif
    }

    private var baseFontSize: CGFloat {
        #if os(macOS)
        14
        #elseif os(iOS)
        UIFont.preferredFont(forTextStyle: .body).pointSize
        #else
        16
        #endif
    }
}

// MARK: - iOS (UITextView)

#if os(iOS)
private struct MarkdownTextView_iOS: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    let baseFontSize: CGFloat
    let editorFontScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            cursorPosition: $cursorPosition,
            baseFontSize: baseFontSize * editorFontScale
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: baseFontSize * editorFontScale)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        tv.textContainer.lineFragmentPadding = 0
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let sel = uiView.selectedTextRange
            uiView.text = text
            uiView.selectedTextRange = sel
        }
        context.coordinator.baseFontSize = baseFontSize * editorFontScale
        context.coordinator.textView = uiView
        context.coordinator.scheduleHighlight(text: text, textView: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var cursorPosition: NSRange
        var baseFontSize: CGFloat
        weak var textView: UITextView?
        private let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        private var highlightTask: Task<Void, Never>?

        init(text: Binding<String>, cursorPosition: Binding<NSRange>, baseFontSize: CGFloat) {
            _text = text
            _cursorPosition = cursorPosition
            self.baseFontSize = baseFontSize
        }

        func scheduleHighlight(text: String, textView: UITextView) {
            highlightTask?.cancel()
            highlightTask = Task { [highlighter, baseFontSize] in
                let spans = await highlighter.parseDebounced(text)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak textView] in
                    guard let tv = textView else { return }
                    applySpans(spans, to: tv, baseFontSize: baseFontSize)
                }
            }
        }

        func applySpans(_ spans: [HighlightSpan], to textView: UITextView, baseFontSize: CGFloat) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: UIFont.systemFont(ofSize: baseFontSize),
                .foregroundColor: UIColor.label
            ], range: fullRange)
            for span in spans {
                let r = span.range
                guard r.location >= 0, r.location + r.length <= storage.length else { continue }
                storage.addAttributes([
                    .font: span.font,
                    .foregroundColor: span.color ?? .label,
                    .backgroundColor: span.backgroundColor ?? .clear,
                    .strikethroughStyle: span.strikethrough ? 1 : 0
                ], range: r)
            }
            storage.endEditing()
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            updateCursorPosition(from: textView)
            scheduleHighlight(text: textView.text ?? "", textView: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateCursorPosition(from: textView)
        }

        private func updateCursorPosition(from textView: UITextView) {
            guard let range = textView.selectedTextRange else { return }
            let loc = textView.offset(from: textView.beginningOfDocument, to: range.start)
            let len = textView.offset(from: range.start, to: range.end)
            cursorPosition = NSRange(location: loc, length: len)
        }
    }
}
#endif

// MARK: - macOS (NSTextView)

#if os(macOS)
private struct MarkdownTextView_macOS: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    let baseFontSize: CGFloat
    let editorFontScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            cursorPosition: $cursorPosition,
            baseFontSize: baseFontSize * editorFontScale
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: baseFontSize * editorFontScale)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(sel)
        }
        context.coordinator.baseFontSize = baseFontSize * editorFontScale
        context.coordinator.scheduleHighlight(text: text, textView: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var cursorPosition: NSRange
        var baseFontSize: CGFloat
        weak var textView: NSTextView?
        private let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        private var highlightTask: Task<Void, Never>?

        init(text: Binding<String>, cursorPosition: Binding<NSRange>, baseFontSize: CGFloat) {
            _text = text
            _cursorPosition = cursorPosition
            self.baseFontSize = baseFontSize
        }

        func scheduleHighlight(text: String, textView: NSTextView) {
            highlightTask?.cancel()
            highlightTask = Task { [highlighter, baseFontSize] in
                let spans = await highlighter.parseDebounced(text)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak textView] in
                    guard let tv = textView else { return }
                    applySpans(spans, to: tv, baseFontSize: baseFontSize)
                }
            }
        }

        func applySpans(_ spans: [HighlightSpan], to textView: NSTextView, baseFontSize: CGFloat) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.systemFont(ofSize: baseFontSize),
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)
            for span in spans {
                let r = span.range
                guard r.location >= 0, r.location + r.length <= storage.length else { continue }
                storage.addAttributes([
                    .font: span.font,
                    .foregroundColor: span.color ?? .labelColor,
                    .backgroundColor: span.backgroundColor ?? .clear,
                    .strikethroughStyle: span.strikethrough ? 1 : 0
                ], range: r)
            }
            storage.endEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateCursorPosition(from: textView)
            scheduleHighlight(text: text, textView: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCursorPosition(from: textView)
        }

        private func updateCursorPosition(from textView: NSTextView) {
            cursorPosition = textView.selectedRange()
        }
    }
}
#endif
