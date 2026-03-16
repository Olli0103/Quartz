import SwiftUI
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// App-Lock Screen: Zeigt Biometrie-Prompt beim App-Start.
///
/// Wird als Overlay über die gesamte App gelegt wenn
/// App-Lock aktiviert ist. Verschwindet nach erfolgreicher
/// Authentifizierung.
public struct AppLockView<Content: View>: View {
    @State private var isUnlocked: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?
    @State private var biometryIcon: String = "lock.fill"

    let authService: BiometricAuthService
    let content: Content

    public init(
        authService: BiometricAuthService,
        @ViewBuilder content: () -> Content
    ) {
        self.authService = authService
        self.content = content()
    }

    public var body: some View {
        ZStack {
            content
                .disabled(!isUnlocked)
                .blur(radius: isUnlocked ? 0 : 20)
                .accessibilityHidden(!isUnlocked)

            if !isUnlocked {
                lockScreen
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isUnlocked)
        .task {
            resolveBiometryIcon()
            await authenticate()
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: biometryIcon)
                .font(.largeTitle)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text(String(localized: "Quartz is Locked", bundle: .module))
                    .font(.title2.bold())
                Text(String(localized: "Authenticate to access your notes", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Spacer()

            Button {
                Task { await authenticate() }
            } label: {
                Label(String(localized: "Unlock", bundle: .module), systemImage: biometryIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .disabled(isAuthenticating)

            Spacer()
                .frame(height: 48)
        }
        .background(.ultraThinMaterial)
    }

    private func resolveBiometryIcon() {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        biometryIcon = switch context.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        @unknown default: "lock.fill"
        }
        #endif
    }

    private func authenticate() async {
        isAuthenticating = true
        errorMessage = nil

        let result = await authService.authenticate(reason: String(localized: "Unlock Quartz to access your notes", bundle: .module))

        switch result {
        case .success:
            withAnimation {
                isUnlocked = true
            }
        case .cancelled:
            break
        case .failed(let message):
            errorMessage = message
        }

        isAuthenticating = false
    }
}
