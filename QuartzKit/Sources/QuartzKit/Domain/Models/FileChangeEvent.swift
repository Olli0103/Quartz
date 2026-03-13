import Foundation

/// Ereignis bei Dateiänderungen im Vault.
public enum FileChangeEvent: Sendable {
    case created(URL)
    case modified(URL)
    case deleted(URL)
}
