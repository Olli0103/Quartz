#if canImport(Speech)
import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4StreamingTranscription")
struct Phase4StreamingTranscriptionTests {

    @Test("Service initializes idle with no retained transcript state")
    func initialStateIsClean() async {
        let service = StreamingTranscriptionService(
            locale: Locale(identifier: "en-US"),
            testBackend: .init(recognizerAvailable: true)
        )

        #expect(await service.state == .idle)
        #expect(await service.accumulatedText.isEmpty)
        #expect(await service.accumulatedSegments.isEmpty)
        #expect(await service.processedDuration == 0)
    }

    @Test("Unavailable recognizer rejects start and preserves idle state")
    func unavailableRecognizerRejectsStart() async {
        let service = StreamingTranscriptionService(
            locale: Locale(identifier: "en-US"),
            testBackend: .init(recognizerAvailable: false)
        )
        let stream = AsyncStream<AudioChunk> { continuation in
            continuation.finish()
        }

        do {
            _ = try await service.startStreaming(audioChunkStream: stream)
            Issue.record("Expected recognizerUnavailable when backend reports unavailable")
        } catch let error as StreamingTranscriptionService.StreamingError {
            let isRecognizerUnavailable: Bool
            if case .recognizerUnavailable = error {
                isRecognizerUnavailable = true
            } else {
                isRecognizerUnavailable = false
                Issue.record("Unexpected streaming error: \(error)")
            }
            #expect(isRecognizerUnavailable)
            #expect(await service.state == .idle)
            #expect(await service.accumulatedText.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Pause and resume retain prior text and offset resumed segments")
    func pauseResumeRetainsTranscriptAndOffsetsSegments() async throws {
        let service = StreamingTranscriptionService(
            locale: Locale(identifier: "en-US"),
            testBackend: .init(recognizerAvailable: true)
        )
        let (audioStream, continuation) = makeAudioStream()
        let partialStream = try await service.startStreaming(audioChunkStream: audioStream)

        let collector = Task<[StreamingTranscriptionService.PartialTranscript], Never> {
            var partials: [StreamingTranscriptionService.PartialTranscript] = []
            for await partial in partialStream {
                partials.append(partial)
                if partials.count == 2 {
                    break
                }
            }
            return partials
        }

        continuation.yield(makeChunk(timestamp: 0, duration: 0.5))
        await service.injectTestTranscript(
            sessionText: "Hello",
            segments: [
                TranscriptionService.TranscriptionSegment(
                    text: "Hello",
                    timestamp: 0,
                    duration: 0.5,
                    confidence: 0.95
                )
            ]
        )
        await Task.yield()

        #expect(await service.state == .streaming)
        #expect(abs(await service.processedDuration - 0.5) < 0.0001)

        await service.pauseStreaming()
        let pausedDuration = await service.processedDuration

        continuation.yield(makeChunk(timestamp: 1.0, duration: 0.5))
        await Task.yield()
        #expect(await service.state == .paused)
        #expect(await service.processedDuration == pausedDuration)

        try await service.resumeStreaming()
        continuation.yield(makeChunk(timestamp: 0, duration: 0.25))
        await service.injectTestTranscript(
            sessionText: "World",
            isFinal: true,
            segments: [
                TranscriptionService.TranscriptionSegment(
                    text: "World",
                    timestamp: 0,
                    duration: 0.25,
                    confidence: 0.9
                )
            ]
        )

        let result = await service.stopStreaming()
        continuation.finish()
        let partials = await collector.value

        #expect(partials.count == 2)
        #expect(partials[0].text == "Hello")
        #expect(partials[1].text == "Hello World")
        #expect(partials[1].segments.count == 2)
        #expect(abs(partials[1].segments[0].timestamp - 0) < 0.0001)
        #expect(abs(partials[1].segments[1].timestamp - 0.5) < 0.0001)
        #expect(abs(result.duration - 0.75) < 0.0001)
        #expect(result.text == "Hello World")
        #expect(result.segments.count == 2)
        #expect(await service.state == .idle)
    }

    @Test("Concurrent start attempts serialize so only one stream enters active state")
    func concurrentStartsAreSerialized() async {
        let service = StreamingTranscriptionService(
            locale: Locale(identifier: "en-US"),
            testBackend: .init(recognizerAvailable: true)
        )

        var successCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let stream = AsyncStream<AudioChunk> { _ in }
                    do {
                        _ = try await service.startStreaming(audioChunkStream: stream)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    successCount += 1
                }
            }
        }

        _ = await service.stopStreaming()

        #expect(successCount == 1)
        #expect(await service.state == .idle)
    }

    @Test("Stopping closes the partial transcript stream and returns the latest accumulation")
    func stopFinishesPartialStream() async throws {
        let service = StreamingTranscriptionService(
            locale: Locale(identifier: "en-US"),
            testBackend: .init(recognizerAvailable: true)
        )
        let (audioStream, continuation) = makeAudioStream()
        let partialStream = try await service.startStreaming(audioChunkStream: audioStream)

        let collector = Task<[String], Never> {
            var texts: [String] = []
            for await partial in partialStream {
                texts.append(partial.text)
            }
            return texts
        }

        continuation.yield(makeChunk(timestamp: 0, duration: 0.25))
        await service.injectTestTranscript(
            sessionText: "Closing cadence",
            isFinal: true,
            segments: [
                TranscriptionService.TranscriptionSegment(
                    text: "Closing cadence",
                    timestamp: 0,
                    duration: 0.25,
                    confidence: 0.88
                )
            ]
        )

        let result = await service.stopStreaming()
        continuation.finish()
        let collected = await collector.value

        #expect(collected == ["Closing cadence"])
        #expect(result.text == "Closing cadence")
        #expect(abs(result.duration - 0.25) < 0.0001)
        #expect(await service.accumulatedText.isEmpty)
        #expect(await service.accumulatedSegments.isEmpty)
    }

    @Test("Stop from idle returns an empty transcription result")
    func stopFromIdleReturnsEmpty() async {
        let service = StreamingTranscriptionService(
            locale: Locale(identifier: "en-US"),
            testBackend: .init(recognizerAvailable: true)
        )

        let result = await service.stopStreaming()
        #expect(result.text.isEmpty)
        #expect(result.segments.isEmpty)
        #expect(result.duration == 0)
        #expect(await service.state == .idle)
    }

    private func makeAudioStream() -> (AsyncStream<AudioChunk>, AsyncStream<AudioChunk>.Continuation) {
        var capturedContinuation: AsyncStream<AudioChunk>.Continuation?
        let stream = AsyncStream<AudioChunk> { continuation in
            capturedContinuation = continuation
        }
        return (stream, capturedContinuation!)
    }

    private func makeChunk(timestamp: TimeInterval, duration: TimeInterval) -> AudioChunk {
        let sampleRate: Float = 4
        let frameCount = max(1, Int(duration * TimeInterval(sampleRate)))
        return AudioChunk(
            samples: [Float](repeating: 0.25, count: frameCount),
            sampleRate: sampleRate,
            frameCount: frameCount,
            timestamp: timestamp
        )
    }
}
#endif
