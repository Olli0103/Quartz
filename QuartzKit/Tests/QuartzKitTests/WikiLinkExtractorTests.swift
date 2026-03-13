import Testing
import Foundation
@testable import QuartzKit

@Suite("WikiLinkExtractor")
struct WikiLinkExtractorTests {
    let extractor = WikiLinkExtractor()

    @Test("Extracts simple wiki links")
    func simpleLinks() {
        let text = "See [[My Note]] for details."
        let links = extractor.extractLinks(from: text)
        #expect(links.count == 1)
        #expect(links[0].target == "My Note")
        #expect(links[0].displayText == "My Note")
    }

    @Test("Returns empty for no links")
    func noLinks() {
        let links = extractor.extractLinks(from: "No links here.")
        #expect(links.isEmpty)
    }

    @Test("Extracts link with alias")
    func linkWithAlias() {
        let text = "See [[My Note|click here]] for info."
        let links = extractor.extractLinks(from: text)
        #expect(links.count == 1)
        #expect(links[0].target == "My Note")
        #expect(links[0].displayText == "click here")
    }

    @Test("Extracts link with heading anchor")
    func linkWithAnchor() {
        let text = "Read [[My Note#Section One]] for details."
        let links = extractor.extractLinks(from: text)
        #expect(links.count == 1)
        #expect(links[0].target == "My Note")
        #expect(links[0].heading == "Section One")
    }

    @Test("Link with both anchor and alias")
    func anchorAndAlias() {
        let link = WikiLink(raw: "Note#Heading|Display")
        #expect(link.target == "Note")
        #expect(link.heading == "Heading")
        #expect(link.displayText == "Display")
    }

    @Test("Extracts multiple links")
    func multipleLinks() {
        let text = "Link to [[Note A]] and [[Note B]] and [[Note C]]."
        let links = extractor.extractLinks(from: text)
        #expect(links.count == 3)
        #expect(links.map(\.target) == ["Note A", "Note B", "Note C"])
    }

    @Test("Handles whitespace in link names")
    func whitespaceHandling() {
        let link = WikiLink(raw: "  Spaces  ")
        #expect(link.target == "Spaces")
    }

    @Test("Link without heading returns nil heading")
    func noHeading() {
        let link = WikiLink(raw: "Simple Note")
        #expect(link.heading == nil)
    }

    @Test("linkRanges returns correct positions")
    func linkRanges() {
        let text = "See [[A]] and [[B]]."
        let ranges = extractor.linkRanges(in: text)
        #expect(ranges.count == 2)
        #expect(ranges[0].link.target == "A")
        #expect(ranges[1].link.target == "B")
    }

    @Test("Empty string returns empty")
    func emptyString() {
        let links = extractor.extractLinks(from: "")
        #expect(links.isEmpty)
    }

    @Test("Incomplete brackets are ignored")
    func incompleteBrackets() {
        let text = "Not a link: [single] or [[unclosed"
        let links = extractor.extractLinks(from: text)
        #expect(links.isEmpty)
    }

    @Test("WikiLink Identifiable conformance")
    func identifiable() {
        let link = WikiLink(raw: "Test Note")
        #expect(link.id == "Test Note")
    }
}
