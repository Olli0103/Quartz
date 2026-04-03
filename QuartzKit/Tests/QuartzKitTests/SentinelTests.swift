import Testing
import Foundation
@testable import QuartzKit

// MARK: - System Sentinel Tests

/// Verifies SystemSentinel health scoring, pressure detection,
/// and simulated state transitions.

@Suite("SystemSentinel")
struct SentinelTests {

    @Test("Initial healthScore is 1.0")
    @MainActor func initialHealthScore() {
        let sentinel = SystemSentinel.shared
        // Reset any previous simulation state
        #if DEBUG
        sentinel.simulateMemoryPressure(.normal)
        sentinel.simulateThermalState(.nominal)
        #endif
        #expect(sentinel.healthScore == 1.0, "Initial health score should be 1.0")
    }

    @Test("isUnderPressure false when normal")
    @MainActor func notUnderPressureWhenNormal() {
        let sentinel = SystemSentinel.shared
        #if DEBUG
        sentinel.simulateMemoryPressure(.normal)
        sentinel.simulateThermalState(.nominal)
        #endif
        #expect(sentinel.isUnderPressure == false)
    }

    @Test("isCritical false when normal")
    @MainActor func notCriticalWhenNormal() {
        let sentinel = SystemSentinel.shared
        #if DEBUG
        sentinel.simulateMemoryPressure(.normal)
        sentinel.simulateThermalState(.nominal)
        #endif
        #expect(sentinel.isCritical == false)
    }

    #if DEBUG
    @Test("Simulated warning memory pressure reduces health score")
    @MainActor func warningPressure() {
        let sentinel = SystemSentinel.shared
        sentinel.simulateMemoryPressure(.normal)
        sentinel.simulateThermalState(.nominal)
        let normalScore = sentinel.healthScore

        sentinel.simulateMemoryPressure(.warning)
        let warningScore = sentinel.healthScore
        #expect(warningScore < normalScore,
            "Warning pressure should reduce health score (normal=\(normalScore), warning=\(warningScore))")
    }

    @Test("Simulated critical memory pressure triggers isCritical")
    @MainActor func criticalPressure() {
        let sentinel = SystemSentinel.shared
        sentinel.simulateMemoryPressure(.critical)
        #expect(sentinel.isCritical == true)
        // Restore
        sentinel.simulateMemoryPressure(.normal)
    }

    @Test("Simulated thermal state affects health score")
    @MainActor func thermalStateAffectsHealth() {
        let sentinel = SystemSentinel.shared
        sentinel.simulateMemoryPressure(.normal)
        sentinel.simulateThermalState(.nominal)
        let nominalScore = sentinel.healthScore

        sentinel.simulateThermalState(.serious)
        let seriousScore = sentinel.healthScore
        #expect(seriousScore < nominalScore,
            "Serious thermal should reduce health (nominal=\(nominalScore), serious=\(seriousScore))")
        // Restore
        sentinel.simulateThermalState(.nominal)
    }

    @Test("Pressure callback invoked on state change")
    @MainActor func pressureCallback() {
        let sentinel = SystemSentinel.shared
        sentinel.simulateMemoryPressure(.normal)

        var callbackFired = false
        sentinel.registerPressureCallback { _ in
            callbackFired = true
        }
        sentinel.simulateMemoryPressure(.warning)
        #expect(callbackFired, "Pressure callback should fire on state change")
        // Restore
        sentinel.simulateMemoryPressure(.normal)
    }
    #endif

    @Test("MemoryPressureLevel raw values are stable")
    func memoryPressureRawValues() {
        #expect(SystemSentinel.MemoryPressureLevel.normal.rawValue == "normal")
        #expect(SystemSentinel.MemoryPressureLevel.warning.rawValue == "warning")
        #expect(SystemSentinel.MemoryPressureLevel.critical.rawValue == "critical")
    }
}

// MARK: - Operation Watchdog Tests

@Suite("OperationWatchdog")
struct WatchdogTests {

    @Test("monitoredSync returns operation result")
    func monitoredSyncReturnsResult() async {
        let watchdog = OperationWatchdog.shared
        await watchdog.resetStatistics()
        let result = await watchdog.monitoredSync(name: "test-op") {
            return 42
        }
        #expect(result == 42)
    }

    @Test("getStatistics tracks operations")
    func statisticsTrackOperations() async {
        let watchdog = OperationWatchdog.shared
        await watchdog.resetStatistics()

        _ = await watchdog.monitoredSync(name: "stat-test") {
            return "ok"
        }

        let stats = await watchdog.getStatistics()
        #expect(stats.totalOperations >= 1,
            "Should track at least 1 operation, got \(stats.totalOperations)")
    }

    @Test("resetStatistics clears counters")
    func resetStatisticsClears() async {
        let watchdog = OperationWatchdog.shared
        _ = await watchdog.monitoredSync(name: "pre-reset") { return 1 }

        await watchdog.resetStatistics()
        let stats = await watchdog.getStatistics()
        #expect(stats.totalOperations == 0, "Reset should clear total operations")
        #expect(stats.slowOperations == 0, "Reset should clear slow operations")
    }

    @Test("monitoredAsync throws on timeout")
    func asyncTimeout() async {
        let watchdog = OperationWatchdog.shared
        await watchdog.resetStatistics()

        do {
            _ = try await watchdog.monitoredAsync(
                name: "timeout-test",
                timeout: .milliseconds(50)
            ) {
                try await Task.sleep(for: .seconds(10))
                return "should not reach"
            }
            Issue.record("Should have thrown timeout error")
        } catch {
            // Expected — WatchdogError.timeout
            #expect(error is OperationWatchdog.WatchdogError)
        }
    }

    @Test("WatchdogError.timeout has description")
    func timeoutErrorDescription() {
        let error = OperationWatchdog.WatchdogError.timeout(operation: "test-op", durationMs: 500.0)
        #expect(error.errorDescription?.contains("test-op") == true)
    }
}
