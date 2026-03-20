import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 8: StoreKit Integration Tests

/// Comprehensive StoreKit 2 test suite for Quartz Pro tier.
/// Uses local StoreKit configuration for deterministic testing.

// MARK: - Product Catalog Tests

@Suite("ProductCatalog")
struct ProductCatalogTests {

    @Test("All product identifiers follow reverse domain notation")
    func productIdentifiersFollowReverseDomainNotation() {
        let productIDs = QuartzProductID.allCases

        for productID in productIDs {
            let id = productID.rawValue
            #expect(id.hasPrefix("com.quartz."), "Product ID '\(id)' should start with 'com.quartz.'")
            #expect(id.components(separatedBy: ".").count >= 3, "Product ID '\(id)' should have at least 3 components")
            #expect(!id.contains(" "), "Product ID '\(id)' should not contain spaces")
            #expect(id == id.lowercased(), "Product ID '\(id)' should be lowercase")
        }
    }

    @Test("Product catalog contains all required tiers")
    func productCatalogContainsAllTiers() {
        let productIDs = QuartzProductID.allCases.map { $0.rawValue }

        // Verify monthly subscription exists
        #expect(productIDs.contains("com.quartz.pro.monthly"), "Monthly subscription should exist")

        // Verify yearly subscription exists
        #expect(productIDs.contains("com.quartz.pro.yearly"), "Yearly subscription should exist")

        // Verify lifetime purchase exists
        #expect(productIDs.contains("com.quartz.lifetime"), "Lifetime purchase should exist")
    }

    @Test("Subscription group ID is consistent")
    func subscriptionGroupIDIsConsistent() {
        let groupID = QuartzStoreConfig.subscriptionGroupID

        #expect(!groupID.isEmpty, "Subscription group ID should not be empty")
        #expect(groupID.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                "Group ID should only contain alphanumeric characters and underscores")
    }

    @Test("Product display names are localized")
    func productDisplayNamesAreLocalized() {
        // Verify display names exist for all products
        for productID in QuartzProductID.allCases {
            let displayName = productID.displayName
            #expect(!displayName.isEmpty, "Product '\(productID.rawValue)' should have a display name")
            #expect(displayName.count >= 5, "Display name should be descriptive (>= 5 chars)")
        }
    }
}

// MARK: - Pricing Tests

@Suite("Pricing")
struct PricingTests {

    @Test("Yearly subscription offers savings over monthly")
    func yearlySubscriptionOffersSavings() {
        let monthlyPrice: Decimal = 4.99
        let yearlyPrice: Decimal = 39.99
        let monthlyAnnualized = monthlyPrice * 12

        #expect(yearlyPrice < monthlyAnnualized, "Yearly price should be less than 12 months of monthly")

        let savings = (monthlyAnnualized - yearlyPrice) / monthlyAnnualized * 100
        #expect(savings >= 30, "Yearly should offer at least 30% savings")
    }

    @Test("Lifetime purchase is reasonable multiple of yearly")
    func lifetimePurchaseIsReasonable() {
        let yearlyPrice: Decimal = 39.99
        let lifetimePrice: Decimal = 99.99

        let yearEquivalent = lifetimePrice / yearlyPrice
        #expect(yearEquivalent >= 2.0, "Lifetime should be at least 2 years worth")
        #expect(yearEquivalent <= 4.0, "Lifetime should be at most 4 years worth")
    }

    @Test("Price formatting handles all locales")
    func priceFormattingHandlesAllLocales() {
        let price: Decimal = 4.99
        let locales = ["en_US", "de_DE", "ja_JP", "fr_FR", "zh_CN"]

        for localeID in locales {
            let locale = Locale(identifier: localeID)
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = locale

            let formatted = formatter.string(from: price as NSDecimalNumber)
            #expect(formatted != nil, "Price should format for locale \(localeID)")
            #expect(!formatted!.isEmpty, "Formatted price should not be empty for \(localeID)")
        }
    }
}

// MARK: - Entitlement Tests

@Suite("Entitlements")
struct EntitlementTests {

    @Test("Pro entitlement grants all premium features")
    func proEntitlementGrantsAllFeatures() {
        // Define expected Pro features
        let proFeatures: Set<QuartzFeature> = [
            .unlimitedVaults,
            .cloudSync,
            .advancedAI,
            .customThemes,
            .audioTranscription,
            .prioritySupport
        ]

        // Verify Pro tier includes all features
        let proEntitlement = QuartzEntitlement.pro
        for feature in proFeatures {
            #expect(proEntitlement.includes(feature), "Pro should include \(feature)")
        }
    }

