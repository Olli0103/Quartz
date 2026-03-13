import Testing
import Foundation
@testable import QuartzKit

@Suite("TagExtractor")
struct TagExtractorTests {
    let extractor = TagExtractor()

    @Test("Extracts simple tags")
    func simpleTags() {
        let text = "This is a #swift note about #ios development."
        let tags = extractor.extractTags(from: text)
        #expect(tags == ["swift", "ios"])
    }

    @Test("Returns empty array for no tags")
    func noTags() {
        let tags = extractor.extractTags(from: "No tags here, just plain text.")
        #expect(tags.isEmpty)
    }

    @Test("Ignores headings")
    func ignoresHeadings() {
        let text = """
        # This is a heading
        ## Another heading
        Regular text with #realtag here.
        """
        let tags = extractor.extractTags(from: text)
        #expect(tags.contains("realtag"))
        #expect(!tags.contains("this"))
        #expect(!tags.contains("another"))
    }

    @Test("Ignores tags inside code blocks")
    func ignoresCodeBlocks() {
        let text = """
        Normal text #valid
        ```swift
        let x = #ignored
        ```
        After code #alsovalid
        """
        let tags = extractor.extractTags(from: text)
        #expect(tags.contains("valid"))
        #expect(tags.contains("alsovalid"))
        #expect(!tags.contains("ignored"))
    }

    @Test("Ignores tags inside inline code")
    func ignoresInlineCode() {
        let text = "Use `#notATag` for colors. Real #tag here."
        let tags = extractor.extractTags(from: text)
        #expect(tags.contains("tag"))
        #expect(!tags.contains("notatag"))
    }

    @Test("Extracts tags with dashes and underscores")
    func specialChars() {
        let text = "#my-tag #another_tag #nested/tag"
        let tags = extractor.extractTags(from: text)
        #expect(tags.contains("my-tag"))
        #expect(tags.contains("another_tag"))
        #expect(tags.contains("nested/tag"))
    }

    @Test("Tags are lowercased and deduplicated")
    func lowercasedDedup() {
        let text = "#Swift #swift #SWIFT"
        let tags = extractor.extractTags(from: text)
        #expect(tags.count == 1)
        #expect(tags[0] == "swift")
    }

    @Test("Tags with unicode characters")
    func unicodeTags() {
        let text = "#café #über #naïve"
        let tags = extractor.extractTags(from: text)
        #expect(tags.contains("café"))
        #expect(tags.contains("über"))
    }

    @Test("tagRanges returns positions")
    func tagRanges() {
        let text = "Hello #world and #swift"
        let ranges = extractor.tagRanges(in: text)
        #expect(ranges.count == 2)
        #expect(ranges[0].tag == "world")
        #expect(ranges[1].tag == "swift")
    }

    @Test("Tag at start of text")
    func tagAtStart() {
        let tags = extractor.extractTags(from: "#first word")
        #expect(tags.contains("first"))
    }

    @Test("Empty string returns empty")
    func emptyString() {
        let tags = extractor.extractTags(from: "")
        #expect(tags.isEmpty)
    }
}
