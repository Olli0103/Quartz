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

    // MARK: - State

    private var state: CaptureState = .idle

    public init() {}

    public var currentState: CaptureState {
        state
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
        case (.diarizing, .generating): return true
        case (.generating, .complete): return true
        case (_, .failed): return true
        case (_, .idle): return true // Reset
        default: return false
        }
    }

    /// Cancels the current session and resets to idle.
    public func cancel() {
        state = .idle
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
}
