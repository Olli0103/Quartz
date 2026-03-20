import Foundation

/// Lightweight service container for dependency injection.
///
/// Registers and provides service instances. Supports both
/// singleton access via `shared` and direct instantiation for testing.
///
/// All registrations should occur before the first resolution.
/// Since the container is `@MainActor`, thread safety is guaranteed
/// through actor isolation.
@MainActor
public final class ServiceContainer {
    public static let shared = ServiceContainer()

    private var vaultProvider: (any VaultProviding)?
    private var frontmatterParser: (any FrontmatterParsing)?
    private var isBootstrapped = false

    /// Creates a new container. Use `shared` for production;
    /// call this directly in tests for isolated instances.
    public init() {}

    // MARK: - Bulk Registration

    /// Registers all services at once. Should be called at app launch
    /// before services are resolved.
    public func bootstrap(
        vaultProvider: (any VaultProviding)? = nil,
        frontmatterParser: (any FrontmatterParsing)? = nil
    ) {
        if let vaultProvider { self.vaultProvider = vaultProvider }
        if let frontmatterParser { self.frontmatterParser = frontmatterParser }
        isBootstrapped = true
    }

    /// Resets all registrations. Intended for test teardown only.
    public func reset() {
        vaultProvider = nil
        frontmatterParser = nil
        isBootstrapped = false
    }

    // MARK: - Registration

    public func register(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    public func register(frontmatterParser: any FrontmatterParsing) {
        self.frontmatterParser = frontmatterParser
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
}
