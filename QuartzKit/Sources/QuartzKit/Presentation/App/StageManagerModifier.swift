import SwiftUI

// MARK: - Stage Manager Support

/// Routes `quartz://` deep links into the app's selection and command system.
///
/// Handles:
/// - `quartz://note/<encoded-path>` → opens the note
/// - `quartz://new` → triggers new note command
/// - `quartz://daily` → triggers daily note command
/// - `quartz://scan` → triggers document scanner
@MainActor
public struct StageManagerModifier: ViewModifier {
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    var appState: AppState
    /// Must match ``ContentView``'s selection so `onOpenURL` opens the same note as sidebar / widgets / Handoff.
    var selectedNoteURL: Binding<URL?>

    public func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "quartz" else { return }
        switch url.host() {
        case "note":
            guard let noteURL = QuartzUserActivity.resolveNoteFileURL(fromQuartzDeepLink: url, vaultRoot: appState.currentVault?.rootURL) else { return }
            selectedNoteURL.wrappedValue = noteURL
        case "new":
            appState.pendingCommand = .newNote
        case "daily":
            appState.pendingCommand = .dailyNote
        case "scan":
            appState.pendingOpenDocumentScanner = true
        default:
            break
        }
    }
}

extension View {
    /// Enables Stage Manager support and routes `quartz://` deep links into the editor selection.
    public func stageManagerSupport(appState: AppState, selectedNoteURL: Binding<URL?>) -> some View {
        modifier(StageManagerModifier(appState: appState, selectedNoteURL: selectedNoteURL))
    }
}