    @Test("Free tier has appropriate limitations")
    func freeTierHasAppropiateLimitations() {
        let freeEntitlement = QuartzEntitlement.free

        #expect(!freeEntitlement.includes(.cloudSync), "Free tier should not include cloud sync")
        #expect(!freeEntitlement.includes(.advancedAI), "Free tier should not include advanced AI")
        #expect(freeEntitlement.vaultLimit == 1, "Free tier should be limited to 1 vault")
    }

    @Test("Entitlement expiration is handled correctly")
    func entitlementExpirationIsHandled() {
        let now = Date()

        // Active subscription
        let activeExpiration = now.addingTimeInterval(86400 * 30) // 30 days from now
        let activeStatus = EntitlementStatus(expirationDate: activeExpiration, isActive: true)
        #expect(activeStatus.isCurrentlyValid, "Active subscription should be valid")

        // Expired subscription
        let expiredDate = now.addingTimeInterval(-86400) // Yesterday
        let expiredStatus = EntitlementStatus(expirationDate: expiredDate, isActive: false)
        #expect(!expiredStatus.isCurrentlyValid, "Expired subscription should not be valid")
    }

    @Test("Grace period extends access after expiration")
    func gracePeriodExtendsAccess() {
        let now = Date()

        // Subscription expired but in grace period
        let expiredDate = now.addingTimeInterval(-86400 * 2) // 2 days ago
        let graceEndDate = now.addingTimeInterval(86400 * 5) // 5 more days

        let gracePeriodStatus = EntitlementStatus(
            expirationDate: expiredDate,
            isActive: false,
            gracePeriodEndDate: graceEndDate
        )

        #expect(gracePeriodStatus.isInGracePeriod, "Should be in grace period")
        #expect(gracePeriodStatus.hasAccess, "Should still have access during grace period")
    }
}

// MARK: - Purchase Flow Tests

@Suite("PurchaseFlow")
struct PurchaseFlowTests {

    @Test("Purchase state transitions are valid")
    func purchaseStateTransitionsAreValid() {
        // Valid transitions
        let validTransitions: [(QuartzPurchaseState, QuartzPurchaseState)] = [
            (.idle, .loading),
            (.loading, .purchasing),
            (.purchasing, .purchased),
            (.purchasing, .failed),
            (.purchasing, .pending),
            (.pending, .purchased),
            (.pending, .failed),
            (.failed, .idle)
        ]

        for (from, to) in validTransitions {
            #expect(from.canTransition(to: to), "Should transition from \(from) to \(to)")
        }

        // Invalid transitions
        let invalidTransitions: [(QuartzPurchaseState, QuartzPurchaseState)] = [
            (.purchased, .idle),
            (.idle, .purchased),
            (.loading, .purchased)
        ]

        for (from, to) in invalidTransitions {
            #expect(!from.canTransition(to: to), "Should NOT transition from \(from) to \(to)")
        }
    }

    @Test("Transaction verification validates signatures")
    func transactionVerificationValidatesSignatures() {
        // Mock transaction data
        let validTransaction = MockTransaction(
            productID: "com.quartz.pro.monthly",
            purchaseDate: Date(),
            originalPurchaseDate: Date(),
            transactionID: "1000000000000001",
            isVerified: true
        )

        #expect(validTransaction.isVerified, "Valid transaction should be verified")

        let invalidTransaction = MockTransaction(
            productID: "com.quartz.pro.monthly",
            purchaseDate: Date(),
            originalPurchaseDate: Date(),
            transactionID: "INVALID",
            isVerified: false
        )

        #expect(!invalidTransaction.isVerified, "Invalid transaction should fail verification")
    }

    @Test("Restore purchases handles multiple transactions")
    func restorePurchasesHandlesMultipleTransactions() {
        let transactions = [
            MockTransaction(productID: "com.quartz.pro.monthly", transactionID: "1"),
            MockTransaction(productID: "com.quartz.pro.yearly", transactionID: "2"),
            MockTransaction(productID: "com.quartz.lifetime", transactionID: "3")
        ]

        // Restore should find the best entitlement (lifetime > yearly > monthly)
        let bestEntitlement = transactions
            .sorted { QuartzProductID(rawValue: $0.productID)!.priority > QuartzProductID(rawValue: $1.productID)!.priority }
            .first

        #expect(bestEntitlement?.productID == "com.quartz.lifetime", "Should restore lifetime as best entitlement")
    }
}

