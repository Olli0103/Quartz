import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Native text view bridge for the EditorSession-based editor.
///
/// **Key architectural property:**
/// - No `@Binding var text` — the native text view is the source of truth.
/// - `updateUIView` / `updateNSView` **never writes text** to the view.
/// - All text mutations go through `EditorSession.applyExternalEdit`.
/// - Delegate callbacks flow text snapshots back to `EditorSession.textDidChange`.
///
/// This eliminates the SwiftUI → TextKit feedback cycle that causes cursor jitter.
#if os(iOS)
@MainActor
final class MarkdownEditorUITextView: UITextView {
    weak var editorSession: EditorSession?
    var hidesInsertionPointForSnapshots = false

    override func caretRect(for position: UITextPosition) -> CGRect {
        if hidesInsertionPointForSnapshots {
            return .zero
        }
        return super.caretRect(for: position)
    }

    override func paste(_ sender: Any?) {
        guard let editorSession else {
            super.paste(sender)
            return
        }
        editorSession.paste(mode: .smart)
    }
}

public struct MarkdownEditorRepresentable: UIViewRepresentable {
    let session: EditorSession
    var editorFontScale: CGFloat
    var editorFontFamily: AppearanceManager.EditorFontFamily = EditorTypography.defaultFontFamily
    var editorLineSpacing: CGFloat = EditorTypography.defaultLineSpacingMultiplier
    var editorMaxWidth: CGFloat = EditorTypography.defaultMaxWidth
    var syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret

    public init(
        session: EditorSession,
        editorFontScale: CGFloat = 1.0,
        editorFontFamily: AppearanceManager.EditorFontFamily = EditorTypography.defaultFontFamily,
        editorLineSpacing: CGFloat = EditorTypography.defaultLineSpacingMultiplier,
        editorMaxWidth: CGFloat = EditorTypography.defaultMaxWidth,
        syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret
    ) {
        self.session = session
        self.editorFontScale = editorFontScale
        self.editorFontFamily = editorFontFamily
        self.editorLineSpacing = editorLineSpacing
        self.editorMaxWidth = editorMaxWidth
        self.syntaxVisibilityMode = syntaxVisibilityMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeUIView(context: Context) -> UITextView {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        let textView = MarkdownEditorUITextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.editorSession = session

        let baseFont = EditorFontFactory.makeFont(family: editorFontFamily, size: baseFontSize)
        textView.font = UIFontMetrics.default.scaledFont(for: baseFont)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 18, bottom: 24, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true

        // iOS-specific: interactive keyboard dismiss and fluid scrolling
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true

        if #available(iOS 18.1, *) {
            textView.writingToolsBehavior = .complete
            textView.allowsEditingTextAttributes = true
        }

        // One-time initial text load
        textView.text = session.currentText

        // Add tap gesture for wiki-link navigation
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)

        // Wire session to text view (weak ref)
        session.activeTextView = textView
        session.contentManager = contentManager
        session.highlighter = MarkdownASTHighlighter(baseFontSize: baseFontSize)
        session.highlighterBaseFontSize = baseFontSize
        session.highlighterFontFamily = editorFontFamily
        session.highlighterLineSpacing = editorLineSpacing
        session.syntaxVisibilityMode = syntaxVisibilityMode
        Task { [editorFontFamily, editorLineSpacing] in
            await session.highlighter?.updateSettings(fontFamily: editorFontFamily, lineSpacing: editorLineSpacing)
        }

        // Trigger initial highlighting (no debounce — instant)
        session.highlightImmediately()

