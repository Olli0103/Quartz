#if canImport(Speech)
import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4StreamingTranscription")
struct Phase4StreamingTranscriptionTests {

    // MARK: - StreamingState

    @Test("StreamingState equality works for all cases")
    func streamingStateEquality() {
        #expect(StreamingTranscriptionService.StreamingState.idle == .idle)
        #expect(StreamingTranscriptionService.StreamingState.streaming == .streaming)
        #expect(StreamingTranscriptionService.StreamingState.paused == .paused)
        #expect(StreamingTranscriptionService.StreamingState.finishing == .finishing)
        #expect(StreamingTranscriptionService.StreamingState.idle != .streaming)
    }

    // MARK: - Initial State

    @Test("Service initializes in idle state")
    func initialState() async {
        let service = StreamingTranscriptionService()
        #expect(await service.state == .idle)
    }

    @Test("Service initial accumulated text is empty")
    func initialAccumulatedText() async {
        let service = StreamingTranscriptionService()
        #expect(await service.accumulatedText.isEmpty)
    }

    @Test("Service initial segments is empty")
    func initialSegments() async {
        let service = StreamingTranscriptionService()
        #expect(await service.accumulatedSegments.isEmpty)
    }

    @Test("Service initial processed duration is zero")
    func initialProcessedDuration() async {
        let service = StreamingTranscriptionService()
        #expect(await service.processedDuration == 0)
    }

    // MARK: - StreamingError Descriptions

    @Test("StreamingError.recognizerUnavailable has non-empty description")
    func recognizerUnavailableDescription() {
        let error = StreamingTranscriptionService.StreamingError.recognizerUnavailable
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("StreamingError.recognitionFailed has description with message")
    func recognitionFailedDescription() {
        let error = StreamingTranscriptionService.StreamingError.recognitionFailed("test reason")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("test reason"))
    }

    @Test("StreamingError.notStreaming has non-empty description")
    func notStreamingDescription() {
        let error = StreamingTranscriptionService.StreamingError.notStreaming
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    // MARK: - PartialTranscript

    @Test("PartialTranscript stores correct properties")
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
        #expect(partial.audioDuration == 2.5)
    }

    @Test("PartialTranscript final flag")
    func partialTranscriptFinal() {
        let partial = StreamingTranscriptionService.PartialTranscript(
            text: "Complete text",
            isFinal: true,
            segments: [],
            audioDuration: 10.0
        )

        #expect(partial.isFinal)
    }

    // MARK: - Stop from Idle

    @Test("Stop from idle returns empty result")
    func stopFromIdleReturnsEmpty() async {
        let service = StreamingTranscriptionService()
        let result = await service.stopStreaming()
        #expect(result.text.isEmpty)
        #expect(result.segments.isEmpty)
        #expect(result.duration == 0)
        #expect(await service.state == .idle)
    }

    // MARK: - Pause from Idle

    @Test("Pause from idle is no-op")
    func pauseFromIdleNoOp() async {
        let service = StreamingTranscriptionService()
        await service.pauseStreaming()
        #expect(await service.state == .idle)
    }

    // MARK: - Custom Locale

    @Test("Service accepts custom locale")
    func customLocale() async {
        let service = StreamingTranscriptionService(locale: Locale(identifier: "de-DE"))
        #expect(await service.state == .idle)
    }
}
#endif
