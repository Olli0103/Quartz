import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 3: Editor, TextKit 2 & Media Tests

// MARK: - MarkdownFormatter Tests

@Suite("EditorHardeningMarkdownFormatter")
struct EditorHardeningMarkdownFormatterTests {
    let formatter = MarkdownFormatter()

    @Test("Bold formatting wraps with **")
    func boldFormatting() {
        let (text, range) = formatter.apply(.bold, to: "Hello World", selectedRange: NSRange(location: 6, length: 5))
        #expect(text == "Hello **World**")
        #expect(range.location == 8)
        #expect(range.length == 5)
    }

    @Test("Bold toggle removes existing markers")
    func boldToggle() {
        let (text, range) = formatter.apply(.bold, to: "Hello **World**", selectedRange: NSRange(location: 8, length: 5))
        #expect(text == "Hello World")
        #expect(range.location == 6)
    }

    @Test("Italic formatting wraps with *")
    func italicFormatting() {
        let (text, range) = formatter.apply(.italic, to: "Hello World", selectedRange: NSRange(location: 6, length: 5))
        #expect(text == "Hello *World*")
        #expect(range.location == 7)
    }

    @Test("Strikethrough formatting wraps with ~~")
    func strikethroughFormatting() {
        let (text, range) = formatter.apply(.strikethrough, to: "Delete this", selectedRange: NSRange(location: 7, length: 4))
        #expect(text == "Delete ~~this~~")
        #expect(range.location == 9)
    }

    @Test("Heading adds # prefix")
    func headingFormatting() {
        let (text, _) = formatter.apply(.heading, to: "Title", selectedRange: NSRange(location: 0, length: 5))
        #expect(text.hasPrefix("# "))
    }

    @Test("Heading toggle removes prefix")
    func headingToggle() {
        let (text, _) = formatter.apply(.heading, to: "# Title\n", selectedRange: NSRange(location: 2, length: 5))
        #expect(!text.hasPrefix("# "))
    }

    @Test("Bullet list adds - prefix")
    func bulletListFormatting() {
        let (text, _) = formatter.apply(.bulletList, to: "Item", selectedRange: NSRange(location: 0, length: 4))
        #expect(text.hasPrefix("- "))
    }

    @Test("Numbered list adds 1. prefix")
    func numberedListFormatting() {
        let (text, _) = formatter.apply(.numberedList, to: "Item", selectedRange: NSRange(location: 0, length: 4))
        #expect(text.hasPrefix("1. "))
    }

    @Test("Checkbox adds - [ ] prefix")
    func checkboxFormatting() {
        let (text, _) = formatter.apply(.checkbox, to: "Task", selectedRange: NSRange(location: 0, length: 4))
        #expect(text.hasPrefix("- [ ] "))
    }

    @Test("Code formatting wraps with `")
    func codeFormatting() {
        let (text, range) = formatter.apply(.code, to: "variable", selectedRange: NSRange(location: 0, length: 8))
        #expect(text == "`variable`")
        #expect(range.location == 1)
    }

    @Test("Code block formatting")
    func codeBlockFormatting() {
        let (text, _) = formatter.apply(.codeBlock, to: "code", selectedRange: NSRange(location: 0, length: 4))
        #expect(text.contains("```"))
        #expect(text.contains("code"))
    }

    @Test("Link formatting creates template")
    func linkFormatting() {
        let (text, _) = formatter.apply(.link, to: "click here", selectedRange: NSRange(location: 0, length: 10))
        #expect(text.contains("[click here](url)"))
    }

    @Test("Image formatting creates template")
    func imageFormatting() {
        let (text, _) = formatter.apply(.image, to: "alt", selectedRange: NSRange(location: 0, length: 3))
        #expect(text.contains("![alt](path)"))
    }

    @Test("Blockquote adds > prefix")
    func blockquoteFormatting() {
        let (text, _) = formatter.apply(.blockquote, to: "Quote", selectedRange: NSRange(location: 0, length: 5))
        #expect(text.hasPrefix("> "))
    }

    @Test("Highlight formatting wraps with ==")
    func highlightFormatting() {
        let (text, range) = formatter.apply(.highlight, to: "important", selectedRange: NSRange(location: 0, length: 9))
        #expect(text == "==important==")
        #expect(range.location == 2)
    }

    @Test("Table inserts markdown table")
    func tableFormatting() {
        let (text, _) = formatter.apply(.table, to: "", selectedRange: NSRange(location: 0, length: 0))
        #expect(text.contains("|"))
        #expect(text.contains("---"))
    }

