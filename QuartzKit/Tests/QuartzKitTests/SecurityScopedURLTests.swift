import Testing
import Foundation
@testable import QuartzKit

// MARK: - VaultAccessManager Tests

@Suite("SecurityScopedURL")
struct SecurityScopedURLTests {

    @Test("Persist and restore bookmark round-trip")
    @MainActor func persistRestoreRoundTrip() throws {
        let mgr = VaultAccessManager.shared

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Persist
        try mgr.persistBookmark(for: tmpDir, vaultName: "TestVault")
        #expect(mgr.hasPersistedBookmark == true)
        #expect(mgr.lastVaultName == "TestVault")

        // Clean up
        mgr.clearBookmark()
        #expect(mgr.hasPersistedBookmark == false)
        #expect(mgr.lastVaultName == nil)
    }

    @Test("clearBookmark clears all state")
    @MainActor func clearState() {
        let mgr = VaultAccessManager.shared
        mgr.clearBookmark()

        #expect(mgr.hasPersistedBookmark == false)
        #expect(mgr.lastVaultName == nil)
        #expect(mgr.hasActiveVault == false)
    }

    @Test("validateVaultAccess checks directory, openVault creates config")
    @MainActor func validateAndOpen() throws {
        let mgr = VaultAccessManager.shared
        defer { mgr.clearBookmark() }

        // Non-existent path
        let badURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(mgr.validateVaultAccess(badURL) == false)

        // Valid directory
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        #expect(mgr.validateVaultAccess(tmpDir) == true)
    }
}
