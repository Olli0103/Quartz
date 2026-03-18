import QuartzKit
import StoreKit

/// Pro feature gate: checks via StoreKit whether the user has purchased Pro
/// and unlocks the corresponding features.
///
/// Registered in `QuartzApp` and overrides the `DefaultFeatureGate`.
///
/// Thread safety is guaranteed through `OSAllocatedUnfairLock` instead of
/// the previous `@unchecked Sendable` + `NSLock` pattern, avoiding the
/// Swift 6 strict-concurrency bypass.
///
/// Usage:
/// ```swift
/// let gate = ProFeatureGate()
/// await gate.checkPurchaseStatus()
/// ServiceContainer.shared.register(featureGate: gate)
/// ```
final class ProFeatureGate: FeatureGating, Sendable {

    /// StoreKit Product ID for the Pro upgrade.
    static let proProductID = "olli.Quartz.pro"

    private let _hasPurchasedPro = OSAllocatedUnfairLock(initialState: false)
    private let _transactionTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// Single source of truth: delegates tier lookup to DefaultFeatureGate.
    private let base = DefaultFeatureGate()

    init() {}

    deinit {
        _transactionTask.withLock { $0?.cancel() }
    }

    // MARK: - FeatureGating

    func isEnabled(_ feature: Feature) -> Bool {
        switch tier(for: feature) {
        case .free:
            return true
        case .pro:
            return _hasPurchasedPro.withLock { $0 }
        }
    }

    func tier(for feature: Feature) -> FeatureTier {
        base.tier(for: feature)
    }

    // MARK: - StoreKit

    /// Checks the current purchase status via StoreKit 2.
    func checkPurchaseStatus() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                found = true
                break
            }
        }
        _hasPurchasedPro.withLock { $0 = found }
    }

    /// Observes transaction updates (purchases, refunds).
    /// Should be started at app launch. Stores the task for cleanup on deinit.
    func observeTransactionUpdates() {
        let purchased = _hasPurchasedPro
        let task = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    if transaction.productID == Self.proProductID {
                        purchased.withLock { $0 = transaction.revocationDate == nil }
                    }
                    await transaction.finish()
                }
            }
        }
        _transactionTask.withLock { $0 = task }
    }
}
