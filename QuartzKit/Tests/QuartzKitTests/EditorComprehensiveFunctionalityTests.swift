import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Comprehensive Editor Functionality Tests
// These tests cover EVERY user-facing editor action to catch regressions.

// ============================================================================
// MARK: - Section 1: All Formatting Actions (24 Actions)
// ============================================================================

@Suite("EditorFormattingComplete")
struct EditorFormattingCompleteTests {
    let formatter = MarkdownFormatter()

    // MARK: - Wrap Actions (6)

    @Test("Bold: wrap selected text")
    func boldWrapSelection() {
        let (result, sel) = formatter.apply(.bold, to: "hello world", selectedRange: NSRange(location: 0, length: 5))
        #expect(result == "**hello** world")
        #expect(sel.location == 2)
        #expect(sel.length == 5)
    }

    @Test("Bold: toggle off when already bold")
    func boldToggleOff() {
        let (result, _) = formatter.apply(.bold, to: "**hello** world", selectedRange: NSRange(location: 2, length: 5))
        #expect(result == "hello world")
    }

    @Test("Bold: insert markers at cursor (empty selection)")
    func boldEmptySelection() {
        let (result, sel) = formatter.apply(.bold, to: "hello", selectedRange: NSRange(location: 5, length: 0))
        #expect(result == "hello****")
        #expect(sel.location == 7) // cursor between markers
    }

    @Test("Italic: wrap selected text")
    func italicWrapSelection() {
        let (result, sel) = formatter.apply(.italic, to: "hello world", selectedRange: NSRange(location: 0, length: 5))
        #expect(result == "*hello* world")
        #expect(sel.location == 1)
    }

    @Test("Italic: toggle off when already italic")
    func italicToggleOff() {
        let (result, _) = formatter.apply(.italic, to: "*hello* world", selectedRange: NSRange(location: 1, length: 5))
        #expect(result == "hello world")
    }

    @Test("Strikethrough: wrap selected text")
    func strikethroughWrapSelection() {
        let (result, _) = formatter.apply(.strikethrough, to: "delete this", selectedRange: NSRange(location: 7, length: 4))
        #expect(result == "delete ~~this~~")
    }

    @Test("Strikethrough: toggle off")
    func strikethroughToggleOff() {
        let (result, _) = formatter.apply(.strikethrough, to: "~~crossed~~", selectedRange: NSRange(location: 2, length: 7))
        #expect(result == "crossed")
    }

    @Test("Inline code: wrap selected text")
    func codeWrapSelection() {
        let (result, _) = formatter.apply(.code, to: "call print() here", selectedRange: NSRange(location: 5, length: 7))
        #expect(result == "call `print()` here")
    }

    @Test("Inline code: toggle off")
    func codeToggleOff() {
        let (result, _) = formatter.apply(.code, to: "`code`", selectedRange: NSRange(location: 1, length: 4))
        #expect(result == "code")
    }

    @Test("Highlight: wrap with ==")
    func highlightWrapSelection() {
        let (result, _) = formatter.apply(.highlight, to: "important text", selectedRange: NSRange(location: 0, length: 9))
        #expect(result == "==important== text")
    }

    @Test("Math: wrap with $")
    func mathWrapSelection() {
        let (result, _) = formatter.apply(.math, to: "E=mc2", selectedRange: NSRange(location: 0, length: 5))
        #expect(result == "$E=mc2$")
    }

    // MARK: - Line Prefix Actions (6)

    @Test("Heading: add # prefix")
    func headingPrefix() {
        let (result, _) = formatter.apply(.heading, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "# Title")
    }

    @Test("Heading: toggle off # prefix")
    func headingToggleOff() {
        let (result, _) = formatter.apply(.heading, to: "# Title", selectedRange: NSRange(location: 2, length: 0))
        #expect(result == "Title")
    }

    @Test("Heading1: add # prefix")
    func heading1Prefix() {
        let (result, _) = formatter.apply(.heading1, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "# Title")
    }

    @Test("Heading2: add ## prefix")
    func heading2Prefix() {
        let (result, _) = formatter.apply(.heading2, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "## Title")
    }

    @Test("Heading3: add ### prefix")
    func heading3Prefix() {
        let (result, _) = formatter.apply(.heading3, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "### Title")
    }

    @Test("Heading4: add #### prefix")
    func heading4Prefix() {
        let (result, _) = formatter.apply(.heading4, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "#### Title")
    }

