import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Wiki Link Flow Tests
//
// Wiki-link → navigate → backlink data flow: WikiLinkExtractor
// parsing, alias/anchor support, and WikiLink identity stability.

@Suite("E2EWikiLinkFlow")
struct E2EWikiLinkFlowTests {

    @Test("WikiLinkExtractor parses simple [[links]]")
    func simpleLinkParsing() {
        let extractor = WikiLinkExtractor()
        let links = extractor.extractLinks(from: "See [[My Note]] for details")

        #expect(links.count == 1)
        #expect(links[0].target == "My Note")
        #expect(links[0].displayText == "My Note")
    }

    @Test("WikiLink supports alias syntax [[target|display]]")
    func aliasSyntax() {
        let extractor = WikiLinkExtractor()
        let links = extractor.extractLinks(from: "Read [[Long Note Name|short name]]")

        #expect(links.count == 1)
        #expect(links[0].target == "Long Note Name")
        #expect(links[0].displayText == "short name")
    }

    @Test("WikiLink supports heading anchor [[Note#Heading]]")
    func headingAnchor() {
        let extractor = WikiLinkExtractor()
        let links = extractor.extractLinks(from: "Jump to [[Note#Section Two]]")

        #expect(links.count == 1)
        #expect(links[0].target == "Note")
        #expect(links[0].heading == "Section Two")
    }

    @Test("WikiLinkExtractor skips links inside code blocks")
    func skipCodeBlocks() {
        let extractor = WikiLinkExtractor()
        let markdown = """
        Real [[Link Here]]

        ```
        [[Not A Link]]
        ```
        """
        let links = extractor.extractLinks(from: markdown)

        #expect(links.count == 1)
        #expect(links[0].target == "Link Here")
    }

    @Test("WikiLink IDs are stable for same raw content")
    func stableIDs() {
        let link1 = WikiLink(raw: "My Note")
        let link2 = WikiLink(raw: "My Note")

        #expect(link1.id == link2.id,
            "Same raw content should produce same ID for stable identity")
    }

    @Test("Multiple wiki links extracted in order")
    func multipleLinks() {
        let extractor = WikiLinkExtractor()
        let links = extractor.extractLinks(from: "See [[Alpha]], [[Beta]], and [[Gamma]]")

        #expect(links.count == 3)
        #expect(links[0].target == "Alpha")
        #expect(links[1].target == "Beta")
        #expect(links[2].target == "Gamma")
    }
}
