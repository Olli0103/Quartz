import SwiftUI
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Security settings: App Lock via biometric authentication.
public struct SecuritySettingsView: View {
    @AppStorage("quartz.appLockEnabled") private var appLockEnabled = false
    @State private var biometryLabel: String = ""
    @State private var biometryAvailable: Bool = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $appLockEnabled) {
                    Text(String(localized: "Require App Lock", bundle: .module))
                }
                .disabled(!biometryAvailable)
            } header: {
                Text(String(localized: "Authentication", bundle: .module))
            } footer: {
                if biometryAvailable {
                    Text("Require \(biometryLabel) to unlock Quartz on launch.")
                } else {
                    Text(String(localized: "Set up Face ID or Touch ID in System Settings to enable App Lock.", bundle: .module))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Security", bundle: .module))
        .task { checkBiometry() }
    }

    private func checkBiometry() {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        biometryAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: nil
        )
        biometryLabel = switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        @unknown default: "biometric authentication"
        }
        #endif
    }
}
