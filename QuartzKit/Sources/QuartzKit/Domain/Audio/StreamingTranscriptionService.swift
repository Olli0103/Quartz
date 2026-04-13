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
    private let backend: Backend

    // MARK: - Internal

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var partialContinuation: AsyncStream<PartialTranscript>.Continuation?
    private var consumeTask: Task<Void, Never>?
    private var sessionTimeOffset: TimeInterval = 0
    private var resumedPrefixText: String = ""
    private var resumedPrefixSegments: [TranscriptionService.TranscriptionSegment] = []

    internal enum Backend {
        case system(SFSpeechRecognizer?)
        case simulated(SimulatedBackend)
    }

    internal struct SimulatedBackend: Sendable {
        let recognizerAvailable: Bool

        internal init(recognizerAvailable: Bool = true) {
            self.recognizerAvailable = recognizerAvailable
        }
    }

    // MARK: - Init

    public init(locale: Locale = .current) {
        self.locale = locale
        self.backend = .system(SFSpeechRecognizer(locale: locale))
    }

    internal init(locale: Locale = .current, testBackend: SimulatedBackend) {
        self.locale = locale
        self.backend = .simulated(testBackend)
    }

    // MARK: - Public API

    /// Starts streaming transcription from an audio chunk stream.
    public func startStreaming(
        audioChunkStream: AsyncStream<AudioChunk>
    ) throws -> AsyncStream<PartialTranscript> {
        guard state == .idle else { throw StreamingError.recognizerUnavailable }
        guard isRecognizerAvailable else {
            throw StreamingError.recognizerUnavailable
        }

        state = .streaming
        accumulatedText = ""
        accumulatedSegments = []
        processedDuration = 0
        sessionTimeOffset = 0
        resumedPrefixText = ""
        resumedPrefixSegments = []

        let stream = AsyncStream<PartialTranscript> { continuation in
            self.partialContinuation = continuation
        }

        switch backend {
        case .system:
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            startRecognitionTask(request: request)
        case .simulated:
            request = nil
        }

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
        tearDownRecognitionSession()
        state = .paused
    }

    /// Resumes streaming after pause.
    public func resumeStreaming() throws {
        guard state == .paused else { return }
        guard isRecognizerAvailable else {
            throw StreamingError.recognizerUnavailable
        }

        sessionTimeOffset = processedDuration
        resumedPrefixText = accumulatedText
        resumedPrefixSegments = accumulatedSegments

        switch backend {
        case .system:
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            startRecognitionTask(request: request)
        case .simulated:
            break
        }
        state = .streaming
    }

    /// Stops streaming and returns the final transcription result.
    public func stopStreaming() -> TranscriptionService.TranscriptionResult {
        state = .finishing

        tearDownRecognitionSession()
        consumeTask?.cancel()
        consumeTask = nil
        partialContinuation?.finish()
        partialContinuation = nil
        resumedPrefixText = ""
        resumedPrefixSegments = []

        let result = TranscriptionService.TranscriptionResult(
            text: accumulatedText,
            segments: accumulatedSegments,
            locale: locale,
            duration: processedDuration
        )

        accumulatedText = ""
        accumulatedSegments = []
        processedDuration = 0
        sessionTimeOffset = 0
        resumedPrefixText = ""
        resumedPrefixSegments = []
        state = .idle
        return result
    }

    // MARK: - Private

    private var recognizer: SFSpeechRecognizer? {
        guard case .system(let recognizer) = backend else { return nil }
        return recognizer
    }

    private var isRecognizerAvailable: Bool {
        switch backend {
        case .system(let recognizer):
            return recognizer?.isAvailable ?? false
        case .simulated(let backend):
            return backend.recognizerAvailable
        }
    }

    private func tearDownRecognitionSession() {
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
    }

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
        let currentSessionSegments = segments.map { seg in
            TranscriptionService.TranscriptionSegment(
                text: seg.text,
                timestamp: seg.timestamp + sessionTimeOffset,
                duration: seg.duration,
                confidence: seg.confidence
            )
        }

        accumulatedSegments = resumedPrefixSegments + currentSessionSegments
        accumulatedText = combineSessionText(prefix: resumedPrefixText, currentSessionText: sessionText)

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

    private func combineSessionText(prefix: String, currentSessionText: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrent = currentSessionText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPrefix.isEmpty { return trimmedCurrent }
        if trimmedCurrent.isEmpty { return trimmedPrefix }
        return "\(trimmedPrefix) \(trimmedCurrent)"
    }

    private func handleRecognitionError(domain: String, code: Int, description: String) {
        // Recognition cancelled is expected during pause/stop
        if domain == "kAFAssistantErrorDomain" && code == 216 { return }
        // Other errors — report
    }

    private func processChunk(_ chunk: AudioChunk) {
        guard state == .streaming else { return }

        switch backend {
        case .system:
            guard let request else { return }

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
        case .simulated:
            processedDuration = max(processedDuration, sessionTimeOffset + chunk.timestamp + chunk.duration)
        }
    }

    internal func injectTestTranscript(
        sessionText: String,
        isFinal: Bool = false,
        segments: [TranscriptionService.TranscriptionSegment]
    ) {
        guard case .simulated = backend else { return }
        guard state == .streaming || state == .paused else { return }
        handleExtractedResult(sessionText: sessionText, isFinal: isFinal, segments: segments)
    }
}
#endif
