import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Native text view bridge for the EditorSession-based editor.
///
/// **Critical architectural difference from `MarkdownTextViewRepresentable`:**
/// - No `@Binding var text` — the native text view is the source of truth.
/// - `updateUIView` / `updateNSView` **never writes text** to the view.
/// - All text mutations go through `EditorSession.applyExternalEdit`.
/// - Delegate callbacks flow text snapshots back to `EditorSession.textDidChange`.
///
/// This eliminates the SwiftUI → TextKit feedback cycle that caused cursor jitter.
#if os(iOS)
public struct MarkdownEditorRepresentable: UIViewRepresentable {
    let session: EditorSession
    var editorFontScale: CGFloat
    var editorFontFamily: AppearanceManager.EditorFontFamily = .system
    var editorLineSpacing: CGFloat = 1.5
    var editorMaxWidth: CGFloat = 720

    public init(
        session: EditorSession,
        editorFontScale: CGFloat = 1.0,
        editorFontFamily: AppearanceManager.EditorFontFamily = .system,
        editorLineSpacing: CGFloat = 1.5,
        editorMaxWidth: CGFloat = 720
    ) {
        self.session = session
        self.editorFontScale = editorFontScale
        self.editorFontFamily = editorFontFamily
        self.editorLineSpacing = editorLineSpacing
        self.editorMaxWidth = editorMaxWidth
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeUIView(context: Context) -> UITextView {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        let textView = UITextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator

        let baseFont = EditorFontFactory.makeFont(family: editorFontFamily, size: baseFontSize)
        textView.font = UIFontMetrics.default.scaledFont(for: baseFont)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true

        if #available(iOS 18.1, *) {
            textView.writingToolsBehavior = .complete
            textView.allowsEditingTextAttributes = true
        }

        // One-time initial text load
        textView.text = session.currentText

        // Wire session to text view (weak ref)
        session.activeTextView = textView
        session.contentManager = contentManager
        session.highlighter = MarkdownASTHighlighter(baseFontSize: baseFontSize)
        session.highlighterBaseFontSize = baseFontSize
        session.highlighterFontFamily = editorFontFamily
        session.highlighterLineSpacing = editorLineSpacing
        Task { [editorFontFamily, editorLineSpacing] in
            await session.highlighter?.updateSettings(fontFamily: editorFontFamily, lineSpacing: editorLineSpacing)
        }

        // Trigger initial highlighting
        session.scheduleHighlight()

        context.coordinator.textView = textView
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        let needsRehighlight = coordinator.lastFontScale != editorFontScale
            || coordinator.lastFontFamily != editorFontFamily
            || coordinator.lastLineSpacing != editorLineSpacing

        if needsRehighlight {
            // Update base font and metrics
            let newFont = EditorFontFactory.makeFont(family: editorFontFamily, size: baseFontSize)
            uiView.font = UIFontMetrics.default.scaledFont(for: newFont)

            session.contentManager?.baseFontSize = baseFontSize
            session.contentManager?.fontScale = editorFontScale
            session.highlighterBaseFontSize = baseFontSize
            session.highlighterFontFamily = editorFontFamily
            session.highlighterLineSpacing = editorLineSpacing
            Task { [editorFontFamily, editorLineSpacing] in
                await session.highlighter?.updateSettings(fontFamily: editorFontFamily, lineSpacing: editorLineSpacing)
            }

            // Re-highlight with new font settings
            session.scheduleHighlight()

            coordinator.lastFontScale = editorFontScale
            coordinator.lastFontFamily = editorFontFamily
            coordinator.lastLineSpacing = editorLineSpacing
        }

        // Dynamic max-width inset
        let viewWidth = uiView.bounds.width
        let minPadding: CGFloat = 16
        if viewWidth > editorMaxWidth + (minPadding * 2) {
            let horizontalInset = (viewWidth - editorMaxWidth) / 2
            uiView.textContainerInset = UIEdgeInsets(top: 16, left: horizontalInset, bottom: 16, right: horizontalInset)
        } else {
            uiView.textContainerInset = UIEdgeInsets(top: 16, left: minPadding, bottom: 16, right: minPadding)
        }
    }

