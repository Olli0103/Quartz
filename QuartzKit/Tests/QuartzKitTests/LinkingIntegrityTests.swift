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
        let references = await catalog.resolvedExplicitReferences(
            in: body,
            sourceNoteURL: sourceURL,
            graphEdgeStore: nil
        )

        #expect(references.count == 1)
        #expect(references.first?.targetNoteURL == targetURL)
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

    @Test("Canonical explicit note resolution stays consistent across catalog and live graph store")
    func canonicalResolverAlignsCatalogAndGraphStore() async {
        let vaultRoot = URL(fileURLWithPath: "/tmp/linking-integrity-canonical-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = vaultRoot.appendingPathComponent("Source.md")
        let targetURL = vaultRoot.appendingPathComponent("Projects/Roadmap.md")
        let targetFrontmatter = Frontmatter(title: "Delivery Plan", aliases: ["Project Phoenix"])
        let tree = [
            FileNode(
                name: "Projects",
                url: vaultRoot.appendingPathComponent("Projects", isDirectory: true),
                nodeType: .folder,
                children: [
                    FileNode(
                        name: "Roadmap.md",
                        url: targetURL,
                        nodeType: .note,
                        frontmatter: targetFrontmatter
                    )
                ]
            ),
            FileNode(name: "Source.md", url: sourceURL, nodeType: .note)
        ]

        let store = GraphEdgeStore()
        await store.configureCanonicalResolution(with: tree)
        let catalog = NoteReferenceCatalog(allNotes: tree)

        for target in ["Roadmap", "Delivery Plan", "Project Phoenix", "Projects/Roadmap"] {
            #expect(await store.resolveTitle(target) == CanonicalNoteIdentity.canonicalFileURL(for: targetURL))
            #expect(await catalog.resolveExplicitLinkTarget(target, graphEdgeStore: store) == CanonicalNoteIdentity.canonicalFileURL(for: targetURL))
        }
    }

    @Test("Note reference catalog deduplicates repeated canonical note URLs")
    func noteReferenceCatalogDeduplicatesCanonicalURLCollisions() async {
        let duplicateURL = URL(fileURLWithPath: "/tmp/linking-integrity-duplicate-\(UUID().uuidString)/Alpha.md")
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: duplicateURL)
        let tree = [
            FileNode(
                name: "Alpha.md",
                url: duplicateURL,
                nodeType: .note,
                frontmatter: Frontmatter(title: "Alpha")
            ),
            FileNode(
                name: "Alpha.md",
                url: duplicateURL,
                nodeType: .note,
                frontmatter: Frontmatter(title: "Project Alpha", aliases: ["PA"])
            )
        ]

        let catalog = NoteReferenceCatalog(allNotes: tree)

        #expect(catalog.allNoteURLs == [canonicalURL])
        let aliasMatches = catalog.linkInsertionSuggestions(matching: "PA", excluding: nil)
        #expect(aliasMatches.count == 1)
        #expect(aliasMatches.first?.noteURL == canonicalURL)
        #expect(aliasMatches.first?.noteName == "Alpha")
    }

    @Test("Live explicit graph edges use the canonical resolver instead of basename-only fallback")
    func liveGraphEdgesUseCanonicalResolver() async {
        let vaultRoot = URL(fileURLWithPath: "/tmp/linking-integrity-live-graph-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = vaultRoot.appendingPathComponent("Source.md")
        let targetURL = vaultRoot.appendingPathComponent("Roadmap.md")
        let targetFrontmatter = Frontmatter(title: "Delivery Plan", aliases: ["Project Phoenix"])
        let tree = [
            FileNode(name: "Source.md", url: sourceURL, nodeType: .note),
            FileNode(name: "Roadmap.md", url: targetURL, nodeType: .note, frontmatter: targetFrontmatter)
        ]

        let store = GraphEdgeStore()
        await store.configureCanonicalResolution(with: tree)
        await store.updateConnections(
            for: sourceURL,
            linkedTitles: ["Project Phoenix"],
            allVaultURLs: NoteReferenceCatalog(allNotes: tree).allNoteURLs
        )

        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let canonicalTargetURL = CanonicalNoteIdentity.canonicalFileURL(for: targetURL)

        #expect(await store.resolveTitle("Project Phoenix") == canonicalTargetURL)
        #expect(await store.backlinks(for: canonicalTargetURL).contains(canonicalSourceURL))
    }

    @Test("Canonical explicit references drive outgoing links live edges backlinks and mention exclusion together")
    func explicitReferencePipelineUnifiesExplicitRelationshipConsumers() async throws {
        let vaultRoot = URL(fileURLWithPath: "/tmp/linking-integrity-pipeline-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = vaultRoot.appendingPathComponent("Source.md")
        let targetURL = vaultRoot.appendingPathComponent("Projects/Roadmap.md")
        let targetFrontmatter = Frontmatter(title: "Delivery Plan", aliases: ["Project Phoenix"])
        let body = "Review [[Projects/Roadmap#Launch Plan|Project Phoenix]] before launch. Project Phoenix should not be suggested again."
        let tree = [
            FileNode(
                name: "Projects",
                url: vaultRoot.appendingPathComponent("Projects", isDirectory: true),
                nodeType: .folder,
                children: [
                    FileNode(
                        name: "Roadmap.md",
                        url: targetURL,
                        nodeType: .note,
                        frontmatter: targetFrontmatter
                    )
                ]
            ),
            FileNode(name: "Source.md", url: sourceURL, nodeType: .note)
        ]

        let catalog = NoteReferenceCatalog(allNotes: tree)
        let references = await catalog.resolvedExplicitReferences(
            in: body,
            sourceNoteURL: sourceURL,
            graphEdgeStore: nil
        )

        #expect(references.count == 1)
        let reference = try #require(references.first)
        #expect(reference.sourceNoteURL == CanonicalNoteIdentity.canonicalFileURL(for: sourceURL))
        #expect(reference.targetNoteURL == CanonicalNoteIdentity.canonicalFileURL(for: targetURL))
        #expect(reference.rawTargetText == "Projects/Roadmap")
        #expect(reference.displayText == "Project Phoenix")
        #expect(reference.headingFragment == "Launch Plan")

        let outgoingLink = InspectorStore.OutgoingLinkItem(reference: reference)
        #expect(outgoingLink.noteURL == reference.targetNoteURL)
        #expect(outgoingLink.displayText == "Project Phoenix")
        #expect(outgoingLink.headingFragment == "Launch Plan")

        let store = GraphEdgeStore()
        await store.configureCanonicalResolution(with: tree)
        await store.updateExplicitReferences(for: sourceURL, references: references)

        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let canonicalTargetURL = CanonicalNoteIdentity.canonicalFileURL(for: targetURL)
        #expect(await store.edges[canonicalSourceURL] == [canonicalTargetURL])
        #expect(await store.backlinks(for: canonicalTargetURL).contains(canonicalSourceURL))

        let liveBacklinks = await store.explicitBacklinks(to: canonicalTargetURL)
        #expect(liveBacklinks == references)

        let suggestions = await LinkSuggestionService().suggestLinks(
            for: body,
            currentNoteURL: sourceURL,
            allNotes: tree,
            graphEdgeStore: store
        )
        #expect(suggestions.isEmpty)
    }

    @Test("Backlink use case overlays live explicit references without weaker reinterpretation")
    func backlinksUseLiveExplicitReferencePayloadForUnsavedLinks() async throws {
        let provider = MockVaultProvider()
        let vaultRoot = URL(fileURLWithPath: "/tmp/linking-integrity-live-backlinks-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = vaultRoot.appendingPathComponent("Source.md")
        let targetURL = vaultRoot.appendingPathComponent("Erika.md")
        let tree = [
            FileNode(name: "Source.md", url: sourceURL, nodeType: .note),
            FileNode(name: "Erika.md", url: targetURL, nodeType: .note, frontmatter: Frontmatter(title: "Erika", aliases: ["Erika Roth"]))
        ]

        await provider.addNote(NoteDocument(
            fileURL: sourceURL,
            frontmatter: Frontmatter(title: "Source"),
            body: "No saved link yet.",
            isDirty: false
        ))
        await provider.addNote(NoteDocument(
            fileURL: targetURL,
            frontmatter: Frontmatter(title: "Erika"),
            body: "# Erika",
            isDirty: false
        ))
        await provider.setFileTree(tree)

        let liveBody = "See [[Erika#Career|Erika Roth]] in the launch review."
        let catalog = NoteReferenceCatalog(allNotes: tree)
        let liveReferences = await catalog.resolvedExplicitReferences(
            in: liveBody,
            sourceNoteURL: sourceURL,
            graphEdgeStore: nil
        )
        let liveReference = try #require(liveReferences.first)

        let store = GraphEdgeStore()
        await store.configureCanonicalResolution(with: tree)
        await store.updateExplicitReferences(for: sourceURL, references: liveReferences)

        let backlinks = try await BacklinkUseCase(
            vaultProvider: provider,
            graphEdgeStore: store
        ).findBacklinks(to: targetURL, in: vaultRoot)

        #expect(backlinks.count == 1)
        #expect(backlinks.first?.sourceNoteURL == CanonicalNoteIdentity.canonicalFileURL(for: sourceURL))
        #expect(backlinks.first?.referenceRange == liveReference.matchRange)
        #expect(backlinks.first?.referenceDisplayText == liveReference.displayText)
        #expect(backlinks.first?.context == liveReference.context)
        #expect(backlinks.first?.headingFragment == liveReference.headingFragment)
    }
}
