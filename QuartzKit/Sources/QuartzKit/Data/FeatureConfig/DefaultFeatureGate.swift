import Foundation

/// Central feature flag configuration.
///
/// Defines which features are Free vs. Pro.
/// To move a feature: change one line in `tierMap`.
/// Thread-safe via NSLock-protected properties.
public final class DefaultFeatureGate: FeatureGating, @unchecked Sendable {
    private let lock = NSLock()

    /// Central mapping: Feature → Tier.
    /// Change here to move features between Free and Pro.
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

    /// Whether the user has purchased Pro. Set by `ProFeatureGate`.
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

    /// Overrides the tier of a feature at runtime.
    public func setTier(_ tier: FeatureTier, for feature: Feature) {
        lock.withLock { _tierMap[feature] = tier }
    }
}
