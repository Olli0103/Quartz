import SwiftUI
import QuartzKit
import os

/// Coordinates deep link handling: widget links, Handoff, and quartz:// URL scheme.
///
/// **Per CODEX.md F1:** Extracted from ContentView to reduce its responsibilities.
/// ContentView is now a thin layout shell; deep link orchestration lives here.
@Observable
@MainActor
public final class DeepLinkCoordinator {

    // MARK: - Dependencies

    private let appState: AppState
    private let logger = Logger(subsystem: "com.quartz", category: "DeepLinkCoordinator")

    // MARK: - State

    /// The shared UserDefaults suite for widget communication.
    private let sharedDefaults = UserDefaults(suiteName: "group.app.quartz.shared")

    // MARK: - Init

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Widget Deep Links

    /// Consumes any pending deep links from widgets or extensions.
    ///
    /// Call this on app activation and after vault restoration.
    ///
    /// - Parameters:
    ///   - coordinator: AppCoordinator for sheet presentation.
    ///   - workspaceStore: WorkspaceStore for route changes.
    ///   - onSelectNote: Callback when a note URL should be selected.
    public func consumePendingWidgetDeepLinks(
        coordinator: AppCoordinator,
        workspaceStore: WorkspaceStore,
        onSelectNote: @escaping (URL) -> Void
    ) {
        // Handle pending document scanner
        if sharedDefaults?.bool(forKey: "pendingDocumentScanner") == true {
            sharedDefaults?.removeObject(forKey: "pendingDocumentScanner")
            // TODO: Scanner presentation needs architectural fix (see CODEX.md F3)
            #if os(iOS)
            // Currently no-op until EditorContainerView observes AppState
            #endif
        }

        // Handle pending deep link
        guard let link = sharedDefaults?.string(forKey: "pendingDeepLink") else { return }
        sharedDefaults?.removeObject(forKey: "pendingDeepLink")

        logger.debug("Processing deep link: \(link)")

        // Handle quartz://note/<path> links
        if let url = URL(string: link), url.scheme == "quartz", url.host() == "note" {
            if let noteURL = resolveNoteDeepLink(url) {
                onSelectNote(noteURL)
            }
            return
        }

        // Handle action deep links
        switch link {
        case "quartz://new":
            appState.pendingCommand = .newNote
        case "quartz://daily":
            appState.pendingCommand = .dailyNote
        case "quartz://audio":
            coordinator.activeSheet = .voiceNote
        case "quartz://dashboard":
            workspaceStore.setRoute(.dashboard)
        case "quartz://scan":
            // TODO: Scanner presentation needs architectural fix (see CODEX.md F3)
            #if os(iOS)
            // Currently no-op until EditorContainerView observes AppState
            #endif
        default:
            logger.warning("Unknown deep link: \(link)")
        }
    }

    // MARK: - Handoff / User Activity

    /// Handles an incoming Handoff user activity for opening a note.
    ///
    /// - Parameters:
    ///   - activity: The NSUserActivity from Handoff.
    ///   - onSelectNote: Callback when a note URL should be selected.
    public func handleOpenNoteActivity(
        _ activity: NSUserActivity,
        onSelectNote: @escaping (URL) -> Void
    ) {
        guard let link = QuartzUserActivity.quartzDeepLink(from: activity) else {
            logger.debug("No quartz deep link in activity")
            return
        }

        logger.debug("Handling Handoff deep link: \(link.absoluteString)")

        if let noteURL = resolveNoteDeepLink(link) {
            onSelectNote(noteURL)
        }
    }

    // MARK: - URL Resolution

    /// Resolves a quartz://note/<path> URL to an actual file URL.
    ///
    /// - Parameter url: The quartz:// deep link URL.
    /// - Returns: The resolved file URL, or nil if resolution failed.
    public func resolveNoteDeepLink(_ url: URL) -> URL? {
        guard let noteURL = QuartzUserActivity.resolveNoteFileURL(
            fromQuartzDeepLink: url,
            vaultRoot: appState.currentVault?.rootURL
        ) else {
            logger.warning("Failed to resolve note deep link: \(url.absoluteString)")
            return nil
        }
        return noteURL
    }

    // MARK: - Deep Link Construction

    /// Creates a quartz:// deep link for the given note URL.
    ///
    /// - Parameters:
    ///   - noteURL: The file URL of the note.
    ///   - vaultRoot: The vault root URL for relative path calculation.
    /// - Returns: A quartz:// URL that can be used as a deep link.
    public func createNoteDeepLink(for noteURL: URL, vaultRoot: URL) -> URL? {
        let relativePath = noteURL.path(percentEncoded: false)
            .replacingOccurrences(of: vaultRoot.path(percentEncoded: false), with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        return URL(string: "quartz://note/\(encodedPath)")
    }
}
