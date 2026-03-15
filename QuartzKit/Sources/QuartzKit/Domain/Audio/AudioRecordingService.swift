import Foundation
import AVFoundation

/// Service für In-App Audio-Aufnahmen.
///
/// Nimmt Audio via `AVAudioRecorder` auf und speichert als `.m4a` im Vault.
/// Bietet eine Wellenform-Visualisierung via Metering.
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
    public private(set) var levelHistory: [Float] = []

    /// URL der letzten Aufnahme.
    public private(set) var lastRecordingURL: URL?

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
    private let maxLevelHistory = 200

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    public override init() {
        super.init()
    }

    // MARK: - Public API

    /// Prüft und fordert Mikrofon-Berechtigung an.
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

    /// Startet eine neue Aufnahme.
    ///
    /// - Parameter vaultURL: Basis-URL des Vaults für die Speicherung
    /// - Returns: URL der Aufnahmedatei
    @discardableResult
    public func startRecording(vaultURL: URL) throws -> URL {
        // Audio Session konfigurieren
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw RecordingError.sessionSetupFailed(error.localizedDescription)
        }
        #endif

        // Dateiname generieren
        let fileName = "recording-\(Self.timestampFormatter.string(from: Date())).m4a"

        let recordingsDir = vaultURL.appending(path: "assets").appending(path: "recordings")
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileURL = recordingsDir.appending(path: fileName)

        // Recorder-Settings
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

        startTimers()

        return fileURL
    }

    /// Pausiert die laufende Aufnahme.
    public func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
        stopTimers()
    }

    /// Setzt eine pausierte Aufnahme fort.
    public func resume() {
        guard state == .paused else { return }
        recorder?.record()
        state = .recording
        startTimers()
    }

    /// Stoppt die Aufnahme.
    ///
    /// - Returns: URL der gespeicherten Aufnahmedatei
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

    /// Verwirft die aktuelle Aufnahme.
    public func discardRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        stopTimers()

        state = .idle
        duration = 0
        lastRecordingURL = nil
    }

    /// Formatierte Dauer als String (MM:SS).
    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Private

    private func startTimers() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.083, repeats: true) { [weak self] _ in
            self?.updateMetering()
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.duration += 1
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

        // Normalisieren: -160..0 dB → 0..1
        currentLevel = normalizeLevel(avgPower)
        peakLevel = normalizeLevel(peakPower)

        if levelHistory.count >= maxLevelHistory {
            levelHistory.replaceSubrange(0..<1, with: [])
        }
        levelHistory.append(currentLevel)
    }

    private func normalizeLevel(_ level: Float) -> Float {
        let minDB: Float = -60
        let clampedLevel = max(level, minDB)
        return (clampedLevel - minDB) / abs(minDB)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecordingService: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, !flag else { return }
            self.state = .idle
            self.lastRecordingURL = nil
            self.stopTimers()
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
