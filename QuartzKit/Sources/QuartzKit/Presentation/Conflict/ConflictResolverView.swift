import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Presents iCloud sync conflicts with a visual diff and merged resolution when versions are available.
public struct ConflictResolverView: View {
    let fileURL: URL
    let onResolved: () -> Void

    @State private var diffState: ConflictDiffState?
    @State private var mergedText: String = ""
    @State private var versions: [ConflictVersion] = []
    @State private var selectedVersion: ConflictVersion?
    @State private var isLoading = true
    @State private var isResolving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(fileURL: URL, onResolved: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onResolved = onResolved
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(String(localized: "Loading versions…", bundle: .module))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff = diffState, !diff.cloudContent.isEmpty || !diff.localContent.isEmpty {
                    diffMergeContent(diff: diff)
                } else if versions.isEmpty {
                    emptyState
                } else {
                    legacyVersionList
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
                    if diffState != nil {
                        Button(String(localized: "Merge & Resolve", bundle: .module)) {
                            resolveMerged()
                        }
                        .disabled(isResolving || mergedText.isEmpty)
                    } else if !versions.isEmpty {
                        Button(String(localized: "Resolve", bundle: .module)) {
                            resolveWithSelectedVersion()
                        }
                        .disabled(isResolving)
                    }
                }
            }
            .task { await loadDiffAndVersions() }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private func diffMergeContent(diff: ConflictDiffState) -> some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 12) {
                    diffColumn(title: String(localized: "Your Copy (device)", bundle: .module), text: diff.localContent, accent: QuartzColors.noteBlue)
                    diffColumn(title: String(localized: "iCloud Edits", bundle: .module), text: diff.cloudContent, accent: QuartzColors.assetOrange)
                }
                .padding()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    diffColumn(title: String(localized: "Your Copy (device)", bundle: .module), text: diff.localContent, accent: QuartzColors.noteBlue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    diffColumn(title: String(localized: "iCloud Edits", bundle: .module), text: diff.cloudContent, accent: QuartzColors.assetOrange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Merged — copy text from above, edit, then tap Merge & Resolve", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $mergedText)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .padding(10)
                    .frame(minHeight: 140)
                    .background {
                        ContainerRelativeShape()
                            .fill(.quaternary.opacity(0.35))
                    }
                    .overlay {
                        ContainerRelativeShape()
                            .strokeBorder(QuartzColors.accent.opacity(0.35), lineWidth: 1)
                    }
            }
            .padding()
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

    private func diffColumn(title: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            ScrollView {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 140, maxHeight: 240)
            .padding(10)
            .background {
                ContainerRelativeShape()
                    .fill(.regularMaterial)
            }
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func resolveMerged() {
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let service = CloudSyncService()
                try await service.resolveConflictWritingMergedContent(at: fileURL, mergedUTF8: mergedText)
                await MainActor.run {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                    isResolving = false
                    onResolved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    #endif
                    isResolving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
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

    private var legacyVersionList: some View {
        List {
            Section {
                Button {
                    selectedVersion = nil
                } label: {
                    versionRow(
                        icon: "laptopcomputer",
                        title: String(localized: "Keep Local (current)", bundle: .module),
                        subtitle: String(localized: "Use the version on this device", bundle: .module),
                        isSelected: selectedVersion == nil
                    )
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(versions) { version in
                    Button {
                        selectedVersion = version
                    } label: {
                        versionRow(
                            icon: "icloud",
                            title: version.displayName,
                            subtitle: version.modificationDate.formatted(.relative(presentation: .named)),
                            isSelected: selectedVersion?.id == version.id
                        )
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

    private func versionRow(icon: String, title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(QuartzColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(QuartzColors.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadDiffAndVersions() async {
        isLoading = true
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? []
        versions = conflicts.enumerated().map { index, v in
            ConflictVersion(
                id: index,
                version: v,
                displayName: v.localizedNameOfSavingComputer ?? String(localized: "Cloud version", bundle: .module),
                modificationDate: v.modificationDate ?? Date()
            )
        }
        if let first = versions.first {
            selectedVersion = first
        }

        let service = CloudSyncService()
        do {
            let built = try await service.buildConflictDiffState(for: fileURL)
            await MainActor.run {
                diffState = built
                if let built {
                    mergedText = built.localContent
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                diffState = nil
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resolveWithSelectedVersion() {
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let service = CloudSyncService()
                if let version = selectedVersion {
                    try service.resolveConflictKeepingVersion(at: fileURL, version: version.version)
                } else {
                    try service.resolveConflictKeepingCurrent(at: fileURL)
                }
                await MainActor.run {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                    isResolving = false
                    onResolved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    #endif
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
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .automatic))
            #endif
        }
    }
}
