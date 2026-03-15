import Foundation
import CryptoKit

/// Service für dateibasierte AES-256-GCM Verschlüsselung.
///
/// Verschlüsselt/entschlüsselt einzelne Dateien im Vault.
/// Der symmetrische Schlüssel wird im Keychain gespeichert
/// und optional durch den Secure Enclave geschützt.
public actor VaultEncryptionService {
    /// Fehler bei Verschlüsselungs-Operationen.
    public enum EncryptionError: LocalizedError, Sendable {
        case keyNotFound
        case encryptionFailed(String)
        case decryptionFailed(String)
        case keychainError(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .keyNotFound: String(localized: "Encryption key not found in Keychain.", bundle: .module)
            case .encryptionFailed(let msg): String(localized: "Encryption failed: \(msg)", bundle: .module)
            case .decryptionFailed(let msg): String(localized: "Decryption failed: \(msg)", bundle: .module)
            case .keychainError(let status): String(localized: "Keychain error: \(status)", bundle: .module)
            }
        }
    }

    private let keychainService = "app.quartz.encryption"

    public init() {}

    // MARK: - Key Management

    /// Generiert einen neuen AES-256 Schlüssel und speichert ihn im Keychain.
    ///
    /// - Parameter vaultID: Eindeutige ID des Vaults
    /// - Returns: Referenz auf den Keychain-Eintrag
    public func generateKey(for vaultID: String) throws -> String {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        let keyRef = "vault-key-\(vaultID)"
        try storeInKeychain(data: keyData, account: keyRef)
        return keyRef
    }

    /// Lädt den Schlüssel für einen Vault aus dem Keychain.
    public func loadKey(ref: String) throws -> SymmetricKey {
        let keyData = try loadFromKeychain(account: ref)
        return SymmetricKey(data: keyData)
    }

    /// Löscht den Schlüssel für einen Vault aus dem Keychain.
    public func deleteKey(ref: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: ref,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status)
        }
    }

    // MARK: - File Encryption

    /// Verschlüsselt Dateidaten mit AES-256-GCM.
    ///
    /// Format: nonce (12 bytes) + ciphertext + tag (16 bytes)
    public func encrypt(data: Data, with key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed("Failed to combine sealed box")
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Entschlüsselt AES-256-GCM verschlüsselte Daten.
    public func decrypt(data: Data, with key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    /// Verschlüsselt eine Datei in-place.
    public func encryptFile(at url: URL, with key: SymmetricKey) throws {
        let plaintext = try Data(contentsOf: url)
        let encrypted = try encrypt(data: plaintext, with: key)
        try encrypted.write(to: url, options: .atomic)
    }

    /// Entschlüsselt eine Datei und gibt den Plaintext zurück.
    public func decryptFile(at url: URL, with key: SymmetricKey) throws -> Data {
        let encrypted = try Data(contentsOf: url)
        return try decrypt(data: encrypted, with: key)
    }

    // MARK: - Keychain Helpers

    private func storeInKeychain(data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Try update first (atomic, no delete needed)
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status)
        }
    }

    private func loadFromKeychain(account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw EncryptionError.keyNotFound
        }

        return data
    }
}
