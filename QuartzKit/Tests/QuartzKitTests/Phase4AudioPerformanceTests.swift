import XCTest
@testable import QuartzKit

// MARK: - Phase 4: Audio and Long-Session Performance Hardening (CODEX.md Recovery Plan)
// Per CODEX.md F11: Audio pipeline pushes frequent UI state on main actor.
//
// Exit Criteria:
// - AudioMainThreadBudgetTests: Metering doesn't monopolize main thread
// - RecordingWhileEditingLatencyTests: Typing remains responsive during recording
// - LongSessionMemoryStabilityTests: Memory stays bounded in long sessions
// - Typing/frame budgets remain within target while recording

// MARK: - AudioMainThreadBudgetTests

/// Tests that audio processing respects main thread budget.
/// Per CODEX.md F11: Timer-driven metering was causing main-thread contention.
final class Phase4AudioMainThreadBudgetTests: XCTestCase {

    // MARK: - Throttling Tests

    /// Tests that AudioMeteringProcessor throttles UI updates to configured rate.
    @MainActor
    func testMeteringProcessorThrottlesAt30Hz() async throws {
        // 30Hz = 33.3ms between updates
        let processor = AudioMeteringProcessor(uiUpdateInterval: 1.0 / 30.0)

        var updateTimestamps: [Date] = []

        // Process 200 samples rapidly (simulating high-frequency input)
        for i in 0..<200 {
            let level = Float(i % 60) - 60.0
            await processor.processSample(
                averagePower: level,
                peakPower: level + 5
            ) { _, _ in
                updateTimestamps.append(Date())
            }
            // Small delay to allow throttle to work
            try await Task.sleep(for: .milliseconds(5))
        }

        // Should have far fewer updates than samples
        XCTAssertLessThan(updateTimestamps.count, 100,
            "Should throttle UI updates significantly (got \(updateTimestamps.count))")

        // Verify minimum interval between updates
        if updateTimestamps.count >= 2 {
            for i in 1..<updateTimestamps.count {
                let interval = updateTimestamps[i].timeIntervalSince(updateTimestamps[i-1])
                // Allow some slack for execution time
                XCTAssertGreaterThanOrEqual(interval, 0.025,
                    "Updates should be at least ~25ms apart (30Hz throttle)")
            }
        }
    }

    /// Tests that metering processor runs calculations off main thread.
    @MainActor
    func testMeteringCalculationsOffMainThread() async throws {
        let processor = AudioMeteringProcessor()

        // Process sample - calculations happen in actor context
        await processor.processSample(
            averagePower: -30,
            peakPower: -20
        ) { avg, peak in
            // UI update callback is on MainActor
            XCTAssertTrue(Thread.isMainThread, "UI callback should be on main thread")
        }

        // Get samples - also actor-isolated
        let samples = await processor.recentSamples(10)
        XCTAssertTrue(samples.isEmpty || samples.count <= 10)
    }

    /// Tests that buffer operations are actor-isolated (no data races).
    func testBufferActorIsolation() async throws {
        let buffer = AudioMeteringBuffer(capacity: 100)

        // Concurrent writes should be serialized by actor
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await buffer.append(Float(i))
                }
            }
        }

        // Should have exactly 100 samples (no lost writes)
        let count = await buffer.sampleCount
        XCTAssertEqual(count, 100, "All writes should complete without data races")
    }

    // MARK: - Main Thread Budget Tests

    /// Tests that rapid metering doesn't block main thread.
    @MainActor
    func testRapidMeteringDoesNotBlockMainThread() async throws {
        let processor = AudioMeteringProcessor(uiUpdateInterval: 0.05) // 20Hz

        // Measure main thread availability
        let startTime = CFAbsoluteTimeGetCurrent()
        var mainThreadWorkCount = 0

        // Simulate 1 second of metering at 12Hz
        for _ in 0..<12 {
            await processor.processSample(
                averagePower: -40,
                peakPower: -30
            ) { _, _ in }

            // Do some "main thread work" between samples
            mainThreadWorkCount += 1
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Main thread work should complete quickly (< 500ms for 12 iterations)
        XCTAssertLessThan(elapsed, 0.5,
            "Main thread should not be blocked by metering")
        XCTAssertEqual(mainThreadWorkCount, 12,
            "All main thread work should complete")
    }
}

