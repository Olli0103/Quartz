import Foundation

/// Protocol for the feature flag system.
///
/// Determines whether a feature is available (based on tier + purchase status).
/// Injected via `@Environment(\.featureGate)` in views.
public protocol FeatureGating: Sendable {
    /// Checks whether a feature is enabled for the current user.
    func isEnabled(_ feature: Feature) -> Bool

    /// Returns the tier (Free/Pro) of a feature.
    func tier(for feature: Feature) -> FeatureTier
}

#if canImport(SwiftUI)
import SwiftUI

// MARK: - SwiftUI Environment

private struct FeatureGateKey: EnvironmentKey {
    static let defaultValue: any FeatureGating = DefaultFeatureGateStub()
}

extension EnvironmentValues {
    public var featureGate: any FeatureGating {
        get { self[FeatureGateKey.self] }
        set { self[FeatureGateKey.self] = newValue }
    }
}

/// Stub implementation: All features enabled (for previews and tests).
private struct DefaultFeatureGateStub: FeatureGating {
    func isEnabled(_ feature: Feature) -> Bool { true }
    func tier(for feature: Feature) -> FeatureTier { .free }
}
#endif