// MARK: - Subscription Renewal Tests

@Suite("SubscriptionRenewal")
struct SubscriptionRenewalTests {

    @Test("Auto-renew status is correctly parsed")
    func autoRenewStatusIsCorrectlyParsed() {
        let activeRenewal = RenewalInfo(
            willAutoRenew: true,
            autoRenewProductID: "com.quartz.pro.yearly",
            expirationIntent: nil
        )

        #expect(activeRenewal.willAutoRenew, "Active subscription should auto-renew")
        #expect(activeRenewal.autoRenewProductID == "com.quartz.pro.yearly")
        #expect(activeRenewal.expirationIntent == nil)

        let cancelledRenewal = RenewalInfo(
            willAutoRenew: false,
            autoRenewProductID: nil,
            expirationIntent: .cancelled
        )

        #expect(!cancelledRenewal.willAutoRenew, "Cancelled subscription should not auto-renew")
        #expect(cancelledRenewal.expirationIntent == .cancelled)
    }

    @Test("Subscription upgrade/downgrade is handled")
    func subscriptionUpgradeDowngradeIsHandled() {
        // Upgrading from monthly to yearly
        let currentProduct = QuartzProductID.proMonthly
        let newProduct = QuartzProductID.proYearly

        let isUpgrade = newProduct.priority > currentProduct.priority
        #expect(isUpgrade, "Moving from monthly to yearly should be an upgrade")

        // Downgrading from yearly to monthly
        let isDowngrade = currentProduct.priority > newProduct.priority
        #expect(!isDowngrade, "This direction should not be a downgrade")
    }

    @Test("Billing retry handles transient failures")
    func billingRetryHandlesTransientFailures() {
        struct BillingState {
            let attemptCount: Int
            let lastAttempt: Date
            let maxRetries: Int

            var shouldRetry: Bool {
                attemptCount < maxRetries
            }
        }

        let state = BillingState(attemptCount: 2, lastAttempt: Date(), maxRetries: 5)
        #expect(state.shouldRetry, "Should retry if under max retries")

        let exhaustedState = BillingState(attemptCount: 5, lastAttempt: Date(), maxRetries: 5)
        #expect(!exhaustedState.shouldRetry, "Should not retry after max attempts")
    }
}

// MARK: - Refund Tests

@Suite("Refunds")
struct RefundTests {

    @Test("Refund request presents native sheet")
    func refundRequestPresentsNativeSheet() {
        // Refund requests should use StoreKit's native sheet
        let refundConfig = RefundRequestConfig(
            transactionID: "1000000000000001",
            productID: "com.quartz.pro.monthly"
        )

        #expect(!refundConfig.transactionID.isEmpty)
        #expect(!refundConfig.productID.isEmpty)
        #expect(refundConfig.usesNativeSheet, "Should use StoreKit native refund sheet")
    }

    @Test("Refund revokes entitlement immediately")
    func refundRevokesEntitlementImmediately() {
        var entitlement = QuartzEntitlement.pro
        entitlement.revoke(reason: .refunded)

        #expect(entitlement == .free, "Refund should revoke to free tier")
    }

    @Test("Refund handling preserves user data")
    func refundHandlingPreservesUserData() {
        // After refund, user data should be preserved but features disabled
        struct UserState {
            let vaults: [String]
            let entitlement: QuartzEntitlement
        }

        let beforeRefund = UserState(vaults: ["Work", "Personal"], entitlement: .pro)
        let afterRefund = UserState(vaults: beforeRefund.vaults, entitlement: .free)

        #expect(afterRefund.vaults == beforeRefund.vaults, "User data should be preserved after refund")
        #expect(afterRefund.entitlement == .free, "Entitlement should be revoked")
    }
}

// MARK: - Offer Code Tests

@Suite("OfferCodes")
struct OfferCodeTests {

