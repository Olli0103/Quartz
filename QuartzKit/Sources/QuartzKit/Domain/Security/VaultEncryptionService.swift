import Foundation
import CryptoKit

/// Service for file-based AES-256-GCM encryption.
///
/// Encrypts/decrypts individual files in the vault.
/// The symmetric key is stored in the Keychain
/// and optionally protected by the Secure Enclave.
public actor VaultEncryptionService {
    /// Errors during encryption operations.
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
            case .keychainError(let status):
                switch status {
                case errSecItemNotFound:
                    String(localized: "Encryption key not found. You may need to set up encryption again.", bundle: .module)
                case errSecAuthFailed:
                    String(localized: "Authentication failed when accessing encryption key.", bundle: .module)
                case errSecInteractionNotAllowed:
                    String(localized: "Cannot access encryption key while device is locked.", bundle: .module)
                default:
                    String(localized: "A keychain error occurred. Please try again. (Code: \(status))", bundle: .module)
                }
            }
        }
    }

    private let keychainService = "app.quartz.encryption"

    public init() {}

    // MARK: - Key Management

    /// Generates a new AES-256 key and stores it in the Keychain.
    ///
    /// - Parameter vaultID: Unique ID of the vault
    /// - Returns: Reference to the Keychain entry
    public func generateKey(for vaultID: String) throws -> String {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        let keyRef = "vault-key-\(vaultID)"
        try storeInKeychain(data: keyData, account: keyRef)
        return keyRef
    }

    /// Loads the key for a vault from the Keychain.
    public func loadKey(ref: String) throws -> SymmetricKey {
        let keyData = try loadFromKeychain(account: ref)
        return SymmetricKey(data: keyData)
    }

    /// Executes an operation with a scoped encryption key.
    ///
    /// The key is loaded from the Keychain and only available within the closure scope,
    /// ensuring it is released as soon as the operation completes.
    public func withKey<T: Sendable>(ref: String, operation: @Sendable (SymmetricKey) throws -> T) throws -> T {
        let key = try loadKey(ref: ref)
        return try operation(key)
    }

    /// Deletes the key for a vault from the Keychain.
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

    /// Encrypts file data with AES-256-GCM.
    ///
    /// Format: nonce (12 bytes) + ciphertext + tag (16 bytes)
    public nonisolated func encrypt(data: Data, with key: SymmetricKey) throws -> Data {
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

    /// Decrypts AES-256-GCM encrypted data.
    public nonisolated func decrypt(data: Data, with key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    /// Maximum file size for in-memory encryption (50 MB).
    /// Files larger than this should use a streaming approach.
    private static let maxInMemoryFileSize: Int = 50_000_000

    /// Encrypts a file in-place using file coordination.
    ///
    /// File coordination is dispatched off the actor to prevent blocking
    /// other actor-isolated calls (e.g. key management) during I/O.
    ///
    /// - Throws: `EncryptionError.encryptionFailed` if the file exceeds
    ///   the safe in-memory size limit (50 MB).
    public func encryptFile(at url: URL, with key: SymmetricKey) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        if let size = attrs[.size] as? Int, size > Self.maxInMemoryFileSize {
            throw EncryptionError.encryptionFailed("File too large for in-memory encryption (\(size) bytes). Maximum: \(Self.maxInMemoryFileSize) bytes.")
        }
        let encryptionService = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var coordinatorError: NSError?
                var opError: Error?
                let coordinator = NSFileCoordinator()
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { actualURL in
                    do {
                        let plaintext = try Data(contentsOf: actualURL)
                        let encrypted = try encryptionService.encrypt(data: plaintext, with: key)
                        try encrypted.write(to: actualURL, options: .atomic)
                    } catch {
                        opError = error
                    }
                }
                if let error = coordinatorError ?? opError {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Decrypts a file and returns the plaintext.
    ///
    /// File coordination is dispatched off the actor to prevent blocking.
    public func decryptFile(at url: URL, with key: SymmetricKey) async throws -> Data {
        let encryptionService = self
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var coordinatorError: NSError?
                var opError: Error?
                var result: Data?
                let coordinator = NSFileCoordinator()
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { actualURL in
                    do {
                        let encrypted = try Data(contentsOf: actualURL)
                        result = try encryptionService.decrypt(data: encrypted, with: key)
                    } catch {
                        opError = error
                    }
                }
                if let error = coordinatorError ?? opError {
                    continuation.resume(throwing: error)
                } else if let data = result {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: EncryptionError.decryptionFailed("File coordination completed without producing data"))
                }
            }
        }
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
            throw EncryptionError.keychainError(status)
        }

        return data
    }
}