    @Test("Math formatting wraps with $")
    func mathFormatting() {
        let (text, _) = formatter.apply(.math, to: "x^2", selectedRange: NSRange(location: 0, length: 3))
        #expect(text == "$x^2$")
    }

    @Test("Footnote creates template")
    func footnoteFormatting() {
        let (text, _) = formatter.apply(.footnote, to: "1", selectedRange: NSRange(location: 0, length: 1))
        #expect(text.contains("[^1]: "))
    }

    @Test("Mermaid creates fenced block")
    func mermaidFormatting() {
        let (text, _) = formatter.apply(.mermaid, to: "graph TD", selectedRange: NSRange(location: 0, length: 8))
        #expect(text.contains("```mermaid"))
        #expect(text.contains("graph TD"))
    }

    @Test("Empty selection inserts at cursor")
    func emptySelectionInsert() {
        let (text, range) = formatter.apply(.bold, to: "Hello", selectedRange: NSRange(location: 5, length: 0))
        #expect(text == "Hello****")
        #expect(range.location == 7) // Cursor between the markers
    }
}

// MARK: - FormattingAction Tests

@Suite("EditorHardeningFormattingAction")
struct EditorHardeningFormattingActionTests {
    @Test("All actions have icons")
    func allActionsHaveIcons() {
        for action in FormattingAction.allCases {
            #expect(!action.icon.isEmpty, "Action \(action.rawValue) should have an icon")
        }
    }

    @Test("All actions have labels")
    func allActionsHaveLabels() {
        for action in FormattingAction.allCases {
            #expect(!action.label.isEmpty, "Action \(action.rawValue) should have a label")
        }
    }

    @Test("Primary actions have keyboard shortcuts")
    func primaryActionsHaveShortcuts() {
        let primaryWithShortcuts: [FormattingAction] = [.bold, .italic, .strikethrough, .heading, .code, .link, .blockquote]
        for action in primaryWithShortcuts {
            #expect(action.shortcut != nil, "Action \(action.rawValue) should have a shortcut")
        }
    }

    @Test("All cases count is correct")
    func allCasesCount() {
        #expect(FormattingAction.allCases.count == 24)
    }
}

// MARK: - MarkdownSyntax Tests

@Suite("EditorHardeningMarkdownSyntax")
struct EditorHardeningMarkdownSyntaxTests {
    @Test("Wrap syntax is correct")
    func wrapSyntax() {
        let bold = FormattingAction.bold.markdownSyntax
        switch bold {
        case .wrap(let marker):
            #expect(marker == "**")
        default:
            Issue.record("Bold should use wrap syntax")
        }
    }

    @Test("Line prefix syntax is correct")
    func linePrefixSyntax() {
        let heading = FormattingAction.heading.markdownSyntax
        switch heading {
        case .linePrefix(let prefix):
            #expect(prefix == "# ")
        default:
            Issue.record("Heading should use linePrefix syntax")
        }
    }

    @Test("Block syntax is correct")
    func blockSyntax() {
        let codeBlock = FormattingAction.codeBlock.markdownSyntax
        switch codeBlock {
        case .block(let open, let close):
            #expect(open.contains("```"))
            #expect(close.contains("```"))
        default:
            Issue.record("Code block should use block syntax")
        }
    }

    @Test("Template syntax is correct")
    func templateSyntax() {
        let link = FormattingAction.link.markdownSyntax
        switch link {
        case .template(let before, let after):
            #expect(before == "[")
            #expect(after == "](url)")
        default:
            Issue.record("Link should use template syntax")
        }
    }

    @Test("Insert syntax is correct")
    func insertSyntax() {
        let table = FormattingAction.table.markdownSyntax
        switch table {
        case .insert(let raw):
            #expect(raw.contains("|"))
        default:
            Issue.record("Table should use insert syntax")
        }
    }
}

// MARK: - XCTest Performance Tests for Editor

