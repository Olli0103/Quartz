import Testing
import Foundation
@testable import QuartzKit

// MARK: - iPad Stage Manager Tests
//
// Multi-window and resize data contracts: independent WorkspaceStore
// per scene, Codable types for scene transfer, Sendable contracts.

@Suite("iPadStageManager")
struct iPadStageManagerTests {

    @Test("WorkspaceStore instances are independent per scene")
    @MainActor func independentStores() {
        let store1 = WorkspaceStore()
        let store2 = WorkspaceStore()

        store1.route = .dashboard
        store2.route = .note(URL(fileURLWithPath: "/vault/note.md"))

        #expect(store1.route == .dashboard)
        #expect(store2.route == .note(URL(fileURLWithPath: "/vault/note.md")))
        #expect(store1.route != store2.route,
            "Each WorkspaceStore should maintain independent route state")
    }

    @Test("WorkspaceStore source selection is independent per scene")
    @MainActor func independentSourceSelection() {
        let store1 = WorkspaceStore()
        let store2 = WorkspaceStore()

        store1.selectedSource = .favorites
        store2.selectedSource = .tag("swift")

        #expect(store1.selectedSource == .favorites)
        #expect(store2.selectedSource == .tag("swift"))
    }

    @Test("VaultConfig is Codable for scene state transfer")
    func vaultConfigCodable() throws {
        let config = VaultConfig(
            id: UUID(),
            name: "TestVault",
            rootURL: URL(fileURLWithPath: "/vault"),
            storageType: .local,
            isDefault: true,
            encryptionEnabled: false,
            createdAt: Date()
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VaultConfig.self, from: data)

        #expect(decoded.name == config.name)
        #expect(decoded.rootURL == config.rootURL)
        #expect(decoded.storageType == config.storageType)
        #expect(decoded.isDefault == config.isDefault)
    }

    @Test("FileNode is Sendable for cross-scene transfer")
    func fileNodeSendable() {
        let node = FileNode(
            name: "Note.md",
            url: URL(fileURLWithPath: "/vault/Note.md"),
            nodeType: .note
        )

        // Sendable conformance verified at compile time
        let sendableNode: any Sendable = node
        #expect(sendableNode is FileNode)
    }

    @Test("NoteDocument is Sendable for cross-scene transfer")
    func noteDocumentSendable() {
        let doc = NoteDocument(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/vault/doc.md"),
            frontmatter: Frontmatter(),
            body: "Content"
        )

        let sendable: any Sendable = doc
        #expect(sendable is NoteDocument)
        #expect(doc.body == "Content")
    }
}
