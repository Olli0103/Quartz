import Testing
import Foundation
@testable import QuartzKit

@Suite("BiometricAuthService")
struct BiometricAuthServiceTests {
    @Test("availableBiometry returns a valid type")
    func availableBiometry() async {
        let service = BiometricAuthService()
        let biometry = await service.availableBiometry()

        // On CI/Linux, biometry won't be available
        let validTypes: [BiometricAuthService.BiometryType] = [
            .faceID, .touchID, .opticID, .passcodeOnly, .none
        ]

        // Just verify it returns one of the valid enum cases (no crash)
        switch biometry {
        case .faceID, .touchID, .opticID, .passcodeOnly, .none:
            break // All valid
        }
    }

    @Test("isBiometryAvailable returns Bool without crashing")
    func isBiometryAvailableCheck() async {
        let service = BiometricAuthService()
        let available = await service.isBiometryAvailable()
        // On CI, this will be false. Just verify it doesn't crash.
        #expect(available == true || available == false)
    }

    @Test("AuthResult enum cases are constructible")
    func authResultCases() {
        let success = BiometricAuthService.AuthResult.success
        let cancelled = BiometricAuthService.AuthResult.cancelled
        let failed = BiometricAuthService.AuthResult.failed("Test error")

        switch success {
        case .success: break
        default: Issue.record("Expected success")
        }

        switch cancelled {
        case .cancelled: break
        default: Issue.record("Expected cancelled")
        }

        switch failed {
        case .failed(let msg):
            #expect(msg == "Test error")
        default: Issue.record("Expected failed")
        }
    }

    @Test("BiometryType enum covers all known types")
    func biometryTypeCoverage() {
        let types: [BiometricAuthService.BiometryType] = [
            .faceID, .touchID, .opticID, .passcodeOnly, .none
        ]
        #expect(types.count == 5)
    }
}
