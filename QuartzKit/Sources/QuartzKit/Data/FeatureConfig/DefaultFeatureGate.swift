import Foundation

/// Zentrale Feature-Flag-Konfiguration.
///
/// Definiert welche Features Free vs. Pro sind.
/// Zum Verschieben eines Features: eine Zeile in `tierMap` ändern.
/// Thread-safe durch NSLock-geschützte Properties.
public final class DefaultFeatureGate: FeatureGating, @unchecked Sendable {
    private let lock = NSLock()

    /// Zentrale Zuordnung: Feature → Tier.
    /// Hier ändern um Features zwischen Free und Pro zu verschieben.
    private var _tierMap: [Feature: FeatureTier] = [
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
    private var _isProUnlocked: Bool = false

    public var isProUnlocked: Bool {
        get { lock.withLock { _isProUnlocked } }
        set { lock.withLock { _isProUnlocked = newValue } }
    }

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
        lock.withLock { _tierMap[feature] ?? .free }
    }

    /// Überschreibt den Tier eines Features zur Laufzeit.
    public func setTier(_ tier: FeatureTier, for feature: Feature) {
        lock.withLock { _tierMap[feature] = tier }
    }
}
