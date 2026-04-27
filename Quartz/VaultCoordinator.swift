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
        clearSelection: Bool = true,
        onComplete: (() -> Void)? = nil
    ) {
        DeveloperDiagnostics.loadVaultConfiguration(from: vault.rootURL)
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .vaultRestore,
            name: "vaultOpenStarted",
            reasonCode: clearSelection ? "vault.manualOpen" : "vault.restoreOpen",
            vaultName: vault.name,
            metadata: ["selectionPolicy": clearSelection ? "cleared" : "preserved"]
        )
        VaultAccessManager.shared.registerActiveVault(vault)
        appState.switchVault(to: vault)
        viewModel?.loadVault(vault, noteListStore: noteListStore)
        if clearSelection {
            workspaceStore.selectedNoteURL = nil
        }

        logger.info("Opened vault: \(vault.name)")
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .vaultRestore,
            name: "vaultOpenCompleted",
            reasonCode: clearSelection ? "vault.manualOpenCompleted" : "vault.restoreCompleted",
            vaultName: vault.name,
            metadata: ["selectionPolicy": clearSelection ? "cleared" : "preserved"]
        )

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
        let vault: VaultConfig
        do {
            vault = try VaultAccessManager.shared.openVault(at: url)
        } catch {
            appState.showError(error.localizedDescription)
            logger.error("Failed to open selected vault: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VaultCoordinator",
                "Failed to open selected vault: \(error.localizedDescription)"
            )
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .vaultRestore,
                name: "vaultOpenFailed",
                reasonCode: "vault.restoreFailed",
                vaultName: url.lastPathComponent,
                metadata: ["error": error.localizedDescription]
            )
            return false
        }

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

        let vault: VaultConfig
        do {
            vault = try VaultAccessManager.shared.openVault(at: url)
        } catch {
            appState.showError(error.localizedDescription)
            logger.error("Failed to register created vault: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VaultCoordinator",
                "Failed to register created vault: \(error.localizedDescription)"
            )
            return false
        }
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
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .vaultRestore,
            name: "vaultRestoreStarted",
            reasonCode: VaultAccessManager.shared.hasPersistedBookmark ? "vault.bookmarkExists" : "vault.noBookmark",
            metadata: ["persistedBookmarkExists": String(VaultAccessManager.shared.hasPersistedBookmark)]
        )

        do {
            if let vault = try await VaultAccessManager.shared.restoreLastVaultWithRetry(maxAttempts: 2) {
                openVault(
                    vault,
                    viewModel: viewModel,
                    noteListStore: noteListStore,
                    workspaceStore: workspaceStore,
                    clearSelection: false,
                    onComplete: onComplete
                )
                logger.info("Restored vault: \(vault.name)")
                SubsystemDiagnostics.record(
                    level: .info,
                    subsystem: .vaultRestore,
                    name: "vaultRestoreCompleted",
                    reasonCode: "vault.restoreCompleted",
                    vaultName: vault.name
                )
                return vault
            }
        } catch {
            logger.warning("Failed to restore vault: \(error.localizedDescription)")
            appState.showError(error.localizedDescription)
            QuartzDiagnostics.warning(
                category: "VaultCoordinator",
                "Failed to restore vault: \(error.localizedDescription)"
            )
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .vaultRestore,
                name: "vaultRestoreFailed",
                reasonCode: "vault.restoreFailed",
                metadata: ["error": error.localizedDescription]
            )
        }

        // Fallback: check if another device synced an iCloud vault via KVStore
        if let iCloudVault = VaultAccessManager.shared.resolveICloudVault() {
            logger.info("Resolved iCloud vault from remote device: \(iCloudVault.name)")
            let vault: VaultConfig
            do {
                vault = try VaultAccessManager.shared.openVault(at: iCloudVault.rootURL, name: iCloudVault.name)
            } catch {
                logger.warning("Failed to open iCloud-synced vault: \(error.localizedDescription)")
                QuartzDiagnostics.warning(
                    category: "VaultCoordinator",
                    "Failed to open iCloud-synced vault: \(error.localizedDescription)"
                )
                return nil
            }
            UserDefaults.standard.set(true, forKey: "quartz.hasCompletedOnboarding")
            openVault(
                vault,
                viewModel: viewModel,
                noteListStore: noteListStore,
                workspaceStore: workspaceStore,
                clearSelection: false,
                onComplete: onComplete
            )
            return vault
        }

        if VaultAccessManager.shared.hasPersistedBookmark {
            QuartzDiagnostics.warning(
                category: "VaultCoordinator",
                "Persisted vault bookmark exists but no vault could be restored"
            )
        } else {
            QuartzDiagnostics.warning(
                category: "VaultCoordinator",
                "Vault restore skipped because no persisted bookmark exists"
            )
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
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .vaultRestore,
            name: "closeVaultStarted",
            vaultName: appState.currentVault?.name
        )
        VaultAccessManager.shared.closeActiveVault()
        appState.currentVault = nil
        logger.info("Closed current vault")
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .vaultRestore,
            name: "closeVaultCompleted"
        )
    }
}
