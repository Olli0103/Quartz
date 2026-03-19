import SwiftUI
import StoreKit

/// Support tiers for one-time and subscription purchases.
public enum SupportTier: String, CaseIterable {
    case bronze
    case silver
    case gold

    var productID: String {
        switch self {
        case .bronze: "olli.Quartz.support.bronze"
        case .silver: "olli.Quartz.support.silver"
        case .gold: "olli.Quartz.support.gold"
        }
    }

    var displayName: String {
        switch self {
        case .bronze: String(localized: "Bronze", bundle: .module)
        case .silver: String(localized: "Silver", bundle: .module)
        case .gold: String(localized: "Gold", bundle: .module)
        }
    }

    var priceLabel: String {
        switch self {
        case .bronze: "€1.99"
        case .silver: "€4.99"
        case .gold: "€1.49/mo"
        }
    }

    var description: String {
        switch self {
        case .bronze: String(localized: "One-time support", bundle: .module)
        case .silver: String(localized: "One-time support", bundle: .module)
        case .gold: String(localized: "Monthly subscription", bundle: .module)
        }
    }

    var isSubscription: Bool { self == .gold }
}

/// "Support My Work" sheet with GitHub Sponsors link and in-app purchase tiers.
public struct SupportView: View {
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.dismiss) private var dismiss
    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var purchaseError: String?
    @State private var purchasingTier: SupportTier?

    private static let githubSponsorsURL = URL(string: "https://github.com/sponsors/Olli0103")!

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    githubSection
                    inAppPurchaseSection
                }
                .padding(24)
            }
            .navigationTitle(String(localized: "Support My Work", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
            .task { await loadProducts() }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(appearance.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Support Quartz", bundle: .module))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "Help keep development going with a one-time tip or monthly support.", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(appearance.accentColor.opacity(0.08)))
        }
    }

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "GitHub Sponsors", bundle: .module))
                .font(.headline)
            Link(destination: Self.githubSponsorsURL) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Sponsor on GitHub", bundle: .module))
                            .font(.body.weight(.medium))
                        Text(String(localized: "Support via GitHub Sponsors", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var inAppPurchaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "In-App Purchase", bundle: .module))
                .font(.headline)

            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text(String(localized: "Loading…", bundle: .module))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    ForEach(SupportTier.allCases, id: \.rawValue) { tier in
                        tierRow(tier: tier)
                    }
                }
            }
        }
    }

    private func tierRow(tier: SupportTier) -> some View {
        let product = products.first { $0.id == tier.productID }
        let displayPrice = product?.displayPrice ?? tier.priceLabel
        let isThisPurchasing = purchasingTier == tier

        return Button {
            Task { await purchase(tier: tier, product: product) }
        } label: {
            HStack(spacing: 16) {
                tierIcon(tier)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.body.weight(.semibold))
                    Text(tier.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isThisPurchasing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(displayPrice)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appearance.accentColor)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .disabled(product == nil || purchasingTier != nil)
    }

    private func tierIcon(_ tier: SupportTier) -> some View {
        let color: Color = switch tier {
        case .bronze: Color(hex: 0xCD7F32)
        case .silver: Color(hex: 0xC0C0C0)
        case .gold: Color(hex: 0xFFD700)
        }
        return Circle()
            .fill(color.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: tier == .gold ? "crown.fill" : "star.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
    }

    private func loadProducts() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            products = try await Product.products(for: SupportTier.allCases.map(\.productID))
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func purchase(tier: SupportTier, product: Product?) async {
        guard let product else {
            purchaseError = String(localized: "Product not available. Configure in App Store Connect.", bundle: .module)
            return
        }
        purchasingTier = tier
        purchaseError = nil
        defer { purchasingTier = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                dismiss()
            case .userCancelled:
                break
            case .pending:
                purchaseError = String(localized: "Purchase pending approval.", bundle: .module)
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
