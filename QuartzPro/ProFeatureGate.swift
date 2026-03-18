import QuartzKit

/// Legacy Pro feature gate – no longer used.
///
/// Quartz is fully open-source. All features are free.
/// This file is kept for backward compatibility but is not
/// instantiated anywhere.
final class ProFeatureGate: FeatureGating, Sendable {
    init() {}

    nonisolated func isEnabled(_ feature: Feature) -> Bool { true }
    nonisolated func tier(for feature: Feature) -> FeatureTier { .free }
}
