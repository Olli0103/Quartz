import Foundation

/// Leichtgewichtiger Service-Container für Dependency Injection.
///
/// Registriert und liefert Service-Instanzen. Singleton-Pattern.
/// Kein Third-Party-DI-Framework – reines Swift.
@MainActor
public final class ServiceContainer {
    public static let shared = ServiceContainer()

    private var vaultProvider: (any VaultProviding)?
    private var frontmatterParser: (any FrontmatterParsing)?
    private var featureGate: (any FeatureGating)?

    private init() {}

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
        guard let provider = vaultProvider else {
            let parser = resolveFrontmatterParser()
            let provider = FileSystemVaultProvider(frontmatterParser: parser)
            self.vaultProvider = provider
            return provider
        }
        return provider
    }

    public func resolveFrontmatterParser() -> any FrontmatterParsing {
        frontmatterParser ?? {
            let parser = FrontmatterParser()
            self.frontmatterParser = parser
            return parser
        }()
    }

    public func resolveFeatureGate() -> any FeatureGating {
        featureGate ?? {
            let gate = DefaultFeatureGate()
            self.featureGate = gate
            return gate
        }()
    }
}
