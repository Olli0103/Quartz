import Foundation
import LocalAuthentication

/// Service für biometrische Authentifizierung (FaceID/TouchID).
///
/// Unterstützt:
/// - App-Start-Lock
/// - Ordner-Lock für sensible Bereiche
/// - Fallback auf Geräte-Passcode
public actor BiometricAuthService {
    /// Verfügbare Biometrie-Typen.
    public enum BiometryType: Sendable {
        case faceID
        case touchID
        case opticID
        case passcodeOnly
        case none
    }

    /// Ergebnis einer Authentifizierung.
    public enum AuthResult: Sendable {
        case success
        case cancelled
        case failed(String)
    }

    public init() {}

    /// Prüft welcher Biometrie-Typ verfügbar ist.
    public func availableBiometry() -> BiometryType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Prüfe ob zumindest Passcode möglich ist
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return .passcodeOnly
            }
            return .none
        }

        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        @unknown default: return .passcodeOnly
        }
    }

    /// Führt biometrische Authentifizierung durch.
    ///
    /// - Parameter reason: Der Grund der Authentifizierung (wird dem User angezeigt)
    /// - Returns: AuthResult mit Erfolg oder Fehler
    public func authenticate(reason: String = "Unlock Quartz") async -> AuthResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // Biometrie + Passcode-Fallback
                localizedReason: reason
            )

            return success ? .success : .failed("Authentication failed")
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .biometryNotAvailable:
                return .failed("Biometry is not available on this device.")
            case .biometryNotEnrolled:
                return .failed("No biometric data enrolled. Please set up Face ID or Touch ID.")
            case .biometryLockout:
                return .failed("Biometry is locked. Please use your passcode.")
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Prüft ob Biometrie verfügbar und eingerichtet ist.
    public func isBiometryAvailable() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}
