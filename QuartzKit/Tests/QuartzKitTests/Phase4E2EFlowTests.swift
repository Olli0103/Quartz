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

    // MARK: - End-to-End Orchestrator Pipeline

    @Test("Orchestrator pipeline runs full capture→transcribe→diarize→persist sequence")
    func orchestratorFullPipeline() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorE2E_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fakeTranscription = FakeTranscriptionStep()
        let fakeDiarization = FakeDiarizationStep()
        let fakeLanguage = FakeLanguageDetectionStep()
        let fakePersistence = FakePersistenceStep(vaultURL: tmpDir)

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: fakeTranscription,
            diarization: fakeDiarization,
            languageDetection: fakeLanguage,
            persistence: fakePersistence
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: true,
            enableDiarization: true
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        let result = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)

        #expect(result.transcription.text == "Hello world from fake transcription.")
        #expect(result.diarization != nil)
        #expect(result.diarization?.speakerCount == 2)
        #expect(result.detectedLanguage == "en")
        #expect(result.persistedURL != nil)
        #expect(!result.combinedTranscript.isEmpty)
        #expect(await orchestrator.currentState == .complete)
    }

    @Test("Orchestrator pipeline without diarization skips diarizing state")
    func orchestratorPipelineNoDiarization() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorNoDiariz_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: FakeTranscriptionStep(),
            persistence: FakePersistenceStep(vaultURL: tmpDir)
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: false,
            enableDiarization: false
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        let result = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)

        #expect(result.transcription.text == "Hello world from fake transcription.")
        #expect(result.diarization == nil)
        #expect(result.detectedLanguage == nil)
        #expect(result.combinedTranscript == "Hello world from fake transcription.")
        #expect(await orchestrator.currentState == .complete)

        // Verify state history never hit .diarizing
        let transitions = await orchestrator.transitions
        let diarizingCount = transitions.filter { $0.0 == .diarizing }.count
        #expect(diarizingCount == 0, "Should not enter diarizing state when diarization disabled")
    }

    @Test("Orchestrator pipeline transitions through all expected states in order")
    func orchestratorStateTransitionOrder() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorOrder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: FakeTranscriptionStep(),
            diarization: FakeDiarizationStep(),
            persistence: FakePersistenceStep(vaultURL: tmpDir)
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: false,
            enableDiarization: true
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        _ = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)

        let transitions = await orchestrator.transitions
        let states = transitions.map(\.0)
        let expectedOrder: [MeetingCaptureOrchestrator.CaptureState] = [
            .preparing, .recording, .transcribing, .diarizing, .generating, .complete
        ]
        #expect(states == expectedOrder, "Pipeline should progress through states in order")
    }

    @Test("Orchestrator pipeline fails gracefully on transcription error")
    func orchestratorTranscriptionFailure() async throws {
        let orchestrator = MeetingCaptureOrchestrator(
            transcription: FailingTranscriptionStep()
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: FileManager.default.temporaryDirectory,
            template: .standard,
            detectLanguage: false,
            enableDiarization: false
        )

        let audioURL = FileManager.default.temporaryDirectory.appending(path: "test.m4a")

        do {
            _ = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Orchestrator should be in failed state
            let state = await orchestrator.currentState
            if case .failed(let msg) = state {
                #expect(msg.contains("Transcription failed"))
            } else {
                #expect(Bool(false), "Should be in failed state, got \(state)")
            }
        }
    }

    @Test("Orchestrator cannot start pipeline when already running")
    func orchestratorCannotDoubleStart() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorDouble_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: FakeTranscriptionStep()
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: false,
            enableDiarization: false
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        // First run succeeds
        _ = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)
        #expect(await orchestrator.currentState == .complete)

        // Second run from .complete → should fail (can't transition from .complete to .preparing)
        do {
            _ = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)
            #expect(Bool(false), "Should have thrown for invalid state")
        } catch {
            // Expected
        }
    }

    @Test("Orchestrator cancel resets to idle from any state")
    func orchestratorCancelResetsToIdle() async {
        let orchestrator = MeetingCaptureOrchestrator()
        await orchestrator.cancel()
        #expect(await orchestrator.currentState == .idle)
    }

    @Test("Orchestrator pipeline persists combined diarized transcript")
    func orchestratorPersistsDiarizedTranscript() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorPersist_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fakePersistence = FakePersistenceStep(vaultURL: tmpDir)

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: FakeTranscriptionStep(),
            diarization: FakeDiarizationStep(),
            persistence: fakePersistence
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: false,
            enableDiarization: true
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        let result = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)
        #expect(result.persistedURL != nil)
        // FakePersistenceStep writes a file we can verify
        if let url = result.persistedURL {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - Concurrency Stress Tests (Lifecycle Transitions)

    @Test("Concurrent cancel during pipeline does not crash or deadlock")
    func concurrentCancelDuringPipeline() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorConcCancel_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: SlowTranscriptionStep(),
            diarization: FakeDiarizationStep(),
            persistence: FakePersistenceStep(vaultURL: tmpDir)
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: false,
            enableDiarization: true
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        // Start pipeline in one task, cancel from another
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await orchestrator.runPipeline(audioURL: audioURL, configuration: config)
            }
            group.addTask {
                // Give pipeline a moment to start, then cancel
                try? await Task.sleep(for: .milliseconds(10))
                await orchestrator.cancel()
            }
        }

        // Should not deadlock — if we get here, the test passes
        let finalState = await orchestrator.currentState
        // State is either .idle (cancelled) or .complete (finished before cancel)
        #expect(finalState == .idle || finalState == .complete,
            "After concurrent cancel, state should be idle or complete, got \(finalState)")
    }

    @Test("Multiple concurrent pipeline attempts are serialized by actor isolation")
    func concurrentPipelineAttemptsAreSerialized() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "OrchestratorConcMulti_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let orchestrator = MeetingCaptureOrchestrator(
            transcription: FakeTranscriptionStep()
        )

        let config = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: tmpDir,
            template: .standard,
            detectLanguage: false,
            enableDiarization: false
        )

        let audioURL = tmpDir.appending(path: "test.m4a")
        try Data("fake audio".utf8).write(to: audioURL)

        // Launch 5 concurrent pipeline attempts — actor serialization means
        // at most one succeeds, rest fail with invalid state
        var successCount = 0
        var failureCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        _ = try await orchestrator.runPipeline(audioURL: audioURL, configuration: config)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            for await success in group {
                if success { successCount += 1 }
                else { failureCount += 1 }
            }
        }

        // Exactly 1 should succeed (the first one through), rest fail
        #expect(successCount == 1, "Only one concurrent pipeline should succeed (got \(successCount))")
        #expect(failureCount == 4, "Other concurrent attempts should fail (got \(failureCount))")
    }

    @Test("Ring buffer handles concurrent append from multiple tasks without data loss")
    func ringBufferConcurrentAppend() async {
        let buffer = AudioChunkRingBuffer(capacity: 100, chunkDuration: 0.5)

        await withTaskGroup(of: Void.self) { group in
            for taskID in 0..<10 {
                group.addTask {
                    for i in 0..<10 {
                        let chunk = AudioChunk(
                            samples: [Float(taskID * 10 + i)],
                            sampleRate: 44100,
                            frameCount: 1,
                            timestamp: Double(taskID * 10 + i)
                        )
                        await buffer.append(chunk)
                    }
                }
            }
        }

        // All 100 appends should complete (actor serialization prevents data races)
        let count = await buffer.chunkCount
        #expect(count == 100, "All concurrent appends should be preserved (got \(count))")
        #expect(await buffer.totalChunksReceived == 100)
    }

    @Test("Metering buffer concurrent read/write does not crash")
    func meteringBufferConcurrentReadWrite() async {
        let buffer = AudioMeteringBuffer(capacity: 50)

        await withTaskGroup(of: Void.self) { group in
            // Writer tasks
            for t in 0..<5 {
                group.addTask {
                    for i in 0..<100 {
                        await buffer.append(Float(t * 100 + i) / 500.0)
                    }
                }
            }
            // Reader tasks
            for _ in 0..<5 {
                group.addTask {
                    for _ in 0..<50 {
                        _ = await buffer.recent(20)
                        _ = await buffer.latest
                        _ = await buffer.rmsLevel(samples: 10)
                    }
                }
            }
        }

        // If we get here without crash, actor isolation is working
        let count = await buffer.sampleCount
        #expect(count == 50, "Buffer should be at capacity after concurrent writes")
        #expect(await buffer.totalSamplesReceived == 500)
    }

    @Test("Capture service state remains consistent under concurrent pause/resume")
    func captureServiceConcurrentStateAccess() async {
        let service = AVAudioEngineCaptureService()

        // Concurrent state reads should all see .idle (no capture started)
        await withTaskGroup(of: AVAudioEngineCaptureService.CaptureState.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await service.state
                }
            }
            for await state in group {
                #expect(state == .idle, "Concurrent reads should all see idle")
            }
        }

        // Concurrent pause attempts from idle should all be no-ops
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await service.pauseCapture()
                }
            }
        }

        #expect(await service.state == .idle, "State should remain idle after concurrent pauses")
    }
}

