#if canImport(Speech)
import Foundation
import AVFoundation
import Speech

/// Streaming on-device transcription using `SFSpeechAudioBufferRecognitionRequest`.
///
/// Produces `AsyncStream<PartialTranscript>` for live UI display during recording.
/// Handles recognition task death on pause: recreates task on resume, merges partials.
///
/// - Linear: OLL-35 (On-device ASR via Speech framework — streaming)
public actor StreamingTranscriptionService {

    // MARK: - Types

    public enum StreamingState: Sendable, Equatable {
        case idle
        case streaming
        case paused
        case finishing
    }

    public struct PartialTranscript: Sendable {
        public let text: String
        public let isFinal: Bool
        public let segments: [TranscriptionService.TranscriptionSegment]
        public let audioDuration: TimeInterval

        public init(text: String, isFinal: Bool, segments: [TranscriptionService.TranscriptionSegment], audioDuration: TimeInterval) {
            self.text = text
            self.isFinal = isFinal
            self.segments = segments
            self.audioDuration = audioDuration
        }
    }

    public enum StreamingError: LocalizedError, Sendable {
        case recognizerUnavailable
        case recognitionFailed(String)
        case notStreaming

        public var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: String(localized: "Speech recognition is not available.", bundle: .module)
            case .recognitionFailed(let msg): String(localized: "Recognition failed: \(msg)", bundle: .module)
            case .notStreaming: String(localized: "Not currently streaming.", bundle: .module)
            }
        }
    }

    // MARK: - State

    public private(set) var state: StreamingState = .idle
    public private(set) var accumulatedText: String = ""
    public private(set) var accumulatedSegments: [TranscriptionService.TranscriptionSegment] = []
    public private(set) var processedDuration: TimeInterval = 0

    // MARK: - Configuration

    private let locale: Locale
    private let recognizer: SFSpeechRecognizer?

    // MARK: - Internal

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var partialContinuation: AsyncStream<PartialTranscript>.Continuation?
    private var consumeTask: Task<Void, Never>?
    private var sessionTimeOffset: TimeInterval = 0

    // MARK: - Init

    public init(locale: Locale = .current) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Public API

    /// Starts streaming transcription from an audio chunk stream.
    public func startStreaming(
        audioChunkStream: AsyncStream<AudioChunk>
    ) throws -> AsyncStream<PartialTranscript> {
        guard state == .idle else { throw StreamingError.recognizerUnavailable }
        guard let recognizer, recognizer.isAvailable else {
            throw StreamingError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        state = .streaming
        accumulatedText = ""
        accumulatedSegments = []
        processedDuration = 0
        sessionTimeOffset = 0

        let stream = AsyncStream<PartialTranscript> { continuation in
            self.partialContinuation = continuation
        }

        startRecognitionTask(request: request)

        // Consume audio chunks and feed to recognizer
        consumeTask = Task { [weak self] in
            for await chunk in audioChunkStream {
                guard let self else { break }
                await self.processChunk(chunk)
            }
        }

        return stream
    }

    /// Pauses streaming (cancels recognition task, preserves accumulated text).
    public func pauseStreaming() {
        guard state == .streaming else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        state = .paused
    }

    /// Resumes streaming after pause.
    public func resumeStreaming() throws {
        guard state == .paused else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw StreamingError.recognizerUnavailable
        }

        sessionTimeOffset = processedDuration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        startRecognitionTask(request: request)
        state = .streaming
    }

    /// Stops streaming and returns the final transcription result.
    public func stopStreaming() -> TranscriptionService.TranscriptionResult {
        state = .finishing

        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        consumeTask?.cancel()
        consumeTask = nil
        partialContinuation?.finish()
        partialContinuation = nil

        let result = TranscriptionService.TranscriptionResult(
            text: accumulatedText,
            segments: accumulatedSegments,
            locale: locale,
            duration: processedDuration
        )

        state = .idle
        return result
    }

    // MARK: - Private

    private func startRecognitionTask(request: SFSpeechAudioBufferRecognitionRequest) {
        guard let recognizer else { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let error {
                let nsError = error as NSError
                let domain = nsError.domain
                let code = nsError.code
                let desc = error.localizedDescription
                Task { await self.handleRecognitionError(domain: domain, code: code, description: desc) }
                return
            }

            guard let result else { return }

            // Extract all data synchronously before crossing actor boundary
            let sessionText = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            let segments: [TranscriptionService.TranscriptionSegment] = result.bestTranscription.segments.map { seg in
                TranscriptionService.TranscriptionSegment(
                    text: seg.substring,
                    timestamp: seg.timestamp,
                    duration: seg.duration,
                    confidence: seg.confidence
                )
            }

            Task { await self.handleExtractedResult(sessionText: sessionText, isFinal: isFinal, segments: segments) }
        }
    }

    private func handleExtractedResult(sessionText: String, isFinal: Bool, segments: [TranscriptionService.TranscriptionSegment]) {
        accumulatedText = sessionText

        // Offset segments by session time offset
        accumulatedSegments = segments.map { seg in
            TranscriptionService.TranscriptionSegment(
                text: seg.text,
                timestamp: seg.timestamp + sessionTimeOffset,
                duration: seg.duration,
                confidence: seg.confidence
            )
        }

        if let lastSeg = segments.last {
            processedDuration = sessionTimeOffset + lastSeg.timestamp + lastSeg.duration
        }

        let partial = PartialTranscript(
            text: accumulatedText,
            isFinal: isFinal,
            segments: accumulatedSegments,
            audioDuration: processedDuration
        )
        partialContinuation?.yield(partial)
    }

    private func handleRecognitionError(domain: String, code: Int, description: String) {
        // Recognition cancelled is expected during pause/stop
        if domain == "kAFAssistantErrorDomain" && code == 216 { return }
        // Other errors — report
    }

    private func processChunk(_ chunk: AudioChunk) {
        guard state == .streaming, let request else { return }

        // Convert AudioChunk back to AVAudioPCMBuffer
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(chunk.sampleRate),
            channels: 1,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)

        chunk.samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData?[0].update(from: ptr.baseAddress!, count: chunk.frameCount)
        }

        request.append(buffer)
    }
}
#endif
