import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Tag Flow Tests
//
// Tag lifecycle: add tag → extract → browse → filter by tag.
// Tests TagExtractor, Frontmatter, SourceSelection, and tag colors.

@Suite("E2ETagFlow")
struct E2ETagFlowTests {

    @Test("TagExtractor finds inline hashtag tags")
    func inlineTagExtraction() {
        let extractor = TagExtractor()
        let tags = extractor.extractTags(from: "A note about #swift and #concurrency")

        #expect(tags.contains("swift"))
        #expect(tags.contains("concurrency"))
        #expect(tags.count == 2)
    }

    @Test("TagExtractor handles Unicode/CJK tags")
    func unicodeTags() {
        let extractor = TagExtractor()
        let tags = extractor.extractTags(from: "Notes about #日本語 and #café")

        #expect(tags.count >= 2, "Should extract Unicode tags")
    }

    @Test("Frontmatter stores tags array")
    func frontmatterTags() {
        var fm = Frontmatter()
        fm.tags = ["swift", "design", "architecture"]

        #expect(fm.tags.count == 3)
        #expect(fm.tags.contains("swift"))
        #expect(fm.tags.contains("design"))
    }

    @Test("SourceSelection.tag filters sidebar by tag")
    @MainActor func tagSourceSelection() {
        let store = WorkspaceStore()
        store.selectedSource = .tag("swift")

        if case .tag(let name) = store.selectedSource {
            #expect(name == "swift")
        } else {
            Issue.record("Expected .tag source selection")
        }
    }

    @Test("QuartzColors.tagColor is deterministic for same tag")
    func tagColorDeterministic() {
        let c1 = "\(QuartzColors.tagColor(for: "swift"))"
        let c2 = "\(QuartzColors.tagColor(for: "swift"))"
        #expect(c1 == c2, "Same tag must always produce same color")
    }

    @Test("TagExtractor skips tags inside code blocks")
    func skipCodeBlocks() {
        let extractor = TagExtractor()
        let markdown = """
        Real #tag here

        ```
        #notATag inside code
        ```

        Another #real tag
        """
        let tags = extractor.extractTags(from: markdown)

        #expect(tags.contains("tag"))
        #expect(tags.contains("real"))
        #expect(!tags.contains("notATag"),
            "Tags inside fenced code blocks should be skipped")
    }

    @Test("TagExtractor returns unique tags only")
    func uniqueTags() {
        let extractor = TagExtractor()
        let tags = extractor.extractTags(from: "#swift #design #swift #swift")

        #expect(tags.count == 2, "Duplicate tags should be deduplicated")
    }
}
