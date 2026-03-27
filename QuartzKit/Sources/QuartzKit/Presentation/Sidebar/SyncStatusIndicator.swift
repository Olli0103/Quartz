import SwiftUI

/// Tiny cloud icon indicating iCloud sync status.
///
/// Embedded in the sidebar's floating search bar. Maps `CloudSyncStatus`
/// to SF Symbols with semantic colors. Uses `symbolEffect(.pulse)` for
/// active sync states (auto-respects Reduce Motion).
///
/// **Ref:** Phase G Spec — Sync Status Indicator
public struct SyncStatusIndicator: View {
    let status: CloudSyncStatus
    var onTap: (() -> Void)?

    public init(status: CloudSyncStatus, onTap: (() -> Void)? = nil) {
        self.status = status
        self.onTap = onTap
    }

    public var body: some View {
        if status != .notApplicable {
            Button {
                QuartzFeedback.selection()
                onTap?()
            } label: {
                image
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(tooltipText)
            #endif
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(String(localized: "Tap to open sync settings", bundle: .module))
            .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private var image: some View {
        switch status {
        case .current:
            Image(systemName: "checkmark.icloud.fill")
        case .uploading:
            Image(systemName: "icloud.and.arrow.up")
                .symbolEffect(.pulse.byLayer)
        case .downloading, .notDownloaded:
            Image(systemName: "icloud.and.arrow.down")
                .symbolEffect(.pulse.byLayer)
        case .conflict:
            Image(systemName: "exclamationmark.icloud.fill")
        case .error:
            Image(systemName: "xmark.icloud.fill")
        case .notApplicable:
            EmptyView()
        }
    }

    private var iconColor: Color {
        switch status {
        case .current: .green
        case .uploading, .downloading, .notDownloaded: .blue
        case .conflict: .orange
        case .error: .red
        case .notApplicable: .clear
        }
    }

    private var tooltipText: String {
        switch status {
        case .current: String(localized: "iCloud: All files synced", bundle: .module)
        case .uploading: String(localized: "iCloud: Uploading changes…", bundle: .module)
        case .downloading, .notDownloaded: String(localized: "iCloud: Downloading changes…", bundle: .module)
        case .conflict: String(localized: "iCloud: Sync conflict detected", bundle: .module)
        case .error: String(localized: "iCloud: Sync error", bundle: .module)
        case .notApplicable: ""
        }
    }

    private var accessibilityText: String {
        switch status {
        case .current: String(localized: "iCloud sync: synced", bundle: .module)
        case .uploading: String(localized: "iCloud sync: uploading", bundle: .module)
        case .downloading, .notDownloaded: String(localized: "iCloud sync: downloading", bundle: .module)
        case .conflict: String(localized: "iCloud sync: conflict detected", bundle: .module)
        case .error: String(localized: "iCloud sync: error", bundle: .module)
        case .notApplicable: ""
        }
    }
}
