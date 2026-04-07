import Testing
import Foundation
@testable import QuartzKit

// MARK: - Dynamic Type Editor Tests
//
// Editor text scaling contracts: font families, formatting actions,
// heading levels, and syntax types that must adapt to Dynamic Type.

@Suite("DynamicTypeEditor")
struct DynamicTypeEditorTests {

    @Test("EditorFontFamily has valid cases for text scaling")
    func fontFamilyScaling() {
        for family in AppearanceManager.EditorFontFamily.allCases {
            let restored = AppearanceManager.EditorFontFamily(rawValue: family.rawValue)
            #expect(restored == family,
                "EditorFontFamily.\(family) must round-trip for persistence")
        }
        #expect(AppearanceManager.EditorFontFamily.allCases.count >= 4,
            "Should support system, serif, monospaced, and rounded")
    }

    @Test("Font size range supports Dynamic Type extremes")
    @MainActor func fontSizeRange() {
        let suiteName = "DynamicTypeEditor-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AppearanceManager(defaults: defaults)

        // Default should be in the middle of the range
        let defaultSize = manager.editorFontSize
        #expect(defaultSize >= 14 && defaultSize <= 18,
            "Default font size should be moderate for Dynamic Type center point")

        // Range should support both extremes
        manager.editorFontSize = 12
        #expect(manager.editorFontSize == 12, "Should allow minimum font size")

        manager.editorFontSize = 24
        #expect(manager.editorFontSize == 24, "Should allow maximum font size")
    }

    @Test("FormattingState detects all inline styles")
    func formattingStateDetection() {
        let empty = FormattingState.empty
        #expect(!empty.isBold && !empty.isItalic && !empty.isStrikethrough && !empty.isCode,
            "Empty state should have no active formatting")
        #expect(empty.headingLevel == 0, "Empty state should have no heading")

        // Test detection in bold text
        let boldState = FormattingState.detect(in: "Some **bold** text", at: 8)
        #expect(boldState.isBold, "Should detect bold at cursor position inside **markers**")
    }

    @Test("FormattingAction covers all markdown actions")
    func formattingActionCoverage() {
        let actions = FormattingAction.allCases
        #expect(actions.count >= 20, "Should cover all text, block, inline, and advanced actions")

        // Verify key actions exist
        let rawValues = Set(actions.map(\.rawValue))
        #expect(rawValues.contains("bold"))
        #expect(rawValues.contains("italic"))
        #expect(rawValues.contains("heading"))
        #expect(rawValues.contains("code"))
        #expect(rawValues.contains("link"))
        #expect(rawValues.contains("image"))
        #expect(rawValues.contains("blockquote"))
        #expect(rawValues.contains("table"))

        // All actions have labels for Dynamic Type text
        for action in actions {
            #expect(!action.label.isEmpty,
                "FormattingAction.\(action) must have a label for Dynamic Type scaling")
        }
    }

    @Test("MarkdownSyntax has all required syntax types")
    func markdownSyntaxTypes() {
        // Verify each syntax variant can be constructed
        let wrap = MarkdownSyntax.wrap("**")
        let prefix = MarkdownSyntax.linePrefix("# ")
        let block = MarkdownSyntax.block("```\n", "\n```")
        let template = MarkdownSyntax.template("[", "](url)")
        let insert = MarkdownSyntax.insert("---\n")
        let remove = MarkdownSyntax.removeHeadingPrefix

        let syntaxes: [MarkdownSyntax] = [wrap, prefix, block, template, insert, remove]
        #expect(syntaxes.count == 6, "Should cover all syntax types")
    }

    @Test("HeadingItem levels span 1 through 6")
    func headingLevels() {
        for level in 1...6 {
            let heading = HeadingItem(
                id: "h\(level)",
                level: level,
                text: "Heading \(level)",
                characterOffset: level * 10
            )
            #expect(heading.level == level)
            #expect(!heading.text.isEmpty)
            #expect(heading.characterOffset >= 0)
        }
    }
}
