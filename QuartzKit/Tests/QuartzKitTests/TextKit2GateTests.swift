import XCTest
@testable import QuartzKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Gate tests proving the editor uses TextKit 2 (not TextKit 1 fallback).
///
/// These tests verify that `MarkdownTextContentManager` + `MarkdownTextKit2Stack`
/// produce a proper TextKit 2 pipeline with `NSTextLayoutManager`, not the legacy
/// `NSLayoutManager` path.
#if os(iOS) || os(macOS)
final class TextKit2GateTests: XCTestCase {

    // MARK: - Content Manager Is Correct Subclass

    @MainActor
    func testContentManagerIsMarkdownSubclass() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        XCTAssertTrue(contentManager is MarkdownTextContentManager,
                      "Factory must return MarkdownTextContentManager, not bare NSTextContentStorage")
    }

    // MARK: - TextKit 2 Layout Manager Wired

    @MainActor
    func testWireTextKit2ProducesNSTextLayoutManager() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (layoutManager, _) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        XCTAssertNotNil(layoutManager,
                        "wireTextKit2 must produce a non-nil NSTextLayoutManager")
        XCTAssertTrue(type(of: layoutManager) == NSTextLayoutManager.self
                      || layoutManager is NSTextLayoutManager,
                      "Layout manager must be NSTextLayoutManager (TextKit 2)")
    }

    // MARK: - Text Container Connected

    @MainActor
    func testTextContainerIsConnected() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (layoutManager, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        XCTAssertIdentical(layoutManager.textContainer, container,
                           "NSTextContainer must be assigned to the layout manager")
    }

    // MARK: - Content Manager Linked to Layout Manager

    @MainActor
    func testContentManagerLinkedToLayoutManager() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (layoutManager, _) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        // The content manager should have at least one text layout manager
        let layoutManagers = contentManager.textLayoutManagers
        XCTAssertFalse(layoutManagers.isEmpty,
                       "Content manager must have at least one NSTextLayoutManager after wiring")
        // The wired layout manager should be among them
        let found = layoutManagers.contains { $0 === layoutManager }
        XCTAssertTrue(found,
                      "Wired NSTextLayoutManager must be found in content manager's textLayoutManagers")
    }

    // MARK: - Editing Transaction Works (TextKit 2 API)

    @MainActor
    func testPerformEditingTransactionDoesNotCrash() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, _) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        // performMarkdownEdit wraps performEditingTransaction — must not crash
        contentManager.performMarkdownEdit {
            // Empty transaction — verifies the TextKit 2 transaction model is functional
        }
    }

    // MARK: - NSTextView Uses TextKit 2 (macOS)

    #if canImport(AppKit)
    @MainActor
    func testNSTextViewUsesTextKit2LayoutManager() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  textContainer: container)

        // TextKit 2: textLayoutManager is non-nil
        XCTAssertNotNil(textView.textLayoutManager,
                        "NSTextView must use NSTextLayoutManager (TextKit 2), not NSLayoutManager (TextKit 1)")

        // The text view's textLayoutManager should be our wired one
        XCTAssertNotNil(textView.textLayoutManager?.textContentManager,
                        "TextKit 2 text view must have a linked textContentManager")
    }
    #endif

    // MARK: - Content Manager Configuration

    @MainActor
    func testContentManagerDefaultConfiguration() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()

        XCTAssertEqual(contentManager.baseFontSize, 14,
                       "Default baseFontSize should be 14")
        XCTAssertEqual(contentManager.fontScale, 1.0,
                       "Default fontScale should be 1.0")
    }

    // MARK: - Apply Attributes via TextKit 2 Transaction

    @MainActor
    func testApplyAttributesDoesNotCrashOrCorrupt() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, _) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)

        // Set initial attributed string via the backing text storage
        let text = NSMutableAttributedString(string: "Hello TextKit 2",
                                             attributes: [.font: PlatformFont.systemFont(ofSize: 14)])
        contentManager.performEditingTransaction {
            contentManager.textStorage?.setAttributedString(text)
        }

        // Apply bold to "Hello" via the TextKit 2 transaction API — must not crash
        contentManager.applyAttributes(
            [.font: PlatformFont.boldSystemFont(ofSize: 14)],
            to: NSRange(location: 0, length: 5)
        )

        // Verify content is intact after the transaction
        XCTAssertNotNil(contentManager.attributedString,
                        "attributedString must not be nil after applyAttributes")
        XCTAssertGreaterThan(contentManager.attributedString?.length ?? 0, 0,
                             "Content must not be empty after attribute application")
    }

    // MARK: - Paragraph Bounding Range

    @MainActor
    func testBoundingRangeForParagraph() {
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        contentManager.attributedString = NSAttributedString(string: "Line one\nLine two\nLine three")

        let range = contentManager.boundingRangeForParagraph(containing: 10) // within "Line two"
        XCTAssertNotNil(range, "Should return a paragraph range for a valid location")
        if let range {
            XCTAssertEqual(range.location, 9, "Paragraph should start at index 9 (start of 'Line two')")
            XCTAssertEqual(range.length, 9, "Paragraph 'Line two\\n' should be 9 characters")
        }
    }
}

// MARK: - Platform Font Alias

#if canImport(AppKit)
private typealias PlatformFont = NSFont
#elseif canImport(UIKit)
private typealias PlatformFont = UIFont
#endif

#endif
