import Foundation

/// Lightweight service container for dependency injection.
///
/// Registers and provides service instances. Singleton pattern.
/// No third-party DI framework – pure Swift.
///
/// All registrations should occur before the first resolution.
/// Since the container is `@MainActor`, thread safety is guaranteed
/// through actor isolation.
@MainActor
public final class ServiceContainer {
    public static let shared = ServiceContainer()

    private var vaultProvider: (any VaultProviding)?
    private var frontmatterParser: (any FrontmatterParsing)?
    private var featureGate: (any FeatureGating)?
    private var isBootstrapped = false

    private init() {}

    // MARK: - Bulk Registration

    /// Registers all services at once. Should be called at app launch
    /// before services are resolved.
    public func bootstrap(
        vaultProvider: (any VaultProviding)? = nil,
        frontmatterParser: (any FrontmatterParsing)? = nil,
        featureGate: (any FeatureGating)? = nil
    ) {
        if let vaultProvider { self.vaultProvider = vaultProvider }
        if let frontmatterParser { self.frontmatterParser = frontmatterParser }
        if let featureGate { self.featureGate = featureGate }
        isBootstrapped = true
    }

    // MARK: - Registration

    public func register(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    public func register(frontmatterParser: any FrontmatterParsing) {
        self.frontmatterParser = frontmatterParser
    }

    public func register(featureGate: any FeatureGating) {
        self.featureGate = featureGate
    }

    // MARK: - Resolution

    public func resolveVaultProvider() -> any VaultProviding {
        if let provider = vaultProvider {
            return provider
        }
        let parser = resolveFrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        self.vaultProvider = provider
        return provider
    }

    public func resolveFrontmatterParser() -> any FrontmatterParsing {
        if let parser = frontmatterParser {
            return parser
        }
        let parser = FrontmatterParser()
        self.frontmatterParser = parser
        return parser
    }

    public func resolveFeatureGate() -> any FeatureGating {
        if let gate = featureGate {
            return gate
        }
        let gate = DefaultFeatureGate()
        self.featureGate = gate
        return gate
    }
}
