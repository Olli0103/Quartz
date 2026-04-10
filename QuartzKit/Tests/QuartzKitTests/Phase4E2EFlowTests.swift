import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4E2EFlow")
struct Phase4E2EFlowTests {

    // MARK: - MeetingMinutesTemplate

    @Test("All MeetingMinutesTemplate cases have non-empty displayName")
    func templateDisplayNames() {
        for template in MeetingMinutesTemplate.allCases {
            #expect(!template.displayName.isEmpty, "\(template.rawValue) should have a display name")
        }
    }

    @Test("All MeetingMinutesTemplate cases have unique raw values")
    func templateUniqueRawValues() {
        let rawValues = MeetingMinutesTemplate.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }

    @Test("All non-custom templates have non-empty system prompts")
    func templateSystemPrompts() {
        for template in MeetingMinutesTemplate.allCases where template != .custom {
            #expect(!template.systemPrompt.isEmpty, "\(template.rawValue) should have a system prompt")
        }
    }

    @Test("Custom template has empty system prompt")
    func customTemplateEmptyPrompt() {
        #expect(MeetingMinutesTemplate.custom.systemPrompt.isEmpty)
    }

    @Test("Template IDs match raw values")
    func templateIDsMatchRaw() {
        for template in MeetingMinutesTemplate.allCases {
            #expect(template.id == template.rawValue)
        }
    }

    // MARK: - MeetingMinutes Model

    @Test("MeetingMinutes toMarkdown contains title")
    func meetingMinutesToMarkdownContainsTitle() {
        let minutes = makeMockMinutes(title: "Sprint Planning", participants: ["Alice", "Bob"])
        let md = minutes.toMarkdown()
        #expect(md.contains("# Sprint Planning"))
    }

    @Test("MeetingMinutes toMarkdown contains participants when provided")
    func meetingMinutesToMarkdownWithParticipants() {
        let minutes = makeMockMinutes(title: "Test", participants: ["Alice", "Bob"])
        let md = minutes.toMarkdown()
        #expect(md.contains("Participants:"))
        #expect(md.contains("Alice"))
        #expect(md.contains("Bob"))
    }

    @Test("MeetingMinutes toMarkdown omits participants when empty")
    func meetingMinutesToMarkdownNoParticipants() {
        let minutes = makeMockMinutes(title: "Solo Meeting", participants: [])
        let md = minutes.toMarkdown()
        #expect(!md.contains("Participants:"))
    }

    @Test("MeetingMinutes toMarkdown formats duration correctly")
    func meetingMinutesDurationFormatting() {
        let minutes = makeMockMinutes(title: "Test", duration: 90, participants: [])
        let md = minutes.toMarkdown()
        #expect(md.contains("01:30"))
    }

    @Test("MeetingMinutes toMarkdown includes frontmatter")
    func meetingMinutesFrontmatter() {
        let minutes = makeMockMinutes(title: "Test", participants: [])
        let md = minutes.toMarkdown()
        #expect(md.contains("---"))
        #expect(md.contains("type: meeting-minutes"))
    }

    @Test("MeetingMinutes toMarkdown includes AI summary")
    func meetingMinutesIncludesSummary() {
        let minutes = makeMockMinutes(title: "Test", participants: [], aiSummary: "This was a productive meeting.")
        let md = minutes.toMarkdown()
        #expect(md.contains("This was a productive meeting."))
    }

    @Test("MeetingMinutes toMarkdown includes full transcript section")
    func meetingMinutesIncludesTranscript() {
        let minutes = makeMockMinutes(title: "Test", participants: [])
        let md = minutes.toMarkdown()
        #expect(md.contains("Full Transcript"))
    }

    // MARK: - MeetingMinutesError

    @Test("MeetingMinutesError.noProviderConfigured has description")
    func noProviderConfiguredDescription() {
        let error = MeetingMinutesError.noProviderConfigured
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("MeetingMinutesError.transcriptionFailed has description with message")
    func transcriptionFailedDescription() {
        let error = MeetingMinutesError.transcriptionFailed("timeout")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("timeout"))
    }

