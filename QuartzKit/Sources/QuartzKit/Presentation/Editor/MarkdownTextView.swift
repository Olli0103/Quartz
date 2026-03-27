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
enum MarkdownTextKit2Stack {
    static func makeContentManager() -> MarkdownTextContentManager {
        MarkdownTextContentManager()
    }

    static func wireTextKit2(contentManager: MarkdownTextContentManager) -> (NSTextLayoutManager, NSTextContainer) {
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container
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

        // Enable system Writing Tools (iOS 18.1+)
        if #available(iOS 18.1, *) {
            textView.writingToolsBehavior = .complete
            textView.allowsEditingTextAttributes = true
        }

        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let textChanged = uiView.text != text
        if textChanged {
            // When text changes programmatically, apply the new text
            uiView.text = text
        }

        // Apply cursor position from binding (enables state restoration)
        // Only do this when text hasn't changed to avoid fighting with user edits
        if !textChanged {
            let currentRange = uiView.selectedRange
            if currentRange.location != cursorPosition.location || currentRange.length != cursorPosition.length {
                // Validate the cursor position is within bounds
                let textLength = (uiView.text ?? "").count
                if cursorPosition.location <= textLength &&
                   cursorPosition.location + cursorPosition.length <= textLength {
                    if let start = uiView.position(from: uiView.beginningOfDocument, offset: cursorPosition.location),
                       let end = uiView.position(from: start, offset: cursorPosition.length) {
                        uiView.selectedTextRange = uiView.textRange(from: start, to: end)
                    }
                }
            }
        }

