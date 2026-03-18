import SwiftUI

/// A button that checks GitHub Releases for a newer Quartz version.
struct UpdateCheckButton: View {
    @State private var isChecking = false
    @State private var updateInfo: UpdateChecker.ReleaseInfo?
    @State private var noUpdateFound = false

    var body: some View {
        VStack(spacing: 8) {
            if let info = updateInfo {
                VStack(spacing: 6) {
                    Label(
                        String(localized: "Quartz \(info.version) is available!", bundle: .module),
                        systemImage: "arrow.down.circle.fill"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(QuartzColors.accent)

                    Link(destination: info.downloadURL) {
                        Text(String(localized: "Download", bundle: .module))
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(QuartzColors.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Button {
                    checkForUpdate()
                } label: {
                    HStack(spacing: 6) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(noUpdateFound
                             ? String(localized: "You're up to date", bundle: .module)
                             : String(localized: "Check for Updates", bundle: .module))
                    }
                    .font(.callout)
                }
                .disabled(isChecking)
                .buttonStyle(.plain)
                .foregroundStyle(noUpdateFound ? .secondary : QuartzColors.accent)
            }
        }
    }

    private func checkForUpdate() {
        isChecking = true
        noUpdateFound = false
        Task {
            let result = await UpdateChecker.shared.forceCheck()
            await MainActor.run {
                isChecking = false
                if let result {
                    updateInfo = result
                } else {
                    noUpdateFound = true
                }
            }
        }
    }
}
