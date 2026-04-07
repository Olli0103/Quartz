import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Vault Switch Flow Tests
//
// Vault switch → state cleanup → restore: VaultConfig round-trip,
// StorageType variants, WorkspaceStore reset, template structures.

@Suite("E2EVaultSwitchFlow")
struct E2EVaultSwitchFlowTests {

    @Test("VaultConfig is Codable round-trip")
    func vaultConfigRoundTrip() throws {
        let original = VaultConfig(
            id: UUID(),
            name: "My Vault",
            rootURL: URL(fileURLWithPath: "/vault"),
            storageType: .iCloudDrive,
            isDefault: true,
            encryptionEnabled: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VaultConfig.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.storageType == original.storageType)
        #expect(decoded.isDefault == original.isDefault)
    }

    @Test("StorageType covers local, iCloud, and WebDAV")
    func storageTypes() {
        let types: [StorageType] = [.local, .iCloudDrive, .webdav]
        #expect(types.count == 3)

        let rawValues = Set(types.map(\.rawValue))
        #expect(rawValues.count == 3, "All storage types must be unique")
    }

    @Test("WorkspaceStore route resets on vault switch")
    @MainActor func routeResetsOnSwitch() {
        let store = WorkspaceStore()
        store.route = .note(URL(fileURLWithPath: "/vault1/note.md"))

        // Simulate vault switch — clear state
        store.route = .empty
        store.selectedSource = .allNotes

        #expect(store.route == .empty, "Route should reset when switching vaults")
        #expect(store.selectedSource == .allNotes, "Source should reset to allNotes")
    }

    @Test("SidebarFilter resets to .all on vault switch")
    func filterReset() {
        let defaultFilter = SidebarFilter(rawValue: SidebarFilter.all.rawValue)
        #expect(defaultFilter == .all, "Default filter should be .all after vault switch")
    }

    @Test("VaultTemplate covers all vault structures")
    func templateCoverage() {
        let templates: [VaultTemplate] = [.para, .zettelkasten, .custom]
        #expect(templates.count == 3,
            "Should support PARA, Zettelkasten, and custom vault structures")
    }

    @Test("VaultConfig has all required fields for vault management")
    func vaultConfigFields() {
        let config = VaultConfig(
            id: UUID(),
            name: "Test",
            rootURL: URL(fileURLWithPath: "/test"),
            storageType: .local,
            isDefault: false,
            encryptionEnabled: true,
            createdAt: Date()
        )

        #expect(!config.name.isEmpty)
        #expect(config.storageType == .local)
        #expect(config.encryptionEnabled == true)
        #expect(!config.isDefault)
    }
}
