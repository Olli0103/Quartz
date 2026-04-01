import Foundation
import os

/// Centralized manager for vault security-scoped bookmark handling.
///
/// **Per CODEX.md F7:** Bookmark logic was duplicated in ContentView and VaultPickerView.
/// This manager centralizes all bookmark operations with consistent error handling.
///
/// **Responsibilities:**
/// - Create security-scoped bookmarks for vault URLs
/// - Restore vaults from persisted bookmarks
/// - Handle stale bookmark refresh
/// - Provide consistent error handling across all entry paths
@MainActor
@Observable
public final class VaultAccessManager {

    // MARK: - Singleton

    /// Shared instance for app-wide vault access management.
    public static let shared = VaultAccessManager()

    // MARK: - State

    /// The currently active vault URL, if any.
    public private(set) var activeVaultURL: URL?

    /// Whether a vault is currently accessible.
    public var hasActiveVault: Bool { activeVaultURL != nil }

    /// Last error encountered during vault operations.
    public private(set) var lastError: VaultAccessError?

    // MARK: - Constants

    private let bookmarkKey = "quartz.lastVault.bookmark"
    private let nameKey = "quartz.lastVault.name"
    private let logger = Logger(subsystem: "com.quartz", category: "VaultAccessManager")

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Creates and persists a security-scoped bookmark for the given vault URL.
    ///
    /// - Parameters:
    ///   - url: The vault root URL to bookmark.
    ///   - name: The display name for the vault.
    /// - Throws: `VaultAccessError` if bookmark creation fails.
    public func persistBookmark(for url: URL, vaultName: String) throws {
        do {
            #if os(macOS)
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif

            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            UserDefaults.standard.set(vaultName, forKey: nameKey)
            logger.info("Persisted bookmark for vault: \(vaultName)")
        } catch {
            logger.error("Failed to persist vault bookmark: \(error.localizedDescription)")
            throw VaultAccessError.bookmarkCreationFailed(error)
        }
    }

    /// Restores a vault from the persisted bookmark.
    ///
    /// - Returns: `VaultConfig` if restoration succeeds, `nil` if no bookmark exists.
    /// - Throws: `VaultAccessError` if bookmark exists but cannot be restored.
    public func restoreLastVault() throws -> VaultConfig? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url: URL

        do {
            #if os(macOS)
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
            #else
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                bookmarkDataIsStale: &isStale
            )
            #endif
        } catch {
            clearBookmark()
            throw VaultAccessError.bookmarkResolutionFailed(error)
        }

        guard url.startAccessingSecurityScopedResource() else {
            clearBookmark()
            throw VaultAccessError.securityScopeAccessDenied(url)
        }

        // Refresh stale bookmarks
        if isStale {
            logger.info("Refreshing stale bookmark for: \(url.lastPathComponent)")
            do {
                try persistBookmark(for: url, vaultName: url.lastPathComponent)
            } catch {
                // Non-fatal: we can still use the old bookmark this session
                logger.warning("Failed to refresh stale bookmark: \(error.localizedDescription)")
            }
        }

        let name = UserDefaults.standard.string(forKey: nameKey) ?? url.lastPathComponent
        activeVaultURL = url

        logger.info("Restored vault: \(name)")
        return VaultConfig(name: name, rootURL: url)
    }

    /// Clears the persisted bookmark.
    public func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        activeVaultURL = nil
        logger.info("Cleared vault bookmark")
    }

    /// Checks if a persisted bookmark exists.
    public var hasPersistedBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Returns the name of the last vault, if any.
    public var lastVaultName: String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    /// Opens a vault URL and persists its bookmark.
    ///
    /// - Parameters:
    ///   - url: The vault root URL.
    ///   - name: Optional display name (defaults to URL's last path component).
    /// - Returns: `VaultConfig` for the opened vault.
    /// - Throws: `VaultAccessError` if access or persistence fails.
    public func openVault(at url: URL, name: String? = nil) throws -> VaultConfig {
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultAccessError.securityScopeAccessDenied(url)
        }

        let vaultName = name ?? url.lastPathComponent
        try persistBookmark(for: url, vaultName: vaultName)

        activeVaultURL = url
        return VaultConfig(name: vaultName, rootURL: url)
    }

    /// Stops accessing the currently active vault.
    public func closeActiveVault() {
        if let url = activeVaultURL {
            url.stopAccessingSecurityScopedResource()
            logger.info("Closed vault: \(url.lastPathComponent)")
        }
        activeVaultURL = nil
    }
}

// MARK: - Error Types

/// Errors that can occur during vault access operations.
public enum VaultAccessError: LocalizedError {
    case bookmarkCreationFailed(Error)
    case bookmarkResolutionFailed(Error)
    case securityScopeAccessDenied(URL)
    case vaultNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed(let error):
            return String(localized: "Could not save vault access: \(error.localizedDescription)")
        case .bookmarkResolutionFailed(let error):
            return String(localized: "Could not restore vault: \(error.localizedDescription)")
        case .securityScopeAccessDenied(let url):
            return String(localized: "Access to '\(url.lastPathComponent)' was denied. Please re-select the folder.")
        case .vaultNotFound(let url):
            return String(localized: "Vault folder not found: \(url.lastPathComponent)")
        }
    }
}
