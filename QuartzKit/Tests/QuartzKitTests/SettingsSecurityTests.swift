import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Swift Testing Suite for Settings & Security

@Suite("AppearanceManager")
struct AppearanceManagerTests {
    @Test("Theme enum has all expected cases")
    func themeCases() {
        let themes = AppearanceManager.Theme.allCases
        #expect(themes.count == 3)
        #expect(themes.contains(.system))
        #expect(themes.contains(.light))
        #expect(themes.contains(.dark))
    }

    @Test("Theme displayName returns localized strings")
    func themeDisplayNames() {
        #expect(!AppearanceManager.Theme.system.displayName.isEmpty)
        #expect(!AppearanceManager.Theme.light.displayName.isEmpty)
        #expect(!AppearanceManager.Theme.dark.displayName.isEmpty)
    }

    @Test("Theme colorScheme mapping is correct")
    func themeColorScheme() {
        #expect(AppearanceManager.Theme.system.colorScheme == nil)
        #expect(AppearanceManager.Theme.light.colorScheme == .light)
        #expect(AppearanceManager.Theme.dark.colorScheme == .dark)
    }

    @MainActor
    @Test("Default values are reasonable")
    func defaultValues() {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        #expect(manager.theme == .system)
        #expect(manager.editorFontScale >= 0.8 && manager.editorFontScale <= 2.0)
        #expect(manager.vibrantTransparency == true)
        #expect(manager.accentColorHex > 0 && manager.accentColorHex <= 0xFFFFFF)
    }