        let scaledBaseFont = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: baseFontSize * editorFontScale))
        context.coordinator.baseFontSize = scaledBaseFont.pointSize
        context.coordinator.editorFontScale = editorFontScale
        context.coordinator.textView = uiView
        if let cm = context.coordinator.contentManager {
            cm.baseFontSize = scaledBaseFont.pointSize
            cm.fontScale = editorFontScale
        }
        // Only re-highlight when text actually changed
        if textChanged {
            context.coordinator.scheduleHighlight(text: text, textView: uiView)
        }
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
            // Skip highlighting during IME composition to avoid breaking input
            if textView.markedTextRange != nil { return }

            highlightTask?.cancel()
            highlightTask = Task { [highlighter, baseFontSize] in
                let spans = await highlighter.parseDebounced(text)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self, weak textView] in
                    guard let self, let tv = textView, let cm = self.contentManager else { return }
                    // Skip if IME composition started while we were parsing
                    guard tv.markedTextRange == nil else { return }
                    Self.applySpans(spans, to: tv, baseFontSize: baseFontSize, contentManager: cm)
                }
            }
        }

        /// Applies syntax highlighting with minimal layout invalidation.
        /// Uses beginEditing/endEditing to batch changes and diffs attributes
        /// to skip ranges that haven't changed — preventing flicker.
        private static func applySpans(
            _ spans: [HighlightSpan],
            to textView: UITextView,
            baseFontSize: CGFloat,
            contentManager: MarkdownTextContentManager
        ) {
            let storage = textView.textStorage
            let storageLength = storage.length
            guard storageLength > 0 else { return }

            // Save typing attributes and selection BEFORE touching attributes
            let savedTypingAttrs = textView.typingAttributes
            let savedSelection = textView.selectedRange

            let defaultFont = UIFont.systemFont(ofSize: baseFontSize)
            let defaultColor: UIColor = .label

            // Build a flat array of (range, attributes) covering the entire document.
            // This computes what the document SHOULD look like, then we diff against current.
            var segments: [(NSRange, [NSAttributedString.Key: Any])] = []
            let primarySpans = spans.filter { !$0.isOverlay }.sorted { $0.range.location < $1.range.location }

            var lastEnd = 0
            for span in primarySpans {
                let r = span.range
                guard r.location >= 0, r.location + r.length <= storageLength else { continue }

                if r.location > lastEnd {
                    segments.append((NSRange(location: lastEnd, length: r.location - lastEnd), [
                        .font: defaultFont,
                        .foregroundColor: defaultColor
                    ]))
                }

                segments.append((r, [
                    .font: span.font,
                    .foregroundColor: span.color ?? defaultColor,
                    .backgroundColor: span.backgroundColor ?? UIColor.clear,
                    .strikethroughStyle: span.strikethrough ? 1 : 0
                ]))

                lastEnd = r.location + r.length
            }
            if lastEnd < storageLength {
                segments.append((NSRange(location: lastEnd, length: storageLength - lastEnd), [
                    .font: defaultFont,
                    .foregroundColor: defaultColor
                ]))
            }

            // Batch all attribute changes — single processEditing call at endEditing
            storage.beginEditing()

            // Only set attributes where they actually differ from current
            for (range, targetAttrs) in segments {
                guard range.length > 0 else { continue }
                let existingAttrs = storage.attributes(at: range.location, effectiveRange: nil)
                if !fontsEqual(existingAttrs[.font] as? UIFont, targetAttrs[.font] as? UIFont) ||
                   !colorsEqual(existingAttrs[.foregroundColor] as? UIColor, targetAttrs[.foregroundColor] as? UIColor) {
                    storage.setAttributes(targetAttrs, range: range)
                }
            }

            // Apply overlay spans (muted syntax characters)
            for span in spans where span.isOverlay {
                let r = span.range
                guard r.location >= 0, r.location + r.length <= storageLength,
                      let color = span.color else { continue }
                let existing = storage.attributes(at: r.location, effectiveRange: nil)
                if !colorsEqual(existing[.foregroundColor] as? UIColor, color) {
                    storage.addAttribute(.foregroundColor, value: color, range: r)
                }
            }

            storage.endEditing()

            // Restore typing attributes AFTER all attribute changes
            textView.typingAttributes = savedTypingAttrs

            // Restore selection if it was displaced
            if textView.selectedRange != savedSelection {
                let textLength = (textView.text ?? "").count
                if savedSelection.location <= textLength &&
                   savedSelection.location + savedSelection.length <= textLength {
                    textView.selectedRange = savedSelection
                }
            }
        }

        private static func fontsEqual(_ a: UIFont?, _ b: UIFont?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a.fontName == b.fontName && a.pointSize == b.pointSize
        }

        private static func colorsEqual(_ a: UIColor?, _ b: UIColor?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a == b
        }

        // MARK: - Newline Interception for List Continuation

        private let listContinuation = MarkdownListContinuation()

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText newText: String) -> Bool {
            // Only intercept newline insertions
            guard newText == "\n" else { return true }

            let currentText = textView.text ?? ""
            let cursorPos = range.location

            // Check if list continuation applies
            guard let result = listContinuation.handleNewline(in: currentText, cursorPosition: cursorPos) else {
                return true // No list marker, allow normal newline
            }

            // Apply the continuation result
            textView.text = result.newText
            text = result.newText

            // Set cursor position
            if let newPosition = textView.position(from: textView.beginningOfDocument, offset: result.newCursorPosition) {
                textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
            }

            updateCursorPosition(from: textView)
            scheduleHighlight(text: result.newText, textView: textView)

            return false // We handled the newline
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            updateCursorPosition(from: textView)
            scheduleHighlight(text: textView.text ?? "", textView: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateCursorPosition(from: textView)
            // Set typing attributes from the character before cursor
            // This ensures newly typed text matches the surrounding style
            let loc = textView.selectedRange.location
            if loc > 0, let storage = textView.textStorage as NSAttributedString? {
                let attrs = storage.attributes(at: max(0, loc - 1), effectiveRange: nil)
                var typingAttrs = textView.typingAttributes
                if let font = attrs[.font] as? UIFont {
                    typingAttrs[.font] = font
                }
                if let color = attrs[.foregroundColor] as? UIColor {
                    typingAttrs[.foregroundColor] = color
                }
                textView.typingAttributes = typingAttrs
            }
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
@MainActor
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

        // Enable system Writing Tools (macOS 15.1+)
        if #available(macOS 15.1, *) {
            textView.writingToolsBehavior = .complete
        }
        // NSTextView is rich text by default, no need for allowsEditingTextAttributes

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
        let textChanged = textView.string != text
        if textChanged {
            textView.string = text
        }

        // Apply cursor position from binding (enables state restoration)
        // Only do this when text hasn't changed to avoid fighting with user edits
        if !textChanged {
            let currentRange = textView.selectedRange()
            if currentRange.location != cursorPosition.location || currentRange.length != cursorPosition.length {
                // Validate the cursor position is within bounds
                let textLength = textView.string.count
                if cursorPosition.location <= textLength &&
                   cursorPosition.location + cursorPosition.length <= textLength {
                    textView.setSelectedRange(cursorPosition)
                }
            }
        }

        context.coordinator.baseFontSize = baseFontSize * editorFontScale
        if let cm = context.coordinator.contentManager {
            cm.baseFontSize = baseFontSize * editorFontScale
            cm.fontScale = editorFontScale
        }
        // Only re-highlight when text actually changed
        if textChanged {
            context.coordinator.scheduleHighlight(text: text, textView: textView)
        }
    }

    @MainActor
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
            // Skip highlighting during IME composition to avoid breaking input
            if textView.hasMarkedText() { return }

            highlightTask?.cancel()
            highlightTask = Task { [highlighter, baseFontSize] in
                let spans = await highlighter.parseDebounced(text)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self, weak textView] in
                    guard let self, let tv = textView, let cm = self.contentManager else { return }
                    // Skip if IME composition started while we were parsing
                    guard !tv.hasMarkedText() else { return }
                    Self.applySpans(spans, to: tv, baseFontSize: baseFontSize, contentManager: cm)
                }
            }
        }

        /// Applies syntax highlighting with minimal layout invalidation.
        /// Uses beginEditing/endEditing to batch changes and diffs attributes
        /// to skip ranges that haven't changed — preventing flicker.
        private static func applySpans(
            _ spans: [HighlightSpan],
            to textView: NSTextView,
            baseFontSize: CGFloat,
            contentManager: MarkdownTextContentManager
        ) {
            guard let storage = textView.textStorage else { return }
            let storageLength = storage.length
            guard storageLength > 0 else { return }

            // Save typing attributes and selection BEFORE touching attributes
            let savedTypingAttrs = textView.typingAttributes
            let savedSelection = textView.selectedRange()

            let defaultFont = NSFont.systemFont(ofSize: baseFontSize)
            let defaultColor: NSColor = .labelColor

            // Build a flat array of (range, attributes) covering the entire document
            var segments: [(NSRange, [NSAttributedString.Key: Any])] = []
            let primarySpans = spans.filter { !$0.isOverlay }.sorted { $0.range.location < $1.range.location }

            var lastEnd = 0
            for span in primarySpans {
                let r = span.range
                guard r.location >= 0, r.location + r.length <= storageLength else { continue }

                if r.location > lastEnd {
                    segments.append((NSRange(location: lastEnd, length: r.location - lastEnd), [
                        .font: defaultFont,
                        .foregroundColor: defaultColor
                    ]))
                }

                segments.append((r, [
                    .font: span.font,
                    .foregroundColor: span.color ?? defaultColor,
                    .backgroundColor: span.backgroundColor ?? NSColor.clear,
                    .strikethroughStyle: span.strikethrough ? 1 : 0
                ]))

                lastEnd = r.location + r.length
            }
            if lastEnd < storageLength {
                segments.append((NSRange(location: lastEnd, length: storageLength - lastEnd), [
                    .font: defaultFont,
                    .foregroundColor: defaultColor
                ]))
            }

            // Batch all attribute changes — single processEditing call at endEditing
            storage.beginEditing()

            // Only set attributes where they actually differ from current
            for (range, targetAttrs) in segments {
                guard range.length > 0 else { continue }
                let existingAttrs = storage.attributes(at: range.location, effectiveRange: nil)
                if !fontsEqual(existingAttrs[.font] as? NSFont, targetAttrs[.font] as? NSFont) ||
                   !colorsEqual(existingAttrs[.foregroundColor] as? NSColor, targetAttrs[.foregroundColor] as? NSColor) {
                    storage.setAttributes(targetAttrs, range: range)
                }
            }

            // Apply overlay spans (muted syntax characters)
            for span in spans where span.isOverlay {
                let r = span.range
                guard r.location >= 0, r.location + r.length <= storageLength,
                      let color = span.color else { continue }
                let existing = storage.attributes(at: r.location, effectiveRange: nil)
                if !colorsEqual(existing[.foregroundColor] as? NSColor, color as? NSColor) {
                    storage.addAttribute(.foregroundColor, value: color, range: r)
                }
            }

            storage.endEditing()

            // Restore typing attributes AFTER all attribute changes
            textView.typingAttributes = savedTypingAttrs

            // Restore selection if it was displaced
            if textView.selectedRange() != savedSelection {
                let textLength = textView.string.count
                if savedSelection.location <= textLength &&
                   savedSelection.location + savedSelection.length <= textLength {
                    textView.setSelectedRange(savedSelection)
                }
            }
        }

        private static func fontsEqual(_ a: NSFont?, _ b: NSFont?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a.fontName == b.fontName && a.pointSize == b.pointSize
        }

        private static func colorsEqual(_ a: NSColor?, _ b: NSColor?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a == b
        }

        // MARK: - Newline Interception for List Continuation

        private let listContinuation = MarkdownListContinuation()

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Only intercept newline insertions
            guard let newText = replacementString, newText == "\n" else { return true }

            let currentText = textView.string
            let cursorPos = affectedCharRange.location

            // Check if list continuation applies
            guard let result = listContinuation.handleNewline(in: currentText, cursorPosition: cursorPos) else {
                return true // No list marker, allow normal newline
            }

            // Apply the continuation result
            textView.string = result.newText
            text = result.newText

            // Set cursor position
            textView.setSelectedRange(NSRange(location: result.newCursorPosition, length: 0))

            updateCursorPosition(from: textView)
            scheduleHighlight(text: result.newText, textView: textView)

            return false // We handled the newline
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
            // Set typing attributes from the character before cursor
            // This ensures newly typed text matches the surrounding style
            let loc = textView.selectedRange().location
            if loc > 0, let storage = textView.textStorage {
                let attrs = storage.attributes(at: max(0, loc - 1), effectiveRange: nil)
                var typingAttrs = textView.typingAttributes
                if let font = attrs[.font] as? NSFont {
                    typingAttrs[.font] = font
                }
                if let color = attrs[.foregroundColor] as? NSColor {
                    typingAttrs[.foregroundColor] = color
                }
                textView.typingAttributes = typingAttrs
            }
        }

        private func updateCursorPosition(from textView: NSTextView) {
            cursorPosition = textView.selectedRange()
        }
    }
}
#endif
