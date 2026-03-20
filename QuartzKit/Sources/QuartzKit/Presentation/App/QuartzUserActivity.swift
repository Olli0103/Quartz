import Foundation

/// Handoff / ``NSUserActivity`` support for the active note session.
///
/// Uses the same `quartz://note/...` shape as widgets and ``OpenNoteIntent`` so routing stays unified.
public enum QuartzUserActivity {
    /// Declared in the app target `Info.plist` (`NSUserActivityTypes`).
    public static let openNoteActivityType = "olli.Quartz.useractivity.openNote"

    public enum UserInfoKey {
        public static let deepLink = "quartzDeepLink"
        public static let noteTitle = "noteTitle"
    }

    // MARK: - Deep link (shared with widgets / URL open)

    /// Builds `quartz://note/...` using the same path-segment rules as ``OpenNoteIntent``.
    public static func quartzDeepLinkForNote(relativeVaultPath: String) -> URL {
        var url = URL(string: "quartz://note")!
        for segment in relativeVaultPath.split(separator: "/") where !segment.isEmpty {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    /// Vault-relative path (POSIX, `/`-separated) for `noteURL`, or `nil` if outside `vaultRoot`.
    public static func relativeVaultPath(noteURL: URL, vaultRoot: URL) -> String? {
        let v = vaultRoot.standardizedFileURL.path(percentEncoded: false)
        let n = noteURL.standardizedFileURL.path(percentEncoded: false)
        guard n.hasPrefix(v) else { return nil }
        let rel = n.dropFirst(v.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rel.isEmpty ? nil : String(rel)
    }

    /// Validates `quartz://note/...` and returns the on-disk note URL when the file exists under the open vault.
    public static func resolveNoteFileURL(fromQuartzDeepLink url: URL, vaultRoot: URL?) -> URL? {
        guard url.scheme == "quartz", url.host() == "note" else { return nil }
        let path = url.pathComponents.dropFirst().joined(separator: "/")
        guard !path.isEmpty, let vaultRoot else { return nil }
        let noteURL = vaultRoot.appending(path: path)
        guard noteURL.standardizedFileURL.path().hasPrefix(vaultRoot.standardizedFileURL.path()) else { return nil }
        guard FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) else { return nil }
        return noteURL
    }

    // MARK: - NSUserActivity

    /// Populates Handoff metadata for the note currently open in the main window.
    public static func configureOpenNoteActivity(
        _ activity: NSUserActivity,
        noteURL: URL,
        displayTitle: String,
        vaultRoot: URL
    ) {
        guard let rel = relativeVaultPath(noteURL: noteURL, vaultRoot: vaultRoot) else {
            activity.isEligibleForHandoff = false
            activity.isEligibleForSearch = false
            return
        }
        let deepLink = quartzDeepLinkForNote(relativeVaultPath: rel)
        activity.title = displayTitle
        activity.addUserInfoEntries(from: [
            UserInfoKey.deepLink: deepLink.absoluteString,
            UserInfoKey.noteTitle: displayTitle
        ])
        // Do not set `webpageURL` to `quartz://…` — NSUserActivity only accepts valid web (http/https)
        // URLs there; newer OS versions throw from `setWebpageURL:`. Continuity uses `userInfo` above.
        activity.webpageURL = nil
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.needsSave = false
    }

    /// Resolves a continued ``NSUserActivity`` into a `quartz://note/...` URL, if present.
    public static func quartzDeepLink(from activity: NSUserActivity) -> URL? {
        if let s = activity.userInfo?[UserInfoKey.deepLink] as? String, let u = URL(string: s) {
            return u
        }
        guard let w = activity.webpageURL, w.scheme == "http" || w.scheme == "https" else { return nil }
        return w
    }
}
