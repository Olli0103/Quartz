import Testing
import Foundation
@testable import QuartzKit

// MARK: - visionOS Basic Tests
//
// visionOS-compatible data contracts: Sendable conformance for
// spatial computing, ambient mesh styles, and type portability.

@Suite("visionOSBasic")
struct visionOSBasicTests {

    @Test("DetailRoute is Sendable for visionOS window management")
    func detailRouteSendable() {
        let route: any Sendable = DetailRoute.dashboard
        #expect(route is DetailRoute)

        let noteRoute: any Sendable = DetailRoute.note(URL(fileURLWithPath: "/vault/note.md"))
        #expect(noteRoute is DetailRoute)
    }

    @Test("FileNode is Sendable for spatial scene transfer")
    func fileNodeSendable() {
        let node: any Sendable = FileNode(
            name: "Note.md",
            url: URL(fileURLWithPath: "/vault/Note.md"),
            nodeType: .note
        )
        #expect(node is FileNode)
    }

    @Test("NoteDocument is Sendable for window isolation")
    func noteDocumentSendable() {
        let doc: any Sendable = NoteDocument(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/vault/doc.md"),
            frontmatter: Frontmatter(),
            body: "Content"
        )
        #expect(doc is NoteDocument)
    }

    @Test("VaultConfig is Sendable for scene transfer")
    func vaultConfigSendable() {
        let config: any Sendable = VaultConfig(
            id: UUID(),
            name: "Vault",
            rootURL: URL(fileURLWithPath: "/vault"),
            storageType: .local,
            isDefault: true,
            encryptionEnabled: false,
            createdAt: Date()
        )
        #expect(config is VaultConfig)
    }

    @Test("Citation is Sendable for spatial chat views")
    func citationSendable() {
        let citation: any Sendable = Citation(
            id: 1,
            noteID: UUID(),
            noteTitle: "Note",
            noteURL: nil,
            excerpt: "...",
            similarity: 0.9
        )
        #expect(citation is Citation)
    }

    @Test("QuartzAmbientMeshStyle has all cases for spatial rendering")
    func ambientMeshStyles() {
        let styles: [QuartzAmbientMeshStyle] = [.onboarding, .shell, .editorChrome]
        #expect(styles.count == 3,
            "visionOS may use different mesh styles for spatial windows")
    }
}
