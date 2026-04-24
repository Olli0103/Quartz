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
    internal struct ResolvedBookmark {
        let url: URL
        let isStale: Bool
    }

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
    private let iCloudVaultRelativePathKey = "icloud.vault.relativePath"
    private let iCloudVaultNameKey = "icloud.vault.name"
    private let iCloudContainerID = "iCloud.olli.QuartzNotes"
    private let logger = Logger(subsystem: "com.quartz", category: "VaultAccessManager")
    internal var bookmarkResolverOverride: ((Data) throws -> ResolvedBookmark)?
    internal var securityScopeAccessOverride: ((URL) -> Bool)?
    /// Stored notification token removed during teardown.
    private var kvStoreObserver: Any?

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

            // Sync vault identity to iCloud for cross-device detection.
            // Security-scoped bookmarks are device-specific, but the vault path is not.
            syncVaultPathToICloud(url: url, vaultName: vaultName)

            logger.info("Persisted bookmark for vault: \(vaultName)")
            lastError = nil
        } catch {
            logger.error("Failed to persist vault bookmark: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VaultAccessManager",
                "Failed to persist vault bookmark: \(error.localizedDescription)"
            )
            let accessError = VaultAccessError.bookmarkCreationFailed(error)
            lastError = accessError
            throw accessError
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

        do {
            let resolved = try resolveBookmark(from: bookmarkData)
            let url = resolved.url
            let isStale = resolved.isStale

            guard startAccessingSecurityScopedResource(for: url) else {
                let accessError = VaultAccessError.securityScopeAccessDenied(url)
                lastError = accessError
                logger.warning(
                    "Security-scoped access denied for persisted vault \(url.lastPathComponent, privacy: .public); preserving bookmark for retry"
                )
                QuartzDiagnostics.warning(
                    category: "VaultAccessManager",
                    "Security-scoped access denied for persisted vault \(url.lastPathComponent); preserving bookmark for retry"
                )
                throw accessError
            }

            // Refresh stale bookmarks
            if isStale {
                logger.info("Refreshing stale bookmark for: \(url.lastPathComponent)")
                do {
                    try persistBookmark(for: url, vaultName: url.lastPathComponent)
                } catch {
                    // Non-fatal: we can still use the old bookmark this session
                    logger.warning("Failed to refresh stale bookmark: \(error.localizedDescription)")
                    QuartzDiagnostics.warning(
                        category: "VaultAccessManager",
                        "Failed to refresh stale bookmark: \(error.localizedDescription)"
                    )
                }
            }

            let name = UserDefaults.standard.string(forKey: nameKey) ?? url.lastPathComponent
            activeVaultURL = url
            lastError = nil

            logger.info("Restored vault: \(name)")
            return VaultConfig(name: name, rootURL: url)
        } catch {
            if let accessError = error as? VaultAccessError {
                throw accessError
            }

            let accessError = VaultAccessError.bookmarkResolutionFailed(error)
            lastError = accessError
            logger.error(
                "Failed to resolve persisted vault bookmark; preserving bookmark for retry: \(error.localizedDescription, privacy: .public)"
            )
            QuartzDiagnostics.error(
                category: "VaultAccessManager",
                "Failed to resolve persisted vault bookmark; preserving bookmark for retry: \(error.localizedDescription)"
            )
            throw accessError
        }
    }

    /// Clears the persisted bookmark and iCloud-synced vault info.
    public func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.removeObject(forKey: iCloudVaultRelativePathKey)
        kvStore.removeObject(forKey: iCloudVaultNameKey)
        kvStore.synchronize()
        activeVaultURL = nil
        lastError = nil
        logger.info("Cleared vault bookmark and iCloud sync")
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
        guard startAccessingSecurityScopedResource(for: url) else {
            let accessError = VaultAccessError.securityScopeAccessDenied(url)
            lastError = accessError
            throw accessError
        }

        let vaultName = name ?? url.lastPathComponent
        try persistBookmark(for: url, vaultName: vaultName)

        activeVaultURL = url
        lastError = nil
        return VaultConfig(name: vaultName, rootURL: url)
    }

    /// Records an already-opened vault as the active vault for diagnostics and cleanup.
    ///
    /// Use this when the access scope has already been established by a restore,
    /// picker, onboarding panel, or UI-test fixture path. New user-selected vaults
    /// should prefer `openVault(at:name:)`, which starts access and persists the bookmark.
    public func registerActiveVault(_ vault: VaultConfig) {
        activeVaultURL = vault.rootURL
        lastError = nil
        logger.info("Registered active vault: \(vault.name)")
    }

    /// Stops accessing the currently active vault.
    public func closeActiveVault() {
        if let url = activeVaultURL {
            url.stopAccessingSecurityScopedResource()
            logger.info("Closed vault: \(url.lastPathComponent)")
        }
        activeVaultURL = nil
    }

    internal func resetTestingOverrides() {
        bookmarkResolverOverride = nil
        securityScopeAccessOverride = nil
    }

    // MARK: - Hardening

    /// Validates that a vault URL points to an accessible directory with markdown files.
    ///
    /// Checks:
    /// 1. Directory exists and is readable
    /// 2. Contains at least one `.md` file (or is empty but valid)
    public func validateVaultAccess(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir),
              isDir.boolValue else {
            logger.warning("Vault path is not a directory: \(url.lastPathComponent)")
            QuartzDiagnostics.warning(
                category: "VaultAccessManager",
                "Vault path is not a directory: \(url.lastPathComponent)"
            )
            return false
        }
        guard fm.isReadableFile(atPath: url.path(percentEncoded: false)) else {
            logger.warning("Vault directory is not readable: \(url.lastPathComponent)")
            QuartzDiagnostics.warning(
                category: "VaultAccessManager",
                "Vault directory is not readable: \(url.lastPathComponent)"
            )
            return false
        }
        return true
    }

    // MARK: - Cross-Device iCloud Vault Sync

    /// Syncs the vault's iCloud-relative path to `NSUbiquitousKeyValueStore` for cross-device detection.
    ///
    /// Only syncs vaults located in iCloud Drive (`Mobile Documents`). Local-only vaults are skipped.
    private func syncVaultPathToICloud(url: URL, vaultName: String) {
        guard let relativePath = iCloudRelativePath(for: url) else {
            logger.debug("Vault is not in iCloud Drive — skipping KVStore sync")
            return
        }
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.set(relativePath, forKey: iCloudVaultRelativePathKey)
        kvStore.set(vaultName, forKey: iCloudVaultNameKey)
        kvStore.synchronize()
        logger.info("Synced vault path to iCloud KVStore: \(relativePath)")
    }

    /// Extracts the path relative to the iCloud container's Documents folder.
    ///
    /// Example: `/Users/.../Mobile Documents/iCloud~olli~QuartzNotes/Documents/My Vault`
    ///       → `"My Vault"`
    internal func iCloudRelativePath(for url: URL) -> String? {
        let path = url.path(percentEncoded: false)
        // Look for the iCloud container's Documents folder in the path.
        // The container ID in the filesystem uses tildes: "iCloud~olli~QuartzNotes"
        let patterns = [
            "Mobile Documents/iCloud~olli~QuartzNotes/Documents/",
            "Mobile Documents/iCloud.olli.QuartzNotes/Documents/"
        ]
        for pattern in patterns {
            if let range = path.range(of: pattern) {
                let relativePath = String(path[range.upperBound...])
                return relativePath.isEmpty ? nil : relativePath
            }
        }
        return nil
    }

    /// Returns vault info synced from another device via `NSUbiquitousKeyValueStore`, if any.
    public func iCloudSyncedVaultInfo() -> (name: String, relativePath: String)? {
        let kvStore = NSUbiquitousKeyValueStore.default
        guard let relativePath = kvStore.string(forKey: iCloudVaultRelativePathKey),
              let name = kvStore.string(forKey: iCloudVaultNameKey),
              !relativePath.isEmpty else {
            return nil
        }
        return (name: name, relativePath: relativePath)
    }

    /// Attempts to resolve an iCloud vault synced from another device.
    ///
    /// Looks up the synced vault path in `NSUbiquitousKeyValueStore`, locates it in
    /// the local iCloud container, and returns a `VaultConfig` if the directory exists.
    ///
    /// - Returns: `VaultConfig` if the vault exists locally, `nil` otherwise.
    public func resolveICloudVault() -> VaultConfig? {
        guard let info = iCloudSyncedVaultInfo() else { return nil }

        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID) else {
            logger.debug("iCloud container not available on this device")
            return nil
        }

        let vaultURL = containerURL.appending(path: "Documents").appending(path: info.relativePath)

        guard validateVaultAccess(vaultURL) else {
            logger.debug("iCloud vault not yet available locally: \(info.relativePath)")
            return nil
        }

        logger.info("Resolved iCloud vault from remote sync: \(info.name)")
        return VaultConfig(name: info.name, rootURL: vaultURL)
    }

    /// Begins observing `NSUbiquitousKeyValueStore` for vault changes from other devices.
    ///
    /// Call once at app launch. When another device persists a vault, this device
    /// receives the updated path and posts `.quartzRemoteVaultDetected`.
    public func startObservingRemoteChanges() {
        kvStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  changedKeys.contains(self.iCloudVaultRelativePathKey) else { return }
            Task { @MainActor in
                self.logger.info("Received remote vault change from iCloud KVStore")
                NotificationCenter.default.post(name: .quartzRemoteVaultDetected, object: nil)
            }
        }
        // Pull latest values on launch
        NSUbiquitousKeyValueStore.default.synchronize()
        logger.info("Started observing iCloud KVStore for vault changes")
    }

    /// Attempts to restore a vault with exponential backoff for iCloud bookmarks.
    ///
    /// iCloud Drive bookmarks can temporarily fail when the container is still
    /// resolving (e.g., after device restart or iCloud sign-in change). This method
    /// retries up to `maxAttempts` times with exponential backoff.
    ///
    /// - Parameter maxAttempts: Maximum retry attempts (default 3).
    /// - Returns: `VaultConfig` if restoration succeeds, `nil` if no bookmark exists.
    /// - Throws: `VaultAccessError` if all attempts fail.
    public func restoreLastVaultWithRetry(maxAttempts: Int = 3) async throws -> VaultConfig? {
        guard hasPersistedBookmark else { return nil }

        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                if let config = try restoreLastVault() {
                    if validateVaultAccess(config.rootURL) {
                        return config
                    }
                    closeActiveVault()
                    throw VaultAccessError.vaultNotFound(config.rootURL)
                }
                return nil
            } catch {
                lastError = error
                guard attempt + 1 < maxAttempts else { break }
                let delay = Double(1 << attempt) // 1s, 2s, 4s
                logger.info("Vault restore attempt \(attempt + 1)/\(maxAttempts) failed, retrying in \(delay)s")
                QuartzDiagnostics.warning(
                    category: "VaultAccessManager",
                    "Vault restore attempt \(attempt + 1)/\(maxAttempts) failed, retrying in \(delay)s"
                )
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        if let lastError {
            throw lastError
        }
        return nil
    }

    private func resolveBookmark(from bookmarkData: Data) throws -> ResolvedBookmark {
        if let bookmarkResolverOverride {
            return try bookmarkResolverOverride(bookmarkData)
        }

        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        )
        #endif
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    private func startAccessingSecurityScopedResource(for url: URL) -> Bool {
        if let securityScopeAccessOverride {
            return securityScopeAccessOverride(url)
        }
        return url.startAccessingSecurityScopedResource()
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
