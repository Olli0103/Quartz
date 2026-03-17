import QuartzKit
import StoreKit

/// Pro-Feature-Gate: Prüft via StoreKit ob der Nutzer Pro gekauft hat
/// und schaltet entsprechende Features frei.
///
/// Wird in `QuartzApp` registriert und überschreibt den `DefaultFeatureGate`.
///
/// Nutzung:
/// ```swift
/// let gate = ProFeatureGate()
/// await gate.checkPurchaseStatus()
/// ServiceContainer.shared.register(featureGate: gate)
/// ```
final class ProFeatureGate: FeatureGating, @unchecked Sendable {

    /// StoreKit Product-ID für das Pro-Upgrade.
    static let proProductID = "olli.Quartz.pro"

    private let lock = NSLock()
    private var _hasPurchasedPro: Bool = false

    private var hasPurchasedPro: Bool {
        get { lock.withLock { _hasPurchasedPro } }
        set { lock.withLock { _hasPurchasedPro = newValue } }
    }

    /// Single source of truth: delegates tier lookup to DefaultFeatureGate.
    private let base = DefaultFeatureGate()

    init() {}

    // MARK: - FeatureGating

    func isEnabled(_ feature: Feature) -> Bool {
        switch tier(for: feature) {
        case .free:
            return true
        case .pro:
            return hasPurchasedPro
        }
    }

    func tier(for feature: Feature) -> FeatureTier {
        base.tier(for: feature)
    }

    // MARK: - StoreKit

    /// Prüft den aktuellen Kaufstatus über StoreKit 2.
    func checkPurchaseStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                hasPurchasedPro = true
                return
            }
        }
        hasPurchasedPro = false
    }

    /// Beobachtet Transaktions-Updates (Käufe, Erstattungen).
    /// Sollte beim App-Start gestartet werden.
    func observeTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    if transaction.productID == Self.proProductID {
                        if transaction.revocationDate != nil {
                            self.hasPurchasedPro = false
                        } else {
                            self.hasPurchasedPro = true
                        }
                    }
                    await transaction.finish()
                }
            }
        }
    }
}
