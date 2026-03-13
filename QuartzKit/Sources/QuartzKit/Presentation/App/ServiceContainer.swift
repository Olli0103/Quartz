import Foundation

/// Leichtgewichtiger Service-Container für Dependency Injection.
///
/// Registriert und liefert Service-Instanzen. Singleton-Pattern.
/// Kein Third-Party-DI-Framework – reines Swift.
///
/// Alle Registrierungen sollten vor der ersten Resolution erfolgen.
/// Da der Container `@MainActor` ist, ist Thread-Safety durch
/// Actor-Isolation garantiert.
@MainActor
public final class ServiceContainer {
    public static let shared = ServiceContainer()

    private var vaultProvider: (any VaultProviding)?
    private var frontmatterParser: (any FrontmatterParsing)?
    private var featureGate: (any FeatureGating)?
    private var isBootstrapped = false

    private init() {}

    // MARK: - Bulk Registration

    /// Registriert alle Services auf einmal. Sollte beim App-Start
    /// aufgerufen werden, bevor Services aufgelöst werden.
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
