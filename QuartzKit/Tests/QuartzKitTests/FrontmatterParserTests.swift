import Testing
@testable import QuartzKit

@Suite("FrontmatterParser")
struct FrontmatterParserTests {
    let parser = FrontmatterParser()

    @Test("Parses complete frontmatter")
    func parseComplete() throws {
        let input = """
        ---
        title: Test Note
        tags: [swift, ios]
        aliases: [TestNote]
        created: 2026-03-13T10:00:00Z
        modified: 2026-03-13T11:00:00Z
        template: daily
        ---

        # Hello World

        Some content here.
        """

        let (fm, body) = try parser.parse(from: input)

        #expect(fm.title == "Test Note")
        #expect(fm.tags == ["swift", "ios"])
        #expect(fm.aliases == ["TestNote"])
        #expect(fm.template == "daily")
        #expect(body.hasPrefix("# Hello World"))
    }

    @Test("Returns empty frontmatter when no delimiter")
    func noFrontmatter() throws {
        let input = "# Just a heading\n\nSome text."
        let (fm, body) = try parser.parse(from: input)

        #expect(fm.title == nil)
        #expect(fm.tags.isEmpty)
        #expect(body == input)
    }

    @Test("Handles empty body after frontmatter")
    func emptyBody() throws {
        let input = """
        ---
        title: Empty
        ---

        """

        let (fm, body) = try parser.parse(from: input)

        #expect(fm.title == "Empty")
        #expect(body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Round-trip preserves content")
    func roundTrip() throws {
        let original = Frontmatter(
            title: "Round Trip",
            tags: ["test", "roundtrip"],
            aliases: ["RT"],
            template: "meeting"
        )

        let yaml = try parser.serialize(original)
        let roundTripped = try parser.parse(from: "---\n\(yaml)---\n\nBody text.")

        #expect(roundTripped.frontmatter.title == original.title)
        #expect(roundTripped.frontmatter.tags == original.tags)
        #expect(roundTripped.frontmatter.aliases == original.aliases)
        #expect(roundTripped.frontmatter.template == original.template)
        #expect(roundTripped.body == "Body text.")
    }

    @Test("Handles custom fields")
    func customFields() throws {
        let input = """
        ---
        title: Custom
        project: Alpha
        status: draft
        ---

        Content.
        """

        let (fm, _) = try parser.parse(from: input)

        #expect(fm.title == "Custom")
        #expect(fm.customFields["project"] == "Alpha")
        #expect(fm.customFields["status"] == "draft")
    }

    @Test("Handles special characters in values")
    func specialCharacters() throws {
        let fm = Frontmatter(
            title: "Note: Important [Draft]",
            tags: ["tag:special", "tag with spaces"]
        )

        let yaml = try parser.serialize(fm)
        let reparsed = try parser.parse(from: "---\n\(yaml)---\n\nBody.")

        #expect(reparsed.frontmatter.title == fm.title)
        #expect(reparsed.frontmatter.tags == fm.tags)
    }
}
