import SwiftUI

/// Backup management section for the Data & Sync settings panel.
///
/// Auto-backup toggle, export/restore buttons, and list of recent backups.
///
/// **Ref:** Phase G Spec — Backup Settings Section
public struct BackupSettingsSection: View {
    let availableBackups: [BackupEntry]
    let isBackupInProgress: Bool
    let backupProgress: Double
    var onExportBackup: (() -> Void)?
    var onRestoreBackup: (() -> Void)?

    @AppStorage("quartzAutoBackupEnabled") private var autoBackupEnabled = false
    @AppStorage("quartzAutoBackupFrequency") private var autoBackupFrequency = "weekly"

    @Environment(\.appearanceManager) private var appearance

    public init(
        availableBackups: [BackupEntry] = [],
        isBackupInProgress: Bool = false,
        backupProgress: Double = 0,
        onExportBackup: (() -> Void)? = nil,
        onRestoreBackup: (() -> Void)? = nil
    ) {
        self.availableBackups = availableBackups
        self.isBackupInProgress = isBackupInProgress
        self.backupProgress = backupProgress
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
    }

    public var body: some View {
        Section {
            // Auto-backup toggle
            Toggle(
                String(localized: "Auto-Backup", bundle: .module),
                isOn: $autoBackupEnabled
            )

            // Frequency picker (only when auto-backup is on)
            if autoBackupEnabled {
                Picker(String(localized: "Frequency", bundle: .module), selection: $autoBackupFrequency) {
                    Text(String(localized: "Daily", bundle: .module)).tag("daily")
                    Text(String(localized: "Weekly", bundle: .module)).tag("weekly")
                    Text(String(localized: "Monthly", bundle: .module)).tag("monthly")
                }
            }

            // Export button / progress
            if isBackupInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Exporting…", bundle: .module))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: backupProgress)
                        .progressViewStyle(.linear)
                        .tint(appearance.accentColor)
                }
            } else if let onExportBackup {
                Button {
                    QuartzFeedback.primaryAction()
                    onExportBackup()
                } label: {
                    Label(String(localized: "Export Backup", bundle: .module), systemImage: "square.and.arrow.up")
                }
            }

            // Restore button
            if let onRestoreBackup {
                Button {
                    QuartzFeedback.primaryAction()
                    onRestoreBackup()
                } label: {
                    Label(String(localized: "Restore from Backup", bundle: .module), systemImage: "arrow.down.doc")
                }
            }

            // Recent backups list
            if !availableBackups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Recent Backups", bundle: .module))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(availableBackups.prefix(5)) { backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.createdAt, style: .date)
                                    .font(.callout)
                                Text(backup.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(formattedSize(backup.sizeBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
        } header: {
            Text(String(localized: "Backup", bundle: .module))
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