    private var baseFontSize: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).pointSize * editorFontScale
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        let session: EditorSession
        weak var textView: UITextView?
        private let listContinuation = MarkdownListContinuation()
        private var scrollThrottleTask: Task<Void, Never>?
        var lastFontScale: CGFloat = -1
        var lastFontFamily: AppearanceManager.EditorFontFamily = .system
        var lastLineSpacing: CGFloat = -1

        init(session: EditorSession) {
            self.session = session
            super.init()
        }

        // MARK: - Scroll Tracking (UITextView inherits UIScrollView)

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Throttle to 100ms to avoid excessive heading lookups
            guard scrollThrottleTask == nil else { return }
            scrollThrottleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.scrollThrottleTask = nil
            }
            guard let textView = scrollView as? UITextView else { return }
            let topPoint = CGPoint(
                x: textView.textContainerInset.left,
                y: textView.contentOffset.y + textView.textContainerInset.top
            )
            if let topPosition = textView.closestPosition(to: topPoint) {
                let offset = textView.offset(from: textView.beginningOfDocument, to: topPosition)
                session.viewportDidScroll(topCharacterOffset: offset)
            }
        }

        // MARK: - Newline Interception (List Continuation)

        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText newText: String) -> Bool {
            guard newText == "\n" else { return true }
            // Don't intercept during IME composition
            guard textView.markedTextRange == nil else { return true }

            let currentText = textView.text ?? ""
            guard let result = listContinuation.handleNewline(in: currentText, cursorPosition: range.location) else {
                return true
            }

            // SURGICAL insert via EditorSession (not full text replacement)
            session.applyExternalEdit(
                replacement: result.insertionText,
                range: result.replacementRange,
                cursorAfter: NSRange(location: result.newCursorPosition, length: 0)
            )
            return false
        }

        // MARK: - Text Did Change

        public func textViewDidChange(_ textView: UITextView) {
            session.textDidChange(textView.text ?? "")
        }

        // MARK: - Selection Did Change

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange else { return }
            let loc = textView.offset(from: textView.beginningOfDocument, to: range.start)
            let len = textView.offset(from: range.start, to: range.end)
            session.selectionDidChange(NSRange(location: loc, length: len))
        }
    }
}

#elseif os(macOS)

public struct MarkdownEditorRepresentable: NSViewRepresentable {
    let session: EditorSession
    var editorFontScale: CGFloat
    var editorFontFamily: AppearanceManager.EditorFontFamily = .system
    var editorLineSpacing: CGFloat = 1.5
    var editorMaxWidth: CGFloat = 720