    @Test("MeetingMinutesError.summarizationFailed has description with message")
    func summarizationFailedDescription() {
        let error = MeetingMinutesError.summarizationFailed("rate limit")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("rate limit"))
    }

    // MARK: - MeetingMinutesService saveAsNote

    @Test("MeetingMinutesService saveAsNote writes file to vault")
    @MainActor
    func meetingMinutesSaveAsNote() async throws {
        let registry = AIProviderRegistry()
        let service = MeetingMinutesService(providerRegistry: registry)
        let minutes = makeMockMinutes(title: "Test Save", participants: ["Alice"])

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "MeetingMinutesTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = try await service.saveAsNote(minutes, vaultURL: tmpDir)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("Test Save"))
        #expect(content.contains("type: meeting-minutes"))
    }

    // MARK: - TranscriptPersistenceService

    @Test("TranscriptPersistenceService saves transcription as markdown")
    func transcriptPersistenceSaves() async throws {
        let service = TranscriptPersistenceService()
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Hello everyone. Welcome to the meeting.",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "Hello everyone", timestamp: 0.0, duration: 1.0, confidence: 0.95),
                TranscriptionService.TranscriptionSegment(text: "Welcome to the meeting", timestamp: 1.0, duration: 1.5, confidence: 0.92),
            ],
            locale: Locale(identifier: "en_US"),
            duration: 2.5
        )

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "TranscriptTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = try await service.saveAsNote(
            transcription: transcription,
            vaultURL: tmpDir,
            title: "Test Transcript"
        )

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("type: transcription"))
        #expect(content.contains("Test Transcript"))
        #expect(content.contains("Hello everyone"))
    }

    @Test("TranscriptPersistenceService auto-generates title from text")
    func transcriptPersistenceAutoTitle() async throws {
        let service = TranscriptPersistenceService()
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Today we discussed the new feature roadmap for Q3",
            segments: [],
            locale: Locale(identifier: "en_US"),
            duration: 5.0
        )

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "TranscriptAutoTitle_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = try await service.saveAsNote(
            transcription: transcription,
            vaultURL: tmpDir
        )

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        // Auto-generated title uses first 5 words
        let fileName = fileURL.lastPathComponent
        #expect(fileName.contains("Today"))
    }

    @Test("TranscriptPersistenceService saves with diarization")
    func transcriptPersistenceWithDiarization() async throws {
        let service = TranscriptPersistenceService()
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Hi Bob. Hi Alice.",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "Hi Bob", timestamp: 0.0, duration: 1.0, confidence: 0.9),
                TranscriptionService.TranscriptionSegment(text: "Hi Alice", timestamp: 2.0, duration: 1.0, confidence: 0.9),
            ],
            locale: Locale(identifier: "en_US"),
            duration: 3.0
        )

        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Alice", startTime: 0.0, endTime: 1.5, confidence: 0.9),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "Bob", startTime: 1.5, endTime: 3.0, confidence: 0.85),
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "Alice", "speaker_1": "Bob"]
        )

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "TranscriptDiarize_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = try await service.saveAsNote(
            transcription: transcription,
            diarization: diarization,
            vaultURL: tmpDir,
            title: "Diarized Meeting"
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("speakers:"))
        #expect(content.contains("Alice"))
        #expect(content.contains("Bob"))
    }

    @Test("TranscriptPersistenceService handles empty transcription gracefully")
    func transcriptPersistenceEmpty() async throws {
        let service = TranscriptPersistenceService()
        let transcription = TranscriptionService.TranscriptionResult(
            text: "",
            segments: [],
            locale: Locale(identifier: "en_US"),
            duration: 0
        )

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "TranscriptEmpty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = try await service.saveAsNote(
            transcription: transcription,
            vaultURL: tmpDir
        )

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("TranscriptPersistenceService includes related note link")
    func transcriptPersistenceRelatedNote() async throws {
        let service = TranscriptPersistenceService()
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Some text here",
            segments: [],
            locale: Locale(identifier: "en_US"),
            duration: 1.0
        )

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "TranscriptRelated_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let relatedURL = tmpDir.appending(path: "MyNote.md")

        let fileURL = try await service.saveAsNote(
            transcription: transcription,
            vaultURL: tmpDir,
            title: "Related Test",
            relatedNoteURL: relatedURL
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("related-note: MyNote.md"))
    }

    // MARK: - TranscriptPersistenceService Error

    @Test("TranscriptPersistence PersistenceError descriptions are non-empty")
    func persistenceErrorDescriptions() {
        let encoding = TranscriptPersistenceService.PersistenceError.encodingFailed
        #expect(encoding.errorDescription != nil)
        #expect(!encoding.errorDescription!.isEmpty)

        let write = TranscriptPersistenceService.PersistenceError.writeFailed("disk full")
        #expect(write.errorDescription != nil)
        #expect(write.errorDescription!.contains("disk full"))
    }

    // MARK: - SpeakerDiarizationService Error Descriptions

    @Test("DiarizationError descriptions are non-empty for all cases")
    func diarizationErrorDescriptions() {
        let errors: [SpeakerDiarizationService.DiarizationError] = [
            .fileNotFound,
            .analysisUnavailable,
            .analysisFailed("test"),
            .insufficientAudio
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "\(error) should have a description")
            #expect(!error.errorDescription!.isEmpty, "\(error) description should be non-empty")
        }
    }

    // MARK: - SpeakerDiarizationService combineWithTranscription

    @Test("combineWithTranscription returns empty for no segments")
    func combineEmpty() async {
        let service = SpeakerDiarizationService()
        let diarization = SpeakerDiarizationService.DiarizationResult(segments: [], speakerCount: 0, speakers: [:])
        let transcription = TranscriptionService.TranscriptionResult(text: "", segments: [], locale: .current, duration: 0)

        let combined = await service.combineWithTranscription(diarization: diarization, transcription: transcription)
        #expect(combined.isEmpty)
    }

    @Test("combineWithTranscription formats speaker labels with timestamps")
    func combineFormatsLabels() async {
        let service = SpeakerDiarizationService()
        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Alice", startTime: 0, endTime: 5, confidence: 0.9)
            ],
            speakerCount: 1,
            speakers: ["speaker_0": "Alice"]
        )
        let transcription = TranscriptionService.TranscriptionResult(
            text: "Hello",
            segments: [TranscriptionService.TranscriptionSegment(text: "Hello", timestamp: 1.0, duration: 1.0, confidence: 0.9)],
            locale: Locale(identifier: "en_US"),
            duration: 5.0
        )

        let combined = await service.combineWithTranscription(diarization: diarization, transcription: transcription)
        #expect(combined.contains("**Alice**"))
        #expect(combined.contains("[00:00]"))
        #expect(combined.contains("Hello"))
    }

    // MARK: - SpeakerSegment

    @Test("SpeakerSegment duration computed correctly")
    func speakerSegmentDuration() {
        let segment = SpeakerDiarizationService.SpeakerSegment(
            speakerID: "speaker_0",
            speakerLabel: "A",
            startTime: 5.0,
            endTime: 15.0,
            confidence: 0.9
        )
        #expect(segment.duration == 10.0)
    }

    // MARK: - AudioChunk

    @Test("AudioChunk stores correct properties")
    func audioChunkProperties() {
        let chunk = AudioChunk(samples: [0.1, 0.2, 0.3, 0.4], sampleRate: 48000, frameCount: 4, timestamp: 2.5)
        #expect(chunk.samples.count == 4)
        #expect(chunk.sampleRate == 48000)
        #expect(chunk.frameCount == 4)
        #expect(chunk.timestamp == 2.5)
    }

    @Test("AudioChunk memorySizeBytes reflects sample count")
    func audioChunkMemorySize() {
        let chunk = AudioChunk(samples: [Float](repeating: 0, count: 1000), sampleRate: 44100, frameCount: 1000, timestamp: 0)
        #expect(chunk.memorySizeBytes == 1000 * MemoryLayout<Float>.size)
    }

    @Test("AudioChunk duration calculation")
    func audioChunkDurationCalc() {
        let chunk = AudioChunk(samples: [Float](repeating: 0, count: 44100), sampleRate: 44100, frameCount: 44100, timestamp: 0)
        #expect(abs(chunk.duration - 1.0) < 0.001)
    }

    // MARK: - AudioChunkRingBuffer Additional

    @Test("Ring buffer recent(0) returns empty array")
    func ringBufferRecentZero() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        for i in 0..<5 {
            await buffer.append(AudioChunk(samples: [Float(i)], sampleRate: 44100, frameCount: 1, timestamp: Double(i)))
        }
        let recent = await buffer.recent(0)
        #expect(recent.isEmpty)
    }

    @Test("Ring buffer recent more than count returns all")
    func ringBufferRecentMoreThanCount() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        for i in 0..<3 {
            await buffer.append(AudioChunk(samples: [Float(i)], sampleRate: 44100, frameCount: 1, timestamp: Double(i)))
        }
        let recent = await buffer.recent(100)
        #expect(recent.count == 3)
    }

}

// MARK: - Free function helper (accessible from @Test methods)

private func makeMockMinutes(
    title: String,
    duration: TimeInterval = 60,
    participants: [String],
    aiSummary: String = "AI summary placeholder."
) -> MeetingMinutes {
    MeetingMinutes(
        title: title,
        date: Date(),
        duration: duration,
        participants: participants,
        transcript: TranscriptionService.TranscriptionResult(
            text: "Test transcript text.",
            segments: [TranscriptionService.TranscriptionSegment(text: "Test transcript text.", timestamp: 0, duration: 5, confidence: 0.9)],
            locale: Locale(identifier: "en_US"),
            duration: duration
        ),
        aiSummary: aiSummary,
        audioURL: URL(fileURLWithPath: "/tmp/test.m4a")
    )
}
