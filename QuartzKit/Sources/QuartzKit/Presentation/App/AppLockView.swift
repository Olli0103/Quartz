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

            if !isUnlocked {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isUnlocked)
        .task {
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
                Text(String(localized: "Quartz is Locked"))
                    .font(.title2.bold())
                Text(String(localized: "Authenticate to access your notes"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                Task { await authenticate() }
            } label: {
                Label(String(localized: "Unlock"), systemImage: biometryIcon)
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

    private var biometryIcon: String {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        @unknown default:
            return "lock.fill"
        }
        #else
        return "lock.fill"
        #endif
    }

    private func authenticate() async {
        isAuthenticating = true
        errorMessage = nil

        let result = await authService.authenticate(reason: String(localized: "Unlock Quartz to access your notes"))

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
