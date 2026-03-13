import Testing
@testable import QuartzKit

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    let renderer = MarkdownRenderer()

    @Test("Renders plain text")
    func plainText() {
        let result = renderer.render("Hello World")
        #expect(String(result.characters).contains("Hello World"))
    }

    @Test("Renders headings with level attribute")
    func headings() {
        let result = renderer.render("# Title\n## Subtitle")
        var foundH1 = false
        var foundH2 = false

        for run in result.runs {
            if run.markdownHeadingLevel == 1 { foundH1 = true }
            if run.markdownHeadingLevel == 2 { foundH2 = true }
        }

        #expect(foundH1)
        #expect(foundH2)
    }

    @Test("Renders bold text")
    func bold() {
        let result = renderer.render("This is **bold** text")
        var foundBold = false

        for run in result.runs {
            if run.markdownBold == true {
                foundBold = true
                #expect(String(result.characters[run.range]).contains("bold"))
            }
        }

        #expect(foundBold)
    }

    @Test("Renders italic text")
    func italic() {
        let result = renderer.render("This is *italic* text")
        var foundItalic = false

        for run in result.runs {
            if run.markdownItalic == true {
                foundItalic = true
            }
        }

        #expect(foundItalic)
    }

    @Test("Renders inline code")
    func inlineCode() {
        let result = renderer.render("Use `print()` to debug")
        var foundCode = false

        for run in result.runs {
            if run.markdownInlineCode == true {
                foundCode = true
                #expect(String(result.characters[run.range]).contains("print()"))
            }
        }

        #expect(foundCode)
    }

    @Test("Renders code blocks")
    func codeBlock() {
        let input = """
        ```swift
        let x = 42
        ```
        """
        let result = renderer.render(input)
        var foundCodeBlock = false

        for run in result.runs {
            if run.markdownCodeBlock == true {
                foundCodeBlock = true
            }
        }

        #expect(foundCodeBlock)
    }

    @Test("Renders links")
    func links() {
        let result = renderer.render("[Apple](https://apple.com)")
        var foundLink = false

        for run in result.runs {
            if run.link != nil {
                foundLink = true
                #expect(run.link?.absoluteString == "https://apple.com")
            }
        }

        #expect(foundLink)
    }

    @Test("Renders unordered lists with bullets")
    func unorderedList() {
        let input = """
        - Item 1
        - Item 2
        """
        let result = renderer.render(input)
        #expect(String(result.characters).contains("•"))
        #expect(String(result.characters).contains("Item 1"))
    }

    @Test("Renders checkboxes")
    func checkboxes() {
        let input = """
        - [x] Done
        - [ ] Todo
        """
        let result = renderer.render(input)
        #expect(String(result.characters).contains("☑"))
        #expect(String(result.characters).contains("☐"))
    }

    @Test("Renders block quotes")
    func blockQuote() {
        let result = renderer.render("> This is a quote")
        var foundQuote = false

        for run in result.runs {
            if run.markdownBlockQuote == true {
                foundQuote = true
            }
        }

        #expect(foundQuote)
    }
}
