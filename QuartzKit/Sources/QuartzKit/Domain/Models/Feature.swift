import Foundation

/// All toggleable features of the app.
///
/// Each feature can be flexibly moved between Free and Pro.
/// The assignment is managed centrally in `DefaultFeatureGate`.
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

/// Membership tier of a feature.
public enum FeatureTier: String, Codable, Sendable {
    /// Always available, without purchase.
    case free
    /// Only available with a one-time Pro purchase.
    case pro
}
