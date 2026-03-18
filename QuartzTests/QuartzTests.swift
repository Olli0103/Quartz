//
//  QuartzTests.swift
//  QuartzTests
//
//  Created by Posselt, Oliver on 13.03.26.
//

import Testing
@testable import QuartzKit

// MARK: - ServiceContainer Tests

@Suite("ServiceContainer")
struct ServiceContainerTests {
    @Test("resolveVaultProvider returns consistent instance")
    @MainActor
    func resolveVaultProviderConsistency() {
        let container = ServiceContainer.shared
        let provider1 = container.resolveVaultProvider()
        let provider2 = container.resolveVaultProvider()
        // Both should be the same instance (FileSystemVaultProvider)
        #expect(provider1 is FileSystemVaultProvider)
        #expect(provider2 is FileSystemVaultProvider)
    }

    @Test("resolveFrontmatterParser returns instance")
    @MainActor
    func resolveFrontmatterParser() {
        let container = ServiceContainer.shared
        let parser = container.resolveFrontmatterParser()
        #expect(parser is FrontmatterParser)
    }

    @Test("resolveFeatureGate returns gate")
    @MainActor
    func resolveFeatureGate() {
        let container = ServiceContainer.shared
        let gate = container.resolveFeatureGate()
        // Should return some implementation of FeatureGating
        #expect(gate.isEnabled(.markdownEditor))
    }

    @Test("bootstrap registers custom services")
    @MainActor
    func bootstrapRegistration() {
        let container = ServiceContainer.shared
        let customGate = DefaultFeatureGate()
        customGate.isProUnlocked = true
        container.bootstrap(featureGate: customGate)

        let gate = container.resolveFeatureGate()
        #expect(gate.isEnabled(.aiChat))
    }
}

// MARK: - AppearanceManager Tests

@Suite("AppearanceManager")
struct AppearanceManagerTests {
    @Test("Default theme is system")
    @MainActor
    func defaultTheme() {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)
        #expect(manager.theme == .system)
    }

    @Test("Theme persists to UserDefaults")
    @MainActor
    func themePersistence() {
        let suiteName = "test.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let manager = AppearanceManager(defaults: defaults)
        manager.theme = .dark

        let manager2 = AppearanceManager(defaults: defaults)
        #expect(manager2.theme == .dark)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Editor font scale defaults to 1.0")
    @MainActor
    func defaultFontScale() {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)
        #expect(manager.editorFontScale == 1.0)
    }

    @Test("Theme colorScheme mapping")
    @MainActor
    func themeColorScheme() {
        #expect(AppearanceManager.Theme.system.colorScheme == nil)
        #expect(AppearanceManager.Theme.light.colorScheme == .light)
        #expect(AppearanceManager.Theme.dark.colorScheme == .dark)
    }
}

// MARK: - FocusModeManager Tests

@Suite("FocusModeManager")
struct FocusModeManagerTests {
    @Test("Initial state is inactive")
    @MainActor
    func initialState() {
        let manager = FocusModeManager()
        #expect(!manager.isFocusModeActive)
        #expect(!manager.isTypewriterModeActive)
        #expect(manager.dimmedLineOpacity == 0.3)
    }

    @Test("Toggle focus mode")
    @MainActor
    func toggleFocus() {
        let manager = FocusModeManager()
        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive)
        manager.toggleFocusMode()
        #expect(!manager.isFocusModeActive)
    }

    @Test("Toggle typewriter mode")
    @MainActor
    func toggleTypewriter() {
        let manager = FocusModeManager()
        manager.toggleTypewriterMode()
        #expect(manager.isTypewriterModeActive)
        manager.toggleTypewriterMode()
        #expect(!manager.isTypewriterModeActive)
    }
}

// MARK: - Open-Source Feature Gate Tests

@Suite("FeatureGate (Open-Source)")
struct OpenSourceFeatureGateTests {
    @Test("All features are enabled – no Pro gating")
    func allFeaturesEnabled() {
        let gate = DefaultFeatureGate()
        for feature in Feature.allCases {
            #expect(gate.isEnabled(feature), "Feature \(feature) should be enabled")
        }
    }
}