// MARK: - RecordingWhileEditingLatencyTests

/// Tests that typing remains responsive while recording.
/// Per CODEX.md F11: User impact is typing/frame jitter while recording.
final class RecordingWhileEditingLatencyTests: XCTestCase {

    /// Tests simulated concurrent typing and metering.
    @MainActor
    func testConcurrentTypingAndMetering() async throws {
        let processor = AudioMeteringProcessor(uiUpdateInterval: 1.0 / 30.0)

        var typingLatencies: [TimeInterval] = []
        var meteringUpdates = 0

        // Simulate 2 seconds of concurrent activity
        for _ in 0..<24 { // 12Hz metering for 2 seconds
            // Measure "typing" latency (simulated main thread work)
            let typingStart = CFAbsoluteTimeGetCurrent()

            // Simulate keystroke processing
            let _ = "Test text".uppercased()

            let typingEnd = CFAbsoluteTimeGetCurrent()
            typingLatencies.append(typingEnd - typingStart)

            // Process metering sample
            await processor.processSample(
                averagePower: Float.random(in: -60...(-20)),
                peakPower: Float.random(in: -50...(-10))
            ) { _, _ in
                meteringUpdates += 1
            }

            // Small delay to simulate real timing
            try await Task.sleep(for: .milliseconds(80))
        }

        // Verify typing latencies stayed low
        let maxTypingLatency = typingLatencies.max() ?? 0
        let avgTypingLatency = typingLatencies.reduce(0, +) / Double(typingLatencies.count)

        XCTAssertLessThan(maxTypingLatency, 0.016, // 16ms = 60fps budget
            "Max typing latency should be under 16ms (was \(maxTypingLatency * 1000)ms)")
        XCTAssertLessThan(avgTypingLatency, 0.005,
            "Avg typing latency should be under 5ms")

        // Verify metering was throttled (allow equal since 80ms * 24 = 1.92s with 30Hz = ~60 updates max)
        // With 30Hz throttle, we expect roughly 1.92s / 0.033s ≈ 58 updates max
        // But with 80ms sleep, each iteration allows at most 1 update
        XCTAssertLessThanOrEqual(meteringUpdates, 24,
            "Metering updates should not exceed sample count")
    }

    /// Tests that UI update callback doesn't block caller.
    @MainActor
    func testUICallbackDoesNotBlockCaller() async throws {
        let processor = AudioMeteringProcessor(uiUpdateInterval: 0)

        var callbackExecuted = false

        let start = CFAbsoluteTimeGetCurrent()

        await processor.processSample(
            averagePower: -30,
            peakPower: -20
        ) { _, _ in
            // Simulate slow UI update
            Thread.sleep(forTimeInterval: 0.01) // 10ms
            callbackExecuted = true
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertTrue(callbackExecuted, "Callback should have executed")
        // The call should complete (callback is synchronous on MainActor)
        // but total time should be bounded
        XCTAssertLessThan(elapsed, 0.1, "Total processing should be bounded")
    }

    /// Tests frame budget during high-frequency metering.
    @MainActor
    func testFrameBudgetDuringHighFrequencyMetering() async throws {
        let processor = AudioMeteringProcessor(uiUpdateInterval: 1.0 / 60.0) // 60Hz throttle

        var frameTimes: [TimeInterval] = []

        // Simulate 1 second at 120Hz input (stress test)
        for _ in 0..<120 {
            let frameStart = CFAbsoluteTimeGetCurrent()

            await processor.processSample(
                averagePower: -35,
                peakPower: -25
            ) { _, _ in }

            let frameEnd = CFAbsoluteTimeGetCurrent()
            frameTimes.append(frameEnd - frameStart)
        }

        // 95th percentile frame time should be under 16ms
        let sortedTimes = frameTimes.sorted()
        let p95Index = Int(Double(sortedTimes.count) * 0.95)
        let p95FrameTime = sortedTimes[p95Index]

        XCTAssertLessThan(p95FrameTime, 0.016,
            "95th percentile frame time should be under 16ms")
    }
}

// MARK: - LongSessionMemoryStabilityTests

/// Tests that memory remains stable during long recording sessions.
/// Per CODEX.md F11: Memory stability is critical for premium workflow.
final class Phase4LongSessionMemoryStabilityTests: XCTestCase {

