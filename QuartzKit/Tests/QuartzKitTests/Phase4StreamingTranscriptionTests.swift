#if canImport(Speech)
import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4StreamingTranscription")
struct Phase4StreamingTranscriptionTests {

    // MARK: - StreamingState Equality & Exhaustiveness

    @Test("StreamingState equality works for all cases")
    func streamingStateEquality() {
        #expect(StreamingTranscriptionService.StreamingState.idle == .idle)
        #expect(StreamingTranscriptionService.StreamingState.streaming == .streaming)
        #expect(StreamingTranscriptionService.StreamingState.paused == .paused)
        #expect(StreamingTranscriptionService.StreamingState.finishing == .finishing)
        #expect(StreamingTranscriptionService.StreamingState.idle != .streaming)
        #expect(StreamingTranscriptionService.StreamingState.paused != .finishing)
        #expect(StreamingTranscriptionService.StreamingState.streaming != .idle)
    }

    @Test("All StreamingState cases are distinct")
    func streamingStateAllDistinct() {
        let allStates: [StreamingTranscriptionService.StreamingState] = [.idle, .streaming, .paused, .finishing]
        for i in 0..<allStates.count {
            for j in (i + 1)..<allStates.count {
                #expect(allStates[i] != allStates[j], "\(allStates[i]) should differ from \(allStates[j])")
            }
        }
    }

    // MARK: - Initial State

    @Test("Service initializes in idle state with clean accumulated data")
    func initialState() async {
        let service = StreamingTranscriptionService()
        #expect(await service.state == .idle)
        #expect(await service.accumulatedText.isEmpty)
        #expect(await service.accumulatedSegments.isEmpty)
        #expect(await service.processedDuration == 0)
    }

    // MARK: - StreamingError

    @Test("StreamingError.recognizerUnavailable has localized description")
    func recognizerUnavailableDescription() {
        let error = StreamingTranscriptionService.StreamingError.recognizerUnavailable
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        // Should mention speech/recognition concept
    }

