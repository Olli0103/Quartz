import Testing
import Foundation
@testable import QuartzKit

@Suite("VaultSearchIndex")
struct SearchIndexTests {
    let vaultRoot = URL(fileURLWithPath: "/vault")

    @Test("Empty search returns empty results")
    func emptySearch() async {
        let provider = MockVaultProvider()
        let index = VaultSearchIndex(vaultProvider: provider)

        let results = await index.search(query: "")
        #expect(results.isEmpty)
    }

    @Test("Search finds title match")
    func titleMatch() async {
        let provider = MockVaultProvider()
        let noteURL = vaultRoot.appendingPathComponent("meeting.md")
        let note = NoteDocument(
            fileURL: noteURL,
            frontmatter: Frontmatter(title: "Weekly Meeting Notes"),
            body: "Discussed project updates."
        )
        await provider.addNote(note)

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: noteURL)

        let results = await index.search(query: "meeting")
        #expect(!results.isEmpty)
        #expect(results[0].title == "Weekly Meeting Notes")
    }

    @Test("Search finds body match")
    func bodyMatch() async {
        let provider = MockVaultProvider()
        let noteURL = vaultRoot.appendingPathComponent("note.md")
        let note = NoteDocument(
            fileURL: noteURL,
            frontmatter: Frontmatter(title: "Random Note"),
            body: "This note contains the keyword algorithm in the body."
        )
        await provider.addNote(note)

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: noteURL)

        let results = await index.search(query: "algorithm")
        #expect(results.count == 1)
        #expect(results[0].context != nil)
    }

    @Test("Search finds tag match")
    func tagMatch() async {
        let provider = MockVaultProvider()
        let noteURL = vaultRoot.appendingPathComponent("tagged.md")
        let note = NoteDocument(
            fileURL: noteURL,
            frontmatter: Frontmatter(title: "Tagged", tags: ["swift", "ios"]),
            body: "Content"
        )
        await provider.addNote(note)

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: noteURL)

        let results = await index.search(query: "swift")
        #expect(!results.isEmpty)
        #expect(results[0].matchedTags.contains("swift"))
    }

    @Test("Title match scores higher than body match")
    func titleScoresHigher() async {
        let provider = MockVaultProvider()
        let titleURL = vaultRoot.appendingPathComponent("title.md")
        let bodyURL = vaultRoot.appendingPathComponent("body.md")

        await provider.addNote(NoteDocument(
            fileURL: titleURL,
            frontmatter: Frontmatter(title: "SwiftUI Guide"),
            body: "A guide about frameworks."
        ))
        await provider.addNote(NoteDocument(
            fileURL: bodyURL,
            frontmatter: Frontmatter(title: "Random Note"),
            body: "This mentions swiftui somewhere in the text."
        ))

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: titleURL)
        await index.updateEntry(for: bodyURL)

        let results = await index.search(query: "swiftui")
        #expect(results.count == 2)
        #expect(results[0].title == "SwiftUI Guide") // Title match scores higher
    }

    @Test("Exact title match scores highest")
    func exactTitleMatch() async {
        let provider = MockVaultProvider()
        let exactURL = vaultRoot.appendingPathComponent("exact.md")
        let partialURL = vaultRoot.appendingPathComponent("partial.md")

        await provider.addNote(NoteDocument(
            fileURL: exactURL,
            frontmatter: Frontmatter(title: "swift"),
            body: ""
        ))
        await provider.addNote(NoteDocument(
            fileURL: partialURL,
            frontmatter: Frontmatter(title: "Learning Swift Programming"),
            body: ""
        ))

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: exactURL)
        await index.updateEntry(for: partialURL)

        let results = await index.search(query: "swift")
        #expect(results.count == 2)
        #expect(results[0].title == "swift") // Exact match first
    }

    @Test("removeEntry removes from index")
    func removeEntry() async {
        let provider = MockVaultProvider()
        let noteURL = vaultRoot.appendingPathComponent("removeme.md")
        await provider.addNote(NoteDocument(
            fileURL: noteURL,
            frontmatter: Frontmatter(title: "Remove Me"),
            body: ""
        ))

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: noteURL)

        var results = await index.search(query: "remove")
        #expect(results.count == 1)

        await index.removeEntry(for: noteURL)
        results = await index.search(query: "remove")
        #expect(results.isEmpty)
    }

    @Test("Multi-term search uses AND logic")
    func multiTermAND() async {
        let provider = MockVaultProvider()
        let matchURL = vaultRoot.appendingPathComponent("match.md")
        let noMatchURL = vaultRoot.appendingPathComponent("nomatch.md")

        await provider.addNote(NoteDocument(
            fileURL: matchURL,
            frontmatter: Frontmatter(title: "Swift iOS Development"),
            body: ""
        ))
        await provider.addNote(NoteDocument(
            fileURL: noMatchURL,
            frontmatter: Frontmatter(title: "Swift Backend"),
            body: ""
        ))

        let index = VaultSearchIndex(vaultProvider: provider)
        await index.updateEntry(for: matchURL)
        await index.updateEntry(for: noMatchURL)

        let results = await index.search(query: "swift ios")
        #expect(results.count == 1)
        #expect(results[0].title == "Swift iOS Development")
    }

    @Test("SearchResult has correct properties")
    func searchResultProperties() {
        let result = SearchResult(
            noteURL: URL(fileURLWithPath: "/test.md"),
            title: "Test",
            score: 10,
            context: "...context...",
            matchedTags: ["tag1"]
        )

        #expect(result.title == "Test")
        #expect(result.score == 10)
        #expect(result.context == "...context...")
        #expect(result.matchedTags == ["tag1"])
        #expect(result.id == URL(fileURLWithPath: "/test.md"))
    }
}