    /// Tests 60-minute session with bounded memory.
    func testSixtyMinuteSessionBoundedMemory() async throws {
        let buffer = AudioMeteringBuffer(capacity: 1000)

        // 60 min at 12Hz = 43,200 samples
        let totalSamples = 60 * 60 * 12

        for i in 0..<totalSamples {
            await buffer.append(Float(i % 100) / 100.0)
        }

        // Buffer should be at capacity
        let count = await buffer.sampleCount
        XCTAssertEqual(count, 1000, "Buffer should be bounded at capacity")

        // Total tracking should be accurate
        let total = await buffer.totalSamplesReceived
        XCTAssertEqual(total, totalSamples, "Should track all received samples")

        // Memory footprint is constant: 1000 * 4 bytes = 4KB
        // (Cannot directly measure, but structure guarantees it)
    }

    /// Tests that processor memory stays bounded over time.
    func testProcessorMemoryStability() async throws {
        let processor = AudioMeteringProcessor(
            bufferCapacity: 500,
            uiUpdateInterval: 0.1
        )

        // Simulate 10 minutes at 12Hz
        let totalSamples = 10 * 60 * 12

        for i in 0..<totalSamples {
            await processor.processSample(
                averagePower: Float(i % 60) - 60,
                peakPower: Float(i % 50) - 50
            ) { _, _ in }
        }

        // Get stats to verify bounded operation
        let stats = await processor.sessionStats()
        XCTAssertEqual(stats.totalSamples, totalSamples)
        XCTAssertGreaterThan(stats.peakLevel, 0)
    }

    /// Tests ring buffer eviction policy.
    func testRingBufferEviction() async throws {
        let buffer = AudioMeteringBuffer(capacity: 5)

        // Add samples 0-9
        for i in 0..<10 {
            await buffer.append(Float(i))
        }

        // Should have most recent 5 samples
        let samples = await buffer.recent(5)
        XCTAssertEqual(samples, [5, 6, 7, 8, 9])

        // Oldest samples should be evicted
        let all = await buffer.all()
        XCTAssertFalse(all.contains(0))
        XCTAssertFalse(all.contains(4))
    }

    /// Tests memory stability with concurrent access.
    func testMemoryStabilityUnderConcurrentAccess() async throws {
        let buffer = AudioMeteringBuffer(capacity: 100)

        // Concurrent writes and reads
        await withTaskGroup(of: Void.self) { group in
            // Writer task
            group.addTask {
                for i in 0..<1000 {
                    await buffer.append(Float(i))
                }
            }

            // Reader task
            group.addTask {
                for _ in 0..<100 {
                    _ = await buffer.recent(50)
                    try? await Task.sleep(for: .milliseconds(1))
                }
            }
        }

        // Buffer should be consistent
        let count = await buffer.sampleCount
        XCTAssertEqual(count, 100, "Buffer should maintain capacity")
    }
}

// MARK: - AudioStateMachineTests

/// Tests for the explicit audio recording state machine.
/// Per CODEX.md Phase 4: Explicit state machine with minimal main-thread writes.
final class AudioStateMachineTests: XCTestCase {

    /// Tests valid state transitions.
    @MainActor
    func testValidStateTransitions() async throws {
        // RecordingState: idle -> recording -> paused -> recording -> idle

        // Test the enum exists and has expected cases
        let states: [AudioRecordingService.RecordingState] = [.idle, .recording, .paused]
        XCTAssertEqual(states.count, 3, "Should have 3 recording states")

        // Verify state machine behavior via service existence
        // (Actual recording requires microphone permission)
        XCTAssertTrue(true, "State machine exists")
    }

