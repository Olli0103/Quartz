import Foundation

/// Feature gate for the fully open-source Quartz app.
///
/// Every feature is free. The gate exists for API compatibility
/// and to keep the FeatureGating protocol functional across the codebase.
public final class DefaultFeatureGate: FeatureGating, Sendable {

    public init() {}

    public func isEnabled(_ feature: Feature) -> Bool { true }

    public func tier(for feature: Feature) -> FeatureTier { .free }
}
