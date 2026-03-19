import Foundation

// MARK: - Meeting Minutes Templates

/// Predefined templates for meeting minutes with different structures and system instructions.
public enum MeetingMinutesTemplate: String, CaseIterable, Identifiable, Sendable {
    case standard = "standard"
    case executive = "executive"
    case technical = "technical"
    case actionFocused = "actionFocused"
    case oneOnOne = "oneOnOne"
    case engineeringSync = "engineeringSync"
    case clientPitch = "clientPitch"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: String(localized: "Standard", bundle: .module)
        case .executive: String(localized: "Executive Summary", bundle: .module)
        case .technical: String(localized: "Technical", bundle: .module)
        case .actionFocused: String(localized: "Action-Focused", bundle: .module)
        case .oneOnOne: String(localized: "1:1", bundle: .module)
        case .engineeringSync: String(localized: "Engineering Sync", bundle: .module)
        case .clientPitch: String(localized: "Client Pitch", bundle: .module)
        case .custom: String(localized: "Custom", bundle: .module)
        }
    }

    public var systemPrompt: String {
        switch self {
        case .standard:
            """
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
        case .executive:
            """
            You are an executive assistant. Create a concise executive summary from this meeting transcript.

            Respond with ONLY:
            ## Executive Summary
            One paragraph (3-5 sentences) capturing the essence of the meeting: key outcomes, decisions, and next steps.

            ## Key Takeaways
            - 3-5 bullet points for leadership

            ## Critical Action Items
            - [ ] Only the most important action items with owners and deadlines (if mentioned)

            Important:
            - Respond in the same language as the transcript.
            - Focus on business impact and strategic relevance.
            - Omit operational details.
            """
        case .technical:
            """
            You are a technical documentation specialist. Create structured technical meeting notes from this transcript.

            Respond with ONLY:
            ## Overview
            Brief technical context of the meeting.

            ## Technical Decisions
            - Architecture, tooling, or implementation decisions made

            ## Discussion Points
            - Technical topics discussed with relevant details

            ## Action Items
            - [ ] Technical tasks with owners (if mentioned)

            ## Blockers & Dependencies
            - Any blockers or dependencies identified

            Important:
            - Respond in the same language as the transcript.
            - Preserve technical terminology accurately.
            - Include code names, versions, or specs if mentioned.
            """
        case .actionFocused:
            """
            You are a project management assistant. Create action-focused meeting notes from this transcript.

            Respond with ONLY:
            ## Summary (1-2 sentences)
            What was decided and what happens next.

            ## Action Items
            - [ ] Action with owner and deadline (if mentioned). Use "TBD" if not specified.

            ## Decisions Made
            - Bullet list of decisions

            ## Follow-up Required
            - Items needing more discussion or input

            Important:
            - Respond in the same language as the transcript.
            - Every action item must be clear and actionable.
            - Prioritize by impact if possible.
            """
        case .oneOnOne:
            """
            You are a 1:1 meeting assistant. Create concise, personal notes from this one-on-one conversation.

            Respond with ONLY:
            ## Summary
            A brief 2-3 sentence overview of the conversation.

            ## Topics Discussed
            - Key topics covered (career, feedback, blockers, goals, etc.)

            ## Action Items
            - [ ] Commitments made by either party with owner (if mentioned)

            ## Follow-up
            - Any scheduled follow-ups or topics to revisit

            Important:
            - Respond in the same language as the transcript.
            - Keep tone professional but personal. Preserve confidentiality.
            - Focus on outcomes and commitments, not verbatim quotes.
            """
        case .engineeringSync:
            """
            You are an engineering standup/sync meeting assistant. Create structured technical notes from this transcript.

            Respond with ONLY:
            ## Overview
            Brief context: sprint, project, or team focus.

            ## Updates by Person/Topic
            - What was shared (blockers, progress, plans)

            ## Blockers & Dependencies
            - Technical blockers, waiting on, or blocked by

            ## Action Items
            - [ ] Technical tasks with owners (if mentioned)

            ## Decisions
            - Architecture, tooling, or process decisions made

            Important:
            - Respond in the same language as the transcript.
            - Preserve technical terms, ticket IDs, and system names.
            - Be concise; standups are time-boxed.
            """
        case .clientPitch:
            """
            You are a client-facing meeting assistant. Create polished meeting notes suitable for client sharing.

            Respond with ONLY:
            ## Executive Summary
            One paragraph capturing the meeting purpose and key outcomes.

            ## Discussion Points
            - Main topics discussed with client

            ## Decisions & Agreements
            - Commitments, approvals, or agreements reached

            ## Next Steps
            - [ ] Clear action items with owners and deadlines (if mentioned)

            ## Open Items
            - Questions or topics to be resolved later

            Important:
            - Respond in the same language as the transcript.
            - Use professional, client-ready language.
            - Emphasize clarity and accountability for follow-ups.
            """
        case .custom:
            ""
        }
    }
}

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
    ///   - template: Template for minutes structure (default: standard)
    ///   - customPrompt: Custom system prompt when template is .custom
    ///   - meetingTitle: Optional title of the meeting
    ///   - participants: Optional list of participants
    /// - Returns: MeetingMinutes with structured Markdown
    public func generateMinutes(
        from audioURL: URL,
        template: MeetingMinutesTemplate = .standard,
        customPrompt: String? = nil,
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
        let systemPrompt: String
        switch template {
        case .custom:
            systemPrompt = customPrompt ?? MeetingMinutesTemplate.standard.systemPrompt
        default:
            systemPrompt = template.systemPrompt
        }

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

    /// Saves meeting minutes as a Markdown note.
    public func saveAsNote(
        _ minutes: MeetingMinutes,
        vaultURL: URL
    ) throws -> URL {
        let markdown = minutes.toMarkdown()

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: minutes.date)

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

    /// Generates the Markdown representation of the meeting minutes.
    public func toMarkdown() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: date)

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