    public init(
        session: EditorSession,
        editorFontScale: CGFloat = 1.0,
        editorFontFamily: AppearanceManager.EditorFontFamily = .system,
        editorLineSpacing: CGFloat = 1.5,
        editorMaxWidth: CGFloat = 720
    ) {
        self.session = session
        self.editorFontScale = editorFontScale
        self.editorFontFamily = editorFontFamily
        self.editorLineSpacing = editorLineSpacing
        self.editorMaxWidth = editorMaxWidth
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.font = EditorFontFactory.makeFont(family: editorFontFamily, size: baseFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if #available(macOS 15.1, *) {
            textView.writingToolsBehavior = .complete
        }

        // One-time initial text load
        textView.string = session.currentText

        // Wire session to text view (weak ref)
        session.activeTextView = textView
        session.contentManager = contentManager
        session.highlighter = MarkdownASTHighlighter(baseFontSize: baseFontSize)
        session.highlighterBaseFontSize = baseFontSize
        session.highlighterFontFamily = editorFontFamily
        session.highlighterLineSpacing = editorLineSpacing
        Task { [editorFontFamily, editorLineSpacing] in
            await session.highlighter?.updateSettings(fontFamily: editorFontFamily, lineSpacing: editorLineSpacing)
        }

        // Trigger initial highlighting
        session.scheduleHighlight()

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Observe scroll position changes for inspector ToC sync
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        // INTENTIONALLY: no text writes. The native view is the source of truth.
        guard let textView = nsView.documentView as? NSTextView else { return }

        let coordinator = context.coordinator
        let needsRehighlight = coordinator.lastFontScale != editorFontScale
            || coordinator.lastFontFamily != editorFontFamily
            || coordinator.lastLineSpacing != editorLineSpacing

        if needsRehighlight {
            // Update base font and metrics
            let newFont = EditorFontFactory.makeFont(family: editorFontFamily, size: baseFontSize)
            textView.font = newFont

            session.contentManager?.baseFontSize = baseFontSize
            session.contentManager?.fontScale = editorFontScale
            session.highlighterBaseFontSize = baseFontSize
            session.highlighterFontFamily = editorFontFamily
            session.highlighterLineSpacing = editorLineSpacing
            Task { [editorFontFamily, editorLineSpacing] in
                await session.highlighter?.updateSettings(fontFamily: editorFontFamily, lineSpacing: editorLineSpacing)
            }

            // Re-highlight with new font settings
            session.scheduleHighlight()

            coordinator.lastFontScale = editorFontScale
            coordinator.lastFontFamily = editorFontFamily
            coordinator.lastLineSpacing = editorLineSpacing
        }

        // Dynamic max-width inset
        let viewWidth = nsView.documentVisibleRect.width
        let minPadding: CGFloat = 16
        if viewWidth > editorMaxWidth + (minPadding * 2) {
            let horizontalInset = (viewWidth - editorMaxWidth) / 2
            textView.textContainerInset = NSSize(width: horizontalInset, height: 16)
        } else {
            textView.textContainerInset = NSSize(width: minPadding, height: 16)
        }
    }

    private var baseFontSize: CGFloat {
        14 * editorFontScale
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        let session: EditorSession
        weak var textView: NSTextView?
        private let listContinuation = MarkdownListContinuation()
        private var scrollThrottleTask: Task<Void, Never>?
        var lastFontScale: CGFloat = -1
        var lastFontFamily: AppearanceManager.EditorFontFamily = .system
        var lastLineSpacing: CGFloat = -1

        init(session: EditorSession) {
            self.session = session
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: - Scroll Tracking

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard scrollThrottleTask == nil else { return }
            scrollThrottleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.scrollThrottleTask = nil
            }
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let visibleRect = scrollView.documentVisibleRect
            let topPoint = NSPoint(x: 0, y: visibleRect.origin.y)
            let charIndex = textView.characterIndexForInsertion(at: topPoint)
            if charIndex != NSNotFound {
                session.viewportDidScroll(topCharacterOffset: charIndex)
            }
        }

        // MARK: - Newline Interception (List Continuation)

        public func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let newText = replacementString, newText == "\n" else { return true }
            guard !textView.hasMarkedText() else { return true }

            let currentText = textView.string
            guard let result = listContinuation.handleNewline(in: currentText, cursorPosition: affectedCharRange.location) else {
                return true
            }

            // SURGICAL insert via EditorSession (not full text replacement)
            session.applyExternalEdit(
                replacement: result.insertionText,
                range: result.replacementRange,
                cursorAfter: NSRange(location: result.newCursorPosition, length: 0)
            )
            return false
        }

        // MARK: - Text Did Change

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.textDidChange(textView.string)
        }

        // MARK: - Selection Did Change

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.selectionDidChange(textView.selectedRange())
        }
    }
}

#endif

// MarkdownTextKit2Stack is defined in MarkdownTextView.swift and shared by both representables.
