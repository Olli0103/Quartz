import Testing
import Foundation
@testable import QuartzKit

@Suite("MarkdownFormatter")
struct MarkdownFormatterTests {
    let formatter = MarkdownFormatter()

    // MARK: - Wrap Actions

    @Test("Bold wraps with double asterisks")
    func boldWrap() {
        let (result, selection) = formatter.apply(.bold, to: "Hello", selectedRange: NSRange(location: 0, length: 5))
        #expect(result == "**Hello**")
        #expect(selection.location == 2)
        #expect(selection.length == 5)
    }

    @Test("Italic wraps with single asterisk")
    func italicWrap() {
        let (result, _) = formatter.apply(.italic, to: "Hello", selectedRange: NSRange(location: 0, length: 5))
        #expect(result == "*Hello*")
    }

    @Test("Code wraps with backtick")
    func codeWrap() {
        let (result, _) = formatter.apply(.code, to: "let x = 1", selectedRange: NSRange(location: 0, length: 9))
        #expect(result == "`let x = 1`")
    }

    @Test("Bold toggle removes markers")
    func boldToggleOff() {
        let text = "**Hello**"
        let (result, _) = formatter.apply(.bold, to: text, selectedRange: NSRange(location: 2, length: 5))
        #expect(result == "Hello")
    }

    @Test("Bold on empty selection inserts markers")
    func boldEmptySelection() {
        let (result, selection) = formatter.apply(.bold, to: "test", selectedRange: NSRange(location: 4, length: 0))
        #expect(result == "test****")
        #expect(selection.location == 6) // cursor between markers
    }

    // MARK: - Line Prefix Actions

    @Test("Heading adds hash prefix")
    func headingPrefix() {
        let (result, _) = formatter.apply(.heading, to: "Title", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "# Title")
    }

    @Test("Bullet list adds dash prefix")
    func bulletPrefix() {
        let (result, _) = formatter.apply(.bulletList, to: "Item", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "- Item")
    }

    @Test("Numbered list adds number prefix")
    func numberedPrefix() {
        let (result, _) = formatter.apply(.numberedList, to: "Item", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "1. Item")
    }

    @Test("Checkbox adds checkbox prefix")
    func checkboxPrefix() {
        let (result, _) = formatter.apply(.checkbox, to: "Task", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "- [ ] Task")
    }

    @Test("Blockquote adds prefix")
    func blockquotePrefix() {
        let (result, _) = formatter.apply(.blockquote, to: "Quote", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "> Quote")
    }

    @Test("Heading toggle removes prefix")
    func headingToggleOff() {
        let (result, _) = formatter.apply(.heading, to: "# Title", selectedRange: NSRange(location: 2, length: 0))
        #expect(result == "Title")
    }

    @Test("Bullet toggle removes prefix")
    func bulletToggleOff() {
        let (result, _) = formatter.apply(.bulletList, to: "- Item", selectedRange: NSRange(location: 2, length: 0))
        #expect(result == "Item")
    }