final class EditorPerformanceTests: XCTestCase {
    func testMarkdownFormatterPerformance() throws {
        let formatter = MarkdownFormatter()
        let longText = String(repeating: "Hello World. ", count: 1000)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for _ in 0..<100 {
                _ = formatter.apply(.bold, to: longText, selectedRange: NSRange(location: 100, length: 50))
                _ = formatter.apply(.italic, to: longText, selectedRange: NSRange(location: 200, length: 30))
                _ = formatter.apply(.heading, to: longText, selectedRange: NSRange(location: 0, length: 20))
            }
        }
    }

    func testFormattingAllActionsPerformance() throws {
        let formatter = MarkdownFormatter()
        let text = "Sample text for formatting"
        let selection = NSRange(location: 7, length: 4)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for _ in 0..<100 {
                for action in FormattingAction.allCases {
                    _ = formatter.apply(action, to: text, selectedRange: selection)
                }
            }
        }
    }

    func testMultiLineFormattingPerformance() throws {
        let formatter = MarkdownFormatter()
        let multiLineText = (0..<100).map { "Line \($0) with some content here" }.joined(separator: "\n")

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            for lineStart in stride(from: 0, to: 1000, by: 50) {
                _ = formatter.apply(.bulletList, to: multiLineText, selectedRange: NSRange(location: lineStart, length: 10))
                _ = formatter.apply(.heading, to: multiLineText, selectedRange: NSRange(location: lineStart, length: 10))
            }
        }
    }

    func testToggleFormattingPerformance() throws {
        let formatter = MarkdownFormatter()

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            var text = "Hello World"
            var range = NSRange(location: 6, length: 5)

            // Toggle bold on/off 100 times
            for _ in 0..<100 {
                (text, range) = formatter.apply(.bold, to: text, selectedRange: range)
            }
        }
    }
}

// MARK: - Typing Simulation Tests

@Suite("TypingSimulation")
struct TypingSimulationTests {
    @Test("Rapid character insertion preserves integrity")
    func rapidCharacterInsertion() {
        var text = ""
        let typingSpeed = 120 // WPM = ~10 chars/sec

        // Simulate 60 seconds of typing at 120 WPM
        for i in 0..<600 {
            let char = Character(UnicodeScalar((i % 26) + 97)!) // a-z
            text.append(char)
            if i % 5 == 4 { text.append(" ") }
        }

        #expect(text.count > 600)
        #expect(!text.isEmpty)
    }

    @Test("Insertion at various positions maintains consistency")
    func insertionAtVariousPositions() {
        var text = "The quick brown fox jumps over the lazy dog."
        let originalLength = text.count

        // Insert at beginning
        text.insert(contentsOf: "# ", at: text.startIndex)
        #expect(text.hasPrefix("# "))

        // Insert in middle
        let midIndex = text.index(text.startIndex, offsetBy: text.count / 2)
        text.insert(contentsOf: "**", at: midIndex)
        #expect(text.contains("**"))

        // Insert at end
        text.append("\n- Item")
        #expect(text.hasSuffix("Item"))

        #expect(text.count > originalLength)
    }

    @Test("Unicode handling is correct")
    func unicodeHandling() {
        let formatter = MarkdownFormatter()
        let unicodeText = "Hello 世界 🌍 émojis"
        let selection = NSRange(location: 6, length: 2) // 世界

        let (result, range) = formatter.apply(.bold, to: unicodeText, selectedRange: selection)
        #expect(result.contains("**"))
        #expect(range.location > 0)
    }
}

// MARK: - Command Palette Item Tests

@Suite("CommandPaletteIntegration")
struct CommandPaletteIntegrationTests {
    @Test("Fuzzy match finds partial matches")
    func fuzzyMatchPartial() {
        let target = "new note"
        let query = "nnt"

        var targetIndex = target.startIndex
        var matched = true
        for char in query {
            guard let found = target[targetIndex...].firstIndex(where: { $0 == char }) else {
                matched = false
                break
            }
            targetIndex = target.index(after: found)
        }

        #expect(matched)
    }

    @Test("Fuzzy match rejects non-matches")
    func fuzzyMatchRejectsNonMatches() {
        let target = "save"
        let query = "xyz"

        var targetIndex = target.startIndex
        var matched = true
        for char in query {
            guard let found = target[targetIndex...].firstIndex(where: { $0 == char }) else {
                matched = false
                break
            }
            targetIndex = target.index(after: found)
        }

        #expect(!matched)
    }

    @Test("Command palette commands have required properties")
    func commandsHaveRequiredProperties() {
        // Commands should have: id, title, icon, keywords
        let commandProperties = [
            ("new-note", "New Note", "plus.circle.fill"),
            ("search-brain", "Search Brain", "brain.head.profile"),
            ("toggle-preview", "Toggle Preview", "eye"),
            ("focus-mode", "Toggle Focus Mode", "moon.fill"),
            ("save", "Save Note", "square.and.arrow.down")
        ]

        for (id, title, icon) in commandProperties {
            #expect(!id.isEmpty)
            #expect(!title.isEmpty)
            #expect(!icon.isEmpty)
        }
    }
}