    @Test("Heading5: add ##### prefix")
    func heading5Prefix() {
        let (result, _) = formatter.apply(.heading5, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "##### Title")
    }

    @Test("Heading6: add ###### prefix")
    func heading6Prefix() {
        let (result, _) = formatter.apply(.heading6, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "###### Title")
    }

    @Test("Paragraph: remove heading prefix")
    func paragraphRemovesHeading() {
        let (result, _) = formatter.apply(.paragraph, to: "## Title", selectedRange: NSRange(location: 3, length: 0))
        #expect(result == "Title")
    }

    @Test("Paragraph: keeps plain text unchanged")
    func paragraphKeepsPlainText() {
        let (result, _) = formatter.apply(.paragraph, to: "Plain text", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "Plain text")
    }

    @Test("Bullet list: add - prefix")
    func bulletListPrefix() {
        let (result, _) = formatter.apply(.bulletList, to: "Item", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "- Item")
    }

    @Test("Bullet list: toggle off - prefix")
    func bulletListToggleOff() {
        let (result, _) = formatter.apply(.bulletList, to: "- Item", selectedRange: NSRange(location: 2, length: 0))
        #expect(result == "Item")
    }

    @Test("Numbered list: add 1. prefix")
    func numberedListPrefix() {
        let (result, _) = formatter.apply(.numberedList, to: "Item", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "1. Item")
    }

    @Test("Numbered list: toggle off 1. prefix")
    func numberedListToggleOff() {
        let (result, _) = formatter.apply(.numberedList, to: "1. Item", selectedRange: NSRange(location: 3, length: 0))
        #expect(result == "Item")
    }

    @Test("Checkbox: add - [ ] prefix")
    func checkboxPrefix() {
        let (result, _) = formatter.apply(.checkbox, to: "Task", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "- [ ] Task")
    }

    @Test("Checkbox: toggle off - [ ] prefix")
    func checkboxToggleOff() {
        let (result, _) = formatter.apply(.checkbox, to: "- [ ] Task", selectedRange: NSRange(location: 6, length: 0))
        #expect(result == "Task")
    }

    @Test("Blockquote: add > prefix")
    func blockquotePrefix() {
        let (result, _) = formatter.apply(.blockquote, to: "Quote", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "> Quote")
    }

    @Test("Blockquote: toggle off > prefix")
    func blockquoteToggleOff() {
        let (result, _) = formatter.apply(.blockquote, to: "> Quote", selectedRange: NSRange(location: 2, length: 0))
        #expect(result == "Quote")
    }

    // MARK: - Block Actions (2)

    @Test("Code block: wrap with fences")
    func codeBlockWrap() {
        let (result, _) = formatter.apply(.codeBlock, to: "let x = 1", selectedRange: NSRange(location: 0, length: 9))
        #expect(result.hasPrefix("```\n"))
        #expect(result.contains("let x = 1"))
        #expect(result.hasSuffix("\n```"))
    }

    @Test("Mermaid: wrap with mermaid fence")
    func mermaidBlockWrap() {
        let (result, _) = formatter.apply(.mermaid, to: "graph TD", selectedRange: NSRange(location: 0, length: 8))
        #expect(result.hasPrefix("```mermaid\n"))
        #expect(result.contains("graph TD"))
        #expect(result.hasSuffix("\n```"))
    }

    // MARK: - Template Actions (3)

    @Test("Link: wrap text with [text](url)")
    func linkTemplate() {
        let (result, _) = formatter.apply(.link, to: "click here", selectedRange: NSRange(location: 0, length: 10))
        #expect(result == "[click here](url)")
    }

    @Test("Link: empty selection creates placeholder")
    func linkEmptySelection() {
        let (result, sel) = formatter.apply(.link, to: "", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "[](url)")
        #expect(sel.location == 1) // cursor inside []
    }

    @Test("Image: wrap text with ![alt](path)")
    func imageTemplate() {
        let (result, _) = formatter.apply(.image, to: "photo", selectedRange: NSRange(location: 0, length: 5))
        #expect(result == "![photo](path)")
    }

    @Test("Footnote: create [^ref]: template")
    func footnoteTemplate() {
        let (result, _) = formatter.apply(.footnote, to: "1", selectedRange: NSRange(location: 0, length: 1))
        #expect(result == "[^1]: ")
    }

