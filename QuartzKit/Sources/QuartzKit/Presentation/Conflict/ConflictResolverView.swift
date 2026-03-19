import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Presents iCloud sync conflict versions and lets the user choose which to keep.
/// Shown when `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` returns versions.
public struct ConflictResolverView: View {
    let fileURL: URL
    let onResolved: () -> Void

    @State private var versions: [ConflictVersion] = []
    @State private var selectedVersion: ConflictVersion?
    @State private var isResolving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let syncService = CloudSyncService()

    public init(fileURL: URL, onResolved: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onResolved = onResolved
    }

    public var body: some View {
        NavigationStack {
            Group {
                if versions.isEmpty {
                    emptyState
                } else {
                    versionList
                }
            }
            .navigationTitle(String(localized: "Resolve Sync Conflict", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    resolveButton
                }
            }
            .task { loadVersions() }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

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

    private var versionList: some View {
        List {
            Section {
                Button {
                    selectedVersion = nil
                } label: {
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .foregroundStyle(QuartzColors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Keep Local (current)", bundle: .module))
                                .font(.body.weight(.medium))
                            Text(String(localized: "Use the version on this device", bundle: .module))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedVersion == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(QuartzColors.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(versions) { version in
                    Button {
                        selectedVersion = version
                    } label: {
                        HStack {
                            Image(systemName: "icloud")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.displayName)
                                    .font(.body.weight(.medium))
                                Text(version.modificationDate, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedVersion?.id == version.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(QuartzColors.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(String(localized: "Other Versions", bundle: .module))
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
    }

    private var resolveButton: some View {
        Button(String(localized: "Resolve", bundle: .module)) {
            resolveConflict()
        }
        .disabled(isResolving)
    }

    private func loadVersions() {
        let conflicts = syncService.conflictVersions(for: fileURL)
        versions = conflicts.enumerated().map { index, v in
            ConflictVersion(
                id: index,
                version: v,
                displayName: v.localizedNameOfSavingComputer ?? String(localized: "Cloud version", bundle: .module),
                modificationDate: v.modificationDate ?? Date()
            )
        }
        if versions.isEmpty {
            selectedVersion = nil
        } else if selectedVersion == nil, let first = versions.first {
            selectedVersion = first
        }
    }

    private func resolveConflict() {
        isResolving = true
        errorMessage = nil
        Task {
            do {
                if let version = selectedVersion {
                    try syncService.resolveConflictKeepingVersion(at: fileURL, version: version.version)
                } else {
                    try syncService.resolveConflictKeepingCurrent(at: fileURL)
                }
                await MainActor.run {
                    isResolving = false
                    onResolved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isResolving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ConflictVersion: Identifiable {
    let id: Int
    let version: NSFileVersion
    let displayName: String
    let modificationDate: Date
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
            ConflictResolverView(fileURL: url) {
                onResolved()
                dismiss()
            }
        } else {
            TabView(selection: $currentIndex) {
                ForEach(Array(fileURLs.enumerated()), id: \.offset) { index, url in
                    ConflictResolverView(fileURL: url) {
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
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .automatic))
        }
    }
}
