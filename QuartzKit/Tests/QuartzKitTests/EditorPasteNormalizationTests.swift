import Testing
@testable import QuartzKit

@Suite("EditorPasteNormalization")
struct EditorPasteNormalizationTests {
    private let normalizer = EditorPasteNormalizer()

    @Test("Raw paste preserves bytes exactly")
    func rawPastePreservesBytes() {
        let source = "Line 1\r\n\t- [ ] task  \r\n**Bold**\r"
        #expect(normalizer.normalizedText(source, mode: .raw) == source)
    }

    @Test("Smart paste normalizes line endings indentation and trailing whitespace")
    func smartPasteNormalizesCalmly() {
        let source = "Line 1\r\n\t- [ ] task  \r\n\t\tIndented\t \r"
        let normalized = normalizer.normalizedText(source, mode: .smart)

        #expect(normalized == "Line 1\n    - [ ] task\n        Indented\n")
    }

    @Test("Smart paste preserves markdown syntax")
    func smartPastePreservesMarkdownTokens() {
        let source = "## Heading\r\n\r\n- **Bold** item\r\n`code`  "
        let normalized = normalizer.normalizedText(source, mode: .smart)

        #expect(normalized.contains("## Heading"))
        #expect(normalized.contains("- **Bold** item"))
        #expect(normalized.contains("`code`"))
    }
}
