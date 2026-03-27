import SwiftUI

/// iCloud sync status and controls for the Data & Sync settings panel.
///
/// Shows different content based on vault location:
/// - **Local vault**: Shows "Enable iCloud Sync" button that migrates the vault to iCloud
/// - **iCloud vault**: Shows sync status, last synced time, and conflict controls
///
/// **Ref:** Phase G Spec — Sync Settings Section
public struct SyncSettingsSection: View {
    let syncStatus: CloudSyncStatus
    let lastSyncTimestamp: Date?
    let conflictCount: Int
    let isVaultInICloud: Bool
    let isICloudAvailable: Bool
    var onEnableICloudSync: (() -> Void)?
    var onSyncNow: (() -> Void)?
    var onResolveConflicts: (() -> Void)?

    public init(
        syncStatus: CloudSyncStatus,
        lastSyncTimestamp: Date?,
        conflictCount: Int = 0,
        isVaultInICloud: Bool = false,
        isICloudAvailable: Bool = false,
        onEnableICloudSync: (() -> Void)? = nil,
        onSyncNow: (() -> Void)? = nil,
        onResolveConflicts: (() -> Void)? = nil
    ) {
        self.syncStatus = syncStatus
        self.lastSyncTimestamp = lastSyncTimestamp
        self.conflictCount = conflictCount
        self.isVaultInICloud = isVaultInICloud
        self.isICloudAvailable = isICloudAvailable
        self.onEnableICloudSync = onEnableICloudSync
        self.onSyncNow = onSyncNow
        self.onResolveConflicts = onResolveConflicts
    }

    @Environment(\.appearanceManager) private var appearance

    public var body: some View {
        Section {
            if isVaultInICloud {
                // Vault is in iCloud — show sync status
                iCloudStatusRow(connected: true)
                lastSyncedRow
                if let onSyncNow {
                    syncNowButton(action: onSyncNow)
                }
                if conflictCount > 0, let onResolveConflicts {
                    conflictRow(count: conflictCount, action: onResolveConflicts)
                }
            } else if isICloudAvailable {
                // Local vault, iCloud available — offer migration
                iCloudStatusRow(connected: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "This vault is stored locally. Enable iCloud Sync to replicate it to iCloud Drive and sync across your devices.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let onEnableICloudSync {
                        Button {
                            QuartzFeedback.primaryAction()
                            onEnableICloudSync()
                        } label: {
                            Label(String(localized: "Enable iCloud Sync", bundle: .module), systemImage: "icloud.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appearance.accentColor)
                    }
                }
            } else {
                // No iCloud at all
                iCloudStatusRow(connected: false)
                Text(String(localized: "Sign in to iCloud in System Settings to enable sync.", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "iCloud Sync", bundle: .module))
        }
    }

    // MARK: - Subviews

    private func iCloudStatusRow(connected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: connected ? "checkmark.icloud.fill" : "icloud.slash")
                .foregroundStyle(connected ? .green : .secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "iCloud Drive", bundle: .module))
                    .font(.body.weight(.medium))
                Text(connected
                     ? String(localized: "Syncing", bundle: .module)
                     : String(localized: "Not Synced", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var lastSyncedRow: some View {
        HStack {
            Text(String(localized: "Last Synced", bundle: .module))
                .foregroundStyle(.secondary)
            Spacer()
            if let timestamp = lastSyncTimestamp {
                Text(timestamp, style: .relative)
                    .foregroundStyle(.tertiary)
            } else {
                Text(String(localized: "Never", bundle: .module))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
    }

    private func syncNowButton(action: @escaping () -> Void) -> some View {
        Button {
            QuartzFeedback.primaryAction()
            action()
        } label: {
            Label(String(localized: "Sync Now", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func conflictRow(count: Int, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(count) \(count == 1 ? "Conflict" : "Conflicts")")
                .font(.callout)
            Spacer()
            Button(String(localized: "Resolve", bundle: .module)) {
                QuartzFeedback.primaryAction()
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