// MARK: - Deterministic Fake Pipeline Steps

private struct FakeTranscriptionStep: MeetingCaptureOrchestrator.TranscriptionStep {
    func transcribe(audioURL: URL) async throws -> TranscriptionService.TranscriptionResult {
        TranscriptionService.TranscriptionResult(
            text: "Hello world from fake transcription.",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "Hello world", timestamp: 0.0, duration: 1.0, confidence: 0.95),
                TranscriptionService.TranscriptionSegment(text: "from fake transcription", timestamp: 1.0, duration: 1.5, confidence: 0.92),
            ],
            locale: Locale(identifier: "en_US"),
            duration: 2.5
        )
    }
}

private struct FailingTranscriptionStep: MeetingCaptureOrchestrator.TranscriptionStep {
    func transcribe(audioURL: URL) async throws -> TranscriptionService.TranscriptionResult {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcription failed: simulated error"])
    }
}

private struct SlowTranscriptionStep: MeetingCaptureOrchestrator.TranscriptionStep {
    func transcribe(audioURL: URL) async throws -> TranscriptionService.TranscriptionResult {
        try await Task.sleep(for: .milliseconds(50))
        return TranscriptionService.TranscriptionResult(
            text: "Slow transcription result.",
            segments: [TranscriptionService.TranscriptionSegment(text: "Slow transcription result.", timestamp: 0, duration: 2.0, confidence: 0.9)],
            locale: Locale(identifier: "en_US"),
            duration: 2.0
        )
    }
}

private struct FakeDiarizationStep: MeetingCaptureOrchestrator.DiarizationStep {
    func diarize(audioURL: URL) async throws -> SpeakerDiarizationService.DiarizationResult {
        SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Alice", startTime: 0.0, endTime: 1.5, confidence: 0.9),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "Bob", startTime: 1.0, endTime: 2.5, confidence: 0.85),
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "Alice", "speaker_1": "Bob"]
        )
    }
}

private struct FakeLanguageDetectionStep: MeetingCaptureOrchestrator.LanguageDetectionStep {
    func detect(text: String) async -> String? {
        "en"
    }
}

private struct FakePersistenceStep: MeetingCaptureOrchestrator.PersistenceStep {
    let vaultURL: URL

    func persist(
        transcription: TranscriptionService.TranscriptionResult,
        diarization: SpeakerDiarizationService.DiarizationResult?,
        vaultURL: URL,
        title: String?
    ) async throws -> URL {
        let dir = vaultURL.appending(path: "Transcriptions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appending(path: "test-pipeline-output.md")
        let content = "# Pipeline Output\n\n\(transcription.text)"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
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