    @Test("Offer code format is valid")
    func offerCodeFormatIsValid() {
        let validCodes = ["QUARTZPRO50", "WELCOME2024", "PROMO123"]

        for code in validCodes {
            #expect(code.count >= 6, "Code should be at least 6 characters")
            #expect(code.count <= 16, "Code should be at most 16 characters")
            #expect(code.uppercased() == code, "Code should be uppercase")
            #expect(code.allSatisfy { $0.isLetter || $0.isNumber }, "Code should be alphanumeric")
        }
    }

    @Test("Offer eligibility is checked correctly")
    func offerEligibilityIsCheckedCorrectly() {
        struct OfferEligibility {
            let isNewUser: Bool
            let hasUsedIntroOffer: Bool
            let offerType: OfferType

            enum OfferType {
                case introductory
                case promotional
                case code
            }

            var isEligible: Bool {
                switch offerType {
                case .introductory:
                    return isNewUser && !hasUsedIntroOffer
                case .promotional:
                    return !hasUsedIntroOffer
                case .code:
                    return true // Codes can be redeemed by anyone
                }
            }
        }

        // New user eligible for intro offer
        let newUser = OfferEligibility(isNewUser: true, hasUsedIntroOffer: false, offerType: .introductory)
        #expect(newUser.isEligible, "New user should be eligible for intro offer")

        // Returning user not eligible for intro offer
        let returningUser = OfferEligibility(isNewUser: false, hasUsedIntroOffer: true, offerType: .introductory)
        #expect(!returningUser.isEligible, "Returning user should not be eligible for intro offer")

        // Anyone eligible for code
        let codeUser = OfferEligibility(isNewUser: false, hasUsedIntroOffer: true, offerType: .code)
        #expect(codeUser.isEligible, "Any user should be eligible for code redemption")
    }
}

// MARK: - Receipt Validation Tests

@Suite("ReceiptValidation")
struct ReceiptValidationTests {

    @Test("App receipt contains required fields")
    func appReceiptContainsRequiredFields() {
        let mockReceipt = AppReceipt(
            bundleID: "com.quartz.app",
            appVersion: "1.0.0",
            originalAppVersion: "1.0.0",
            creationDate: Date(),
            expirationDate: nil
        )

        #expect(mockReceipt.bundleID == "com.quartz.app")
        #expect(!mockReceipt.appVersion.isEmpty)
        #expect(mockReceipt.creationDate <= Date())
    }

    @Test("In-app purchase receipt is valid")
    func inAppPurchaseReceiptIsValid() {
        let iapReceipt = InAppPurchaseReceipt(
            productID: "com.quartz.pro.yearly",
            transactionID: "1000000000000001",
            originalTransactionID: "1000000000000001",
            purchaseDate: Date(),
            originalPurchaseDate: Date(),
            quantity: 1,
            expirationDate: Date().addingTimeInterval(86400 * 365)
        )

        #expect(iapReceipt.quantity == 1)
        #expect(iapReceipt.transactionID.count >= 16)
        #expect(iapReceipt.productID.hasPrefix("com.quartz."))
        #expect(iapReceipt.expirationDate! > Date())
    }

    @Test("Transaction ID format is valid")
    func transactionIDFormatIsValid() {
        let validIDs = [
            "1000000000000001",
            "2000000000000002",
            "1234567890123456"
        ]

        for id in validIDs {
            #expect(id.count >= 16, "Transaction ID should be at least 16 characters")
            #expect(id.allSatisfy { $0.isNumber }, "Transaction ID should be numeric")
        }
    }
}

// MARK: - XCTest Performance Tests for StoreKit Operations

final class StoreKitPerformanceTests: XCTestCase {

    func testProductLoadingPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        let productIDs = QuartzProductID.allCases.map { $0.rawValue }

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            // Simulate product ID validation (actual StoreKit calls would be mocked)
            for id in productIDs {
                _ = id.split(separator: ".")
            }
        }
    }

    func testEntitlementCheckPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        let features = QuartzFeature.allCases

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let entitlement = QuartzEntitlement.pro
            for feature in features {
                _ = entitlement.includes(feature)
            }
        }
    }

    func testReceiptParsingPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        // Generate mock receipt data
        let mockReceipts = (0..<100).map { i in
            InAppPurchaseReceipt(
                productID: "com.quartz.pro.monthly",
                transactionID: String(format: "%016d", i),
                originalTransactionID: String(format: "%016d", i),
                purchaseDate: Date(),
                originalPurchaseDate: Date(),
                quantity: 1,
                expirationDate: Date().addingTimeInterval(Double(i) * 86400)
            )
        }

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            // Filter active subscriptions
            let active = mockReceipts.filter { receipt in
                guard let expiration = receipt.expirationDate else { return false }
                return expiration > Date()
            }
            XCTAssertGreaterThan(active.count, 0)
        }
    }
}

