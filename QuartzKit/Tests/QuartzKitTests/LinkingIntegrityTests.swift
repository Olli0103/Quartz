import Foundation
import Testing
@testable import QuartzKit

@Suite("Linking integrity")
struct LinkingIntegrityTests {

    @Test("Explicit wiki links do not reappear as unlinked mentions for the same note")
    func explicitLinksExcludeUnlinkedMentions() async {
        let currentNoteURL = URL(fileURLWithPath: "/tmp/linking-integrity-current-\(UUID().uuidString).md")
        let linkedNoteURL = URL(fileURLWithPath: "/tmp/linking-integrity-target-\(UUID().uuidString).md")
        let tree = [
            FileNode(name: "Current.md", url: currentNoteURL, nodeType: .note),
            FileNode(name: "Beta.md", url: linkedNoteURL, nodeType: .note)
        ]
        let content = "See [[Beta]] in this note. Beta is already linked and must not reappear as an unlinked mention."

        let suggestions = await LinkSuggestionService().suggestLinks(
            for: content,
            currentNoteURL: currentNoteURL,
            allNotes: tree
        )

        #expect(suggestions.isEmpty)
    }

    @Test("Alias resolution stays consistent across backlinks and unlinked mentions")
    func aliasResolutionRemainsCoherent() async throws {
        let provider = MockVaultProvider()
        let vaultRoot = URL(fileURLWithPath: "/tmp/linking-integrity-alias-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = vaultRoot.appendingPathComponent("Source.md")
        let targetURL = vaultRoot.appendingPathComponent("Roadmap.md")
        let targetFrontmatter = Frontmatter(title: "Roadmap", aliases: ["Project Phoenix"])
        let tree = [
            FileNode(name: "Source.md", url: sourceURL, nodeType: .note),
            FileNode(name: "Roadmap.md", url: targetURL, nodeType: .note, frontmatter: targetFrontmatter)
        ]

        await provider.addNote(NoteDocument(
            fileURL: sourceURL,
            frontmatter: Frontmatter(title: "Source"),
            body: "We already linked [[Project Phoenix]] in this note. Project Phoenix should not also be suggested as unlinked.",
            isDirty: false
        ))
        await provider.addNote(NoteDocument(
            fileURL: targetURL,
            frontmatter: targetFrontmatter,
            body: "# Roadmap",
            isDirty: false
        ))
        await provider.setFileTree(tree)

        let suggestions = await LinkSuggestionService().suggestLinks(
            for: "We already linked [[Project Phoenix]] in this note. Project Phoenix should not also be suggested as unlinked.",
            currentNoteURL: sourceURL,
            allNotes: tree
        )

        #expect(suggestions.isEmpty)

        let backlinks = try await BacklinkUseCase(vaultProvider: provider).findBacklinks(
            to: targetURL,
            in: vaultRoot
        )

        #expect(backlinks.count == 1)
        #expect(backlinks.first?.sourceNoteURL == sourceURL)
        #expect(backlinks.first?.context.contains("[[Project Phoenix]]") == true)
    }

    @Test("Explicit references drive outgoing links and backlink provenance from one model")
    func explicitReferenceCatalogMatchesBacklinkPayload() async throws {
        let provider = MockVaultProvider()
        let vaultRoot = URL(fileURLWithPath: "/tmp/linking-integrity-provenance-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = vaultRoot.appendingPathComponent("Source.md")
        let targetURL = vaultRoot.appendingPathComponent("Erika.md")
        let body = "Discuss [[Erika|Erika Roth]] in the product review."
        let tree = [
            FileNode(name: "Source.md", url: sourceURL, nodeType: .note),
            FileNode(name: "Erika.md", url: targetURL, nodeType: .note)
        ]

        await provider.addNote(NoteDocument(
            fileURL: sourceURL,
            frontmatter: Frontmatter(title: "Source"),
            body: body,
            isDirty: false
        ))
        await provider.addNote(NoteDocument(
            fileURL: targetURL,
            frontmatter: Frontmatter(title: "Erika"),
            body: "# Erika",
            isDirty: false
        ))
        await provider.setFileTree(tree)

        let catalog = NoteReferenceCatalog(allNotes: tree)
        let references = await catalog.resolvedExplicitReferences(in: body, graphEdgeStore: nil)

        #expect(references.count == 1)
        #expect(references.first?.noteURL == targetURL)
        #expect(references.first?.displayText == "Erika Roth")
        #expect(references.first?.context.contains("[[Erika|Erika Roth]]") == true)

        let backlinks = try await BacklinkUseCase(vaultProvider: provider).findBacklinks(
            to: targetURL,
            in: vaultRoot
        )

        #expect(backlinks.count == 1)
        #expect(backlinks.first?.sourceNoteURL == sourceURL)
        #expect(backlinks.first?.referenceRange == references.first?.matchRange)
        #expect(backlinks.first?.referenceDisplayText == references.first?.displayText)
        #expect(backlinks.first?.context == references.first?.context)
    }
}
