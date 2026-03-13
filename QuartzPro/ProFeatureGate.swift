import QuartzKit

/// Pro-Feature-Gate: Prüft via StoreKit ob der Nutzer Pro gekauft hat
/// und schaltet entsprechende Features frei.
///
/// Wird in `QuartzApp` registriert und überschreibt den `DefaultFeatureGate`.
final class ProFeatureGate: @unchecked Sendable {
    // TODO: StoreKit Integration in Phase 6
    private var hasPurchasedPro: Bool = false

    func isProUnlocked() -> Bool {
        hasPurchasedPro
    }
}
