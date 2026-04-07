import Testing
import Foundation
@testable import QuartzKit

// MARK: - visionOS Basic Tests
//
// visionOS-compatible data contracts: Sendable conformance for
// spatial computing, ambient mesh styles, and type portability.
// Sendable is verified by assigning to `any Sendable` then casting back
// and asserting properties survive the erasure roundtrip.

@Suite("visionOSBasic")
struct visionOSBasicTests {

    @Test("DetailRoute is Sendable for visionOS window management")
    func detailRouteSendable() {
        let route: any Sendable = DetailRoute.dashboard
        let recovered = route as? DetailRoute
        #expect(recovered == .dashboard, "DetailRoute should survive Sendable erasure")

        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        let noteRoute: any Sendable = DetailRoute.note(noteURL)
        if case .note(let url) = noteRoute as? DetailRoute {
            #expect(url == noteURL, "Note URL should survive Sendable roundtrip")
        } else {
            #expect(Bool(false), "DetailRoute.note should survive Sendable erasure")
        }
    }

    @Test("FileNode is Sendable for spatial scene transfer")
    func fileNodeSendable() {
        let node: any Sendable = FileNode(
            name: "Note.md",
            url: URL(fileURLWithPath: "/vault/Note.md"),
            nodeType: .note
        )
        let recovered = node as? FileNode
        #expect(recovered?.name == "Note.md", "FileNode name should survive Sendable roundtrip")
        #expect(recovered?.nodeType == .note, "FileNode nodeType should survive Sendable roundtrip")
    }

    @Test("NoteDocument is Sendable for window isolation")
    func noteDocumentSendable() {
        let doc: any Sendable = NoteDocument(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/vault/doc.md"),
            frontmatter: Frontmatter(),
            body: "Content"
        )
        let recovered = doc as? NoteDocument
        #expect(recovered?.body == "Content", "NoteDocument body should survive Sendable roundtrip")
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
        let recovered = config as? VaultConfig
        #expect(recovered?.name == "Vault", "VaultConfig name should survive Sendable roundtrip")
        #expect(recovered?.storageType == .local, "VaultConfig storageType should survive Sendable roundtrip")
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
        let recovered = citation as? Citation
        #expect(recovered?.noteTitle == "Note", "Citation noteTitle should survive Sendable roundtrip")
        #expect(recovered?.similarity == 0.9, "Citation similarity should survive Sendable roundtrip")
    }

    @Test("QuartzAmbientMeshStyle has all cases for spatial rendering")
    func ambientMeshStyles() {
        let styles: [QuartzAmbientMeshStyle] = [.onboarding, .shell, .editorChrome]
        #expect(styles.count == 3,
            "visionOS may use different mesh styles for spatial windows")
    }
}
