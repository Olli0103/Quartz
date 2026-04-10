import Foundation

/// Saves transcription results as Markdown notes in the vault.
///
/// Creates notes in `Transcriptions/` directory with frontmatter metadata.
///
/// - Linear: OLL-38 (Transcript persistence as markdown)
public actor TranscriptPersistenceService {

    public enum PersistenceError: LocalizedError, Sendable {
        case encodingFailed
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed: String(localized: "Failed to encode transcription.", bundle: .module)
            case .writeFailed(let msg): String(localized: "Failed to write transcription: \(msg)", bundle: .module)
            }
        }
    }

    public init() {}

    /// Saves a transcription as a Markdown note.
    ///
    /// - Parameters:
    ///   - transcription: The transcription result
    ///   - diarization: Optional speaker diarization
    ///   - vaultURL: Base URL of the vault
    ///   - title: Optional title (auto-generated if nil)
    ///   - relatedNoteURL: Optional URL of the note being recorded from
    /// - Returns: URL of the saved note
    @discardableResult
    public func saveAsNote(
        transcription: TranscriptionService.TranscriptionResult,
        diarization: SpeakerDiarizationService.DiarizationResult? = nil,
        vaultURL: URL,
        title: String? = nil,
        relatedNoteURL: URL? = nil
    ) throws -> URL {
        let noteTitle = sanitizeTitle(title ?? generateTitle(from: transcription.text))

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let isoFormatter = ISO8601DateFormatter()
        let isoStr = isoFormatter.string(from: Date())

        let durationMin = Int(transcription.duration) / 60
        let durationSec = Int(transcription.duration) % 60

        // Build frontmatter
        var frontmatter = """
        ---
        type: transcription
        created: \(isoStr)
        duration: \(String(format: "%02d:%02d", durationMin, durationSec))
        language: \(transcription.locale.identifier)
        """

        if let diarization, !diarization.speakers.isEmpty {
            frontmatter += "\nspeakers:"
            for (_, label) in diarization.speakers.sorted(by: { $0.key < $1.key }) {
                frontmatter += "\n  - \(label)"
            }
        }

        if let relatedNoteURL {
            frontmatter += "\nrelated-note: \(relatedNoteURL.lastPathComponent)"
        }

        frontmatter += "\n---\n"

        // Build body
        var body = "# \(noteTitle)\n\n"

        if let diarization, !diarization.segments.isEmpty {
            // Diarized format
            for segment in diarization.segments {
                let min = Int(segment.startTime) / 60
                let sec = Int(segment.startTime) % 60
                let matchingText = transcription.segments
                    .filter { $0.timestamp >= segment.startTime && $0.timestamp < segment.endTime }
                    .map(\.text)
                    .joined(separator: " ")

                if !matchingText.isEmpty {
                    body += "**\(segment.speakerLabel)** [\(String(format: "%02d:%02d", min, sec))]: \(matchingText)\n\n"
                }
            }
        } else if !transcription.segments.isEmpty {
            // Timestamped format
            for segment in transcription.segments {
                let min = Int(segment.timestamp) / 60
                let sec = Int(segment.timestamp) % 60
                body += "[\(String(format: "%02d:%02d", min, sec))] \(segment.text)\n"
            }
        } else {
            // Plain text
            body += transcription.text
        }

        let markdown = frontmatter + "\n" + body

        // Write to file
        let transcriptionsDir = vaultURL.appending(path: "Transcriptions")
        let writer = CoordinatedFileWriter.shared
        try writer.createDirectory(at: transcriptionsDir)

        let fileName = "\(dateStr) \(noteTitle).md"
        let fileURL = transcriptionsDir.appending(path: fileName)

        guard let data = markdown.data(using: .utf8) else {
            throw PersistenceError.encodingFailed
        }

        try writer.write(data, to: fileURL)
        return fileURL
    }

    // MARK: - Private

    private func generateTitle(from text: String) -> String {
        let words = text.prefix(200).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.isEmpty { return "Transcription" }
        let preview = words.prefix(5).joined(separator: " ")
        return preview
    }

    private func sanitizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