    // MARK: - Insert Actions (1)

    @Test("Table: insert markdown table")
    func tableInsert() {
        let (result, _) = formatter.apply(.table, to: "", selectedRange: NSRange(location: 0, length: 0))
        #expect(result.contains("| Column 1 |"))
        #expect(result.contains("| --- |"))
        #expect(result.contains("| Cell 1 |"))
    }
}

// ============================================================================
// MARK: - Section 2: List Continuation (Enter Key Behavior)
// ============================================================================

@Suite("EditorListContinuationComplete")
struct EditorListContinuationCompleteTests {
    let engine = MarkdownListContinuation()

    // MARK: - Bullet Lists (all markers)

    @Test("Bullet (-): continue on enter")
    func bulletDashContinue() {
        let result = engine.handleNewline(in: "- item", cursorPosition: 6)
        #expect(result?.newText == "- item\n- ")
    }

    @Test("Bullet (*): continue on enter")
    func bulletAsteriskContinue() {
        let result = engine.handleNewline(in: "* item", cursorPosition: 6)
        #expect(result?.newText == "* item\n* ")
    }

    @Test("Bullet (+): continue on enter")
    func bulletPlusContinue() {
        let result = engine.handleNewline(in: "+ item", cursorPosition: 6)
        #expect(result?.newText == "+ item\n+ ")
    }

    @Test("Bullet: exit list on empty marker line")
    func bulletExitOnEmpty() {
        let result = engine.handleNewline(in: "- item\n- ", cursorPosition: 9)
        #expect(result?.newText == "- item\n\n")
    }

    // MARK: - Numbered Lists

    @Test("Numbered: continue with incremented number")
    func numberedContinue() {
        let result = engine.handleNewline(in: "1. first", cursorPosition: 8)
        #expect(result?.newText == "1. first\n2. ")
    }

    @Test("Numbered: 9 -> 10 increment")
    func numberedNineToTen() {
        let result = engine.handleNewline(in: "9. ninth", cursorPosition: 8)
        #expect(result?.newText == "9. ninth\n10. ")
    }

    @Test("Numbered: exit list on empty marker line")
    func numberedExitOnEmpty() {
        let result = engine.handleNewline(in: "1. item\n2. ", cursorPosition: 11)
        #expect(result?.newText == "1. item\n\n")
    }

    // MARK: - Checkboxes

    @Test("Checkbox unchecked: continue unchecked")
    func checkboxUncheckedContinue() {
        let result = engine.handleNewline(in: "- [ ] task", cursorPosition: 10)
        #expect(result?.newText == "- [ ] task\n- [ ] ")
    }

    @Test("Checkbox checked: continue unchecked")
    func checkboxCheckedContinuesUnchecked() {
        let result = engine.handleNewline(in: "- [x] done", cursorPosition: 10)
        #expect(result?.newText == "- [x] done\n- [ ] ")
    }

    @Test("Checkbox: exit list on empty")
    func checkboxExitOnEmpty() {
        let result = engine.handleNewline(in: "- [ ] task\n- [ ] ", cursorPosition: 17)
        #expect(result?.newText == "- [ ] task\n\n")
    }

    // MARK: - Blockquotes

    @Test("Blockquote: continue on enter")
    func blockquoteContinue() {
        let result = engine.handleNewline(in: "> quote", cursorPosition: 7)
        #expect(result?.newText == "> quote\n> ")
    }

    @Test("Blockquote nested: continue nested")
    func blockquoteNestedContinue() {
        let result = engine.handleNewline(in: "> > nested", cursorPosition: 10)
        #expect(result?.newText == "> > nested\n> > ")
    }

    @Test("Blockquote: exit on empty")
    func blockquoteExitOnEmpty() {
        let result = engine.handleNewline(in: "> text\n> ", cursorPosition: 9)
        #expect(result?.newText == "> text\n\n")
    }

    // MARK: - Indentation Preservation

    @Test("Bullet indented 2 spaces: preserve indent")
    func bulletIndentedSpaces() {
        let result = engine.handleNewline(in: "  - nested", cursorPosition: 10)
        #expect(result?.newText == "  - nested\n  - ")
    }

    @Test("Bullet indented tab: preserve tab")
    func bulletIndentedTab() {
        let result = engine.handleNewline(in: "\t- tabbed", cursorPosition: 9)
        #expect(result?.newText == "\t- tabbed\n\t- ")
    }