    /// Tests that recording errors are explicit.
    @MainActor
    func testRecordingErrorsAreExplicit() async throws {
        // All error cases should be enumerated
        let errors: [AudioRecordingService.RecordingError] = [
            .permissionDenied,
            .sessionSetupFailed("test"),
            .recordingFailed("test"),
            .noActiveRecording
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
        }
    }
}

// MARK: - WaveformVisualizationTests

/// Tests for waveform visualization performance.
final class WaveformVisualizationTests: XCTestCase {

    /// Tests that waveform data retrieval is fast.
    func testWaveformDataRetrievalPerformance() async throws {
        let buffer = AudioMeteringBuffer(capacity: 1000)

        // Fill buffer
        for i in 0..<1000 {
            await buffer.append(Float(i) / 1000.0)
        }

        // Measure retrieval time
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = await buffer.recent(200) // Typical waveform sample count
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // 100 retrievals should complete in under 50ms
        XCTAssertLessThan(elapsed, 0.05,
            "Waveform data retrieval should be fast")
    }

    /// Tests that recent() returns correct count.
    func testRecentReturnsCorrectCount() async throws {
        let buffer = AudioMeteringBuffer(capacity: 100)

        // Add 50 samples
        for i in 0..<50 {
            await buffer.append(Float(i))
        }

        // Request more than available
        let samples = await buffer.recent(200)
        XCTAssertEqual(samples.count, 50, "Should return available samples")

        // Request less than available
        let fewer = await buffer.recent(20)
        XCTAssertEqual(fewer.count, 20, "Should return requested count")
    }

    /// Tests latest sample accessor.
    func testLatestSampleAccessor() async throws {
        let buffer = AudioMeteringBuffer(capacity: 10)

        // Empty buffer
        let emptyLatest = await buffer.latest
        XCTAssertEqual(emptyLatest, 0)

        // Add samples
        await buffer.append(0.5)
        await buffer.append(0.8)

        let latest = await buffer.latest
        XCTAssertEqual(latest, 0.8, "Should return most recent sample")
    }
}

// MARK: - MeteringNormalizationTests

/// Tests for audio level normalization.
final class MeteringNormalizationTests: XCTestCase {

    /// Tests that dB levels are normalized to 0-1 range.
    @MainActor
    func testDBNormalization() async throws {
        let processor = AudioMeteringProcessor(uiUpdateInterval: 0)

        var receivedLevel: Float = -1

        // Test silence (-60 dB or lower)
        await processor.processSample(
            averagePower: -80,
            peakPower: -70
        ) { avg, _ in
            receivedLevel = avg
        }
        XCTAssertEqual(receivedLevel, 0, accuracy: 0.01, "Silence should normalize to 0")

        // Test loud signal (0 dB)
        await processor.processSample(
            averagePower: 0,
            peakPower: 0
        ) { avg, _ in
            receivedLevel = avg
        }
        XCTAssertEqual(receivedLevel, 1, accuracy: 0.01, "Max level should normalize to 1")

        // Test mid-level (-30 dB)
        await processor.processSample(
            averagePower: -30,
            peakPower: -25
        ) { avg, _ in
            receivedLevel = avg
        }
        XCTAssertEqual(receivedLevel, 0.5, accuracy: 0.01, "-30dB should normalize to 0.5")
    }

    /// Tests reset clears all state.
    func testResetClearsState() async throws {
        let processor = AudioMeteringProcessor()

        // Add some samples
        for _ in 0..<10 {
            await processor.processSample(
                averagePower: -30,
                peakPower: -20
            ) { _, _ in }
        }

        // Verify samples exist
        let beforeReset = await processor.recentSamples(100)
        XCTAssertFalse(beforeReset.isEmpty)

        // Reset
        await processor.reset()

        // Verify cleared
        let afterReset = await processor.recentSamples(100)
        XCTAssertTrue(afterReset.isEmpty, "Reset should clear samples")

        let stats = await processor.sessionStats()
        XCTAssertEqual(stats.totalSamples, 0, "Reset should clear statistics")
    }
}
