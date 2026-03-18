import Foundation

/// AI pipeline: Transcription → Summarization → Structured Meeting Minutes.
///
/// Automatically generates meeting minutes with action items as Markdown.
public actor MeetingMinutesService {
    private let transcriptionService: TranscriptionService
    private let providerRegistry: AIProviderRegistry

    public init(
        transcriptionService: TranscriptionService = TranscriptionService(),
        providerRegistry: AIProviderRegistry
    ) {
        self.transcriptionService = transcriptionService
        self.providerRegistry = providerRegistry
    }

    /// Generates meeting minutes from an audio recording.
    ///
    /// Pipeline: Audio → Transcription → AI summarization → Markdown
    ///
    /// - Parameters:
    ///   - audioURL: Path to the audio file
    ///   - meetingTitle: Optional title of the meeting
    ///   - participants: Optional list of participants
    /// - Returns: MeetingMinutes with structured Markdown
    public func generateMinutes(
        from audioURL: URL,
        meetingTitle: String? = nil,
        participants: [String] = []
    ) async throws -> MeetingMinutes {
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider else {
            throw MeetingMinutesError.noProviderConfigured
        }

        // 1. Transcription
        let transcription = try await transcriptionService.transcribe(audioURL: audioURL)

        // 2. AI summarization
        let systemPrompt = """
        You are a meeting minutes assistant. Analyze the following transcript and create structured meeting minutes.

        Respond with ONLY the following sections in Markdown format:
        ## Summary
        A brief 2-3 sentence summary of the meeting.

        ## Key Discussion Points
        - Bullet points of main topics discussed

        ## Decisions Made
        - Bullet points of decisions (if any)

        ## Action Items
        - [ ] Action item with responsible person (if mentioned)

        ## Open Questions
        - Questions that were raised but not resolved (if any)

        Important:
        - Respond in the same language as the transcript.
        - Be concise and factual.
        - If no decisions or action items are clear, omit those sections.
        """

        let messages: [AIMessage] = [
            AIMessage(role: .system, content: systemPrompt),
            AIMessage(role: .user, content: "Here is the meeting transcript:\n\n\(transcription.text)")
        ]

        let response = try await provider.chat(
            messages: messages,
            model: modelID,
            temperature: 0.3
        )

        // 3. Structure meeting minutes
        let minutes = MeetingMinutes(
            title: meetingTitle ?? generateTitle(from: transcription.text),
            date: Date(),
            duration: transcription.duration,
            participants: participants,
            transcript: transcription,
            aiSummary: response.content,
            audioURL: audioURL
        )

        return minutes
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Saves meeting minutes as a Markdown note.
    public func saveAsNote(
        _ minutes: MeetingMinutes,
        vaultURL: URL
    ) throws -> URL {
        let markdown = minutes.toMarkdown()

        let dateStr = Self.dateOnlyFormatter.string(from: minutes.date)

        let sanitizedTitle = minutes.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let fileName = "\(dateStr) \(sanitizedTitle).md"
        let meetingsDir = vaultURL.appending(path: "Meetings")
        let writer = CoordinatedFileWriter.shared
        try writer.createDirectory(at: meetingsDir)

        let fileURL = meetingsDir.appending(path: fileName)
        guard let data = markdown.data(using: .utf8) else {
            throw MeetingMinutesError.summarizationFailed("Failed to encode markdown")
        }
        try writer.write(data, to: fileURL)

        return fileURL
    }

    // MARK: - Private

    private func generateTitle(from text: String) -> String {
        let words = text.prefix(200).components(separatedBy: .whitespacesAndNewlines)
        let preview = words.prefix(5).joined(separator: " ")
        return String(localized: "Meeting – \(preview)...", bundle: .module)
    }
}

// MARK: - Meeting Minutes Model

/// Structured meeting minutes.
public struct MeetingMinutes: Sendable {
    public let title: String
    public let date: Date
    public let duration: TimeInterval
    public let participants: [String]
    public let transcript: TranscriptionService.TranscriptionResult
    public let aiSummary: String
    public let audioURL: URL

    public init(
        title: String,
        date: Date,
        duration: TimeInterval,
        participants: [String],
        transcript: TranscriptionService.TranscriptionResult,
        aiSummary: String,
        audioURL: URL
    ) {
        self.title = title
        self.date = date
        self.duration = duration
        self.participants = participants
        self.transcript = transcript
        self.aiSummary = aiSummary
        self.audioURL = audioURL
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// Generates the Markdown representation of the meeting minutes.
    public func toMarkdown() -> String {
        let dateStr = Self.dateTimeFormatter.string(from: date)

        let durationMin = Int(duration) / 60
        let durationSec = Int(duration) % 60

        var md = """
        ---
        type: meeting-minutes
        date: \(dateStr)
        duration: \(String(format: "%02d:%02d", durationMin, durationSec))
        audio: \(audioURL.lastPathComponent)
        """

        if !participants.isEmpty {
            md += "\nparticipants:\n"
            for p in participants {
                md += "  - \(p)\n"
            }
        }

        md += """
        ---

        # \(title)

        **Date:** \(dateStr)
        **Duration:** \(String(format: "%02d:%02d", durationMin, durationSec))
        """

        if !participants.isEmpty {
            md += "\n**Participants:** \(participants.joined(separator: ", "))\n"
        }

        md += "\n\(aiSummary)\n"

        md += """

        ---

        ## Full Transcript

        \(transcript.text)
        """

        return md
    }
}

// MARK: - Errors

public enum MeetingMinutesError: LocalizedError, Sendable {
    case noProviderConfigured
    case transcriptionFailed(String)
    case summarizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noProviderConfigured: String(localized: "No AI provider configured for meeting summarization.", bundle: .module)
        case .transcriptionFailed(let msg): String(localized: "Transcription failed: \(msg)", bundle: .module)
        case .summarizationFailed(let msg): String(localized: "Summarization failed: \(msg)", bundle: .module)
        }
    }
}
