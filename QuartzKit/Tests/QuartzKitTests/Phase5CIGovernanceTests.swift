import XCTest
@testable import QuartzKit

// MARK: - Phase 5: CI Governance and Non-Negotiable Gates (CODEX.md Recovery Plan)
// Per CODEX.md F12: Block regressions automatically.
//
// Exit Criteria:
// - CIBudgetGateValidationTests: Performance budgets exist and are enforced
// - CriticalFlowSmokeMatrixTests: Critical user flow tests exist
// - Merges fail on performance or critical flow regression

// MARK: - CIBudgetGateValidationTests

/// Tests that performance budgets exist and CI can enforce them.
/// Per CODEX.md Phase 5: "add mandatory performance + critical-flow UI gates to CI"
final class CIBudgetGateValidationTests: XCTestCase {

    // MARK: - Budget Definition Tests

    /// Tests that all required performance budgets are defined.
    func testPerformanceBudgetsDefined() throws {
        // Per CODEX.md optimization ledger, these budgets must exist:
        let requiredBudgets = PerformanceBudgetRegistry.allBudgets

        // Verify all required metrics have budgets
        XCTAssertNotNil(requiredBudgets.first { $0.name == "typing_latency" },
            "Typing latency budget must be defined")
        XCTAssertNotNil(requiredBudgets.first { $0.name == "note_switch" },
            "Note switch budget must be defined")
        XCTAssertNotNil(requiredBudgets.first { $0.name == "graph_update" },
            "Graph update budget must be defined")
        XCTAssertNotNil(requiredBudgets.first { $0.name == "highlight_pass" },
            "Highlight pass budget must be defined")
        XCTAssertNotNil(requiredBudgets.first { $0.name == "audio_metering_ui_update" },
            "Audio metering UI update budget must be defined")
    }

    /// Tests that budget thresholds are reasonable.
    func testBudgetThresholdsReasonable() throws {
        let typingBudget = PerformanceBudgetRegistry.budget(named: "typing_latency")!
        XCTAssertLessThanOrEqual(typingBudget.errorThreshold, 0.050,
            "Typing budget should fail at 50ms or less")

        let noteSwitchBudget = PerformanceBudgetRegistry.budget(named: "note_switch")!
        XCTAssertLessThanOrEqual(noteSwitchBudget.errorThreshold, 0.200,
            "Note switch budget should fail at 200ms or less")

        let graphBudget = PerformanceBudgetRegistry.budget(named: "graph_update")!
        XCTAssertLessThanOrEqual(graphBudget.errorThreshold, 0.050,
            "Graph update budget should fail at 50ms or less")
    }

    // MARK: - Budget Enforcement Tests

    /// Tests that budget violations are detected.
    func testBudgetViolationDetection() throws {
        let result = PerformanceBudgetValidator.validate(
            measurement: 0.060, // 60ms
            against: PerformanceBudgetRegistry.budget(named: "typing_latency")!
        )

        XCTAssertEqual(result.status, .error,
            "60ms typing latency should be a budget violation")
        XCTAssertNotNil(result.message)
    }

    /// Tests that budget compliance is recognized.
    func testBudgetComplianceRecognition() throws {
        let result = PerformanceBudgetValidator.validate(
            measurement: 0.010, // 10ms
            against: PerformanceBudgetRegistry.budget(named: "typing_latency")!
        )

        XCTAssertEqual(result.status, .pass,
            "10ms typing latency should pass budget")
    }

    /// Tests that warnings are issued near threshold.
    func testBudgetWarningNearThreshold() throws {
        let result = PerformanceBudgetValidator.validate(
            measurement: 0.014, // 14ms - within budget but close
            against: PerformanceBudgetRegistry.budget(named: "typing_latency")!
        )

        XCTAssertEqual(result.status, .warning,
            "Near-threshold measurement should trigger warning")
    }

    // MARK: - Regression Detection Tests

    /// Tests that regression from baseline is detected.
    func testRegressionFromBaselineDetected() throws {
        let budget = PerformanceBudgetRegistry.budget(named: "typing_latency")!

        // Simulate baseline of 8ms and current of 15ms = 87.5% regression
        let result = PerformanceBudgetValidator.validateRegression(
            current: 0.015,
            baseline: 0.008,
            budget: budget
        )

        XCTAssertEqual(result.status, .error,
            "87.5% regression should fail (max is 50%)")
        XCTAssertTrue(result.message?.contains("regression") ?? false)
    }