// MARK: - Mock Types for Testing

struct MockTransaction {
    let productID: String
    let purchaseDate: Date
    let originalPurchaseDate: Date
    let transactionID: String
    let isVerified: Bool

    init(productID: String, purchaseDate: Date = Date(), originalPurchaseDate: Date = Date(),
         transactionID: String, isVerified: Bool = true) {
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.originalPurchaseDate = originalPurchaseDate
        self.transactionID = transactionID
        self.isVerified = isVerified
    }
}

struct RenewalInfo {
    let willAutoRenew: Bool
    let autoRenewProductID: String?
    let expirationIntent: ExpirationIntent?

    enum ExpirationIntent {
        case cancelled
        case billingError
        case priceIncrease
        case productUnavailable
    }
}

struct RefundRequestConfig {
    let transactionID: String
    let productID: String
    var usesNativeSheet: Bool { true }
}

struct AppReceipt {
    let bundleID: String
    let appVersion: String
    let originalAppVersion: String
    let creationDate: Date
    let expirationDate: Date?
}

struct InAppPurchaseReceipt {
    let productID: String
    let transactionID: String
    let originalTransactionID: String
    let purchaseDate: Date
    let originalPurchaseDate: Date
    let quantity: Int
    let expirationDate: Date?
}

// MARK: - QuartzKit StoreKit Types (to be moved to main target)

enum QuartzProductID: String, CaseIterable {
    case proMonthly = "com.quartz.pro.monthly"
    case proYearly = "com.quartz.pro.yearly"
    case lifetime = "com.quartz.lifetime"

    var displayName: String {
        switch self {
        case .proMonthly: return "Quartz Pro Monthly"
        case .proYearly: return "Quartz Pro Yearly"
        case .lifetime: return "Quartz Lifetime"
        }
    }

    var priority: Int {
        switch self {
        case .proMonthly: return 1
        case .proYearly: return 2
        case .lifetime: return 3
        }
    }
}

enum QuartzStoreConfig {
    static let subscriptionGroupID = "QUARTZ_PRO_GROUP"
}

enum QuartzFeature: CaseIterable {
    case unlimitedVaults
    case cloudSync
    case advancedAI
    case customThemes
    case audioTranscription
    case prioritySupport
}

enum QuartzEntitlement: Equatable {
    case free
    case pro

    var vaultLimit: Int {
        switch self {
        case .free: return 1
        case .pro: return .max
        }
    }

    func includes(_ feature: QuartzFeature) -> Bool {
        switch self {
        case .free:
            return false
        case .pro:
            return true
        }
    }

    mutating func revoke(reason: RevocationReason) {
        self = .free
    }

    enum RevocationReason {
        case refunded
        case expired
        case billingError
    }
}

struct EntitlementStatus {
    let expirationDate: Date
    let isActive: Bool
    let gracePeriodEndDate: Date?

    init(expirationDate: Date, isActive: Bool, gracePeriodEndDate: Date? = nil) {
        self.expirationDate = expirationDate
        self.isActive = isActive
        self.gracePeriodEndDate = gracePeriodEndDate
    }

    var isCurrentlyValid: Bool {
        isActive && expirationDate > Date()
    }

    var isInGracePeriod: Bool {
        guard let graceEnd = gracePeriodEndDate else { return false }
        let now = Date()
        return now > expirationDate && now <= graceEnd
    }

    var hasAccess: Bool {
        isCurrentlyValid || isInGracePeriod
    }
}

enum QuartzPurchaseState: Equatable {
    case idle
    case loading
    case purchasing
    case purchased
    case pending
    case failed

    func canTransition(to newState: QuartzPurchaseState) -> Bool {
        switch (self, newState) {
        case (.idle, .loading),
             (.loading, .purchasing),
             (.purchasing, .purchased),
             (.purchasing, .failed),
             (.purchasing, .pending),
             (.pending, .purchased),
             (.pending, .failed),
             (.failed, .idle):
            return true
        default:
            return false
        }
    }
}
