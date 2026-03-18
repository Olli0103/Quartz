import Foundation

/// Central feature flag configuration.
///
/// Defines which features are Free vs. Pro.
/// To move a feature: change one line in `tierMap`.
/// Thread-safe via `OSAllocatedUnfairLock` (replacing `@unchecked Sendable` + NSLock).
public final class DefaultFeatureGate: FeatureGating, Sendable {
    /// Central mapping: Feature → Tier.
    /// Change here to move features between Free and Pro.
    private let state = OSAllocatedUnfairLock(initialState: GateState())

    private struct GateState {
        var tierMap: [Feature: FeatureTier] = [
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

        var isProUnlocked: Bool = false
    }

    /// Whether the user has purchased Pro. Set by `ProFeatureGate`.
    public var isProUnlocked: Bool {
        get { state.withLock { $0.isProUnlocked } }
        set { state.withLock { $0.isProUnlocked = newValue } }
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
        state.withLock { $0.tierMap[feature] ?? .free }
    }

    /// Overrides the tier of a feature at runtime.
    public func setTier(_ tier: FeatureTier, for feature: Feature) {
        state.withLock { $0.tierMap[feature] = tier }
    }
}
