import Foundation
import AVFoundation
import Accelerate

/// Capture service using `AVAudioEngine` for streaming audio.
///
/// Provides dual output: `.m4a` file archival + `AsyncStream<AudioChunk>` for
/// real-time consumers (streaming transcription, live metering).
///
/// Uses a tap on the input node to capture 500ms PCM chunks at 44.1kHz mono.
///
/// - Linear: OLL-34 (AVAudioEngine capture graph with ring-buffer chunking)
public actor AVAudioEngineCaptureService {

    // MARK: - Types

    public enum CaptureState: Sendable, Equatable {
        case idle
        case preparing
        case capturing
        case paused
        case stopping
    }

    public enum CaptureError: LocalizedError, Sendable {
        case engineSetupFailed(String)
        case noActiveCapture
        case alreadyCapturing

        public var errorDescription: String? {
            switch self {
            case .engineSetupFailed(let msg): String(localized: "Audio engine setup failed: \(msg)", bundle: .module)
            case .noActiveCapture: String(localized: "No active capture session.", bundle: .module)
            case .alreadyCapturing: String(localized: "Already capturing audio.", bundle: .module)
            }
        }
    }

    /// Audio interruption event for UI notification.
    public enum InterruptionEvent: Sendable {
        case began
        case endedWithResume
        case endedWithoutResume
        case routeChange(reason: String)
    }

    // MARK: - Configuration

    public let chunkDuration: TimeInterval
    public let sampleRate: Double
    public let channelCount: UInt32

    // MARK: - State

    public private(set) var state: CaptureState = .idle
    public private(set) var outputURL: URL?
    public private(set) var capturedDuration: TimeInterval = 0

    // MARK: - Streams

    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var meteringContinuation: AsyncStream<Float>.Continuation?
    private var interruptionContinuation: AsyncStream<InterruptionEvent>.Continuation?

    // MARK: - Internal

    private let ringBuffer: AudioChunkRingBuffer
    private var engine: AVAudioEngine?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // MARK: - Init

    public init(
        chunkDuration: TimeInterval = 0.5,
        sampleRate: Double = 44100,
        channelCount: UInt32 = 1
    ) {
        self.chunkDuration = chunkDuration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.ringBuffer = AudioChunkRingBuffer(
            capacity: Int(60.0 / chunkDuration),  // 60s of buffered chunks
            chunkDuration: chunkDuration
        )
    }

    // MARK: - Stream Factories

    /// Creates an async stream of audio chunks for real-time consumers.
    public func makeAudioChunkStream() -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            self.chunkContinuation = continuation
        }
    }

    /// Creates an async stream of metering levels.
    public func makeMeteringStream() -> AsyncStream<Float> {
        AsyncStream { continuation in
            self.meteringContinuation = continuation
        }
    }

    /// Creates an async stream of interruption events.
    public func makeInterruptionStream() -> AsyncStream<InterruptionEvent> {
        AsyncStream { continuation in
            self.interruptionContinuation = continuation
        }
    }

    // MARK: - Capture Control

    /// Starts audio capture, writing to the given URL.
    public func startCapture(outputURL: URL) async throws {
        guard state == .idle else { throw CaptureError.alreadyCapturing }

        state = .preparing
        self.outputURL = outputURL
        capturedDuration = 0

        do {
            let engine = AVAudioEngine()
            self.engine = engine

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Create output file
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 128_000,
            ]
            let tapFileWriter = try AVAudioFile(forWriting: outputURL, settings: settings)

            // Install tap for PCM chunk capture
            let bufferSize = AVAudioFrameCount(chunkDuration * inputFormat.sampleRate)
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self, tapFileWriter] buffer, when in
                guard let self else { return }

                // Write to file
                try? tapFileWriter.write(from: buffer)

                // Extract samples for chunk
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

                let chunk = AudioChunk(
                    samples: samples,
                    sampleRate: Float(inputFormat.sampleRate),
                    frameCount: frameCount,
                    timestamp: Double(when.sampleTime) / inputFormat.sampleRate
                )

                // Compute RMS for metering
                var rms: Float = 0
                vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

                Task {
                    await self.handleChunk(chunk, rmsLevel: rms)
                }
            }

            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            #endif

            try engine.start()

            setupInterruptionHandling()
            state = .capturing
        } catch {
            state = .idle
            self.outputURL = nil
            throw CaptureError.engineSetupFailed(error.localizedDescription)
        }
    }

    /// Pauses capture (keeps engine running, stops writing).
    public func pauseCapture() {
        guard state == .capturing else { return }
        engine?.pause()
        state = .paused
    }

    /// Resumes capture after pause.
    public func resumeCapture() throws {
        guard state == .paused else { return }
        try engine?.start()
        state = .capturing
    }

    /// Stops capture and tears down the engine.
    public func stopCapture() throws -> URL {
        guard state == .capturing || state == .paused else {
            throw CaptureError.noActiveCapture
        }

        state = .stopping

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        removeInterruptionHandling()
        chunkContinuation?.finish()
        meteringContinuation?.finish()
        interruptionContinuation?.finish()

        state = .idle

        guard let url = outputURL else {
            throw CaptureError.noActiveCapture
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        return url
    }

    /// Returns recent metering samples for waveform display.
    public func recentMeteringSamples(_ count: Int) async -> [AudioChunk] {
        await ringBuffer.recent(count)
    }

    // MARK: - Private

    private func handleChunk(_ chunk: AudioChunk, rmsLevel: Float) async {
        await ringBuffer.append(chunk)
        capturedDuration += chunk.duration
        chunkContinuation?.yield(chunk)
        meteringContinuation?.yield(rmsLevel)
    }

    private func setupInterruptionHandling() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard let typeValue else { return }
            Task { await self.handleInterruption(typeValue: typeValue, optionsValue: optionsValue) }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let reasonValue = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            Task { await self.handleRouteChange(reasonValue: reasonValue) }
        }
        #endif
    }

    private func removeInterruptionHandling() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleInterruption(typeValue: UInt, optionsValue: UInt) {
        #if os(iOS)
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            pauseCapture()
            interruptionContinuation?.yield(.began)
        case .ended:
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            if shouldResume {
                try? resumeCapture()
                interruptionContinuation?.yield(.endedWithResume)
            } else {
                interruptionContinuation?.yield(.endedWithoutResume)
            }
        @unknown default:
            break
        }
        #endif
    }

    private func handleRouteChange(reasonValue: UInt) {
        #if os(iOS)
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            pauseCapture()
            interruptionContinuation?.yield(.routeChange(reason: "Audio device disconnected"))
        default:
            break
        }
        #endif
    }
}
