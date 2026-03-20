import Testing
import Foundation
@testable import QuartzKit

@Suite("MarkdownListContinuation")
struct MarkdownListContinuationTests {
    let engine = MarkdownListContinuation()

    // MARK: - Bullet List Continuation

    @Test("Bullet dash continues on newline")
    func bulletDashContinues() {
        let text = "- item one"
        let cursorAt = text.count // end of line
        let result = engine.handleNewline(in: text, cursorPosition: cursorAt)
        #expect(result?.newText == "- item one\n- ")
        #expect(result?.newCursorPosition == text.count + 3) // after "- "
    }

    @Test("Bullet asterisk continues on newline")
    func bulletAsteriskContinues() {
        let text = "* item one"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "* item one\n* ")
        #expect(result?.newCursorPosition == text.count + 3)
    }

    @Test("Bullet plus continues on newline")
    func bulletPlusContinues() {
        let text = "+ item one"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "+ item one\n+ ")
        #expect(result?.newCursorPosition == text.count + 3)
    }

    @Test("Bullet with leading space continues with same indent")
    func bulletIndentedContinues() {
        let text = "  - nested item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "  - nested item\n  - ")
        #expect(result?.newCursorPosition == text.count + 5) // "\n  - " = 5 chars
    }

    @Test("Bullet with tab indent continues with same indent")
    func bulletTabIndentContinues() {
        let text = "\t- tabbed item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "\t- tabbed item\n\t- ")
        #expect(result?.newCursorPosition == text.count + 4)
    }

    // MARK: - Numbered List Continuation

    @Test("Numbered list continues with incremented number")
    func numberedListIncrements() {
        let text = "1. first item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "1. first item\n2. ")
        #expect(result?.newCursorPosition == text.count + 4) // "\n2. " = 4 chars
    }

    @Test("Numbered list at 9 increments to 10")
    func numberedListNineToTen() {
        let text = "9. ninth item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "9. ninth item\n10. ")
        #expect(result?.newCursorPosition == text.count + 5) // "\n10. " = 5 chars
    }

    @Test("Numbered list preserves indent")
    func numberedListIndented() {
        let text = "   3. indented number"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "   3. indented number\n   4. ")
        #expect(result?.newCursorPosition == text.count + 7) // "\n   4. " = 7 chars
    }

    // MARK: - Checkbox Continuation

    @Test("Unchecked checkbox continues unchecked")
    func uncheckedCheckboxContinues() {
        let text = "- [ ] todo item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "- [ ] todo item\n- [ ] ")
        #expect(result?.newCursorPosition == text.count + 7) // "\n- [ ] " = 7 chars
    }

    @Test("Checked checkbox continues unchecked")
    func checkedCheckboxContinuesUnchecked() {
        let text = "- [x] done item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "- [x] done item\n- [ ] ")
        #expect(result?.newCursorPosition == text.count + 7)
    }

    @Test("Checkbox with asterisk marker continues")
    func checkboxAsteriskContinues() {
        let text = "* [ ] task"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "* [ ] task\n* [ ] ")
        #expect(result?.newCursorPosition == text.count + 7)
    }

    // MARK: - Empty Marker Line (Exit List)

    @Test("Empty bullet line removes marker")
    func emptyBulletExits() {
        let text = "- item\n- "
        let cursorAt = text.count // at end after "- "
        let result = engine.handleNewline(in: text, cursorPosition: cursorAt)
        #expect(result?.newText == "- item\n\n")
        #expect(result?.newCursorPosition == 8) // after the two newlines
    }

    @Test("Empty numbered line removes marker")
    func emptyNumberedExits() {
        let text = "1. item\n2. "
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "1. item\n\n")
        #expect(result?.newCursorPosition == 9)
    }

    @Test("Empty checkbox line removes marker")
    func emptyCheckboxExits() {
        let text = "- [ ] task\n- [ ] "
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "- [ ] task\n\n")
        #expect(result?.newCursorPosition == 12)
    }

    @Test("Empty indented bullet line removes marker and indent")
    func emptyIndentedBulletExits() {
        let text = "  - nested\n  - "
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "  - nested\n\n")
        #expect(result?.newCursorPosition == 12)
    }

    // MARK: - Non-List Lines

    @Test("Plain text returns nil (no interception)")
    func plainTextNoInterception() {
        let text = "just some text"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result == nil)
    }

    @Test("Line starting with dash but no space returns nil")
    func dashNoSpaceNoInterception() {
        let text = "-not a list"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result == nil)
    }

    @Test("Code block marker returns nil")
    func codeBlockNoInterception() {
        let text = "```swift"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result == nil)
    }

    // MARK: - Cursor in Middle of Line

    @Test("Cursor in middle of bullet item inserts newline with continuation")
    func cursorMiddleBullet() {
        let text = "- hello world"
        let cursorAt = 8 // after "- hello "
        let result = engine.handleNewline(in: text, cursorPosition: cursorAt)
        #expect(result?.newText == "- hello \n- world")
        #expect(result?.newCursorPosition == 11) // after "- hello \n- "
    }

    @Test("Cursor at start of bullet text continues normally")
    func cursorStartBulletText() {
        let text = "- item"
        let cursorAt = 2 // right after "- "
        let result = engine.handleNewline(in: text, cursorPosition: cursorAt)
        #expect(result?.newText == "- \n- item")
        #expect(result?.newCursorPosition == 5) // after "- \n- "
    }

    // MARK: - Multi-Line Context

    @Test("Continuation works with preceding lines")
    func multiLineContext() {
        let text = "# Heading\n\n- first\n- second"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "# Heading\n\n- first\n- second\n- ")
        #expect(result?.newCursorPosition == text.count + 3)
    }

    @Test("Continuation only affects current line")
    func onlyAffectsCurrentLine() {
        let text = "plain line\n- bullet"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "plain line\n- bullet\n- ")
    }

    // MARK: - Blockquote Continuation

    @Test("Blockquote continues on newline")
    func blockquoteContinues() {
        let text = "> quoted text"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "> quoted text\n> ")
        #expect(result?.newCursorPosition == text.count + 3)
    }

    @Test("Empty blockquote line exits")
    func emptyBlockquoteExits() {
        let text = "> quote\n> "
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "> quote\n\n")
    }

    @Test("Nested blockquote continues nested")
    func nestedBlockquoteContinues() {
        let text = "> > nested quote"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText == "> > nested quote\n> > ")
    }
}