    /// Tests that acceptable regression passes.
    func testAcceptableRegressionPasses() throws {
        let budget = PerformanceBudgetRegistry.budget(named: "typing_latency")!

        // Simulate baseline of 8ms and current of 10ms = 25% regression
        let result = PerformanceBudgetValidator.validateRegression(
            current: 0.010,
            baseline: 0.008,
            budget: budget
        )

        XCTAssertNotEqual(result.status, .error,
            "25% regression should be acceptable")
    }

    // MARK: - CI Gate Integration Tests

    /// Tests that gate can be queried for pass/fail status.
    func testCIGateStatus() throws {
        var gate = CIPerformanceGate()

        // Record some measurements
        gate.record(metric: "typing_latency", value: 0.012)
        gate.record(metric: "note_switch", value: 0.080)
        gate.record(metric: "graph_update", value: 0.005)

        // All within budget
        XCTAssertTrue(gate.passes, "Gate should pass when all metrics are within budget")
    }

    /// Tests that single violation fails gate.
    func testSingleViolationFailsGate() throws {
        var gate = CIPerformanceGate()

        gate.record(metric: "typing_latency", value: 0.012) // OK
        gate.record(metric: "note_switch", value: 0.500)    // VIOLATION
        gate.record(metric: "graph_update", value: 0.005)   // OK

        XCTAssertFalse(gate.passes, "Gate should fail with single violation")
        XCTAssertTrue(gate.violations.contains { $0.metric == "note_switch" })
    }

    /// Tests that gate summary is generated for CI output.
    func testGateSummaryGeneration() throws {
        var gate = CIPerformanceGate()
        gate.record(metric: "typing_latency", value: 0.012)
        gate.record(metric: "note_switch", value: 0.080)

        let summary = gate.summary()

        XCTAssertTrue(summary.contains("typing_latency"))
        XCTAssertTrue(summary.contains("note_switch"))
        XCTAssertTrue(summary.contains("PASS") || summary.contains("OK"))
    }
}

// MARK: - CriticalFlowSmokeMatrixTests

/// Tests that critical user flows are covered by smoke tests.
/// Per CODEX.md Phase 5: Fast PR gates for critical user journeys.
final class CriticalFlowSmokeMatrixTests: XCTestCase {

    // MARK: - Flow Coverage Tests

    /// Tests that all critical flows are enumerated.
    func testCriticalFlowsEnumerated() throws {
        let flows = CriticalFlowRegistry.allFlows

        // Per CODEX.md, critical flows include:
        XCTAssertTrue(flows.contains { $0.name == "note_creation" },
            "Note creation flow must be covered")
        XCTAssertTrue(flows.contains { $0.name == "note_editing" },
            "Note editing flow must be covered")
        XCTAssertTrue(flows.contains { $0.name == "note_switching" },
            "Note switching flow must be covered")
        XCTAssertTrue(flows.contains { $0.name == "search" },
            "Search flow must be covered")
        XCTAssertTrue(flows.contains { $0.name == "sync_conflict_resolution" },
            "Sync conflict resolution flow must be covered")
        XCTAssertTrue(flows.contains { $0.name == "undo_redo" },
            "Undo/redo flow must be covered")
    }

    /// Tests that each critical flow has a test.
    func testEachFlowHasTest() throws {
        for flow in CriticalFlowRegistry.allFlows {
            XCTAssertTrue(flow.hasTest,
                "Flow '\(flow.name)' must have associated test")
        }
    }

    // MARK: - Smoke Test Execution Tests

    /// Tests note creation smoke flow.
    @MainActor
    func testNoteCreationSmokeFlow() async throws {
        let result = await CriticalFlowRunner.run(.noteCreation)

        XCTAssertEqual(result.status, .passed,
            "Note creation flow should pass: \(result.failureReason ?? "unknown")")
        XCTAssertLessThan(result.duration, 1.0,
            "Note creation should complete in under 1 second")
    }

