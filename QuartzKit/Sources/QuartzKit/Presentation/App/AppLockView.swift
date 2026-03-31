import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen lock overlay that redacts all app content when the app is locked.
///
/// **Security guarantees**:
/// - `.regularMaterial` blur completely obscures note text underneath
/// - `.allowsHitTesting(false)` on the content layer prevents interaction
/// - Covers the entire window bounds (including macOS App Switcher thumbnails)
/// - Auto-triggers biometric prompt on appear
///
/// **Design**: Matches the Liquid Glass aesthetic with a centered lock icon,
/// app name, and a prominent "Unlock" button.
public struct AppLockView: View {
    let orchestrator: SecurityOrchestrator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var didAutoPrompt = false

    public init(orchestrator: SecurityOrchestrator) {
        self.orchestrator = orchestrator
    }

    public var body: some View {
        ZStack {
            // Full-screen redaction layer — heavy material blur
            Rectangle()
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
                .ignoresSafeArea()

            // Lock content
            VStack(spacing: 0) {
                Spacer()

                // Icon
                Image(systemName: orchestrator.biometryIconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.bottom, 20)

                // Title
                Text(String(localized: "Quartz is Locked", bundle: .module))
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 6)

                Text(String(localized: "Authenticate to access your notes", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Error message
                if let error = orchestrator.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                        .transition(.opacity)
                        .accessibilityLabel(String(localized: "Authentication error: \(error)", bundle: .module))
                }

                Spacer()

                // Unlock button
                Button {
                    Task { await orchestrator.authenticate() }
                } label: {
                    HStack(spacing: 8) {
                        if orchestrator.isAuthenticating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: orchestrator.biometryIconName)
                        }
                        Text(String(localized: "Unlock", bundle: .module))
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.gradient)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(orchestrator.isAuthenticating)
                .accessibilityLabel(String(localized: "Unlock Quartz", bundle: .module))
                .accessibilityHint(String(localized: "Double tap to authenticate with \(orchestrator.biometryLabel)", bundle: .module))

                Spacer()
                    .frame(height: 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(String(localized: "App is locked", bundle: .module))
        .task {
            // Auto-prompt biometric authentication on first appear
            guard !didAutoPrompt else { return }
            didAutoPrompt = true
            // Small delay so the UI renders before the system auth dialog appears
            try? await Task.sleep(for: .milliseconds(300))
            await orchestrator.authenticate()
        }
    }
}
