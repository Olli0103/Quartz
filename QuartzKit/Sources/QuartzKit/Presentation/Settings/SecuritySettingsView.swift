import SwiftUI
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Timeout duration options for the app lock.
private enum LockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .immediately: String(localized: "Immediately", bundle: .module)
        case .oneMinute: String(localized: "1 Minute", bundle: .module)
        case .fiveMinutes: String(localized: "5 Minutes", bundle: .module)
        case .fifteenMinutes: String(localized: "15 Minutes", bundle: .module)
        }
    }
}

/// Security settings: App Lock via biometric authentication with configurable timeout.
public struct SecuritySettingsView: View {
    let orchestrator: SecurityOrchestrator

    @State private var biometryAvailable: Bool = false

    public init(orchestrator: SecurityOrchestrator = .shared) {
        self.orchestrator = orchestrator
    }

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { orchestrator.isAppLockEnabled },
                    set: { orchestrator.isAppLockEnabled = $0 }
                )) {
                    Label {
                        Text(String(localized: "Require \(orchestrator.biometryLabel)", bundle: .module))
                    } icon: {
                        Image(systemName: orchestrator.biometryIconName)
                    }
                }
                .disabled(!biometryAvailable)
                .tint(QuartzColors.accent)
            } header: {
                Text(String(localized: "Authentication", bundle: .module))
            } footer: {
                if biometryAvailable {
                    Text(String(localized: "Lock Quartz with \(orchestrator.biometryLabel) when inactive. Your notes stay private even if someone else picks up your device.", bundle: .module))
                } else {
                    Text(String(localized: "Set up Face ID or Touch ID in System Settings to enable App Lock.", bundle: .module))
                }
            }

            if orchestrator.isAppLockEnabled {
                Section {
                    Picker(selection: Binding(
                        get: { orchestrator.lockTimeoutMinutes },
                        set: { orchestrator.lockTimeoutMinutes = $0 }
                    )) {
                        ForEach(LockTimeout.allCases) { timeout in
                            Text(timeout.label).tag(timeout.rawValue)
                        }
                    } label: {
                        Label(String(localized: "Lock After", bundle: .module), systemImage: "clock")
                    }
                } header: {
                    Text(String(localized: "Timeout", bundle: .module))
                } footer: {
                    Text(String(localized: "How long Quartz can be in the background before requiring authentication again.", bundle: .module))
                }

                Section {
                    Button {
                        orchestrator.lock()
                    } label: {
                        Label(String(localized: "Lock Now", bundle: .module), systemImage: "lock.fill")
                    }
                } footer: {
                    Text(String(localized: "Immediately lock the app. You'll need to authenticate to continue.", bundle: .module))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Security", bundle: .module))
        .task { checkBiometry() }
    }

    private func checkBiometry() {
        biometryAvailable = orchestrator.isAuthenticationAvailable
    }
}
