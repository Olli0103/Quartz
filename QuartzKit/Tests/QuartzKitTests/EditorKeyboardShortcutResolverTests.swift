import XCTest
@testable import QuartzKit

final class EditorKeyboardShortcutResolverTests: XCTestCase {
    func testResolvesInlineFormattingShortcuts() {
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "b", modifiers: .command),
            .formatting(.bold)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "i", modifiers: .command),
            .formatting(.italic)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "x", modifiers: [.command, .shift]),
            .formatting(.strikethrough)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "l", modifiers: [.command, .shift]),
            .formatting(.link)
        )
    }

    func testResolvesHeadingAndParagraphShortcuts() {
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "2", modifiers: .command),
            .formatting(.heading2)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "0", modifiers: .command),
            .formatting(.paragraph)
        )
    }

    func testResolvesCodeAndPasteShortcuts() {
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "e", modifiers: [.command, .alternate]),
            .formatting(.code)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "e", modifiers: [.command, .shift]),
            .formatting(.codeBlock)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "v", modifiers: [.command, .alternate]),
            .paste(.smart)
        )
        XCTAssertEqual(
            EditorKeyboardShortcutResolver.resolve(input: "v", modifiers: [.command, .shift]),
            .paste(.raw)
        )
    }

    func testReturnsNilForUnsupportedShortcut() {
        XCTAssertNil(EditorKeyboardShortcutResolver.resolve(input: "b", modifiers: []))
        XCTAssertNil(EditorKeyboardShortcutResolver.resolve(input: "z", modifiers: .command))
    }
}
