import SwiftUI
import QuartzKit
import os

/// Coordinates vault lifecycle: opening, switching, restoration, and bookmark persistence.
///
/// **Per CODEX.md F1:** Extracted from ContentView to reduce its responsibilities.
/// ContentView is now a thin layout shell; vault orchestration lives here.
@Observable
@MainActor
public final class VaultCoordinator {
    private static let uiTestShellModeArgument = "--ui-test-shell-mode"

    private static var isUITestShellMode: Bool {
        CommandLine.arguments.contains(uiTestShellModeArgument)
    }

    // MARK: - Dependencies

    private let appState: AppState
    private let logger = Logger(subsystem: "com.quartz", category: "VaultCoordinator")

    // MARK: - State

    /// Whether vault restoration has been attempted this session.
    public private(set) var hasAttemptedRestoration = false

    /// The currently active vault, if any.
    public var currentVault: VaultConfig? {
        appState.currentVault
    }

    // MARK: - Init

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Vault Opening

    /// Opens a vault and performs all associated setup.
    ///
    /// - Parameters:
    ///   - vault: The vault configuration to open.
    ///   - viewModel: ContentViewModel to load the vault into.
    ///   - noteListStore: Store for the note list.
    ///   - workspaceStore: Store to clear selection.
    ///   - onComplete: Callback after vault is loaded (for restoration).
    public func openVault(
        _ vault: VaultConfig,
        viewModel: ContentViewModel?,
        noteListStore: NoteListStore,
        workspaceStore: WorkspaceStore,
        onComplete: (() -> Void)? = nil
    ) {
        appState.switchVault(to: vault)
        viewModel?.loadVault(vault, noteListStore: noteListStore)
        workspaceStore.selectedNoteURL = nil

        logger.info("Opened vault: \(vault.name)")

        if Self.isUITestShellMode {
            onComplete?()
        } else {
            // Allow UI to settle before restoration
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                onComplete?()
            }
        }
    }

    /// Opens a vault from a URL (e.g., from file picker).
    ///
    /// Handles security-scoped access and bookmark persistence.
    public func openVaultFromURL(
        _ url: URL,
        viewModel: ContentViewModel?,
        noteListStore: NoteListStore,
        workspaceStore: WorkspaceStore,
        onComplete: (() -> Void)? = nil
    ) -> Bool {
        guard url.startAccessingSecurityScopedResource() else {
            appState.showError(String(localized: "Unable to access the selected folder. Please try again."))
            return false
        }

        let vault = VaultConfig(name: url.lastPathComponent, rootURL: url)
        persistBookmark(for: url, vaultName: vault.name)
        QuartzFeedback.success()
        openVault(vault, viewModel: viewModel, noteListStore: noteListStore, workspaceStore: workspaceStore, onComplete: onComplete)
        return true
    }

    /// Creates a new vault folder at the given URL.
    public func createVault(
        at url: URL,
        viewModel: ContentViewModel?,
        noteListStore: NoteListStore,
        workspaceStore: WorkspaceStore,
        onComplete: (() -> Void)? = nil
    ) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            appState.showError(String(localized: "Could not create the vault folder."))
            return false
        }

        _ = url.startAccessingSecurityScopedResource()
        let vault = VaultConfig(name: url.lastPathComponent, rootURL: url)
        persistBookmark(for: url, vaultName: vault.name)
        QuartzFeedback.success()
        openVault(vault, viewModel: viewModel, noteListStore: noteListStore, workspaceStore: workspaceStore, onComplete: onComplete)
        return true
    }

    // MARK: - Vault Restoration

    /// Attempts to restore the last opened vault from persisted bookmark.
    ///
    /// - Returns: The restored vault, or nil if restoration failed.
    @discardableResult
    public func restoreLastVault(
        viewModel: ContentViewModel?,
        noteListStore: NoteListStore,
        workspaceStore: WorkspaceStore,
        onComplete: (() -> Void)? = nil
    ) async -> VaultConfig? {
        hasAttemptedRestoration = true

        do {
            if let vault = try await VaultAccessManager.shared.restoreLastVaultWithRetry(maxAttempts: 2) {
                openVault(vault, viewModel: viewModel, noteListStore: noteListStore, workspaceStore: workspaceStore, onComplete: onComplete)
                logger.info("Restored vault: \(vault.name)")
                return vault
            }
        } catch {
            logger.warning("Failed to restore vault: \(error.localizedDescription)")
            QuartzDiagnostics.warning(
                category: "VaultCoordinator",
                "Failed to restore vault: \(error.localizedDescription)"
            )
        }

        // Fallback: check if another device synced an iCloud vault via KVStore
        if let iCloudVault = VaultAccessManager.shared.resolveICloudVault() {
            logger.info("Resolved iCloud vault from remote device: \(iCloudVault.name)")
            persistBookmark(for: iCloudVault.rootURL, vaultName: iCloudVault.name)
            UserDefaults.standard.set(true, forKey: "quartz.hasCompletedOnboarding")
            openVault(iCloudVault, viewModel: viewModel, noteListStore: noteListStore, workspaceStore: workspaceStore, onComplete: onComplete)
            return iCloudVault
        }

        return nil
    }

    /// Checks if there's a vault to restore without actually restoring it.
    public var canRestoreVault: Bool {
        VaultAccessManager.shared.hasPersistedBookmark
    }

    /// The name of the last vault, if available.
    public var lastVaultName: String? {
        VaultAccessManager.shared.lastVaultName
    }

    // MARK: - Bookmark Persistence

    /// Persists a security-scoped bookmark for the vault URL.
    public func persistBookmark(for url: URL, vaultName: String) {
        do {
            try VaultAccessManager.shared.persistBookmark(for: url, vaultName: vaultName)
        } catch {
            logger.error("Failed to persist bookmark: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VaultCoordinator",
                "Failed to persist bookmark: \(error.localizedDescription)"
            )
        }
    }

    /// Clears the persisted bookmark.
    public func clearBookmark() {
        VaultAccessManager.shared.clearBookmark()
        logger.info("Cleared vault bookmark")
    }

    // MARK: - Vault Switching

    /// Closes the current vault and prepares for a new one.
    public func closeCurrentVault() {
        VaultAccessManager.shared.closeActiveVault()
        appState.currentVault = nil
        logger.info("Closed current vault")
    }
}