    /// Tests note editing smoke flow.
    @MainActor
    func testNoteEditingSmokeFlow() async throws {
        let result = await CriticalFlowRunner.run(.noteEditing)

        XCTAssertEqual(result.status, .passed,
            "Note editing flow should pass: \(result.failureReason ?? "unknown")")
        XCTAssertLessThan(result.duration, 0.5,
            "Note editing should complete in under 500ms")
    }

    /// Tests note switching smoke flow.
    @MainActor
    func testNoteSwitchingSmokeFlow() async throws {
        let result = await CriticalFlowRunner.run(.noteSwitching)

        XCTAssertEqual(result.status, .passed,
            "Note switching flow should pass: \(result.failureReason ?? "unknown")")
        XCTAssertLessThan(result.duration, 0.2,
            "Note switching should complete in under 200ms")
    }

    /// Tests search smoke flow.
    @MainActor
    func testSearchSmokeFlow() async throws {
        let result = await CriticalFlowRunner.run(.search)

        XCTAssertEqual(result.status, .passed,
            "Search flow should pass: \(result.failureReason ?? "unknown")")
        XCTAssertLessThan(result.duration, 0.5,
            "Search should complete in under 500ms")
    }

    /// Tests undo/redo smoke flow.
    @MainActor
    func testUndoRedoSmokeFlow() async throws {
        let result = await CriticalFlowRunner.run(.undoRedo)

        XCTAssertEqual(result.status, .passed,
            "Undo/redo flow should pass: \(result.failureReason ?? "unknown")")
        XCTAssertLessThan(result.duration, 0.1,
            "Undo/redo should complete in under 100ms")
    }

    /// Tests conflict resolution smoke flow.
    @MainActor
    func testConflictResolutionSmokeFlow() async throws {
        let result = await CriticalFlowRunner.run(.conflictResolution)

        XCTAssertEqual(result.status, .passed,
            "Conflict resolution flow should pass: \(result.failureReason ?? "unknown")")
    }

    // MARK: - Matrix Execution Tests

    /// Tests that all flows can be run as a matrix.
    @MainActor
    func testSmokeMatrixExecution() async throws {
        let matrix = await CriticalFlowRunner.runAll()

        XCTAssertEqual(matrix.passedCount, matrix.totalCount,
            "All smoke tests should pass. Failed: \(matrix.failedFlows.map(\.flowName))")
    }

    /// Tests that matrix reports timing for CI.
    @MainActor
    func testMatrixTimingReport() async throws {
        let matrix = await CriticalFlowRunner.runAll()

        let report = matrix.timingReport()

        for flow in CriticalFlowRegistry.allFlows {
            XCTAssertTrue(report.contains(flow.name),
                "Timing report should include \(flow.name)")
        }
    }

    /// Tests that matrix can be filtered by platform.
    func testMatrixPlatformFiltering() throws {
        let iosFlows = CriticalFlowRegistry.flows(for: .iOS)
        let macOSFlows = CriticalFlowRegistry.flows(for: .macOS)

        // Core flows should exist on both
        XCTAssertTrue(iosFlows.contains { $0.name == "note_creation" })
        XCTAssertTrue(macOSFlows.contains { $0.name == "note_creation" })
    }
}

// MARK: - BaselineVersioningTests

/// Tests baseline versioning for performance regression tracking.
/// Per CODEX.md Phase 5: "baseline versioning policy"
final class BaselineVersioningTests: XCTestCase {

    /// Tests that baseline can be recorded.
    func testBaselineRecording() throws {
        var baseline = PerformanceBaseline()

        baseline.record(metric: "typing_latency", value: 0.010, version: "1.0.0")
        baseline.record(metric: "note_switch", value: 0.080, version: "1.0.0")

        XCTAssertEqual(baseline.value(for: "typing_latency"), 0.010)
        XCTAssertEqual(baseline.value(for: "note_switch"), 0.080)
    }

    /// Tests that baseline is versioned.
    func testBaselineVersioning() throws {
        var baseline = PerformanceBaseline()

        baseline.record(metric: "typing_latency", value: 0.010, version: "1.0.0")
        baseline.record(metric: "typing_latency", value: 0.012, version: "1.1.0")

        XCTAssertEqual(baseline.value(for: "typing_latency", version: "1.0.0"), 0.010)
        XCTAssertEqual(baseline.value(for: "typing_latency", version: "1.1.0"), 0.012)
    }

