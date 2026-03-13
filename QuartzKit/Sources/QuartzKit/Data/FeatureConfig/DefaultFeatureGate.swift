import Foundation

/// Zentrale Feature-Flag-Konfiguration.
///
/// Definiert welche Features Free vs. Pro sind.
/// Zum Verschieben eines Features: eine Zeile in `tierMap` ändern.
public final class DefaultFeatureGate: FeatureGating, @unchecked Sendable {
    /// Zentrale Zuordnung: Feature → Tier.
    /// Hier ändern um Features zwischen Free und Pro zu verschieben.
    private var tierMap: [Feature: FeatureTier] = [
        // Editor – Free
        .markdownEditor:      .free,
        .focusMode:           .free,
        .typewriterMode:      .free,

        // Organisation – Free
        .biDirectionalLinks:  .free,
        .tagSystem:           .free,
        .fullTextSearch:      .free,

        // AI – Pro
        .aiChat:              .pro,
        .aiSummarize:         .pro,
        .vaultSearch:         .pro,

        // Audio – Mixed
        .audioRecording:      .free,
        .transcription:       .free,
        .meetingMinutes:      .pro,
        .speakerDiarization:  .pro,
    ]

    /// Ob der Nutzer Pro gekauft hat. Wird von `ProFeatureGate` gesetzt.
    public var isProUnlocked: Bool = false

    public init() {}

    public func isEnabled(_ feature: Feature) -> Bool {
        switch tier(for: feature) {
        case .free:
            return true
        case .pro:
            return isProUnlocked
        }
    }

    public func tier(for feature: Feature) -> FeatureTier {
        tierMap[feature] ?? .free
    }

    /// Überschreibt den Tier eines Features zur Laufzeit.
    public func setTier(_ tier: FeatureTier, for feature: Feature) {
        tierMap[feature] = tier
    }
}
