import Foundation

/// Alle schaltbaren Features der App.
///
/// Jedes Feature kann flexibel zwischen Free und Pro verschoben werden.
/// Die Zuordnung erfolgt zentral im `DefaultFeatureGate`.
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

/// Zugehörigkeits-Tier eines Features.
public enum FeatureTier: String, Codable, Sendable {
    /// Immer verfügbar, ohne Kauf.
    case free
    /// Nur mit Pro-Einmalkauf verfügbar.
    case pro
}
