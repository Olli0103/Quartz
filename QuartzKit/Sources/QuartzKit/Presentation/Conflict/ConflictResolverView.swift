import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Presents iCloud sync conflicts with a side-by-side diff and three clear resolution options.
///
/// **Zero-data-loss guarantee**: If the user is unsure, "Keep Both" branches the conflict
/// into a sibling file so nothing is ever silently overwritten.
///
/// **Per CODEX.md F6**: Uses `ConflictResolverCoordinator` to ensure all resolutions go
/// through the state machine with typed events.
///
/// Layout:
/// - Side-by-side comparison: "Your Mac's Version" (left) vs "iCloud Version" (right)
/// - Three action buttons: Keep Local, Keep iCloud, Keep Both
/// - Timestamps shown for each version
public struct ConflictResolverView: View {
    let fileURL: URL
    let onResolved: (ConflictResolution) -> Void

    /// The coordinator handling state machine and event publishing.
    @State private var coordinator = ConflictResolverCoordinator()
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    /// What the user chose.
    public enum ConflictResolution {
        case keptLocal
        case keptCloud
        case keptBoth(conflictURL: URL)
    }

    public init(fileURL: URL, onResolved: @escaping (ConflictResolution) -> Void) {
        self.fileURL = fileURL
        self.onResolved = onResolved
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(String(localized: "Loading versions\u{2026}", bundle: .module))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff = coordinator.diffState {
                    diffContent(diff: diff)
                } else {
                    emptyState
                }
            }
            .navigationTitle(String(localized: "Resolve Sync Conflict", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        try? coordinator.cancel()
                        dismiss()
                    }
                }
            }
            .task { await loadDiff() }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    // MARK: - Diff Content

    private func diffContent(diff: ConflictDiffState) -> some View {
        VStack(spacing: 0) {
            // Side-by-side comparison
            HStack(alignment: .top, spacing: 1) {
                diffColumn(
                    title: String(localized: "Your Mac's Version", bundle: .module),
                    subtitle: diff.localModified.map { formattedDate($0) },
                    text: diff.localContent,
                    accent: QuartzColors.noteBlue,
                    icon: "laptopcomputer"
                )

                Divider()

                diffColumn(
                    title: String(localized: "iCloud Version", bundle: .module),
                    subtitle: diff.cloudModified.map { formattedDate($0) },
                    text: diff.cloudContent,
                    accent: QuartzColors.assetOrange,
                    icon: "icloud"
                )
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Error
            if let errorMessage = coordinator.lastError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Resolution buttons
            resolutionButtons
        }
    }

    private func diffColumn(title: String, subtitle: String?, text: String, accent: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(accent.opacity(0.06))

            // Content
            ScrollView {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(text.prefix(200))")
    }

    // MARK: - Resolution Buttons

    private var resolutionButtons: some View {
        HStack(spacing: 12) {
            // Keep Local
            Button {
                resolve(.keepLocal)
            } label: {
                Label(String(localized: "Keep Local", bundle: .module), systemImage: "laptopcomputer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(coordinator.isOperating)
            .accessibilityHint(String(localized: "Discards the iCloud version and keeps your local edits", bundle: .module))

            // Keep iCloud
            Button {
                resolve(.keepCloud)
            } label: {
                Label(String(localized: "Keep iCloud", bundle: .module), systemImage: "icloud")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(coordinator.isOperating)
            .accessibilityHint(String(localized: "Replaces your local version with the iCloud version", bundle: .module))

            // Keep Both — the safe option
            Button {
                resolve(.keepBoth)
            } label: {
                Label(String(localized: "Keep Both", bundle: .module), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(coordinator.isOperating)
            .accessibilityHint(String(localized: "Saves the iCloud version as a separate note so you can merge them manually", bundle: .module))
        }
        .padding(16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.icloud")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No conflicts to resolve", bundle: .module))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "This file may have been resolved elsewhere.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func loadDiff() async {
        isLoading = true
        do {
            try await coordinator.loadConflict(at: fileURL)
        } catch {
            // Error is stored in coordinator.lastError
        }
        isLoading = false
    }

    // MARK: - Resolution Actions

    private enum ResolutionAction {
        case keepLocal, keepCloud, keepBoth
    }

    private func resolve(_ action: ResolutionAction) {
        Task {
            do {
                let resolution: ConflictResolution

                switch action {
                case .keepLocal:
                    try await coordinator.resolveKeepingLocal()
                    resolution = .keptLocal

                case .keepCloud:
                    try await coordinator.resolveKeepingCloud()
                    resolution = .keptCloud

                case .keepBoth:
                    try await coordinator.resolveKeepingBoth()
                    // The conflict URL is the branched file
                    let baseName = fileURL.deletingPathExtension().lastPathComponent
                    let ext = fileURL.pathExtension
                    let conflictURL = fileURL.deletingLastPathComponent()
                        .appending(path: "\(baseName) (iCloud Conflict).\(ext)")
                    resolution = .keptBoth(conflictURL: conflictURL)
                }

                await MainActor.run {
                    QuartzFeedback.success()
                    onResolved(resolution)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    QuartzFeedback.warning()
                    // Error is stored in coordinator.lastError
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Multi-File Conflict List

/// Lists all files with conflicts and lets the user resolve each.
public struct ConflictListResolverView: View {
    let fileURLs: [URL]
    let onResolved: () -> Void

    @State private var currentIndex = 0
    @Environment(\.dismiss) private var dismiss

    public init(fileURLs: [URL], onResolved: @escaping () -> Void) {
        self.fileURLs = fileURLs
        self.onResolved = onResolved
    }

    public var body: some View {
        if fileURLs.isEmpty {
            ContentUnavailableView(
                String(localized: "No Conflicts", bundle: .module),
                systemImage: "checkmark.icloud",
                description: Text(String(localized: "All files are in sync.", bundle: .module))
            )
            .onAppear { dismiss() }
        } else if fileURLs.count == 1, let url = fileURLs.first {
            ConflictResolverView(fileURL: url) { _ in
                onResolved()
                dismiss()
            }
        } else {
            TabView(selection: $currentIndex) {
                ForEach(Array(fileURLs.enumerated()), id: \.offset) { index, url in
                    ConflictResolverView(fileURL: url) { _ in
                        if index == fileURLs.count - 1 {
                            onResolved()
                            dismiss()
                        } else {
                            currentIndex = index + 1
                        }
                    }
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .automatic))
            #endif
        }
    }
}
