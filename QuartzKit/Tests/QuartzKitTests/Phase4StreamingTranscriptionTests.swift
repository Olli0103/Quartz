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
}
#endif
