import Foundation

/// Persists favorite note markers in `UserDefaults` with **vault-scoped, path-stable** keys.
///
/// Keys are `"<canonical vault path><TAB><relative path from vault root>"` (POSIX, `/`-separated).
/// Legacy entries stored as a bare filename are still read when they can be resolved unambiguously
/// within the current vault tree.
public enum FavoriteNoteStorage {
    public static let userDefaultsKey = "quartz.favoriteNotes"

    private static let separator = "\t"

    /// Canonical filesystem path for the vault root (stable for a given folder on disk).
    public static func canonicalVaultPath(_ vaultRoot: URL) -> String {
        vaultRoot.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    /// Storage token for `fileURL` inside `vaultRoot`, or `nil` if the file is not under the vault.
    public static func storageKey(fileURL: URL, vaultRoot: URL) -> String? {
        let base = canonicalVaultPath(vaultRoot)
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard filePath != base, filePath.hasPrefix(base + "/") else { return nil }
        let rel = String(filePath.dropFirst((base + "/").count))
        guard !rel.isEmpty else { return nil }
        return base + separator + rel
    }

    public static func readStoredKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? [])
    }

    public static func isFavorite(
        fileURL: URL,
        vaultRoot: URL?,
        storedKeys: Set<String>,
        fileTree: [FileNode]?
    ) -> Bool {
        guard let root = vaultRoot else { return false }
        if let key = storageKey(fileURL: fileURL, vaultRoot: root), storedKeys.contains(key) {
            return true
        }
        let legacy = fileURL.lastPathComponent
        guard storedKeys.contains(legacy) else { return false }
        let count = countNotes(matchingLastPathComponent: legacy, in: fileTree ?? [])
        if count == 0 {
            // Tree not loaded or empty: preserve legacy behavior for migration.
            return true
        }
        return count == 1
    }

    /// Toggles favorite state; returns the new `isFavorite` value.
    @discardableResult
    public static func toggleFavorite(
        fileURL: URL,
        vaultRoot: URL?,
        fileTree: [FileNode]?
    ) -> Bool {
        var favs = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        let set = Set(favs)
        let wasFavorite = isFavorite(
            fileURL: fileURL,
            vaultRoot: vaultRoot,
            storedKeys: set,
            fileTree: fileTree
        )
        if wasFavorite {
            if let root = vaultRoot, let key = storageKey(fileURL: fileURL, vaultRoot: root) {
                favs.removeAll { $0 == key }
            }
            favs.removeAll { $0 == fileURL.lastPathComponent }
        } else {
            if let root = vaultRoot, let key = storageKey(fileURL: fileURL, vaultRoot: root) {
                favs.append(key)
                favs.removeAll { $0 == fileURL.lastPathComponent }
            } else {
                favs.append(fileURL.lastPathComponent)
            }
        }
        UserDefaults.standard.set(favs, forKey: userDefaultsKey)
        NotificationCenter.default.post(name: .quartzFavoritesDidChange, object: nil)
        return !wasFavorite
    }

    private static func countNotes(matchingLastPathComponent name: String, in nodes: [FileNode]) -> Int {
        var n = 0
        for node in nodes {
            if node.isNote, node.url.lastPathComponent == name {
                n += 1
            }
            if let children = node.children {
                n += countNotes(matchingLastPathComponent: name, in: children)
            }
        }
        return n
    }
}
