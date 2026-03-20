import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Live Markdown Editor (TextKit 2 + AST)

/// Production-ready markdown editor using `UITextView` / `NSTextView` with a full **TextKit 2**
/// stack (`MarkdownTextContentManager` → `NSTextLayoutManager` → `NSTextContainer`).
/// Live AST highlighting applies attributes inside `performEditingTransaction` via
/// `MarkdownTextContentManager.performMarkdownEdit` for efficient invalidation on large documents.
///
/// **Performance:** Debounced async parsing keeps the main thread responsive for ProMotion (120fps).
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

// MARK: - TextKit 2 stack factory

#if os(iOS) || os(macOS)
@MainActor
private enum MarkdownTextKit2Stack {
    static func makeContentManager() -> MarkdownTextContentManager {
        MarkdownTextContentManager()
    }

    static func wireTextKit2(contentManager: MarkdownTextContentManager) -> (NSTextLayoutManager, NSTextContainer) {
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        contentManager.addTextLayoutManager(layoutManager)
        return (layoutManager, container)
    }
}
#endif

// MARK: - iOS (UITextView + TextKit 2)

#if os(iOS)
private struct MarkdownTextView_iOS: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: NSRange
    let baseFontSize: CGFloat
    let editorFontScale: CGFloat

    func makeCoordinator() -> Coordinator {
        let scaledBaseFont = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: baseFontSize * editorFontScale))
        return Coordinator(
            text: $text,
            cursorPosition: $cursorPosition,
            baseFontSize: scaledBaseFont.pointSize,
            editorFontScale: editorFontScale
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        // TextKit 2: `UITextView(usingTextLayoutManager:)` builds its own content stack; we use
        // `UITextView(frame:textContainer:)` so the container is already bound to our `MarkdownTextContentManager`.
        let textView = UITextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        context.coordinator.contentManager = contentManager

        let baseFont = UIFont.systemFont(ofSize: baseFontSize * editorFontScale)
        textView.font = UIFontMetrics.default.scaledFont(for: baseFont)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let sel = uiView.selectedTextRange
            uiView.text = text
            uiView.selectedTextRange = sel
        }
        let scaledBaseFont = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: baseFontSize * editorFontScale))
        context.coordinator.baseFontSize = scaledBaseFont.pointSize
        context.coordinator.editorFontScale = editorFontScale
        context.coordinator.textView = uiView
        if let cm = context.coordinator.contentManager {
            cm.baseFontSize = scaledBaseFont.pointSize
            cm.fontScale = editorFontScale
        }
        context.coordinator.scheduleHighlight(text: text, textView: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var cursorPosition: NSRange
        var baseFontSize: CGFloat
        var editorFontScale: CGFloat
        weak var textView: UITextView?
        /// Owns the TextKit 2 document; attribute edits must use `performMarkdownEdit`.
        var contentManager: MarkdownTextContentManager?
        private let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        private var highlightTask: Task<Void, Never>?

        init(text: Binding<String>, cursorPosition: Binding<NSRange>, baseFontSize: CGFloat, editorFontScale: CGFloat) {
            _text = text
            _cursorPosition = cursorPosition
            self.baseFontSize = baseFontSize
            self.editorFontScale = editorFontScale
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentSizeCategoryDidChange),
                name: UIContentSizeCategory.didChangeNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func contentSizeCategoryDidChange() {
            guard let tv = textView else { return }
            let preferredSize = UIFont.preferredFont(forTextStyle: .body).pointSize
            let scaledFont = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: preferredSize * editorFontScale))
            baseFontSize = scaledFont.pointSize
            tv.font = scaledFont
            contentManager?.baseFontSize = scaledFont.pointSize
            contentManager?.fontScale = editorFontScale
            scheduleHighlight(text: tv.text ?? "", textView: tv)
        }

        func scheduleHighlight(text: String, textView: UITextView) {
            highlightTask?.cancel()
            highlightTask = Task { [highlighter, baseFontSize] in
                let spans = await highlighter.parseDebounced(text)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self, weak textView] in
                    guard let self, let tv = textView, let cm = self.contentManager else { return }
                    Self.applySpans(spans, to: tv, baseFontSize: baseFontSize, contentManager: cm)
                }
            }
        }

        /// Applies syntax highlighting inside a TextKit 2 editing transaction (no legacy `beginEditing`/`endEditing` on the hot path).
        private static func applySpans(
            _ spans: [HighlightSpan],
            to textView: UITextView,
            baseFontSize: CGFloat,
            contentManager: MarkdownTextContentManager
        ) {
            guard let storage = textView.textStorage else { return }
            let storageLength = storage.length
            guard storageLength > 0 else { return }

            let updateRange: NSRange
            if spans.isEmpty {
                updateRange = NSRange(location: 0, length: storageLength)
            } else {
                var minLoc = storageLength
                var maxEnd = 0
                for span in spans {
                    let r = span.range
                    guard r.location >= 0, r.location + r.length <= storageLength else { continue }
                    minLoc = min(minLoc, r.location)
                    maxEnd = max(maxEnd, r.location + r.length)
                }
                if minLoc <= maxEnd {
                    updateRange = NSRange(location: minLoc, length: maxEnd - minLoc)
                } else {
                    updateRange = NSRange(location: 0, length: storageLength)
                }
            }

            contentManager.performMarkdownEdit {
                storage.setAttributes([
                    .font: UIFont.systemFont(ofSize: baseFontSize),
                    .foregroundColor: UIColor.label
                ], range: updateRange)
                for span in spans {
                    let r = span.range
                    guard r.location >= 0, r.location + r.length <= storageLength else { continue }
                    storage.addAttributes([
                        .font: span.font,
                        .foregroundColor: span.color ?? .label,
                        .backgroundColor: span.backgroundColor ?? .clear,
                        .strikethroughStyle: span.strikethrough ? 1 : 0
                    ], range: r)
                }
            }
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

// MARK: - macOS (NSTextView + TextKit 2)

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
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        // Same as iOS: `NSTextView(usingTextLayoutManager:)` would not use our `MarkdownTextContentManager`.
        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        context.coordinator.contentManager = contentManager
        textView.font = .systemFont(ofSize: baseFontSize * editorFontScale)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
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
        if let cm = context.coordinator.contentManager {
            cm.baseFontSize = baseFontSize * editorFontScale
            cm.fontScale = editorFontScale
        }
        context.coordinator.scheduleHighlight(text: text, textView: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var cursorPosition: NSRange
        var baseFontSize: CGFloat
        weak var textView: NSTextView?
        var contentManager: MarkdownTextContentManager?
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
                await MainActor.run { [weak self, weak textView] in
                    guard let self, let tv = textView, let cm = self.contentManager else { return }
                    Self.applySpans(spans, to: tv, baseFontSize: baseFontSize, contentManager: cm)
                }
            }
        }

        private static func applySpans(
            _ spans: [HighlightSpan],
            to textView: NSTextView,
            baseFontSize: CGFloat,
            contentManager: MarkdownTextContentManager
        ) {
            guard let storage = textView.textStorage else { return }
            let storageLength = storage.length
            guard storageLength > 0 else { return }

            let updateRange: NSRange
            if spans.isEmpty {
                updateRange = NSRange(location: 0, length: storageLength)
            } else {
                var minLoc = storageLength
                var maxEnd = 0
                for span in spans {
                    let r = span.range
                    guard r.location >= 0, r.location + r.length <= storageLength else { continue }
                    minLoc = min(minLoc, r.location)
                    maxEnd = max(maxEnd, r.location + r.length)
                }
                if minLoc <= maxEnd {
                    updateRange = NSRange(location: minLoc, length: maxEnd - minLoc)
                } else {
                    updateRange = NSRange(location: 0, length: storageLength)
                }
            }

            contentManager.performMarkdownEdit {
                storage.setAttributes([
                    .font: NSFont.systemFont(ofSize: baseFontSize),
                    .foregroundColor: NSColor.labelColor
                ], range: updateRange)
                for span in spans {
                    let r = span.range
                    guard r.location >= 0, r.location + r.length <= storageLength else { continue }
                    storage.addAttributes([
                        .font: span.font,
                        .foregroundColor: span.color ?? .labelColor,
                        .backgroundColor: span.backgroundColor ?? .clear,
                        .strikethroughStyle: span.strikethrough ? 1 : 0
                    ], range: r)
                }
            }
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