    @Test("Numbered indented: preserve indent")
    func numberedIndented() {
        let result = engine.handleNewline(in: "   1. indented", cursorPosition: 14)
        #expect(result?.newText == "   1. indented\n   2. ")
    }

    // MARK: - Cursor in Middle of Line

    @Test("Cursor middle of bullet: split and continue")
    func cursorMiddleBullet() {
        let result = engine.handleNewline(in: "- hello world", cursorPosition: 8) // after "- hello "
        #expect(result?.newText == "- hello \n- world")
    }

    @Test("Cursor at marker end: continue with rest")
    func cursorAtMarkerEnd() {
        let result = engine.handleNewline(in: "- item", cursorPosition: 2) // right after "- "
        #expect(result?.newText == "- \n- item")
    }

    // MARK: - Non-List Lines (No Interception)

    @Test("Plain text: no interception")
    func plainTextNoInterception() {
        let result = engine.handleNewline(in: "plain text", cursorPosition: 10)
        #expect(result == nil)
    }

    @Test("Heading: no interception")
    func headingNoInterception() {
        let result = engine.handleNewline(in: "# Heading", cursorPosition: 9)
        #expect(result == nil)
    }

    @Test("Code fence: no interception")
    func codeFenceNoInterception() {
        let result = engine.handleNewline(in: "```swift", cursorPosition: 8)
        #expect(result == nil)
    }

    @Test("Horizontal rule: no interception")
    func horizontalRuleNoInterception() {
        let result = engine.handleNewline(in: "---", cursorPosition: 3)
        #expect(result == nil)
    }
}

// ============================================================================
// MARK: - Section 3: Selection & Cursor Behavior
// ============================================================================

@Suite("EditorSelectionBehavior")
struct EditorSelectionBehaviorTests {
    let formatter = MarkdownFormatter()

    // MARK: - Selection Preservation After Formatting

    @Test("Bold: selection stays on wrapped text")
    func boldSelectionPreserved() {
        let (_, sel) = formatter.apply(.bold, to: "Hello world", selectedRange: NSRange(location: 6, length: 5))
        // "Hello **world**" - selection should be on "world"
        #expect(sel.location == 8)
        #expect(sel.length == 5)
    }

    @Test("Italic: selection stays on wrapped text")
    func italicSelectionPreserved() {
        let (_, sel) = formatter.apply(.italic, to: "Hello world", selectedRange: NSRange(location: 6, length: 5))
        // "Hello *world*" - selection should be on "world"
        #expect(sel.location == 7)
        #expect(sel.length == 5)
    }

    @Test("Heading: cursor stays in content")
    func headingCursorPosition() {
        let (_, sel) = formatter.apply(.heading, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        // "# Title" - cursor should be at start of "Title"
        #expect(sel.location == 2)
    }

    @Test("Bullet: cursor stays in content")
    func bulletCursorPosition() {
        let (_, sel) = formatter.apply(.bulletList, to: "Item", selectedRange: NSRange(location: 0, length: 0))
        // "- Item" - cursor should be at start of "Item"
        #expect(sel.location == 2)
    }

    // MARK: - Multi-line Selection

    @Test("Bold on partial multi-line: only first line affected")
    func boldMultiLineSelection() {
        let text = "Line one\nLine two"
        let (result, _) = formatter.apply(.bold, to: text, selectedRange: NSRange(location: 0, length: 8))
        #expect(result == "**Line one**\nLine two")
    }

    @Test("Heading on second line: only second line gets prefix")
    func headingSecondLine() {
        let text = "Line one\nLine two"
        let (result, _) = formatter.apply(.heading, to: text, selectedRange: NSRange(location: 9, length: 0))
        #expect(result == "Line one\n# Line two")
    }

    // MARK: - Edge Cases

    @Test("Selection at document start")
    func selectionAtStart() {
        let (result, sel) = formatter.apply(.bold, to: "text", selectedRange: NSRange(location: 0, length: 4))
        #expect(result == "**text**")
        #expect(sel.location == 2)
    }

    @Test("Selection at document end")
    func selectionAtEnd() {
        let (result, _) = formatter.apply(.bold, to: "some text", selectedRange: NSRange(location: 5, length: 4))
        #expect(result == "some **text**")
    }

    @Test("Empty document: bold inserts markers")
    func emptyDocumentBold() {
        let (result, sel) = formatter.apply(.bold, to: "", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "****")
        #expect(sel.location == 2)
    }

    @Test("Empty document: heading inserts prefix")
    func emptyDocumentHeading() {
        let (result, _) = formatter.apply(.heading, to: "", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "# ")
    }
}

// ============================================================================
// MARK: - Section 4: Unicode & Special Characters
// ============================================================================

@Suite("EditorUnicodeHandling")
struct EditorUnicodeHandlingTests {
    let formatter = MarkdownFormatter()
    let engine = MarkdownListContinuation()

