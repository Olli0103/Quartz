import QuartzKit
import StoreKit

/// Pro feature gate: checks via StoreKit whether the user has purchased Pro
/// and unlocks the corresponding features.
///
/// Registered in `QuartzApp` and overrides the `DefaultFeatureGate`.
///
/// Usage:
/// ```swift
/// let gate = ProFeatureGate()
/// await gate.checkPurchaseStatus()
/// ServiceContainer.shared.register(featureGate: gate)
/// ```
final class ProFeatureGate: FeatureGating, @unchecked Sendable {

    /// StoreKit Product ID for the Pro upgrade.
    static let proProductID = "olli.Quartz.pro"

    private let lock = NSLock()
    private var _hasPurchasedPro: Bool = false
    private var transactionTask: Task<Void, Never>?

    private var hasPurchasedPro: Bool {
        get { lock.withLock { _hasPurchasedPro } }
        set { lock.withLock { _hasPurchasedPro = newValue } }
    }

    /// Single source of truth: delegates tier lookup to DefaultFeatureGate.
    private let base = DefaultFeatureGate()

    init() {}

    deinit {
        transactionTask?.cancel()
    }

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

    /// Checks the current purchase status via StoreKit 2.
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

    /// Observes transaction updates (purchases, refunds).
    /// Should be started at app launch. Stores the task for cleanup on deinit.
    func observeTransactionUpdates() {
        transactionTask = Task.detached { [weak self] in
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
