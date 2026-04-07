import Testing
import Foundation
@testable import QuartzKit

/// Verifies actor-isolation invariants for the UI bootstrap path:
/// mock vault creation → AppState setup → WorkspaceStore route transitions.
///
/// These are compile-time and runtime safety checks that prove Swift 6 strict
/// concurrency compliance for the UI test bootstrap workflow.
@Suite("UI Bootstrap Concurrency")
struct UIBootstrapConcurrencyTests {

    // MARK: - VaultConfig Sendable

    @Test("VaultConfig is Sendable across isolation boundaries")
    func vaultConfigCrossesIsolation() async {
        // Create on a non-main-actor task, send to main actor — proves Sendable conformance
        let config = VaultConfig(
            name: "Concurrency Test",
            rootURL: URL(fileURLWithPath: "/tmp/concurrency-test")
        )

        let receivedName = await MainActor.run {
            // Receiving Sendable value on main actor
            config.name
        }

        #expect(receivedName == "Concurrency Test")
    }

    @Test("VaultConfig can be created and sent from background task")
    func vaultConfigFromBackgroundTask() async {
        let config: VaultConfig = await Task.detached {
            VaultConfig(
                name: "Background Vault",
                rootURL: URL(fileURLWithPath: "/tmp/bg-vault")
            )
        }.value

        #expect(config.name == "Background Vault")
    }

    // MARK: - AppState Main Actor Isolation

    @Test("AppState requires main actor for initialization")
    @MainActor func appStateOnMainActor() {
        let state = AppState()
        #expect(state.currentVault == nil)
    }

    @Test("AppState vault assignment is main-actor-isolated")
    @MainActor func appStateVaultAssignment() {
        let state = AppState()
        let vault = VaultConfig(
            name: "Test Vault",
            rootURL: URL(fileURLWithPath: "/tmp/test-vault")
        )
        state.currentVault = vault
        #expect(state.currentVault?.name == "Test Vault")
    }

    @Test("AppState can receive VaultConfig from async context")
    func appStateReceivesFromAsync() async {
        // Build config off main actor
        let config = VaultConfig(
            name: "Async Config",
            rootURL: URL(fileURLWithPath: "/tmp/async-vault")
        )

        // Assign on main actor — proves Sendable + isolation boundary
        await MainActor.run {
            let state = AppState()
            state.currentVault = config
            #expect(state.currentVault?.name == "Async Config")
        }
    }

    // MARK: - WorkspaceStore Route Isolation

    @Test("WorkspaceStore.setRoute is main-actor-isolated")
    @MainActor func setRouteIsolation() {
        let store = WorkspaceStore()
        let url = URL(fileURLWithPath: "/tmp/isolation-test.md")
        store.setRoute(.note(url))
        #expect(store.route == .note(url))
    }

    @Test("WorkspaceStore route can be set from async caller via MainActor.run")
    func setRouteFromAsync() async {
        let url = URL(fileURLWithPath: "/tmp/async-route.md")

        await MainActor.run {
            let store = WorkspaceStore()
            store.setRoute(.note(url))
            #expect(store.route == .note(url))
        }
    }

    @Test("Rapid route changes from async context remain coherent")
    func rapidAsyncRouteChanges() async {
        await MainActor.run {
            let store = WorkspaceStore()
            for i in 0..<100 {
                let url = URL(fileURLWithPath: "/tmp/rapid-\(i).md")
                store.setRoute(.note(url))
            }
            // After all changes, route must be the last one set
            let expectedURL = URL(fileURLWithPath: "/tmp/rapid-99.md")
            #expect(store.route == .note(expectedURL))
        }
    }

    // MARK: - Bootstrap Sequence

    @Test("Full bootstrap sequence: create config → assign to AppState → set route")
    func fullBootstrapSequence() async {
        // Step 1: Create config off main actor (like UITestFixtureVault.create())
        let config = VaultConfig(
            name: "Bootstrap Test",
            rootURL: URL(fileURLWithPath: "/tmp/bootstrap-vault")
        )

        // Step 2+3: Assign to AppState and set route on main actor
        await MainActor.run {
            let state = AppState()
            state.currentVault = config

            let store = WorkspaceStore()
            let noteURL = config.rootURL.appending(path: "Welcome.md")
            store.setRoute(.note(noteURL))

            #expect(state.currentVault?.name == "Bootstrap Test")
            #expect(store.route == .note(noteURL))
        }
    }
}
