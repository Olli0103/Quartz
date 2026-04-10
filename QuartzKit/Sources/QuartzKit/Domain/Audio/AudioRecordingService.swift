import Foundation
import AVFoundation

/// Service for in-app audio recordings.
///
/// Records audio via `AVAudioRecorder` and saves as `.m4a` in the vault.
/// Provides waveform visualization via metering.
///
/// **Per CODEX.md F8:** Uses `AudioMeteringProcessor` for background metering
/// with throttled UI updates to avoid main thread contention during recording.
@Observable
@MainActor
public final class AudioRecordingService: NSObject {
    // MARK: - State

    public enum RecordingState {
        case idle
        case recording
        case paused
    }

    public private(set) var state: RecordingState = .idle

    /// Backwards-compatible convenience accessor.
    public var isRecording: Bool { state == .recording || state == .paused }

    /// Backwards-compatible convenience accessor.
    public var isPaused: Bool { state == .paused }
    public private(set) var duration: TimeInterval = 0
    public private(set) var currentLevel: Float = 0
    public private(set) var peakLevel: Float = 0

    /// Recent level history for waveform visualization.
    /// Updated from the background metering processor.
    public private(set) var levelHistory: [Float] = []

    /// URL of the last recording.
    public private(set) var lastRecordingURL: URL?

    /// Callback for interruption events (phone call, Siri, route change).
    public var onInterruption: ((AVAudioEngineCaptureService.InterruptionEvent) -> Void)?

    public enum RecordingError: LocalizedError, Sendable {
        case permissionDenied
        case sessionSetupFailed(String)
        case recordingFailed(String)
        case noActiveRecording

        public var errorDescription: String? {
            switch self {
            case .permissionDenied: String(localized: "Microphone access denied. Please enable in Settings.", bundle: .module)
            case .sessionSetupFailed(let msg): String(localized: "Audio session setup failed: \(msg)", bundle: .module)
            case .recordingFailed(let msg): String(localized: "Recording failed: \(msg)", bundle: .module)
            case .noActiveRecording: String(localized: "No active recording.", bundle: .module)
            }
        }
    }

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?

    /// Background metering processor for off-main-thread processing.
    /// **Per CODEX.md F8:** Reduces main thread contention during recording.
    private let meteringProcessor = AudioMeteringProcessor(
        bufferCapacity: 1000,
        uiUpdateInterval: 1.0 / 30.0  // 30Hz UI updates
    )

    /// Number of recent samples to display in waveform.
    private let waveformSampleCount = 200

    private static func formattedTimestamp(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    public override init() {
        super.init()
    }

    // MARK: - Public API

    /// Checks and requests microphone permission.
    public func requestPermission() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #elseif os(macOS)
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return false
        #endif
    }

    /// Starts a new recording.
    ///
    /// - Parameter vaultURL: Base URL of the vault for storage
    /// - Returns: URL of the recording file
    @discardableResult
    public func startRecording(vaultURL: URL) throws -> URL {
        // Configure audio session
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw RecordingError.sessionSetupFailed(error.localizedDescription)
        }
        #endif

        // Generate file name
        let fileName = "recording-\(Self.formattedTimestamp(from: Date())).m4a"

        let recordingsDir = vaultURL.appending(path: "assets").appending(path: "recordings")
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileURL = recordingsDir.appending(path: fileName)

        // Recorder settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000,
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.delegate = self
            recorder?.record()
        } catch {
            throw RecordingError.recordingFailed(error.localizedDescription)
        }

        state = .recording
        duration = 0
        levelHistory = []
        lastRecordingURL = fileURL

        // Reset the metering processor for new session
        Task {
            await meteringProcessor.reset()
        }

        startTimers()

        return fileURL
    }

    /// Pauses the current recording.
    public func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
        stopTimers()
    }

    /// Resumes a paused recording.
    public func resume() {
        guard state == .paused else { return }
        recorder?.record()
        state = .recording
        startTimers()
    }

    /// Stops the recording.
    ///
    /// - Returns: URL of the saved recording file
    @discardableResult
    public func stopRecording() throws -> URL {
        guard let recorder, state != .idle else {
            throw RecordingError.noActiveRecording
        }

        recorder.stop()
        stopTimers()

        state = .idle

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)
        #endif

        guard let url = lastRecordingURL else {
            throw RecordingError.noActiveRecording
        }

        return url
    }

    /// Discards the current recording.
    public func discardRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        stopTimers()

        state = .idle
        duration = 0
        lastRecordingURL = nil
    }

    /// Formatted duration as string (MM:SS), locale-aware.
    /// Created per-call because DateComponentsFormatter is not Sendable.
    public var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }

    /// Returns session statistics from the metering processor.
    public func sessionStats() async -> (totalSamples: Int, peakLevel: Float, avgLevel: Float) {
        await meteringProcessor.sessionStats()
    }

    // MARK: - Private

    private func startTimers() {
        // Metering timer fires at ~12Hz, but UI updates are throttled by processor
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.083, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMetering()
            }
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.duration += 1
            }
        }
    }

    private func stopTimers() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateMetering() {
        recorder?.updateMeters()
        let avgPower = recorder?.averagePower(forChannel: 0) ?? -160
        let peakPower = recorder?.peakPower(forChannel: 0) ?? -160

        // Process sample in background, receive throttled UI updates
        Task {
            await meteringProcessor.processSample(
                averagePower: avgPower,
                peakPower: peakPower
            ) { [weak self] normalizedAvg, normalizedPeak in
                // This closure runs on MainActor at throttled rate (30Hz)
                self?.currentLevel = normalizedAvg
                self?.peakLevel = normalizedPeak
            }

            // Update waveform from ring buffer (also throttled via actor)
            let samples = await meteringProcessor.recentSamples(self.waveformSampleCount)
            await MainActor.run { [weak self] in
                self?.levelHistory = samples
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecordingService: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !flag {
                // Recording failed — clear state
                self.state = .idle
                self.lastRecordingURL = nil
                self.stopTimers()
            }
        }
    }

    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .idle
            self.lastRecordingURL = nil
            self.stopTimers()
        }
    }
}
