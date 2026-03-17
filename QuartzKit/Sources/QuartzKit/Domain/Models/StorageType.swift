import Foundation

/// Storage location type of a vault.
public enum StorageType: String, Codable, Sendable {
    case local
    case iCloudDrive
    case webdav
}
