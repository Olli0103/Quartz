#if os(macOS)
import SwiftUI
import QuartzKit

/// Isolated editor surface for the secondary `WindowGroup(for: URL.self)`.
///
/// Does not share `ContentViewModel` or `EditorSession` with the main window.
/// Each standalone window owns its own `EditorSession`, which provides:
/// autosave, file watching, inspector, formatting state, and conflict banners.
///
/// Binds to a **snapshot** of the vault at the time the window was opened,
/// plus a dedicated security-scoped access on that vault root. This keeps the
/// editor consistent when the main window switches to another vault.
struct NoteWindowRoot: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appearanceManager) private var appearance
    @Binding var noteURL: URL?

    @State private var editorSession: EditorSession?
    @State private var inspectorStore = InspectorStore()
    @State private var loadError: String?
    /// Vault for this window only; does not track main-window vault switches.
    @State private var windowVault: VaultConfig?
    /// Balances `startAccessingSecurityScopedResource` for `windowVault`.
    @State private var windowVaultAccessing = false
    @State private var trackedNoteURL: URL?

    /// Handoff element — only when the editor loaded successfully.
    private var handoffNoteElementURL: URL? {
        guard loadError == nil, editorSession != nil, let url = noteURL else { return nil }
        return url
    }

    private var vaultRootForHandoff: URL? {
        windowVault?.rootURL ?? appState.currentVault?.rootURL
    }

    var body: some View {
        Group {
            if let err = loadError {
                errorState(err)
            } else if let session = editorSession, session.note != nil {
                EditorContainerView(session: session)
                    .navigationTitle(session.note?.displayName ?? "Note")
            } else if noteURL != nil, loadError == nil, editorSession == nil {
                if windowVault == nil, appState.currentVault == nil {
                    Text(String(localized: "Open a vault from the main window first."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(String(localized: "No note selected"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .quartzAmbientShellBackground()
        .userActivity(QuartzUserActivity.openNoteActivityType, element: handoffNoteElementURL) { activeFileURL, activity in
            guard let vaultRoot = vaultRootForHandoff else {
                activity.isEligibleForHandoff = false
                activity.isEligibleForSearch = false
                return
            }
            let title = editorSession?.note?.displayName ?? activeFileURL.deletingPathExtension().lastPathComponent
            QuartzUserActivity.configureOpenNoteActivity(
                activity,
                noteURL: activeFileURL,
                displayTitle: title,
                vaultRoot: vaultRoot
            )
        }
        .task(id: noteURL) {
            await loadEditorIfNeeded()
        }
        .onDisappear {
            releaseWindowVaultAccessIfNeeded()
        }
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Security-Scoped Access

    private func releaseWindowVaultAccessIfNeeded() {
        if windowVaultAccessing, let v = windowVault {
            v.rootURL.stopAccessingSecurityScopedResource()
            windowVaultAccessing = false
        }
    }

    // MARK: - Editor Loading

    private func loadEditorIfNeeded() async {
        loadError = nil
        editorSession = nil

        guard let url = noteURL else {
            trackedNoteURL = nil
            releaseWindowVaultAccessIfNeeded()
            windowVault = nil
            return
        }

        let normalized = url.standardizedFileURL
        if trackedNoteURL != normalized {
            releaseWindowVaultAccessIfNeeded()
            windowVault = nil
            trackedNoteURL = normalized
        }

        // Resolve vault
        let vault: VaultConfig?
        if let w = windowVault {
            vault = w
        } else if let appVault = appState.currentVault,
                  normalized.path(percentEncoded: false).hasPrefix(appVault.rootURL.standardizedFileURL.path(percentEncoded: false)) {
            vault = appVault
            windowVault = appVault
            windowVaultAccessing = appVault.rootURL.startAccessingSecurityScopedResource()
        } else {
            if appState.currentVault == nil {
                return // Vault not open yet — will retry when appState changes
            }
            loadError = String(localized: "That note is not inside the open vault.")
            return
        }

        guard let vault else { return }

        guard normalized.path(percentEncoded: false).hasPrefix(vault.rootURL.standardizedFileURL.path(percentEncoded: false)) else {
            loadError = String(localized: "That note is not inside the open vault.")
            return
        }
        guard FileManager.default.fileExists(atPath: normalized.path(percentEncoded: false)) else {
            loadError = String(localized: "That note could not be found on disk.")
            return
        }

        // Create an independent EditorSession for this window
        let container = ServiceContainer.shared
        let session = EditorSession(
            vaultProvider: container.resolveVaultProvider(),
            frontmatterParser: container.resolveFrontmatterParser(),
            inspectorStore: inspectorStore
        )
        session.vaultRootURL = vault.rootURL

        // Load file tree for link suggestions
        let sidebarVM = SidebarViewModel(vaultProvider: container.resolveVaultProvider())
        await sidebarVM.loadTree(at: vault.rootURL)
        session.fileTree = sidebarVM.fileTree

        // Load the note
        await session.loadNote(at: normalized)
        editorSession = session
    }
}
#endif
