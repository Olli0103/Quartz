import Foundation
import AVFoundation

/// Service für In-App Audio-Aufnahmen.
///
/// Nimmt Audio via `AVAudioRecorder` auf und speichert als `.m4a` im Vault.
/// Bietet eine Wellenform-Visualisierung via Metering.
@Observable
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
            case .permissionDenied: "Microphone access denied. Please enable in Settings."
            case .sessionSetupFailed(let msg): "Audio session setup failed: \(msg)"
            case .recordingFailed(let msg): "Recording failed: \(msg)"
            case .noActiveRecording: "No active recording."
            }
        }
    }

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private let maxLevelHistory = 200

    public override init() {
        super.init()
    }

    // MARK: - Public API

    /// Prüft und fordert Mikrofon-Berechtigung an.
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "recording-\(formatter.string(from: Date())).m4a"

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
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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

        levelHistory.append(currentLevel)
        if levelHistory.count > maxLevelHistory {
            levelHistory.removeFirst()
        }
    }

    private func normalizeLevel(_ level: Float) -> Float {
        let minDB: Float = -60
        let clampedLevel = max(level, minDB)
        return (clampedLevel - minDB) / abs(minDB)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecordingService: AVAudioRecorderDelegate {
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            state = .idle
        }
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        state = .idle
    }
}
