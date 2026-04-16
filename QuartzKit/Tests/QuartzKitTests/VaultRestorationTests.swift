import Testing
import Foundation
@testable import QuartzKit

// MARK: - Startup Coordinator Tests

@Suite("StartupCoordinator")
struct VaultRestorationTests {

    @Test("Phases advance sequentially and awaitPhase resolves")
    @MainActor func sequentialAdvance() async {
        let coord = StartupCoordinator()
        #expect(coord.currentPhase == .initial)
        #expect(coord.isFullyStarted == false)

        // Advance through all phases in order
        #expect(coord.advance(to: .vaultResolved) == true)
        #expect(coord.currentPhase == .vaultResolved)

        #expect(coord.advance(to: .editorMounted) == true)
        #expect(coord.currentPhase == .editorMounted)

        #expect(coord.advance(to: .indexWarm) == true)
        #expect(coord.currentPhase == .indexWarm)

        #expect(coord.advance(to: .restorationApplied) == true)
        #expect(coord.currentPhase == .restorationApplied)
        #expect(coord.isFullyStarted == true)
    }

    @Test("Cannot skip phases")
    @MainActor func cannotSkip() {
        let coord = StartupCoordinator()
        // Try to skip from initial to editorMounted
        #expect(coord.advance(to: .editorMounted) == false)
        #expect(coord.currentPhase == .initial)

        // Try to skip from initial to indexWarm
        #expect(coord.advance(to: .indexWarm) == false)
        #expect(coord.currentPhase == .initial)
    }

    @Test("awaitPhase returns immediately if already past target")
    @MainActor func awaitPastPhase() async {
        let coord = StartupCoordinator()
        coord.advance(to: .vaultResolved)
        coord.advance(to: .editorMounted)

        // Awaiting a phase we've already passed should return immediately
        await coord.awaitPhase(.vaultResolved)
        #expect(coord.currentPhase == .editorMounted)
    }

    @Test("Reset returns to initial and phases are Comparable")
    @MainActor func resetAndComparable() {
        let coord = StartupCoordinator()
        coord.advance(to: .vaultResolved)
        coord.advance(to: .editorMounted)

        coord.reset()
        #expect(coord.currentPhase == .initial)
        #expect(coord.isFullyStarted == false)

        // Phase ordering
        typealias Phase = StartupCoordinator.StartupPhase
        #expect(Phase.initial < Phase.vaultResolved)
        #expect(Phase.vaultResolved < Phase.editorMounted)
        #expect(Phase.editorMounted < Phase.indexWarm)
        #expect(Phase.indexWarm < Phase.restorationApplied)
        #expect(Phase.allCases.count == 5)
    }

    @Test("ContentViewModel completes restoration phase only after index warm")
    @MainActor func restorationAppliedWaitsForIndexWarm() async {
        let viewModel = ContentViewModel(appState: AppState())
        let coord = viewModel.startupCoordinator

        #expect(coord.advance(to: .vaultResolved) == true)
        #expect(coord.advance(to: .editorMounted) == true)

        viewModel.completeStartupRestorationIfNeeded()
        try? await Task.sleep(for: .milliseconds(10))

        #expect(coord.currentPhase == .editorMounted)

        #expect(coord.advance(to: .indexWarm) == true)
        try? await Task.sleep(for: .milliseconds(10))

        #expect(coord.currentPhase == .restorationApplied)
        #expect(coord.isFullyStarted == true)
    }
}
