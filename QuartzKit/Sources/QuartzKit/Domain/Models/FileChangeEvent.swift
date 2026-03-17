import Foundation

/// Event for file changes in the vault.
public enum FileChangeEvent: Sendable {
    case created(URL)
    case modified(URL)
    case deleted(URL)
}
