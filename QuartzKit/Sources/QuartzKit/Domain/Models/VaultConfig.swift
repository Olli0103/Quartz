import Foundation

/// Sync configuration for a vault.
public struct SyncConfig: Codable, Sendable, Equatable {
    public var webdavURL: URL?
    public var syncInterval: TimeInterval

    public init(webdavURL: URL? = nil, syncInterval: TimeInterval = 300) {
        self.webdavURL = webdavURL
        self.syncInterval = syncInterval
    }
}

/// Configuration of a vault.
public struct VaultConfig: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var rootURL: URL
    public var storageType: StorageType
    public var isDefault: Bool
    public var encryptionEnabled: Bool
    public var templateStructure: VaultTemplate?
    public var createdAt: Date
    public var syncConfig: SyncConfig?

    public init(
        id: UUID = UUID(),
        name: String,
        rootURL: URL,
        storageType: StorageType = .local,
        isDefault: Bool = false,
        encryptionEnabled: Bool = false,
        templateStructure: VaultTemplate? = nil,
        createdAt: Date = .now,
        syncConfig: SyncConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.storageType = storageType
        self.isDefault = isDefault
        self.encryptionEnabled = encryptionEnabled
        self.templateStructure = templateStructure
        self.createdAt = createdAt
        self.syncConfig = syncConfig
    }
}

/// Vordefinierte Vault-Vorlagen.
public enum VaultTemplate: String, Codable, Sendable {
    case para
    case zettelkasten
    case custom
}