    @Test("Bullet action removes non-canonical bullet markers semantically")
    func bulletToggleOffForNonCanonicalMarker() {
        let text = "* Item"
        let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: [])
        let (result, selection) = formatter.apply(
            .bulletList,
            to: text,
            selectedRange: NSRange(location: 2, length: 0),
            semanticDocument: semanticDocument
        )
        #expect(result == "Item")
        #expect(selection.location == 0)
    }

    @Test("Bullet action replaces checkbox syntax semantically")
    func bulletReplacesCheckboxPrefix() {
        let text = "- [ ] Task"
        let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: [])
        let (result, selection) = formatter.apply(
            .bulletList,
            to: text,
            selectedRange: NSRange(location: 6, length: 0),
            semanticDocument: semanticDocument
        )
        #expect(result == "- Task")
        #expect(selection.location == 2)
    }

    @Test("Blockquote action replaces numbered list syntax semantically")
    func blockquoteReplacesNumberedListPrefix() {
        let text = "1. Item"
        let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: [])
        let (result, selection) = formatter.apply(
            .blockquote,
            to: text,
            selectedRange: NSRange(location: 3, length: 0),
            semanticDocument: semanticDocument
        )
        #expect(result == "> Item")
        #expect(selection.location == 2)
    }

    @Test("Paragraph action removes checkbox syntax semantically")
    func paragraphRemovesCheckboxPrefix() {
        let text = "- [ ] Task"
        let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: [])
        let (result, selection) = formatter.apply(
            .paragraph,
            to: text,
            selectedRange: NSRange(location: 8, length: 0),
            semanticDocument: semanticDocument
        )
        #expect(result == "Task")
        #expect(selection.location == 2)
    }

    @Test("Paragraph action removes surrounding code fences semantically")
    func paragraphRemovesCodeFence() {
        let text = "```swift\nlet x = 1\n```"
        let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: [])
        let (result, selection) = formatter.apply(
            .paragraph,
            to: text,
            selectedRange: NSRange(location: 11, length: 0),
            semanticDocument: semanticDocument
        )
        #expect(result == "let x = 1\n")
        #expect(selection.location == 2)
    }

    @Test("Mermaid action converts plain code fence semantically")
    func mermaidReplacesPlainCodeFence() {
        let text = "```\ngraph TD\n```"
        let semanticDocument = EditorSemanticDocument.build(markdown: text, spans: [])
        let (result, selection) = formatter.apply(
            .mermaid,
            to: text,
            selectedRange: NSRange(location: 4, length: 0),
            semanticDocument: semanticDocument
        )
        #expect(result == "```mermaid\ngraph TD\n```")
        #expect(selection.location == 11)
    }

    // MARK: - Block Actions

    @Test("Code block wraps content")
    func codeBlockWrap() {
        let (result, _) = formatter.apply(.codeBlock, to: "code", selectedRange: NSRange(location: 0, length: 4))
        #expect(result == "```\ncode\n```")
    }

    // MARK: - Template Actions

    @Test("Link template creates markdown link")
    func linkTemplate() {
        let (result, _) = formatter.apply(.link, to: "click here", selectedRange: NSRange(location: 0, length: 10))
        #expect(result == "[click here](url)")
    }

    @Test("Link with empty selection places cursor")
    func linkEmptySelection() {
        let (result, selection) = formatter.apply(.link, to: "", selectedRange: NSRange(location: 0, length: 0))
        #expect(result == "[](url)")
        #expect(selection.location == 1) // cursor inside brackets
    }

    @Test("Image template creates markdown image")
    func imageTemplate() {
        let (result, _) = formatter.apply(.image, to: "alt text", selectedRange: NSRange(location: 0, length: 8))
        #expect(result == "![alt text](path)")
    }

    // MARK: - Mid-Text Operations

    @Test("Bold in middle of text")
    func boldMiddle() {
        let text = "Hello world today"
        let (result, _) = formatter.apply(.bold, to: text, selectedRange: NSRange(location: 6, length: 5))
        #expect(result == "Hello **world** today")
    }

    @Test("Heading on second line")
    func headingSecondLine() {
        let text = "Line one\nLine two\nLine three"
        let (result, _) = formatter.apply(.heading, to: text, selectedRange: NSRange(location: 9, length: 0))
        #expect(result == "Line one\n# Line two\nLine three")
    }

    // MARK: - FormattingAction Properties

    @Test("All actions have icons")
    func allActionsHaveIcons() {
        for action in FormattingAction.allCases {
            #expect(!action.icon.isEmpty)
        }
    }

    @Test("All actions have labels")
    func allActionsHaveLabels() {
        for action in FormattingAction.allCases {
            #expect(!action.label.isEmpty)
        }
    }

    @Test("Action count is correct")
    func actionCount() {
        #expect(FormattingAction.allCases.count == 24)
    }

    // MARK: - Selection Preservation

    @Test("Bold preserves selection around wrapped text")
    func boldPreservesSelection() {
        let (result, selection) = formatter.apply(.bold, to: "This", selectedRange: NSRange(location: 0, length: 4))
        #expect(result == "**This**")
        #expect(selection.location == 2)
        #expect(selection.length == 4)
    }

    @Test("Italic on partial word")
    func italicPartialWord() {
        let text = "This is a text"
        let (result, _) = formatter.apply(.italic, to: text, selectedRange: NSRange(location: 0, length: 4))
        #expect(result == "*This* is a text")
    }

    @Test("Link on selected text")
    func linkSelectedText() {
        let (result, _) = formatter.apply(.link, to: "text", selectedRange: NSRange(location: 0, length: 4))
        #expect(result == "[text](url)")
    }
}
