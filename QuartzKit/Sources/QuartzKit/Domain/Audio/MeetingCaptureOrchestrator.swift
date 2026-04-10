import Foundation

/// Orchestrator for the full meeting capture pipeline.
///
/// Manages the state machine for a complete meeting capture session:
/// `idle → preparing → recording → transcribing → diarizing → generating → complete`
///
/// Coordinates between AVAudioEngine capture, streaming transcription,
/// speaker diarization, and meeting minutes generation.
///
/// - Linear: OLL-45 (Meeting capture orchestrator — end-to-end pipeline)
public actor MeetingCaptureOrchestrator {

    // MARK: - Types

    public enum CaptureState: Equatable, Sendable {
        case idle
        case preparing
        case recording
        case paused
        case transcribing
        case diarizing
        case generating
        case complete
        case failed(String)

        public static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing), (.recording, .recording),
                 (.paused, .paused), (.transcribing, .transcribing), (.diarizing, .diarizing),
                 (.generating, .generating), (.complete, .complete):
                return true
            case (.failed(let l), .failed(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    public struct CaptureConfiguration: Sendable {
        public let vaultURL: URL
        public let template: MeetingMinutesTemplate
        public let detectLanguage: Bool
        public let enableDiarization: Bool

        public init(vaultURL: URL, template: MeetingMinutesTemplate, detectLanguage: Bool, enableDiarization: Bool) {
            self.vaultURL = vaultURL
            self.template = template
            self.detectLanguage = detectLanguage
            self.enableDiarization = enableDiarization
        }
    }

    /// Result of a complete capture session pipeline.
    public struct CaptureResult: Sendable {
        public let transcription: TranscriptionService.TranscriptionResult
        public let diarization: SpeakerDiarizationService.DiarizationResult?
        public let detectedLanguage: String?
        public let persistedURL: URL?
        public let combinedTranscript: String

        public init(
            transcription: TranscriptionService.TranscriptionResult,
            diarization: SpeakerDiarizationService.DiarizationResult? = nil,
            detectedLanguage: String? = nil,
            persistedURL: URL? = nil,
            combinedTranscript: String = ""
        ) {
            self.transcription = transcription
            self.diarization = diarization
            self.detectedLanguage = detectedLanguage
            self.persistedURL = persistedURL
            self.combinedTranscript = combinedTranscript
        }
    }

    // MARK: - Pipeline Step Protocols

    /// Transcription step of the capture pipeline.
    public protocol TranscriptionStep: Sendable {
        func transcribe(audioURL: URL) async throws -> TranscriptionService.TranscriptionResult
    }

    /// Diarization step of the capture pipeline.
    public protocol DiarizationStep: Sendable {
        func diarize(audioURL: URL) async throws -> SpeakerDiarizationService.DiarizationResult
    }

    /// Language detection step of the capture pipeline.
    public protocol LanguageDetectionStep: Sendable {
        func detect(text: String) async -> String?
    }

    /// Persistence step of the capture pipeline.
    public protocol PersistenceStep: Sendable {
        func persist(
            transcription: TranscriptionService.TranscriptionResult,
            diarization: SpeakerDiarizationService.DiarizationResult?,
            vaultURL: URL,
            title: String?
        ) async throws -> URL
    }

    // MARK: - State

    private var state: CaptureState = .idle
    private var stateHistory: [(CaptureState, Date)] = []

    // Pipeline steps (injectable for testing)
    private let transcriptionStep: (any TranscriptionStep)?
    private let diarizationStep: (any DiarizationStep)?
    private let languageDetectionStep: (any LanguageDetectionStep)?
    private let persistenceStep: (any PersistenceStep)?

    public init() {
        self.transcriptionStep = nil
        self.diarizationStep = nil
        self.languageDetectionStep = nil
        self.persistenceStep = nil
    }

    /// Creates an orchestrator with injectable pipeline steps for testing.
    public init(
        transcription: (any TranscriptionStep)? = nil,
        diarization: (any DiarizationStep)? = nil,
        languageDetection: (any LanguageDetectionStep)? = nil,
        persistence: (any PersistenceStep)? = nil
    ) {
        self.transcriptionStep = transcription
        self.diarizationStep = diarization
        self.languageDetectionStep = languageDetection
        self.persistenceStep = persistence
    }

    public var currentState: CaptureState {
        state
    }

    /// Returns the state transition history for diagnostics.
    public var transitions: [(CaptureState, Date)] {
        stateHistory
    }

    // MARK: - State Machine

    /// Returns whether a transition to the given state is valid from the current state.
    public func canTransition(to newState: CaptureState) -> Bool {
        switch (state, newState) {
        case (.idle, .preparing): return true
        case (.preparing, .recording): return true
        case (.recording, .paused): return true
        case (.paused, .recording): return true
        case (.recording, .transcribing): return true
        case (.transcribing, .diarizing): return true
        case (.transcribing, .generating): return true  // Skip diarization
        case (.diarizing, .generating): return true
        case (.generating, .complete): return true
        case (_, .failed): return true
        case (_, .idle): return true // Reset
        default: return false
        }
    }

    @discardableResult
    private func transition(to newState: CaptureState) -> Bool {
        guard canTransition(to: newState) else { return false }
        state = newState
        stateHistory.append((newState, Date()))
        return true
    }

    /// Cancels the current session and resets to idle.
    public func cancel() {
        state = .idle
        stateHistory.append((.idle, Date()))
    }

    // MARK: - End-to-End Pipeline

    /// Runs the full capture→transcribe→diarize→persist pipeline.
    ///
    /// This is the primary orchestration method. It progresses through
    /// each state in sequence, executing the appropriate pipeline step.
    ///
    /// - Parameters:
    ///   - audioURL: URL of the captured audio file
    ///   - configuration: Pipeline configuration
    /// - Returns: Complete capture result with all artifacts
    public func runPipeline(
        audioURL: URL,
        configuration: CaptureConfiguration
    ) async throws -> CaptureResult {
        // Prepare
        guard transition(to: .preparing) else {
            throw PipelineError.invalidState("Cannot start pipeline from state: \(state)")
        }

        // Recording phase (already complete — audio file exists)
        guard transition(to: .recording) else {
            throw PipelineError.invalidState("Cannot transition to recording")
        }

        // Transcription
        guard transition(to: .transcribing) else {
            throw PipelineError.invalidState("Cannot transition to transcribing")
        }

        let transcription: TranscriptionService.TranscriptionResult
        do {
            guard let step = transcriptionStep else {
                throw PipelineError.stepNotConfigured("transcription")
            }
            transcription = try await step.transcribe(audioURL: audioURL)
        } catch {
            transition(to: .failed("Transcription failed: \(error.localizedDescription)"))
            throw error
        }

        // Language detection (optional)
        var detectedLanguage: String?
        if configuration.detectLanguage, let langStep = languageDetectionStep {
            detectedLanguage = await langStep.detect(text: transcription.text)
        }

        // Diarization (optional)
        var diarization: SpeakerDiarizationService.DiarizationResult?
        if configuration.enableDiarization {
            guard transition(to: .diarizing) else {
                throw PipelineError.invalidState("Cannot transition to diarizing")
            }

            do {
                guard let step = diarizationStep else {
                    throw PipelineError.stepNotConfigured("diarization")
                }
                diarization = try await step.diarize(audioURL: audioURL)
            } catch {
                transition(to: .failed("Diarization failed: \(error.localizedDescription)"))
                throw error
            }
        }

        // Generate combined transcript
        guard transition(to: .generating) else {
            throw PipelineError.invalidState("Cannot transition to generating")
        }

        let combinedTranscript: String
        if let diarization {
            combinedTranscript = combineTranscriptionWithDiarization(
                transcription: transcription,
                diarization: diarization
            )
        } else {
            combinedTranscript = transcription.text
        }

        // Persist
        var persistedURL: URL?
        if let persistStep = persistenceStep {
            do {
                persistedURL = try await persistStep.persist(
                    transcription: transcription,
                    diarization: diarization,
                    vaultURL: configuration.vaultURL,
                    title: nil
                )
            } catch {
                transition(to: .failed("Persistence failed: \(error.localizedDescription)"))
                throw error
            }
        }

        // Complete
        guard transition(to: .complete) else {
            throw PipelineError.invalidState("Cannot transition to complete")
        }

        return CaptureResult(
            transcription: transcription,
            diarization: diarization,
            detectedLanguage: detectedLanguage,
            persistedURL: persistedURL,
            combinedTranscript: combinedTranscript
        )
    }

    // MARK: - Pipeline Helpers

    /// Combines transcription with diarization into a formatted Markdown string.
    public func combineTranscriptionWithDiarization(
        transcription: TranscriptionService.TranscriptionResult,
        diarization: SpeakerDiarizationService.DiarizationResult
    ) -> String {
        var result = ""

        for segment in diarization.segments {
            let matchingText = transcription.segments
                .filter { $0.timestamp >= segment.startTime && $0.timestamp < segment.endTime }
                .map(\.text)
                .joined(separator: " ")

            if !matchingText.isEmpty {
                let min = Int(segment.startTime) / 60
                let sec = Int(segment.startTime) % 60
                result += "**\(segment.speakerLabel)** [\(String(format: "%02d:%02d", min, sec))]: \(matchingText)\n\n"
            }
        }

        return result
    }

    // MARK: - Errors

    public enum PipelineError: LocalizedError, Sendable {
        case invalidState(String)
        case stepNotConfigured(String)

        public var errorDescription: String? {
            switch self {
            case .invalidState(let msg): "Invalid pipeline state: \(msg)"
            case .stepNotConfigured(let step): "Pipeline step not configured: \(step)"
            }
        }
    }
}