    @Test("Bold: Chinese characters")
    func boldChinese() {
        let (result, _) = formatter.apply(.bold, to: "Hello world", selectedRange: NSRange(location: 6, length: 5))
        #expect(result.contains("**"))
    }

    @Test("Bold: emoji content")
    func boldEmoji() {
        let (result, _) = formatter.apply(.bold, to: "Hello world", selectedRange: NSRange(location: 0, length: 5))
        #expect(result.contains("**Hello**"))
    }

    @Test("List continuation: Chinese bullet item")
    func listContinuationChinese() {
        let text = "- Apple"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText.hasSuffix("- ") == true)
    }

    @Test("List continuation: emoji bullet item")
    func listContinuationEmoji() {
        let text = "- Party item"
        let result = engine.handleNewline(in: text, cursorPosition: text.count)
        #expect(result?.newText.hasSuffix("- ") == true)
    }

    @Test("Bold: RTL text (Arabic)")
    func boldArabic() {
        let text = "Hello world"
        let (result, _) = formatter.apply(.bold, to: text, selectedRange: NSRange(location: 0, length: 5))
        #expect(result.contains("**"))
    }
}

// ============================================================================
// MARK: - Section 5: FormattingAction Metadata
// ============================================================================

@Suite("EditorFormattingActionMetadata")
struct EditorFormattingActionMetadataTests {

    @Test("All 24 actions exist")
    func allActionsExist() {
        #expect(FormattingAction.allCases.count == 24)
    }

    @Test("All actions have icons")
    func allActionsHaveIcons() {
        for action in FormattingAction.allCases {
            #expect(!action.icon.isEmpty, "\(action) missing icon")
        }
    }

    @Test("All actions have labels")
    func allActionsHaveLabels() {
        for action in FormattingAction.allCases {
            #expect(!action.label.isEmpty, "\(action) missing label")
        }
    }

    @Test("Primary actions have keyboard shortcuts")
    func primaryActionsHaveShortcuts() {
        let withShortcuts: [FormattingAction] = [.bold, .italic, .strikethrough, .heading, .paragraph, .code, .link, .blockquote]
        for action in withShortcuts {
            #expect(action.shortcut != nil, "\(action) should have shortcut")
        }
    }

    @Test("Keyboard shortcut format is correct")
    func shortcutFormatCorrect() {
        #expect(FormattingAction.bold.shortcut == "\u{2318}B")
        #expect(FormattingAction.italic.shortcut == "\u{2318}I")
    }
}

// ============================================================================
// MARK: - Section 6: Table Operations
// ============================================================================

@Suite("EditorTableOperations")
struct EditorTableOperationsTests {
    let formatter = MarkdownFormatter()

    @Test("Table insert creates 3-column table")
    func tableInsertStructure() {
        let (result, _) = formatter.apply(.table, to: "", selectedRange: NSRange(location: 0, length: 0))

        let lines = result.components(separatedBy: "\n")
        #expect(lines.count >= 3) // header, divider, at least one row

        // Check header row
        #expect(lines[0].contains("Column 1"))
        #expect(lines[0].contains("Column 2"))
        #expect(lines[0].contains("Column 3"))

        // Check divider
        #expect(lines[1].contains("---"))

        // Check body row
        #expect(lines[2].contains("Cell"))
    }

    @Test("Table insert at non-empty location")
    func tableInsertNonEmpty() {
        let (result, _) = formatter.apply(.table, to: "Text before", selectedRange: NSRange(location: 11, length: 0))
        #expect(result.hasPrefix("Text before"))
        #expect(result.contains("| Column 1 |"))
    }
}

// ============================================================================
// MARK: - Section 7: Code Block Language Handling
// ============================================================================

