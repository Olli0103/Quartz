import Foundation

/// Speicherort-Typ eines Vaults.
public enum StorageType: String, Codable, Sendable {
    case local
    case iCloudDrive
    case webdav
}
