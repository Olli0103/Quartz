import Foundation

/// All toggleable features of the app.
///
/// Quartz is fully open-source – every feature is free.
/// The Feature enum exists for runtime checks and future extensibility.
public enum Feature: String, CaseIterable, Codable, Sendable {
    // MARK: - Editor
    case markdownEditor
    case focusMode
    case typewriterMode

    // MARK: - Organisation
    case biDirectionalLinks
    case tagSystem
    case fullTextSearch

    // MARK: - AI
    case aiChat
    case aiSummarize
    case vaultSearch

    // MARK: - Audio
    case audioRecording
    case transcription
    case meetingMinutes
    case speakerDiarization
}

/// Feature tier – kept for API compatibility.
/// All features are free in the open-source release.
public enum FeatureTier: String, Codable, Sendable {
    case free
}