    /// Tests that baseline comparison works.
    func testBaselineComparison() throws {
        var baseline = PerformanceBaseline()
        baseline.record(metric: "typing_latency", value: 0.010, version: "1.0.0")

        let comparison = baseline.compare(
            metric: "typing_latency",
            current: 0.015,
            againstVersion: "1.0.0"
        )

        XCTAssertEqual(comparison.regressionPercent, 50.0, accuracy: 0.1)
        XCTAssertTrue(comparison.isRegression)
    }
}

// MARK: - FlakyQuarantineTests

/// Tests for flaky test quarantine protocol.
/// Per CODEX.md Phase 5: "flaky quarantine protocol"
final class Phase5FlakyQuarantineTests: XCTestCase {

    /// Tests that quarantine registry exists.
    func testQuarantineRegistryExists() throws {
        let registry = FlakyTestQuarantine.shared

        XCTAssertNotNil(registry)
        XCTAssertTrue(registry.quarantinedTests.isEmpty,
                      "Fresh registry should start with no quarantined tests")
    }

    /// Tests that test can be quarantined.
    func testQuarantineTest() throws {
        var registry = FlakyTestQuarantine()

        registry.quarantine(
            test: "testSomeTimingSensitiveOperation",
            reason: "Flaky on CI due to timing",
            issue: "QUARTZ-123"
        )

        XCTAssertTrue(registry.isQuarantined("testSomeTimingSensitiveOperation"))
    }

    /// Tests that quarantine has expiry.
    func testQuarantineExpiry() throws {
        var registry = FlakyTestQuarantine()

        registry.quarantine(
            test: "testFlakyOperation",
            reason: "Investigation in progress",
            issue: "QUARTZ-456",
            expiresAt: Date().addingTimeInterval(-1) // Already expired
        )

        // Expired quarantines should be flagged
        let expired = registry.expiredQuarantines
        XCTAssertTrue(expired.contains { $0.testName == "testFlakyOperation" })
    }

    /// Tests that quarantine report is generated.
    func testQuarantineReport() throws {
        var registry = FlakyTestQuarantine()

        registry.quarantine(
            test: "testFlaky1",
            reason: "Timing issue",
            issue: "QUARTZ-100"
        )
        registry.quarantine(
            test: "testFlaky2",
            reason: "Resource contention",
            issue: "QUARTZ-101"
        )

        let report = registry.report()

        XCTAssertTrue(report.contains("testFlaky1"))
        XCTAssertTrue(report.contains("testFlaky2"))
        XCTAssertTrue(report.contains("QUARTZ-100"))
    }
}

// MARK: - TestPartitioningTests

/// Tests for test partitioning for reliable CI runtime.
/// Per CODEX.md Phase 5: "test partitioning for reliable runtime/flake control"
final class TestPartitioningTests: XCTestCase {

    /// Tests that tests are categorized by speed.
    func testSpeedCategorization() throws {
        let fast = TestPartition.fast
        let slow = TestPartition.slow
        let integration = TestPartition.integration

        XCTAssertLessThan(fast.expectedDuration, slow.expectedDuration)
        XCTAssertLessThan(slow.expectedDuration, integration.expectedDuration)
    }

    /// Tests that CI can run partitions separately.
    func testPartitionedExecution() throws {
        // Fast tests should run in under 30 seconds total
        let fastPartition = TestPartition.fast
        XCTAssertLessThan(fastPartition.expectedDuration, 30.0)

        // Integration tests may take longer
        let integrationPartition = TestPartition.integration
        XCTAssertLessThan(integrationPartition.expectedDuration, 300.0) // 5 minutes max
    }

    /// Tests that PR gate uses fast partition.
    func testPRGatePartition() throws {
        let prGate = CIPartitionConfig.prGate

        XCTAssertEqual(prGate.partitions, [.fast, .smoke])
        XCTAssertFalse(prGate.partitions.contains(.slow))
        XCTAssertFalse(prGate.partitions.contains(.integration))
    }

    /// Tests that nightly build uses all partitions.
    func testNightlyPartition() throws {
        let nightly = CIPartitionConfig.nightly

        XCTAssertTrue(nightly.partitions.contains(.fast))
        XCTAssertTrue(nightly.partitions.contains(.slow))
        XCTAssertTrue(nightly.partitions.contains(.integration))
    }
}