        context.coordinator.textView = textView
        context.coordinator.lastFontScale = editorFontScale
        context.coordinator.lastFontFamily = editorFontFamily
        context.coordinator.lastLineSpacing = editorLineSpacing
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
        let minPadding: CGFloat = 18
        if viewWidth > editorMaxWidth + (minPadding * 2) {
            let horizontalInset = (viewWidth - editorMaxWidth) / 2
            uiView.textContainerInset = UIEdgeInsets(top: 20, left: horizontalInset, bottom: 24, right: horizontalInset)
        } else {
            uiView.textContainerInset = UIEdgeInsets(top: 20, left: minPadding, bottom: 24, right: minPadding)
        }
    }

    private var baseFontSize: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).pointSize * editorFontScale
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let session: EditorSession
        weak var textView: UITextView?
        private let listContinuation = MarkdownListContinuation()
        private let tableNavigation = MarkdownTableNavigation()
        private var scrollThrottleTask: Task<Void, Never>?
        var lastFontScale: CGFloat = -1
        var lastFontFamily: AppearanceManager.EditorFontFamily = .system
        var lastLineSpacing: CGFloat = -1

        init(session: EditorSession) {
            self.session = session
            super.init()
        }

        // MARK: - Wiki-Link Tap

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let point = gesture.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let charIndex = textView.offset(from: textView.beginningOfDocument, to: position)
            guard charIndex >= 0, charIndex < textView.textStorage.length else { return }

            if let linkedTitle = textView.textStorage.attribute(.quartzWikiLink, at: charIndex, effectiveRange: nil) as? String {
                session.navigateToWikiLink(title: linkedTitle)
            }
        }

        /// Allow the tap gesture to work simultaneously with the text view's built-in gestures.
        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
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
            // Don't intercept during IME composition
            guard textView.markedTextRange == nil else { return true }

            // Tab interception for table navigation
            if newText == "\t" {
                let currentText = textView.text ?? ""
                if let result = tableNavigation.handleTab(in: currentText, cursorPosition: range.location, isShiftTab: false) {
                    if let insertion = result.newRowInsertion {
                        session.applyExternalEdit(
                            replacement: insertion.rowText,
                            range: NSRange(location: insertion.insertionPoint, length: 0),
                            cursorAfter: result.selectionRange,
                            origin: .tableNavigation
                        )
                    } else {
                        textView.selectedRange = result.selectionRange
                    }
                    return false
                }
            }

            // Newline interception for list continuation
            guard newText == "\n" else { return true }

            let currentText = textView.text ?? ""
            guard let result = listContinuation.handleNewline(in: currentText, cursorPosition: range.location) else {
                return true
            }

            // SURGICAL insert via EditorSession (not full text replacement)
            session.applyExternalEdit(
                replacement: result.insertionText,
                range: result.replacementRange,
                cursorAfter: NSRange(location: result.newCursorPosition, length: 0),
                origin: .listContinuation
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

// MARK: - Custom NSTextView Subclass (Drag-and-Drop)

/// Custom NSTextView subclass that intercepts file drops (images, PDFs) and
/// imports them into the vault as Markdown links. Regular text drags pass through
/// to the standard NSTextView behavior.
///
/// Also overrides `drawBackground(in:)` to render uniform-width table blocks
/// with zebra striping, header shading, and rounded borders.
@MainActor
final class MarkdownEditorNSTextView: NSTextView {
    weak var editorSession: EditorSession?

    /// Info about a single table line's layout for custom drawing.
    private struct TableLineInfo {
        let rect: CGRect
        let style: QuartzTableRowStyle
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Custom Table Background Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let storage = textStorage, let layoutManager = textLayoutManager,
              let contentStorage = layoutManager.textContentManager as? NSTextContentStorage else { return }

        // The text container origin transforms fragment coords → view coords.
        // layoutFragmentFrame is in the text container's coordinate space.
        let origin = textContainerOrigin

        // Collect all table line fragments grouped into contiguous table blocks
        var tableBlocks: [[TableLineInfo]] = []
        var currentBlock: [TableLineInfo] = []
        let docStart = layoutManager.documentRange.location

        // NOTE: Do NOT use .ensuresLayout here — we're inside drawBackground,
        // and triggering layout during drawing causes recursion warnings.
        // Layout should already be complete by the time we're drawing.
        layoutManager.enumerateTextLayoutFragments(
            from: docStart,
            options: []
        ) { fragment in
            let charOffset = contentStorage.offset(from: docStart, to: fragment.rangeInElement.location)
            guard charOffset >= 0, charOffset < storage.length else {
                if !currentBlock.isEmpty {
                    tableBlocks.append(currentBlock)
                    currentBlock = []
                }
                return true
            }

            if let styleRaw = storage.attribute(.quartzTableRowStyle, at: charOffset, effectiveRange: nil) as? Int,
               let style = QuartzTableRowStyle(rawValue: styleRaw) {
                currentBlock.append(TableLineInfo(rect: fragment.layoutFragmentFrame, style: style))
            } else {
                if !currentBlock.isEmpty {
                    tableBlocks.append(currentBlock)
                    currentBlock = []
                }
            }
            return true
        }
        if !currentBlock.isEmpty {
            tableBlocks.append(currentBlock)
        }

        guard !tableBlocks.isEmpty else { return }

        // Colors — adaptive for light/dark mode
        let headerBg = NSColor.controlBackgroundColor.blended(
            withFraction: 0.06, of: NSColor.labelColor
        ) ?? NSColor.controlBackgroundColor
        let altRowBg = NSColor.controlBackgroundColor.blended(
            withFraction: 0.025, of: NSColor.labelColor
        ) ?? NSColor.controlBackgroundColor
        let borderColor = NSColor.separatorColor
        let dividerLineColor = NSColor.separatorColor

        let hPad: CGFloat = 8 // horizontal padding around the table block

        for block in tableBlocks {
            guard !block.isEmpty else { continue }

            // Compute uniform bounding box from ALL fragments in this table block.
            // Fragment rects are in text container coords — apply origin to get view coords.
            let trueMinX = block.map { $0.rect.minX }.min()! + origin.x
            let trueMaxRight = block.map { $0.rect.maxX }.max()! + origin.x
            let trueMaxWidth = trueMaxRight - trueMinX
            let trueMinY = block.first!.rect.minY + origin.y
            let trueMaxY = block.last!.rect.maxY + origin.y

            let tableBounds = NSRect(
                x: trueMinX - hPad,
                y: trueMinY,
                width: trueMaxWidth + hPad * 2,
                height: trueMaxY - trueMinY
            )

            // Draw each row background at uniform width
            for line in block {
                let lineY = line.rect.minY + origin.y
                let lineH = line.rect.height
                let rowRect = NSRect(x: tableBounds.minX, y: lineY, width: tableBounds.width, height: lineH)

                switch line.style {
                case .header:
                    headerBg.setFill()
                    rowRect.fill()
                case .divider:
                    // 1px horizontal separator at the vertical center of the divider row
                    let separatorY = lineY + lineH / 2
                    let linePath = NSBezierPath()
                    linePath.move(to: NSPoint(x: tableBounds.minX + 4, y: separatorY))
                    linePath.line(to: NSPoint(x: tableBounds.maxX - 4, y: separatorY))
                    linePath.lineWidth = 1
                    dividerLineColor.setStroke()
                    linePath.stroke()
                case .bodyEven:
                    break // transparent
                case .bodyOdd:
                    altRowBg.setFill()
                    rowRect.fill()
                }
            }

            // Outer border: subtle rounded rectangle
            let borderRect = tableBounds.insetBy(dx: -1, dy: -1)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 4, yRadius: 4)
            borderPath.lineWidth = 0.5
            borderColor.setStroke()
            borderPath.stroke()
        }
    }

    // MARK: - Table Tab Navigation

    private let tableNavigation = MarkdownTableNavigation()

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertTab(_:)) || selector == #selector(insertBacktab(_:)) {
            let isShiftTab = selector == #selector(insertBacktab(_:))
            let cursor = selectedRange().location
            if let result = tableNavigation.handleTab(in: string, cursorPosition: cursor, isShiftTab: isShiftTab) {
                if let insertion = result.newRowInsertion {
                    // Insert new row, then select first cell
                    editorSession?.applyExternalEdit(
                        replacement: insertion.rowText,
                        range: NSRange(location: insertion.insertionPoint, length: 0),
                        cursorAfter: result.selectionRange,
                        origin: .tableNavigation
                    )
                } else {
                    // Just move selection to target cell
                    setSelectedRange(result.selectionRange)
                }
                return
            }
        }
        super.doCommand(by: selector)
    }

    override func paste(_ sender: Any?) {
        guard let editorSession else {
            super.paste(sender)
            return
        }
        editorSession.paste(mode: .smart)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let editorSession else {
            super.pasteAsPlainText(sender)
            return
        }
        editorSession.paste(mode: .raw)
    }

    // MARK: - Wiki-Link Click Interception

    override func mouseDown(with event: NSEvent) {
        // Only intercept single-clicks (not double-click for word selection)
        guard event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        guard charIndex != NSNotFound,
              let storage = textStorage,
              charIndex < storage.length else {
            super.mouseDown(with: event)
            return
        }

        // Check if the clicked character has a QuartzWikiLink attribute
        if let linkedTitle = storage.attribute(.quartzWikiLink, at: charIndex, effectiveRange: nil) as? String {
            editorSession?.navigateToWikiLink(title: linkedTitle)
            return
        }

        super.mouseDown(with: event)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(in: sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(in: sender) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let fileURLs = extractSupportedFileURLs(from: sender), !fileURLs.isEmpty else {
            // Not a file drop we handle — let NSTextView handle text/RTF drags
            return super.performDragOperation(sender)
        }

        guard let session = editorSession,
              let vaultRoot = session.vaultRootURL,
              let noteURL = session.note?.fileURL else {
            return false
        }

        // Calculate the character index at the drop point
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let charIndex = characterIndexForInsertion(at: dropPoint)
        guard charIndex != NSNotFound else { return false }

        // Import each file asynchronously
        let assetManager = AssetManager()
        let insertionIndex = charIndex

        Task { @MainActor [weak session] in
            guard let session else { return }

            var markdownFragments: [String] = []

            for fileURL in fileURLs {
                do {
                    let markdownLink = try await assetManager.importAsset(
                        from: fileURL,
                        vaultRoot: vaultRoot,
                        noteURL: noteURL
                    )
                    markdownFragments.append(markdownLink)
                } catch {
                    session.errorMessage = error.localizedDescription
                }
            }

            guard !markdownFragments.isEmpty else { return }

            // Join multiple assets with newlines, ensure surrounding newlines for block elements
            let insertText = markdownFragments.joined(separator: "\n")

            // Ensure we insert on a new line for clean formatting
            let text = session.currentText as NSString
            let needsLeadingNewline = insertionIndex > 0
                && insertionIndex <= text.length
                && text.character(at: insertionIndex - 1) != UInt16(UnicodeScalar("\n").value)
            let needsTrailingNewline = insertionIndex < text.length
                && text.character(at: insertionIndex) != UInt16(UnicodeScalar("\n").value)

            let finalText = (needsLeadingNewline ? "\n" : "")
                + insertText
                + (needsTrailingNewline ? "\n" : "")

            let range = NSRange(location: insertionIndex, length: 0)
            let cursorAfter = NSRange(
                location: insertionIndex + (finalText as NSString).length,
                length: 0
            )

            session.applyExternalEdit(
                replacement: finalText,
                range: range,
                cursorAfter: cursorAfter,
                origin: .pasteOrDrop
            )
        }

        return true
    }

    // MARK: - Helpers

    /// Returns true if the pasteboard contains file URLs with supported extensions.
    private func hasFileURLs(in sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return false
        }
        return urls.contains { AssetManager.isSupportedAsset($0) }
    }

    /// Extracts file URLs with supported media extensions from the drag pasteboard.
    private func extractSupportedFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }
        let supported = urls.filter { AssetManager.isSupportedAsset($0) }
        return supported.isEmpty ? nil : supported
    }
}

