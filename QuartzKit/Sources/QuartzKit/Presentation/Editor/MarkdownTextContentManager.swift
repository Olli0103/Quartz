import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - TextKit 2 Markdown Content Manager

/// Custom `NSTextContentStorage` subclass for AST-driven markdown in TextKit 2.
///
/// `MarkdownTextView` wires this as the document’s `NSTextContentManager`, with an
/// `NSTextLayoutManager` and `NSTextContainer`. Syntax highlighting applies attributes
/// inside `performMarkdownEdit` / `performEditingTransaction` so layout invalidation stays coherent.
///
/// **Architecture:** Subclasses `NSTextContentStorage`; use `performMarkdownEdit` for
/// attribute passes from `MarkdownASTHighlighter` instead of raw `beginEditing`/`endEditing`.
public final class MarkdownTextContentManager: NSTextContentStorage {

    // MARK: - Configuration

    /// Base font size for markdown rendering. Used when applying AST-derived attributes.
    public var baseFontSize: CGFloat = 14

    /// Scale factor for Dynamic Type / user preference.
    public var fontScale: CGFloat = 1.0

    // MARK: - AST Integration Hooks (Future)

    /// Called when content changes and AST-based attributes should be applied.
    /// Override or set to integrate with `MarkdownASTHighlighter`.
    /// - Parameter range: The range of text that changed (for incremental invalidation).
    public var onContentChangeNeedsASTUpdate: ((NSRange) -> Void)?

    /// The range of text that was last edited. Used for incremental layout invalidation
    /// instead of full-document attribute application.
    public private(set) var lastEditedRange: NSRange = NSRange(location: 0, length: 0)

    // MARK: - Initialization

    public override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Editing Transactions (TextKit 2 Contract)

    /// Wraps content mutations in a transaction so TextKit 2 can coordinate layout.
    /// All edits to `attributedString` must go through this.
    public func performMarkdownEdit(_ block: () -> Void) {
        performEditingTransaction {
            block()
        }
    }

    /// Applies attributes to a specific range. Use this instead of mutating
    /// `attributedString` directly to ensure proper invalidation.
    /// - Parameters:
    ///   - attributes: The attributes to apply.
    ///   - range: The range to update. For performance, prefer the smallest range
    ///     that contains the edited paragraph (see `boundingRangeForParagraph`).
    public func applyAttributes(_ attributes: [NSAttributedString.Key: Any], to range: NSRange) {
        performEditingTransaction {
            let storage = attributedString as? NSMutableAttributedString
            guard let storage, range.location >= 0,
                  range.location + range.length <= storage.length else { return }
            storage.addAttributes(attributes, range: range)
        }
    }

    /// Computes the bounding range of the paragraph containing the given location.
    /// Use for incremental invalidation: only re-apply AST attributes to this range.
    public func boundingRangeForParagraph(containing location: Int) -> NSRange? {
        guard let str = attributedString?.string, !str.isEmpty else { return nil }
        let nsString = str as NSString
        let safeLoc = min(location, nsString.length - 1)
        let lineRange = nsString.lineRange(for: NSRange(location: safeLoc, length: 0))
        return lineRange
    }

    /// Computes the union of paragraph ranges that intersect the given range.
    /// Use when the edited region spans multiple paragraphs.
    public func boundingRangeForParagraphs(intersecting range: NSRange) -> NSRange? {
        guard let str = attributedString?.string, !str.isEmpty else { return nil }
        let nsString = str as NSString
        var start = range.location
        var end = range.location + range.length
        let startLineRange = nsString.lineRange(for: NSRange(location: start, length: 0))
        let endLineRange = nsString.lineRange(for: NSRange(location: min(end, nsString.length - 1), length: 0))
        start = startLineRange.location
        end = endLineRange.location + endLineRange.length
        return NSRange(location: start, length: end - start)
    }

    // MARK: - NSTextContentStorageDelegate Hooks (Future)

    /// Override `textLayoutManager(_:textLayoutFragmentFor:in:)` in a delegate to provide
    /// custom `NSTextLayoutFragment` subclasses for markdown elements (headings, code blocks, etc.).
    /// This enables native TextKit 2 line-fragment invalidation per element.
    ///
    /// Example implementation (not included here):
    /// ```swift
    /// func textLayoutManager(_ layoutManager: NSTextLayoutManager,
    ///                        textLayoutFragmentFor location: NSTextLocation,
    ///                        in textElement: NSTextElement) -> NSTextLayoutFragment? {
    ///     // Return custom MarkdownFragment for headings, code blocks, etc.
    ///     return nil // Use default for now
    /// }
    /// ```
}
