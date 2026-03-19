import Foundation
import Speech
import AVFoundation
import os

/// On-device transcription via `SFSpeechRecognizer`.
///
/// Transcribes audio recordings (.m4a) to text.
/// Supports 60+ languages with on-device recognition.
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

    /// Result of a transcription.
    public struct TranscriptionResult: Sendable {
        /// The complete transcribed text.
        public let text: String
        /// Individual segments with timestamps.
        public let segments: [TranscriptionSegment]
        /// Recognized language.
        public let locale: Locale
        /// Duration of the audio file.
        public let duration: TimeInterval

        public init(text: String, segments: [TranscriptionSegment], locale: Locale, duration: TimeInterval) {
            self.text = text
            self.segments = segments
            self.locale = locale
            self.duration = duration
        }
    }

    /// A transcribed segment with timestamp.
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

    /// Preferred language for recognition. Uses device locale for automatic language (user's primary language).
    private let locale: Locale

    /// Uses device locale by default so transcription follows the user's primary language.
    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: - Permissions

    /// Checks and requests transcription permission.
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Checks whether recognition is available.
    public var isAvailable: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable
    }

    // MARK: - Transcription

    /// Transcribes an audio file.
    ///
    /// - Parameter audioURL: Path to the audio file (.m4a, .wav, etc.)
    /// - Returns: TranscriptionResult with text and segments
    public func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        let path = audioURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw TranscriptionError.fileNotFound
        }

        // Copy to temp when in cloud/sandboxed paths – Speech framework often fails to read those directly.
        let workingURL: URL
        if needsTempCopy(audioURL) {
            let tempDir = FileManager.default.temporaryDirectory
            let tempName = "transcribe-\(UUID().uuidString).m4a"
            let tempURL = tempDir.appending(path: tempName)
            do {
                try FileManager.default.copyItem(at: audioURL, to: tempURL)
            } catch {
                throw TranscriptionError.fileNotFound
            }
            defer { try? FileManager.default.removeItem(at: tempURL) }
            workingURL = tempURL
        } else {
            workingURL = audioURL
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Determine audio duration
        let asset = AVURLAsset(url: workingURL)
        let duration = try await asset.load(.duration).seconds

        let request = SFSpeechURLRecognitionRequest(url: workingURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            let didResume = OSAllocatedUnfairLock(initialState: false)

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let alreadyResumed = didResume.withLock { resumed -> Bool in
                        if resumed { return true }
                        resumed = true
                        return false
                    }
                    guard !alreadyResumed else { return }
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else { return }

                let alreadyResumed = didResume.withLock { resumed -> Bool in
                    if resumed { return true }
                    resumed = true
                    return false
                }
                guard !alreadyResumed else { return }

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

    /// Transcribes and saves the result as Markdown next to the audio file.
    public func transcribeAndSave(audioURL: URL) async throws -> TranscriptionResult {
        let result = try await transcribe(audioURL: audioURL)

        // Create Markdown file
        let markdownURL = audioURL.deletingPathExtension().appendingPathExtension("md")
        let markdown = formatAsMarkdown(result, audioFileName: audioURL.lastPathComponent)

        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: markdownURL, options: .forReplacing, error: &coordinatorError) { actualURL in
            do {
                try markdown.write(to: actualURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let error = coordinatorError ?? writeError { throw error }

        return result
    }

    // MARK: - Private

    /// Copy to temp when file is in cloud-synced or security-scoped location (Speech framework can fail there).
    private func needsTempCopy(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.contains("/Library/CloudStorage/") || path.contains("/iCloud.")
    }

    /// Thread-safe ISO 8601 formatting. Creates a new formatter per call
    /// since `ISO8601DateFormatter` is not thread-safe.
    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func formatAsMarkdown(_ result: TranscriptionResult, audioFileName: String) -> String {
        let durationMinutes = Int(result.duration) / 60
        let durationSeconds = Int(result.duration) % 60

        var md = """
        ---
        type: transcription
        audio: \(audioFileName)
        duration: \(String(format: "%02d:%02d", durationMinutes, durationSeconds))
        language: \(result.locale.identifier)
        date: \(Self.iso8601String(from: Date()))
        ---

        # Transcription

        \(result.text)

        """

        // Segments with timestamps
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
