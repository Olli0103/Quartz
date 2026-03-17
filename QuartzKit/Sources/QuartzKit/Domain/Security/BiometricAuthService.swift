import Foundation
import LocalAuthentication

/// Service for biometric authentication (FaceID/TouchID).
///
/// Supports:
/// - App launch lock
/// - Folder lock for sensitive areas
/// - Fallback to device passcode
public actor BiometricAuthService {
    /// Available biometry types.
    public enum BiometryType: Sendable {
        case faceID
        case touchID
        case opticID
        case passcodeOnly
        case none
    }

    /// Result of an authentication.
    public enum AuthResult: Sendable {
        case success
        case cancelled
        case failed(String)
    }

    public init() {}

    /// Checks which biometry type is available.
    public func availableBiometry() -> BiometryType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Check if at least passcode is available
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

    /// Performs biometric authentication.
    ///
    /// - Parameter reason: The reason for authentication (shown to the user)
    /// - Returns: AuthResult with success or failure
    public func authenticate(reason: String? = nil) async -> AuthResult {
        let localizedReason = reason ?? String(localized: "Unlock Quartz", bundle: .module)
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel", bundle: .module)
        context.localizedFallbackTitle = String(localized: "Use Passcode", bundle: .module)

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // Biometry + passcode fallback
                localizedReason: localizedReason
            )

            return success ? .success : .failed(String(localized: "Authentication failed.", bundle: .module))
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .biometryNotAvailable:
                return .failed(String(localized: "Biometry is not available on this device.", bundle: .module))
            case .biometryNotEnrolled:
                return .failed(String(localized: "No biometric data enrolled. Please set up Face ID or Touch ID.", bundle: .module))
            case .biometryLockout:
                return .failed(String(localized: "Biometry is locked. Please use your passcode.", bundle: .module))
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Checks whether biometry is available and set up.
    public func isBiometryAvailable() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}