    @MainActor
    @Test("Theme changes persist to UserDefaults")
    func themePersistence() {
        let defaults = UserDefaults(suiteName: "test.appearance.persist.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        manager.theme = .dark
        #expect(defaults.string(forKey: "quartz.appearance.theme") == "dark")

        manager.theme = .light
        #expect(defaults.string(forKey: "quartz.appearance.theme") == "light")
    }

    @MainActor
    @Test("Editor font scale clamps to valid range")
    func fontScaleClamping() {
        let defaults = UserDefaults(suiteName: "test.appearance.scale.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        manager.editorFontScale = 0.5 // Below minimum
        #expect(manager.editorFontScale >= 0.8)

        manager.editorFontScale = 3.0 // Above maximum
        #expect(manager.editorFontScale <= 2.0)

        manager.editorFontScale = 1.5 // Valid
        #expect(manager.editorFontScale == 1.5)
    }

    @MainActor
    @Test("Accent color changes persist")
    func accentColorPersistence() {
        let defaults = UserDefaults(suiteName: "test.appearance.accent.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        manager.accentColorHex = 0xFF0000
        #expect(defaults.integer(forKey: "quartz.appearance.accentColorHex") == 0xFF0000)
    }
}

@Suite("KeychainHelper")
struct KeychainHelperTests {
    @Test("Save and retrieve API key")
    func saveAndRetrieveKey() async throws {
        let helper = KeychainHelper()
        let testProvider = "test-provider-\(UUID().uuidString)"
        let testKey = "sk-test-key-12345"

        try await helper.saveKey(testKey, for: testProvider)
        let retrieved = try await helper.getKey(for: testProvider)

        #expect(retrieved == testKey)

        // Cleanup
        await helper.deleteKey(for: testProvider)
    }

    @Test("hasKey returns correct status")
    func hasKeyCheck() async throws {
        let helper = KeychainHelper()
        let testProvider = "test-haskey-\(UUID().uuidString)"

        #expect(helper.hasKey(for: testProvider) == false)

        try await helper.saveKey("test-key", for: testProvider)
        #expect(helper.hasKey(for: testProvider) == true)

        await helper.deleteKey(for: testProvider)
        #expect(helper.hasKey(for: testProvider) == false)
    }

    @Test("Delete key removes from keychain")
    func deleteKeyRemoves() async throws {
        let helper = KeychainHelper()
        let testProvider = "test-delete-\(UUID().uuidString)"

        try await helper.saveKey("test-key", for: testProvider)
        #expect(helper.hasKey(for: testProvider) == true)

        await helper.deleteKey(for: testProvider)
        #expect(helper.hasKey(for: testProvider) == false)
    }

    @Test("Update existing key overwrites")
    func updateKeyOverwrites() async throws {
        let helper = KeychainHelper()
        let testProvider = "test-update-\(UUID().uuidString)"

        try await helper.saveKey("first-key", for: testProvider)
        try await helper.saveKey("second-key", for: testProvider)

        let retrieved = try await helper.getKey(for: testProvider)
        #expect(retrieved == "second-key")

        await helper.deleteKey(for: testProvider)
    }
}

@Suite("VaultEncryptionService")
struct VaultEncryptionServiceTests {
    @Test("Generate and load key round-trip")
    func generateAndLoadKey() async throws {
        let service = VaultEncryptionService()
        let vaultID = "test-vault-\(UUID().uuidString)"

        let keyRef = try await service.generateKey(for: vaultID)
        #expect(keyRef.hasPrefix("vault-key-"))

        let key = try await service.loadKey(ref: keyRef)
        // Key should be 256 bits (32 bytes)
        key.withUnsafeBytes { bytes in
            #expect(bytes.count == 32)
        }

        // Cleanup
        try await service.deleteKey(ref: keyRef)
    }

    @Test("Encrypt and decrypt data round-trip")
    func encryptDecryptRoundTrip() async throws {
        let service = VaultEncryptionService()
        let vaultID = "test-vault-encrypt-\(UUID().uuidString)"

        let keyRef = try await service.generateKey(for: vaultID)
        let key = try await service.loadKey(ref: keyRef)

        let plaintext = "Hello, Quartz! 🔐".data(using: .utf8)!
        let encrypted = try service.encrypt(data: plaintext, with: key)

        // Encrypted data should be different and larger (nonce + tag overhead)
        #expect(encrypted != plaintext)
        #expect(encrypted.count > plaintext.count)

        let decrypted = try service.decrypt(data: encrypted, with: key)
        #expect(decrypted == plaintext)

        try await service.deleteKey(ref: keyRef)
    }

    @Test("Decryption fails with wrong key")
    func decryptionFailsWithWrongKey() async throws {
        let service = VaultEncryptionService()

        let keyRef1 = try await service.generateKey(for: "vault-1-\(UUID().uuidString)")
        let keyRef2 = try await service.generateKey(for: "vault-2-\(UUID().uuidString)")

        let key1 = try await service.loadKey(ref: keyRef1)
        let key2 = try await service.loadKey(ref: keyRef2)

        let plaintext = "Secret data".data(using: .utf8)!
        let encrypted = try service.encrypt(data: plaintext, with: key1)

        #expect(throws: VaultEncryptionService.EncryptionError.self) {
            _ = try service.decrypt(data: encrypted, with: key2)
        }

        try await service.deleteKey(ref: keyRef1)
        try await service.deleteKey(ref: keyRef2)
    }

    @Test("withKey scoped operation")
    func withKeyScopedOperation() async throws {
        let service = VaultEncryptionService()
        let vaultID = "test-vault-scoped-\(UUID().uuidString)"

        let keyRef = try await service.generateKey(for: vaultID)

        let result: Int = try await service.withKey(ref: keyRef) { key in
            key.withUnsafeBytes { bytes in
                bytes.count
            }
        }

        #expect(result == 32) // 256-bit key

        try await service.deleteKey(ref: keyRef)
    }
}

@Suite("AIProviderRegistry")
struct AIProviderRegistryTests {
    @MainActor
    @Test("Registry has expected providers")
    func registryHasProviders() {
        let registry = AIProviderRegistry()
        let providerIDs = registry.providers.map(\.id)

        #expect(providerIDs.contains("openai"))
        #expect(providerIDs.contains("anthropic"))
        #expect(providerIDs.contains("gemini"))
        #expect(providerIDs.contains("openrouter"))
        #expect(providerIDs.contains("ollama"))
    }

    @MainActor
    @Test("Provider selection persists")
    func providerSelectionPersists() {
        let registry = AIProviderRegistry()

        registry.selectedProviderID = "anthropic"
        #expect(UserDefaults.standard.string(forKey: "quartz.ai.selectedProviderID") == "anthropic")

        registry.selectedProviderID = "openai"
        #expect(UserDefaults.standard.string(forKey: "quartz.ai.selectedProviderID") == "openai")
    }

    @MainActor
    @Test("All providers have valid models")
    func providersHaveModels() {
        let registry = AIProviderRegistry()

        for provider in registry.providers {
            let models = provider.availableModels
            #expect(!models.isEmpty, "Provider \(provider.id) should have models")

            for model in models {
                #expect(!model.id.isEmpty)
                #expect(!model.name.isEmpty)
                #expect(model.contextWindow > 0)
                #expect(model.provider == provider.id)
            }
        }
    }
}

// MARK: - XCTest Performance Tests

final class SettingsPerformanceTests: XCTestCase {
    @MainActor
    func testThemeTogglePerformance() throws {
        let defaults = UserDefaults(suiteName: "test.perf.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTCPUMetric(), XCTClockMetric()], options: options) {
            // Rapid theme toggling should not cause CPU spikes
            for _ in 0..<100 {
                manager.theme = .dark
                manager.theme = .light
                manager.theme = .system
            }
        }
    }

    @MainActor
    func testAppearanceSettingsMemoryStability() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTMemoryMetric()], options: options) {
            var managers: [AppearanceManager] = []
            for i in 0..<50 {
                let defaults = UserDefaults(suiteName: "test.mem.\(i).\(UUID().uuidString)")!
                let manager = AppearanceManager(defaults: defaults)
                manager.theme = AppearanceManager.Theme.allCases[i % 3]
                manager.editorFontScale = Double(i % 10) / 10.0 + 1.0
                managers.append(manager)
            }
            managers.removeAll()
        }
    }

    func testEncryptionPerformance() async throws {
        let service = VaultEncryptionService()
        let vaultID = "perf-test-\(UUID().uuidString)"
        let keyRef = try await service.generateKey(for: vaultID)
        let key = try await service.loadKey(ref: keyRef)

        // 1 MB of data
        let largeData = Data(repeating: 0x42, count: 1_000_000)

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            do {
                let encrypted = try service.encrypt(data: largeData, with: key)
                _ = try service.decrypt(data: encrypted, with: key)
            } catch {
                XCTFail("Encryption round-trip failed: \(error)")
            }
        }

        try await service.deleteKey(ref: keyRef)
    }

    func testKeychainAccessPerformance() async throws {
        let helper = KeychainHelper()
        let testProvider = "perf-keychain-\(UUID().uuidString)"
        try await helper.saveKey("test-key-for-performance", for: testProvider)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric()], options: options) {
            for _ in 0..<100 {
                _ = helper.hasKey(for: testProvider)
            }
        }

        await helper.deleteKey(for: testProvider)
    }
}

// MARK: - Biometric Auth Performance Tests

final class BiometricAuthPerformanceTests: XCTestCase {
    func testBiometryAvailabilityCheckPerformance() async throws {
        let service = BiometricAuthService()

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Biometry check")
            Task {
                for _ in 0..<50 {
                    _ = await service.availableBiometry()
                    _ = await service.isBiometryAvailable()
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}