public struct MarkdownEditorRepresentable: NSViewRepresentable {
    let session: EditorSession
    var editorFontScale: CGFloat
    var editorFontFamily: AppearanceManager.EditorFontFamily = EditorTypography.defaultFontFamily
    var editorLineSpacing: CGFloat = EditorTypography.defaultLineSpacingMultiplier
    var editorMaxWidth: CGFloat = EditorTypography.defaultMaxWidth
    var syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret

    public init(
        session: EditorSession,
        editorFontScale: CGFloat = 1.0,
        editorFontFamily: AppearanceManager.EditorFontFamily = EditorTypography.defaultFontFamily,
        editorLineSpacing: CGFloat = EditorTypography.defaultLineSpacingMultiplier,
        editorMaxWidth: CGFloat = EditorTypography.defaultMaxWidth,
        syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret
    ) {
        self.session = session
        self.editorFontScale = editorFontScale
        self.editorFontFamily = editorFontFamily
        self.editorLineSpacing = editorLineSpacing
        self.editorMaxWidth = editorMaxWidth
        self.syntaxVisibilityMode = syntaxVisibilityMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        let textView = MarkdownEditorNSTextView(frame: .zero, textContainer: container)
        textView.editorSession = session
        textView.delegate = context.coordinator
        textView.font = EditorFontFactory.makeFont(family: editorFontFamily, size: baseFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
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
        session.syntaxVisibilityMode = syntaxVisibilityMode
        Task { [editorFontFamily, editorLineSpacing] in
            await session.highlighter?.updateSettings(fontFamily: editorFontFamily, lineSpacing: editorLineSpacing)
        }

        // Trigger initial highlighting (no debounce — instant)
        session.highlightImmediately()

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastFontScale = editorFontScale
        context.coordinator.lastFontFamily = editorFontFamily
        context.coordinator.lastLineSpacing = editorLineSpacing

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
        let minPadding: CGFloat = 24
        if viewWidth > editorMaxWidth + (minPadding * 2) {
            let horizontalInset = (viewWidth - editorMaxWidth) / 2
            textView.textContainerInset = NSSize(width: horizontalInset, height: 24)
        } else {
            textView.textContainerInset = NSSize(width: minPadding, height: 24)
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
                cursorAfter: NSRange(location: result.newCursorPosition, length: 0),
                origin: .listContinuation
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
