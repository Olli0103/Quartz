import SwiftUI

/// Overlay banner shown when the currently-open note has an iCloud sync conflict.
///
/// Provides quick resolution actions (Keep Mine, Keep Theirs) for the 90% case,
/// and a "View Diff" button that escalates to the full ConflictResolverView.
///
/// Follows the same visual pattern as `externalModificationBanner` in `EditorContainerView`.
///
/// **Ref:** Phase G Spec — Sync Conflict Banner
struct SyncConflictBanner: View {
    var onKeepMine: () -> Void
    var onKeepTheirs: () -> Void
    var onViewDiff: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)

            Text(String(localized: "This note has a sync conflict.", bundle: .module))
                .font(.callout)

            Spacer()

            Button(String(localized: "Keep Mine", bundle: .module)) {
                QuartzFeedback.success()
                onKeepMine()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(String(localized: "Keep Theirs", bundle: .module)) {
                QuartzFeedback.success()
                onKeepTheirs()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(String(localized: "View Diff", bundle: .module)) {
                QuartzFeedback.primaryAction()
                onViewDiff()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .quartzMaterialBackground(cornerRadius: 12, shadowRadius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Sync conflict detected for this note", bundle: .module))
    }
}
