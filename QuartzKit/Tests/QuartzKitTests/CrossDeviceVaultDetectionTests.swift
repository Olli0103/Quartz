import Testing
import Foundation
@testable import QuartzKit

// MARK: - Cross-Device iCloud Vault Detection Tests

@Suite("CrossDeviceVaultDetection")
struct CrossDeviceVaultDetectionTests {

    // MARK: - iCloud Relative Path Extraction

    @Test("Extracts relative path from iCloud container URL (tilde format)")
    @MainActor func iCloudRelativePathExtraction_tildeFormat() {
        let manager = VaultAccessManager.shared
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/iCloud~olli~QuartzNotes/Documents/My Vault")
        let relativePath = manager.iCloudRelativePath(for: url)
        #expect(relativePath == "My Vault")
    }

    @Test("Extracts relative path from iCloud container URL (dot format)")
    @MainActor func iCloudRelativePathExtraction_dotFormat() {
        let manager = VaultAccessManager.shared
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/iCloud.olli.QuartzNotes/Documents/My Vault")
        let relativePath = manager.iCloudRelativePath(for: url)
        #expect(relativePath == "My Vault")
    }

    @Test("Returns nil for non-iCloud vault path")
    @MainActor func iCloudRelativePathExtraction_nonICloud() {
        let manager = VaultAccessManager.shared
        let url = URL(fileURLWithPath: "/Users/test/Documents/LocalVault")
        let relativePath = manager.iCloudRelativePath(for: url)
        #expect(relativePath == nil)
    }

    @Test("Returns nil for iCloud container root (empty relative path)")
    @MainActor func iCloudRelativePathExtraction_containerRoot() {
        let manager = VaultAccessManager.shared
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/iCloud~olli~QuartzNotes/Documents/")
        let relativePath = manager.iCloudRelativePath(for: url)
        #expect(relativePath == nil)
    }

    // MARK: - KVStore API

    @Test("iCloudSyncedVaultInfo returns nil when KVStore has no vault data")
    @MainActor func kvStoreReturnsNilWhenEmpty() {
        // In test runner without iCloud entitlements, KVStore is always empty
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.removeObject(forKey: "icloud.vault.relativePath")
        kvStore.removeObject(forKey: "icloud.vault.name")

        let info = VaultAccessManager.shared.iCloudSyncedVaultInfo()
        #expect(info == nil, "Should return nil when no vault info is synced")
    }

    // MARK: - Resolve Returns Nil

    @Test("resolveICloudVault returns nil when no synced vault exists")
    @MainActor func resolveReturnsNilWhenNoSyncedVault() {
        // Ensure KVStore is clean
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.removeObject(forKey: "icloud.vault.relativePath")
        kvStore.removeObject(forKey: "icloud.vault.name")
        kvStore.synchronize()

        let result = VaultAccessManager.shared.resolveICloudVault()
        #expect(result == nil, "Should return nil when no vault is synced")
    }

    // MARK: - Clear Bookmark

    @Test("clearBookmark resets active vault and local bookmark state")
    @MainActor func clearBookmarkResetsState() {
        let manager = VaultAccessManager.shared

        // Clear should not crash and should reset activeVaultURL
        manager.clearBookmark()

        #expect(manager.activeVaultURL == nil,
            "Active vault URL should be nil after clearBookmark")
        #expect(manager.hasPersistedBookmark == false,
            "No persisted bookmark should remain after clearBookmark")
        #expect(manager.lastVaultName == nil,
            "Last vault name should be nil after clearBookmark")

        // iCloudSyncedVaultInfo should also be nil (KVStore cleared)
        let info = manager.iCloudSyncedVaultInfo()
        #expect(info == nil, "Synced vault info should be nil after clearBookmark")
    }
}
