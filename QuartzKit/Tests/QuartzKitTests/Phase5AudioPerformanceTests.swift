import XCTest
@testable import QuartzKit

// MARK: - Phase 5: Audio & Long-Session Performance Hardening (CODEX.md Recovery Plan)
// Per CODEX.md F8: Audio pipeline puts frequent metering/history mutation on MainActor.

// MARK: - AudioMainThreadBudgetTests

/// Tests that audio recording doesn't monopolize the main thread.
/// Per CODEX.md F8: AudioMeteringProcessor now handles metering off MainActor.
final class AudioMainThreadBudgetTests: XCTestCase {

    /// Tests that AudioMeteringProcessor throttles UI updates.
    @MainActor
    func testMeteringProcessorThrottlesUIUpdates() async throws {
        let processor = AudioMeteringProcessor(uiUpdateInterval: 0.1)

        var updateCount = 0

        // Process 100 samples rapidly (simulating 12Hz for ~8 seconds)
        for i in 0..<100 {
            let level = Float(i % 50) / 50.0 - 0.8 // Simulate varying dB levels
            let update = await processor.processSample(
                averagePower: level * 60 - 60,
                peakPower: level * 60 - 50
            )
            if update != nil {
                updateCount += 1
            }
        }

        // With 0.1s throttle, we should have far fewer than 100 updates
        // (depends on execution speed, but should be significantly throttled)
        XCTAssertGreaterThan(updateCount, 0, "Throttling should still allow some UI updates through")
        XCTAssertLessThan(updateCount, 50, "UI updates should be throttled")
    }

    /// Tests that a simple recording session can start.
    @MainActor
    func testAudioRecordingServiceExists() async throws {
        let service = AudioRecordingService()

        XCTAssertEqual(service.state, .idle, "Recording service should start idle")
        XCTAssertFalse(service.isRecording, "Idle service must not report recording")
        XCTAssertFalse(service.isPaused, "Idle service must not report paused")
        XCTAssertEqual(service.duration, 0, accuracy: 0.001, "Fresh service should have zero duration")
        XCTAssertEqual(service.currentLevel, 0, accuracy: 0.001, "Fresh service should have zero current level")
        XCTAssertEqual(service.peakLevel, 0, accuracy: 0.001, "Fresh service should have zero peak level")
        XCTAssertTrue(service.levelHistory.isEmpty, "Fresh service should not expose stale waveform history")
        XCTAssertNil(service.lastRecordingURL, "Fresh service should not point at an old recording")
    }
}

// MARK: - LongRecordingMemoryStabilityTests

/// Tests that long recording sessions don't exhaust memory.
final class LongRecordingMemoryStabilityTests: XCTestCase {

    /// Tests that ring buffer has bounded size.
    func testRingBufferBoundedSize() async throws {
        let buffer = AudioMeteringBuffer(capacity: 100)

        // Add more samples than capacity
        for i in 0..<500 {
            await buffer.append(Float(i))
        }

        // Buffer should be at capacity, not 500
        let count = await buffer.sampleCount
        XCTAssertEqual(count, 100, "Buffer should be bounded at capacity")

        // Total received should be 500
        let total = await buffer.totalSamplesReceived
        XCTAssertEqual(total, 500, "Should track total samples received")
    }

    /// Tests ring buffer FIFO ordering.
    func testRingBufferFIFOOrdering() async throws {
        let buffer = AudioMeteringBuffer(capacity: 5)

        // Add samples 0-9
        for i in 0..<10 {
            await buffer.append(Float(i))
        }

        // Should have 5-9 (most recent 5)
        let samples = await buffer.all()
        XCTAssertEqual(samples, [5, 6, 7, 8, 9], "Should retain most recent samples in order")
    }