@Suite("EditorCodeBlockLanguage")
struct EditorCodeBlockLanguageTests {
    let formatter = MarkdownFormatter()

    @Test("Code block: default no language")
    func codeBlockDefaultNoLanguage() {
        let (result, _) = formatter.apply(.codeBlock, to: "code", selectedRange: NSRange(location: 0, length: 4))
        #expect(result.hasPrefix("```\n"))
    }

    @Test("Mermaid block: includes mermaid language")
    func mermaidBlockHasLanguage() {
        let (result, _) = formatter.apply(.mermaid, to: "graph TD", selectedRange: NSRange(location: 0, length: 8))
        #expect(result.hasPrefix("```mermaid\n"))
    }
}

// ============================================================================
// MARK: - Section 8: Frontmatter Tag Handling
// ============================================================================

@Suite("EditorFrontmatterTags")
struct EditorFrontmatterTagsTests {

    @Test("Frontmatter: can add tags")
    func frontmatterAddTags() {
        var fm = Frontmatter(title: "Test")
        fm.tags = ["swift", "testing"]
        #expect(fm.tags.count == 2)
    }

    @Test("Frontmatter: can remove tags")
    func frontmatterRemoveTags() {
        var fm = Frontmatter(title: "Test")
        fm.tags = ["swift", "testing", "quartz"]
        fm.tags.removeAll { $0 == "testing" }
        #expect(fm.tags == ["swift", "quartz"])
    }

    @Test("Frontmatter: empty tags array")
    func frontmatterEmptyTags() {
        let fm = Frontmatter(title: "Test")
        #expect(fm.tags.isEmpty)
    }
}

// ============================================================================
// MARK: - Section 9: Focus Mode
// ============================================================================

@Suite("EditorFocusMode")
struct EditorFocusModeTests {

    @Test("FocusModeManager: default state is off")
    @MainActor
    func focusModeDefaultOff() {
        UserDefaults.standard.removeObject(forKey: "quartz.editor.focusModeActive")
        let manager = FocusModeManager()
        #expect(manager.isFocusModeActive == false)
    }

    @Test("FocusModeManager: toggle changes state")
    @MainActor
    func focusModeToggle() {
        UserDefaults.standard.removeObject(forKey: "quartz.editor.focusModeActive")
        let manager = FocusModeManager()
        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == true)
        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == false)
    }

    @Test("TypewriterMode: default state is off")
    @MainActor
    func typewriterModeDefaultOff() {
        UserDefaults.standard.removeObject(forKey: "quartz.editor.typewriterModeActive")
        let manager = FocusModeManager()
        #expect(manager.isTypewriterModeActive == false)
    }

    @Test("TypewriterMode: toggle changes state")
    @MainActor
    func typewriterModeToggle() {
        UserDefaults.standard.removeObject(forKey: "quartz.editor.typewriterModeActive")
        let manager = FocusModeManager()
        manager.toggleTypewriterMode()
        #expect(manager.isTypewriterModeActive == true)
    }
}

// ============================================================================
// MARK: - Section 10: XCTest Performance Baselines
// ============================================================================

final class EditorComprehensivePerformanceTests: XCTestCase {

    func testFormattingAllActions100Times() throws {
        let formatter = MarkdownFormatter()
        let text = "Hello world this is a test"
        let selection = NSRange(location: 6, length: 5)

        measure {
            for _ in 0..<100 {
                for action in FormattingAction.allCases {
                    _ = formatter.apply(action, to: text, selectedRange: selection)
                }
            }
        }
    }

    func testListContinuation1000Times() throws {
        let engine = MarkdownListContinuation()
        let text = "- item"

        measure {
            for _ in 0..<1000 {
                _ = engine.handleNewline(in: text, cursorPosition: text.count)
            }
        }
    }

    func testFormattingLargeDocument() throws {
        let formatter = MarkdownFormatter()
        let text = String(repeating: "word ", count: 10_000)
        let selection = NSRange(location: 5000, length: 100)

        measure {
            _ = formatter.apply(.bold, to: text, selectedRange: selection)
        }
    }

    func testListContinuationLargeDocument() throws {
        let engine = MarkdownListContinuation()
        var text = ""
        for i in 0..<1000 {
            text += "- item \(i)\n"
        }
        text += "- current"

        measure {
            _ = engine.handleNewline(in: text, cursorPosition: text.count)
        }
    }
}
