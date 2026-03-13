import SwiftUI

/// App-Lock Screen: Zeigt Biometrie-Prompt beim App-Start.
///
/// Wird als Overlay über die gesamte App gelegt wenn
/// App-Lock aktiviert ist. Verschwindet nach erfolgreicher
/// Authentifizierung.
public struct AppLockView: View {
    @State private var isUnlocked: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?

    let authService: BiometricAuthService
    let content: AnyView

    public init<Content: View>(
        authService: BiometricAuthService,
        @ViewBuilder content: () -> Content
    ) {
        self.authService = authService
        self.content = AnyView(content())
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
        .animation(.easeInOut(duration: 0.3), value: isUnlocked)
        .task {
            await authenticate()
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: biometryIcon)
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Quartz is Locked")
                    .font(.title2.bold())
                Text("Authenticate to access your notes")
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
                Label("Unlock", systemImage: biometryIcon)
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
        // Wird zur Laufzeit basierend auf Geräte-Biometrie bestimmt
        "faceid" // Default, könnte auch touchid oder opticid sein
    }

    private func authenticate() async {
        isAuthenticating = true
        errorMessage = nil

        let result = await authService.authenticate(reason: "Unlock Quartz to access your notes")

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