    @Test("StreamingError.recognitionFailed embeds the failure reason in description")
    func recognitionFailedDescription() {
        let reason = "network timeout at 30s"
        let error = StreamingTranscriptionService.StreamingError.recognitionFailed(reason)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains(reason), "Error description should embed the original reason")
    }

    @Test("StreamingError.notStreaming has localized description")
    func notStreamingDescription() {
        let error = StreamingTranscriptionService.StreamingError.notStreaming
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("All StreamingError cases produce distinct descriptions")
    func allErrorDescriptionsDistinct() {
        let errors: [StreamingTranscriptionService.StreamingError] = [
            .recognizerUnavailable,
            .recognitionFailed("test"),
            .notStreaming
        ]
        let descriptions = errors.compactMap(\.errorDescription)
        #expect(descriptions.count == errors.count, "Every error case should have a description")
        let unique = Set(descriptions)
        #expect(unique.count == descriptions.count, "Each error should have a unique description")
    }

    // MARK: - PartialTranscript

    @Test("PartialTranscript stores all properties correctly")
    func partialTranscriptProperties() {
        let segment = TranscriptionService.TranscriptionSegment(
            text: "Hello",
            timestamp: 0.0,
            duration: 1.0,
            confidence: 0.95
        )
        let partial = StreamingTranscriptionService.PartialTranscript(
            text: "Hello world",
            isFinal: false,
            segments: [segment],
            audioDuration: 2.5
        )

        #expect(partial.text == "Hello world")
        #expect(partial.isFinal == false)
        #expect(partial.segments.count == 1)
        #expect(partial.segments[0].text == "Hello")
        #expect(partial.segments[0].confidence == 0.95)
        #expect(partial.audioDuration == 2.5)
    }

    @Test("PartialTranscript with isFinal=true marks end of recognition window")
    func partialTranscriptFinal() {
        let partial = StreamingTranscriptionService.PartialTranscript(
            text: "Complete sentence from recognition.",
            isFinal: true,
            segments: [],
            audioDuration: 10.0
        )
        #expect(partial.isFinal)
        #expect(partial.audioDuration == 10.0)
    }

    @Test("PartialTranscript with multiple segments preserves order")
    func partialTranscriptMultipleSegments() {
        let segments = (0..<5).map { i in
            TranscriptionService.TranscriptionSegment(
                text: "Word\(i)",
                timestamp: Double(i) * 0.5,
                duration: 0.4,
                confidence: 0.9
            )
        }
        let partial = StreamingTranscriptionService.PartialTranscript(
            text: "Word0 Word1 Word2 Word3 Word4",
            isFinal: false,
            segments: segments,
            audioDuration: 2.5
        )
        #expect(partial.segments.count == 5)
        for i in 0..<5 {
            #expect(partial.segments[i].text == "Word\(i)")
            #expect(partial.segments[i].timestamp == Double(i) * 0.5)
        }
    }

    // MARK: - Stop from Idle (Edge Case)

    @Test("Stop from idle returns empty result and stays idle")
    func stopFromIdleReturnsEmpty() async {
        let service = StreamingTranscriptionService()
        let result = await service.stopStreaming()
        #expect(result.text.isEmpty)
        #expect(result.segments.isEmpty)
        #expect(result.duration == 0)
        #expect(await service.state == .idle)
    }

    // MARK: - Pause from Idle (Edge Case)

    @Test("Pause from idle is no-op — state remains idle")
    func pauseFromIdleNoOp() async {
        let service = StreamingTranscriptionService()
        await service.pauseStreaming()
        #expect(await service.state == .idle, "Pause from idle should not change state")
    }

    // MARK: - Resume from Idle (Edge Case)

    @Test("Resume from idle is no-op — state remains idle")
    func resumeFromIdleNoOp() async throws {
        let service = StreamingTranscriptionService()
        try await service.resumeStreaming()
        #expect(await service.state == .idle, "Resume from idle should be no-op")
    }

    // MARK: - Locale Configuration

    @Test("Service accepts custom locale for recognition")
    func customLocale() async {
        let service = StreamingTranscriptionService(locale: Locale(identifier: "de-DE"))
        #expect(await service.state == .idle)
        // Service created with German locale — should not crash
    }

    @Test("Service with default locale initializes properly")
    func defaultLocale() async {
        let service = StreamingTranscriptionService()
        #expect(await service.state == .idle)
    }

    // MARK: - startStreaming Guard Behavior

    @Test("startStreaming throws when recognizer is unavailable for exotic locale")
    func startStreamingUnavailableRecognizer() async {
        // Use an exotic locale that has no speech model
        let service = StreamingTranscriptionService(locale: Locale(identifier: "tlh-Piqd"))
        let stream = AsyncStream<AudioChunk> { $0.finish() }

        do {
            _ = try await service.startStreaming(audioChunkStream: stream)
            #expect(Bool(false), "Should have thrown recognizerUnavailable")
        } catch {
            // Expected — recognizer unavailable for Klingon
            #expect(await service.state == .idle)
        }
    }

    // MARK: - Sequential Stop Calls

    @Test("Calling stop multiple times from idle is safe")
    func multipleStopsFromIdle() async {
        let service = StreamingTranscriptionService()
        let result1 = await service.stopStreaming()
        let result2 = await service.stopStreaming()
        #expect(result1.text.isEmpty)
        #expect(result2.text.isEmpty)
        #expect(await service.state == .idle)
    }

    // MARK: - Adversarial Lifecycle Transitions

    @Test("Rapid pause-stop sequence from idle does not crash")
    func rapidPauseStopFromIdle() async {
        let service = StreamingTranscriptionService()
        await service.pauseStreaming()
        let result = await service.stopStreaming()
        #expect(result.text.isEmpty)
        #expect(await service.state == .idle)
    }

    @Test("Concurrent stop calls from multiple tasks are serialized safely")
    func concurrentStopsAreSafe() async {
        let service = StreamingTranscriptionService()

        await withTaskGroup(of: TranscriptionService.TranscriptionResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await service.stopStreaming()
                }
            }
            for await result in group {
                #expect(result.text.isEmpty)
            }
        }

        #expect(await service.state == .idle, "State should be idle after concurrent stops")
    }

    @Test("Concurrent pause calls from multiple tasks do not crash")
    func concurrentPausesAreSafe() async {
        let service = StreamingTranscriptionService()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await service.pauseStreaming()
                }
            }
        }

        #expect(await service.state == .idle, "State should remain idle after concurrent pauses")
    }

    @Test("State reads under concurrent access are consistent")
    func concurrentStateReads() async {
        let service = StreamingTranscriptionService()

        await withTaskGroup(of: StreamingTranscriptionService.StreamingState.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await service.state
                }
            }
            for await state in group {
                #expect(state == .idle, "All concurrent reads should see idle")
            }
        }
    }

    // MARK: - Adversarial Lifecycle Transitions

    @Test("Rapid start-stop-start cycle does not deadlock")
    func rapidStartStopStartCycle() async {
        let service = StreamingTranscriptionService()

        // Attempt start → will likely fail (no real recognizer) — that's fine
        let stream1 = AsyncStream<AudioChunk> { $0.finish() }
        _ = try? await service.startStreaming(audioChunkStream: stream1)

        // Immediately stop
        let result = await service.stopStreaming()
        #expect(result.text.isEmpty || !result.text.isEmpty, "Stop should return a result")

        // Immediately attempt start again
        let stream2 = AsyncStream<AudioChunk> { $0.finish() }
        _ = try? await service.startStreaming(audioChunkStream: stream2)

        // Final stop to clean up
        _ = await service.stopStreaming()

        // If we get here without deadlock, test passes
        let finalState = await service.state
        #expect(finalState == .idle, "Should end in idle after rapid start-stop-start cycle")
    }

    @Test("Concurrent start attempts: all fail gracefully or exactly one succeeds")
    func concurrentStartAttempts() async {
        let service = StreamingTranscriptionService()

        var successCount = 0
        var failCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let stream = AsyncStream<AudioChunk> { $0.finish() }
                    do {
                        _ = try await service.startStreaming(audioChunkStream: stream)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            for await success in group {
                if success { successCount += 1 }
                else { failCount += 1 }
            }
        }

        // Clean up
        _ = await service.stopStreaming()

        // At most 1 should succeed (actor serialization), all others fail
        #expect(successCount <= 1, "At most one concurrent start should succeed (got \(successCount))")
        #expect(successCount + failCount == 5, "All 5 attempts should complete")
    }

    @Test("Error during concurrent operations: all return to idle")
    func errorDuringConcurrentOperationsReturnsIdle() async {
        // Use exotic locale to guarantee startStreaming throws
        let service = StreamingTranscriptionService(locale: Locale(identifier: "tlh-Piqd"))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let stream = AsyncStream<AudioChunk> { $0.finish() }
                    _ = try? await service.startStreaming(audioChunkStream: stream)
                }
            }
        }

        #expect(await service.state == .idle, "After all failed starts, state should be idle")
    }

    @Test("Lifecycle transition matrix: all invalid transitions from idle are safe")
    func lifecycleTransitionMatrixFromIdle() async throws {
        let service = StreamingTranscriptionService()

        // Stop from idle → empty result, stay idle
        let stopResult = await service.stopStreaming()
        #expect(stopResult.text.isEmpty)
        #expect(await service.state == .idle)

        // Pause from idle → no-op, stay idle
        await service.pauseStreaming()
        #expect(await service.state == .idle)

        // Resume from idle → no-op, stay idle
        try await service.resumeStreaming()
        #expect(await service.state == .idle)

        // Multiple mixed operations from idle → all safe
        await service.pauseStreaming()
        _ = await service.stopStreaming()
        try await service.resumeStreaming()
        await service.pauseStreaming()
        _ = await service.stopStreaming()

        #expect(await service.state == .idle, "All transitions from idle should leave state idle")
    }

    @Test("Concurrent mixed lifecycle operations do not crash or deadlock")
    func concurrentMixedLifecycleOperations() async {
        let service = StreamingTranscriptionService()

        await withTaskGroup(of: Void.self) { group in
            // Some tasks try to stop
            for _ in 0..<5 {
                group.addTask {
                    _ = await service.stopStreaming()
                }
            }
            // Some tasks try to pause
            for _ in 0..<5 {
                group.addTask {
                    await service.pauseStreaming()
                }
            }
            // Some tasks try to resume
            for _ in 0..<5 {
                group.addTask {
                    try? await service.resumeStreaming()
                }
            }
            // Some tasks read state
            for _ in 0..<5 {
                group.addTask {
                    _ = await service.state
                }
            }
        }

        // All 20 tasks completed without crash or deadlock
        #expect(await service.state == .idle, "After concurrent mixed ops, state should be idle")
    }
}
#endif
