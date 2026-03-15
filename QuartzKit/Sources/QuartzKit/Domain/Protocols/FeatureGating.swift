import Foundation

/// Protocol für das Feature-Flag-System.
///
/// Bestimmt ob ein Feature verfügbar ist (basierend auf Tier + Kaufstatus).
/// Wird per `@Environment(\.featureGate)` in Views injiziert.
public protocol FeatureGating: Sendable {
    /// Prüft ob ein Feature für den aktuellen Nutzer aktiviert ist.
    func isEnabled(_ feature: Feature) -> Bool

    /// Gibt den Tier (Free/Pro) eines Features zurück.
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

/// Stub-Implementierung: Alle Features aktiviert (für Previews und Tests).
private struct DefaultFeatureGateStub: FeatureGating {
    func isEnabled(_ feature: Feature) -> Bool { true }
    func tier(for feature: Feature) -> FeatureTier { .free }
}
#endif