    /// Tests memory budget for 60-minute session.
    func testSixtyMinuteSessionMemoryBudget() async throws {
        // Per CODEX.md: 60 min at 12Hz = 43,200 samples
        // With ring buffer capacity 1000, we stay bounded

        let buffer = AudioMeteringBuffer(capacity: 1000)

        // Simulate 60 minutes at 12Hz
        let samples = 60 * 60 * 12  // 43,200

        for i in 0..<samples {
            await buffer.append(Float(i % 100) / 100.0)
        }

        // Memory should be constant (1000 floats = 4KB)
        let count = await buffer.sampleCount
        XCTAssertEqual(count, 1000, "Buffer should stay at capacity")

        // Verify we tracked all samples
        let total = await buffer.totalSamplesReceived
        XCTAssertEqual(total, samples, "Should track all samples received")
    }

    /// Tests peak level tracking.
    func testPeakLevelTracking() async throws {
        let buffer = AudioMeteringBuffer(capacity: 100)

        await buffer.append(0.5)
        await buffer.append(0.9)
        await buffer.append(0.3)

        let peak = await buffer.sessionPeakLevel
        XCTAssertEqual(peak, 0.9, "Should track session peak")
    }

    /// Tests statistics computation.
    func testStatisticsComputation() async throws {
        let buffer = AudioMeteringBuffer(capacity: 100)

        // Add samples with known values
        for _ in 0..<10 {
            await buffer.append(0.5)
        }

        let avg = await buffer.averageLevel(samples: 10)
        XCTAssertEqual(avg, 0.5, accuracy: 0.001, "Average should be 0.5")

        let rms = await buffer.rmsLevel(samples: 10)
        XCTAssertEqual(rms, 0.5, accuracy: 0.001, "RMS of constant signal equals signal")
    }
}

// MARK: - DiarizationQualityFixtureTests

/// Tests speaker diarization quality with synthetic fixtures.
final class DiarizationQualityFixtureTests: XCTestCase {

    /// Documents diarization implementation status.
    @MainActor
    func testDiarizationStatusDocumentation() async throws {
        let service = SpeakerDiarizationService()
        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                .init(
                    speakerID: "speaker_0",
                    speakerLabel: "Speaker A",
                    startTime: 0,
                    endTime: 10,
                    confidence: 0.93
                )
            ],
            speakerCount: 1,
            speakers: ["speaker_0": "Speaker A"]
        )
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Opening remarks",
            segments: [
                .init(text: "Opening remarks", timestamp: 1, duration: 2, confidence: 0.95)
            ],
            locale: Locale(identifier: "en_US"),
            duration: 10
        )

        let combined = await service.combineWithTranscription(
            diarization: diarization,
            transcription: transcription
        )

        XCTAssertTrue(combined.contains("**Speaker A** [00:00]:"), "Combined transcript should label the speaker")
        XCTAssertTrue(combined.contains("Opening remarks"), "Combined transcript should carry transcription text")
    }

    /// Tests that speaker segments align with transcription.
    @MainActor
    func testSpeakerSegmentAlignment() async throws {
        let service = SpeakerDiarizationService()
        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                .init(
                    speakerID: "speaker_0",
                    speakerLabel: "Speaker A",
                    startTime: 0,
                    endTime: 5,
                    confidence: 0.91
                ),
                .init(
                    speakerID: "speaker_1",
                    speakerLabel: "Speaker B",
                    startTime: 5,
                    endTime: 10,
                    confidence: 0.89
                )
            ],
            speakerCount: 2,
            speakers: [
                "speaker_0": "Speaker A",
                "speaker_1": "Speaker B"
            ]
        )
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Intro response trailing",
            segments: [
                .init(text: "Intro", timestamp: 1, duration: 1, confidence: 0.95),
                .init(text: "response", timestamp: 6, duration: 1, confidence: 0.94),
                .init(text: "trailing", timestamp: 12, duration: 1, confidence: 0.80)
            ],
            locale: Locale(identifier: "en_US"),
            duration: 12
        )

        let combined = await service.combineWithTranscription(
            diarization: diarization,
            transcription: transcription
        )

        XCTAssertTrue(combined.contains("**Speaker A** [00:00]: Intro"), "First speaker block should capture only in-range text")
        XCTAssertTrue(combined.contains("**Speaker B** [00:05]: response"), "Second speaker block should capture its own text")
        XCTAssertFalse(combined.contains("trailing"), "Out-of-range transcription text should not be orphaned into a speaker block")
    }
}
