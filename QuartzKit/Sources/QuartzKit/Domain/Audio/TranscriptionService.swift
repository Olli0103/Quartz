import Foundation
import Speech
import AVFoundation

/// On-Device Transkription via `SFSpeechRecognizer`.
///
/// Transkribiert Audio-Aufnahmen (.m4a) in Text.
/// Unterstützt 60+ Sprachen mit On-Device-Erkennung.
public actor TranscriptionService {
    public enum TranscriptionError: LocalizedError, Sendable {
        case permissionDenied
        case recognizerUnavailable
        case recognitionFailed(String)
        case fileNotFound

        public var errorDescription: String? {
            switch self {
            case .permissionDenied: String(localized: "Speech recognition permission denied.", bundle: .module)
            case .recognizerUnavailable: String(localized: "Speech recognizer is not available for this language.", bundle: .module)
            case .recognitionFailed(let msg): String(localized: "Transcription failed: \(msg)", bundle: .module)
            case .fileNotFound: String(localized: "Audio file not found.", bundle: .module)
            }
        }
    }

    /// Ergebnis einer Transkription.
    public struct TranscriptionResult: Sendable {
        /// Der vollständige transkribierte Text.
        public let text: String
        /// Einzelne Segmente mit Zeitstempeln.
        public let segments: [TranscriptionSegment]
        /// Erkannte Sprache.
        public let locale: Locale
        /// Dauer der Audio-Datei.
        public let duration: TimeInterval

        public init(text: String, segments: [TranscriptionSegment], locale: Locale, duration: TimeInterval) {
            self.text = text
            self.segments = segments
            self.locale = locale
            self.duration = duration
        }
    }

    /// Ein transkribiertes Segment mit Zeitstempel.
    public struct TranscriptionSegment: Sendable {
        public let text: String
        public let timestamp: TimeInterval
        public let duration: TimeInterval
        public let confidence: Float

        public init(text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Float) {
            self.text = text
            self.timestamp = timestamp
            self.duration = duration
            self.confidence = confidence
        }
    }

    /// Bevorzugte Sprache für die Erkennung.
    private let locale: Locale

    public init(locale: Locale = Locale(identifier: "de-DE")) {
        self.locale = locale
    }

    // MARK: - Permissions

    /// Prüft und fordert Transkriptions-Berechtigung an.
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Prüft ob die Erkennung verfügbar ist.
    public var isAvailable: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable
    }

    // MARK: - Transcription

    /// Transkribiert eine Audio-Datei.
    ///
    /// - Parameter audioURL: Pfad zur Audio-Datei (.m4a, .wav, etc.)
    /// - Returns: TranscriptionResult mit Text und Segmenten
    public func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: audioURL.path()) else {
            throw TranscriptionError.fileNotFound
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Audio-Dauer ermitteln
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else { return }

                hasResumed = true

                let segments = result.bestTranscription.segments.map { segment in
                    TranscriptionSegment(
                        text: segment.substring,
                        timestamp: segment.timestamp,
                        duration: segment.duration,
                        confidence: segment.confidence
                    )
                }

                let transcription = TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    segments: segments,
                    locale: recognizer.locale,
                    duration: duration
                )

                continuation.resume(returning: transcription)
            }
        }
    }

    /// Transkribiert und speichert das Ergebnis als Markdown neben der Audio-Datei.
    public func transcribeAndSave(audioURL: URL) async throws -> TranscriptionResult {
        let result = try await transcribe(audioURL: audioURL)

        // Markdown-Datei erstellen
        let markdownURL = audioURL.deletingPathExtension().appendingPathExtension("md")
        let markdown = formatAsMarkdown(result, audioFileName: audioURL.lastPathComponent)

        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        return result
    }

    // MARK: - Private

    private func formatAsMarkdown(_ result: TranscriptionResult, audioFileName: String) -> String {
        let durationMinutes = Int(result.duration) / 60
        let durationSeconds = Int(result.duration) % 60

        var md = """
        ---
        type: transcription
        audio: \(audioFileName)
        duration: \(String(format: "%02d:%02d", durationMinutes, durationSeconds))
        language: \(result.locale.identifier)
        date: \(ISO8601DateFormatter().string(from: Date()))
        ---

        # Transcription

        \(result.text)

        """

        // Segmente mit Zeitstempeln
        if !result.segments.isEmpty {
            md += "\n## Timestamps\n\n"
            for segment in result.segments {
                let min = Int(segment.timestamp) / 60
                let sec = Int(segment.timestamp) % 60
                md += "- **[\(String(format: "%02d:%02d", min, sec))]** \(segment.text)\n"
            }
        }

        return md
    }
}
