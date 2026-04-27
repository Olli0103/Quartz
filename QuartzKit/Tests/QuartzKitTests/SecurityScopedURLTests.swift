import Testing
import Foundation
@testable import QuartzKit

// MARK: - VaultAccessManager Tests

@Suite("SecurityScopedURL", .serialized)
struct SecurityScopedURLTests {
    private enum StubRestoreError: Error {
        case resolutionFailed
    }

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

    @Test("restoreLastVault preserves bookmark when bookmark resolution fails")
    @MainActor func restoreLastVaultPreservesBookmarkOnResolutionFailure() throws {
        let mgr = VaultAccessManager.shared
        mgr.clearBookmark()
        mgr.resetTestingOverrides()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-restore-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            mgr.resetTestingOverrides()
            mgr.clearBookmark()
            try? FileManager.default.removeItem(at: tmpDir)
        }

        try mgr.persistBookmark(for: tmpDir, vaultName: "RetryVault")
        mgr.bookmarkResolverOverride = { _ in
            throw StubRestoreError.resolutionFailed
        }

        do {
            _ = try mgr.restoreLastVault()
            Issue.record("Expected bookmark resolution to fail")
        } catch let error as VaultAccessError {
            guard case .bookmarkResolutionFailed = error else {
                Issue.record("Unexpected vault access error: \(error.localizedDescription)")
                return
            }
        }

        #expect(mgr.hasPersistedBookmark == true)
        #expect(mgr.lastVaultName == "RetryVault")
        #expect(mgr.hasActiveVault == false)
    }

    @Test("restoreLastVault preserves bookmark when security scope access is denied")
    @MainActor func restoreLastVaultPreservesBookmarkOnAccessDenied() throws {
        let mgr = VaultAccessManager.shared
        mgr.clearBookmark()
        mgr.resetTestingOverrides()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-access-denied-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            mgr.resetTestingOverrides()
            mgr.clearBookmark()
            try? FileManager.default.removeItem(at: tmpDir)
        }

        try mgr.persistBookmark(for: tmpDir, vaultName: "RetryVault")
        mgr.bookmarkResolverOverride = { _ in
            VaultAccessManager.ResolvedBookmark(url: tmpDir, isStale: false)
        }
        mgr.securityScopeAccessOverride = { _ in false }

        do {
            _ = try mgr.restoreLastVault()
            Issue.record("Expected security-scoped restore to fail")
        } catch let error as VaultAccessError {
            guard case .securityScopeAccessDenied = error else {
                Issue.record("Unexpected vault access error: \(error.localizedDescription)")
                return
            }
        }

        #expect(mgr.hasPersistedBookmark == true)
        #expect(mgr.lastVaultName == "RetryVault")
        #expect(mgr.hasActiveVault == false)
    }

    @Test("failed restore clears stale active vault URL")
    @MainActor func failedRestoreClearsStaleActiveVaultURL() throws {
        let mgr = VaultAccessManager.shared
        mgr.clearBookmark()
        mgr.resetTestingOverrides()

        let oldVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-active-vault-\(UUID().uuidString)")
        let retryVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry-active-vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: oldVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: retryVault, withIntermediateDirectories: true)
        defer {
            mgr.resetTestingOverrides()
            mgr.clearBookmark()
            try? FileManager.default.removeItem(at: oldVault)
            try? FileManager.default.removeItem(at: retryVault)
        }

        mgr.registerActiveVault(VaultConfig(name: "OldVault", rootURL: oldVault))
        #expect(mgr.hasActiveVault == true)

        try mgr.persistBookmark(for: retryVault, vaultName: "RetryVault")
        mgr.bookmarkResolverOverride = { _ in
            VaultAccessManager.ResolvedBookmark(url: retryVault, isStale: false)
        }
        mgr.securityScopeAccessOverride = { _ in false }

        do {
            _ = try mgr.restoreLastVault()
            Issue.record("Expected security-scoped restore to fail")
        } catch let error as VaultAccessError {
            guard case .securityScopeAccessDenied = error else {
                Issue.record("Unexpected vault access error: \(error.localizedDescription)")
                return
            }
        }

        #expect(mgr.hasPersistedBookmark == true)
        #expect(mgr.lastVaultName == "RetryVault")
        #expect(mgr.hasActiveVault == false)
    }
}
