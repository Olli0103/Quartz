import SwiftUI

// MARK: - Morning Command Center (Pillar 8)

/// Dashboard acting as a "Morning Command Center" with AI briefing, action items, and Jump Back In.
///
/// **Architecture:**
/// - **AI Morning Briefing:** Uses `DashboardBriefingService` to summarize recent notes via AI provider
/// - **Action Items:** Parses `- [ ]` from recently edited notes (see load scope) via `TaskItemParser`
/// - **Jump Back In:** Rich cards for recent notes using `.ultraThinMaterial`
public struct DashboardView: View {
    let sidebarViewModel: SidebarViewModel?
    let vaultProvider: (any VaultProviding)?
    let onSelectNote: (URL) -> Void
    let onNewNote: () -> Void
    let onExploreGraph: () -> Void
    var onRecordVoiceNote: (() -> Void)? = nil
    var onRecordMeetingMinutes: (() -> Void)? = nil

    @State private var briefing: String?
    @State private var briefingLoading = false
    @State private var actionItems: [DashboardTaskItem] = []
    @State private var actionItemsLoading = false
    @State private var togglingTaskID: UUID?
    @State private var taskToggledSuccessfully = false

    private static let navyButton = Color(hex: 0x1E3A5F)
    private static let cardRadius: CGFloat = 20

    public init(
        sidebarViewModel: SidebarViewModel?,
        vaultProvider: (any VaultProviding)? = nil,
        onSelectNote: @escaping (URL) -> Void,
        onNewNote: @escaping () -> Void,
        onExploreGraph: @escaping () -> Void,
        onRecordVoiceNote: (() -> Void)? = nil,
        onRecordMeetingMinutes: (() -> Void)? = nil
    ) {
        self.sidebarViewModel = sidebarViewModel
        self.vaultProvider = vaultProvider
        self.onSelectNote = onSelectNote
        self.onNewNote = onNewNote
        self.onExploreGraph = onExploreGraph
        self.onRecordVoiceNote = onRecordVoiceNote
        self.onRecordMeetingMinutes = onRecordMeetingMinutes
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection

                aiMorningBriefingSection

                actionItemsSection

                jumpBackInSection

                bottomCardsRow
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(QuartzColors.sidebarBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.success, trigger: taskToggledSuccessfully)
        .task {
            await loadDashboardData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Dashboard", bundle: .module))
                .font(.system(size: 28, weight: .bold))
            Text(String(localized: "Your morning command center.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI Morning Briefing

    private var aiMorningBriefingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuartzColors.accent)
                Text(String(localized: "AI MORNING BRIEFING", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuartzColors.accent)
                    .textCase(.uppercase)
            }
            Text(String(localized: "Summarizes excerpts from your most recently edited notes. Cached up to 4 hours per vault.", bundle: .module))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if briefingLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(QuartzColors.accent)
                    Text(String(localized: "Generating your briefing…", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            } else if let briefing {
                Text(briefing)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(String(localized: "Configure an AI provider in Settings to summarize excerpts from your most recently edited notes.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - Action Items

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(String(localized: "Action Items", bundle: .module), systemImage: "checklist")
                    .font(.headline)
                Spacer()
                if !actionItems.isEmpty {
                    Text("\(actionItems.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
            }
            Text(String(localized: "Open tasks from notes you edited recently (up to 15 files).", bundle: .module))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if actionItemsLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(QuartzColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else if actionItems.isEmpty {
                Text(String(localized: "No open tasks. Add `- [ ]` to your notes to see them here.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(actionItems.prefix(10)) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                QuartzFeedback.toggle()
                                toggleTask(item)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.body)
                                    .foregroundStyle(QuartzColors.accent)
                                    .contentShape(Rectangle())
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .disabled(togglingTaskID == item.id)
                            .accessibilityLabel(String(localized: "Complete task", bundle: .module))
                            .accessibilityHint(String(localized: "Double tap to mark as done", bundle: .module))

                            Button {
                                QuartzFeedback.selection()
                                onSelectNote(item.noteURL)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.text)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)
                                        Text(item.noteTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.text)
                            .accessibilityHint(String(localized: "From \(item.noteTitle). Double tap to open note.", bundle: .module))
                        }
                        .padding(12)
                        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - Jump Back In (Recent Notes)

    private var jumpBackInSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Jump Back In", bundle: .module))
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentNotes) { note in
                        JumpBackInCard(note: note, onTap: { onSelectNote(note.url) })
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var recentNotes: [FileNode] {
        sidebarViewModel?.recentNotes(limit: 6) ?? []
    }

    // MARK: - Bottom Row

    private var bottomCardsRow: some View {
        HStack(spacing: 20) {
            brainGardenCard
            quickCaptureCard
            if onRecordVoiceNote != nil || onRecordMeetingMinutes != nil {
                voiceCaptureCard
            }
        }
    }

    private var brainGardenCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "KNOWLEDGE GRAPH", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuartzColors.accent)
                    .textCase(.uppercase)
                Text(String(localized: "Brain Garden", bundle: .module))
                    .font(.title2.weight(.bold))
                Text(String(format: String(localized: "%lld notes in vault. Explore wiki-links and semantic links from on-device embeddings.", bundle: .module), nodeCount))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 12)
                Button {
                    QuartzFeedback.primaryAction()
                    onExploreGraph()
                } label: {
                    Text(String(localized: "Explore Graph", bundle: .module))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Explore knowledge graph", bundle: .module))
                .accessibilityHint(String(localized: "\(nodeCount) notes in vault", bundle: .module))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(QuartzColors.accent.opacity(0.6 + Double(i % 3) * 0.1))
                        .frame(width: 6, height: 6)
                        .offset(
                            x: CGFloat((i % 4) * 24) - 36,
                            y: CGFloat((i / 4) * 20) - 20
                        )
                }
            }
            .frame(width: 120, height: 80)
        }
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Self.navyButton, Self.navyButton.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        )
    }

    private var nodeCount: Int {
        guard let vm = sidebarViewModel else { return 0 }
        var count = 0
        func walk(_ nodes: [FileNode]) {
            for n in nodes {
                if n.isNote { count += 1 }
                if let c = n.children { walk(c) }
            }
        }
        walk(vm.fileTree)
        return count
    }

    private var voiceCaptureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let onVoice = onRecordVoiceNote {
                    Button {
                        QuartzFeedback.primaryAction()
                        onVoice()
                    } label: {
                        Label(String(localized: "Quick Note", bundle: .module), systemImage: "mic.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(QuartzColors.accent)
                    }
                    .buttonStyle(.plain)
                }
                if let onMeeting = onRecordMeetingMinutes {
                    Button {
                        QuartzFeedback.primaryAction()
                        onMeeting()
                    } label: {
                        Label(String(localized: "Meeting Minutes", bundle: .module), systemImage: "person.2.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(QuartzColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(String(localized: "Record voice to create a note or meeting minutes.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }

    private var quickCaptureCard: some View {
        Button {
            onNewNote()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                Text(String(localized: "Capture a Spark", bundle: .module))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(String(localized: "Have a fleeting idea? Capture it quickly before it fades.", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                Spacer(minLength: 8)
                HStack {
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.2)))
                }
            }
            .padding(20)
            .frame(width: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .fill(QuartzColors.accent.gradient)
                    .shadow(color: QuartzColors.accent.opacity(0.3), radius: 12, y: 6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Capture a Spark", bundle: .module))
        .accessibilityHint(String(localized: "Double tap to create a new quick note", bundle: .module))
    }

    // MARK: - Data Loading

    private func loadDashboardData() async {
        guard let provider = vaultProvider, let vm = sidebarViewModel, let vaultRoot = vm.vaultRootURL else { return }

        let recent = vm.recentNotes(limit: 15)
        guard !recent.isEmpty else { return }

        // Offload task parsing to background actor (non-blocking)
        actionItemsLoading = true
        let taskActor = DashboardTaskActor(vaultProvider: provider)
        let noteURLs = recent.map(\.url)
        let allTasks = await taskActor.parseOpenTasks(from: noteURLs)
        actionItems = allTasks
        actionItemsLoading = false

        // Load briefing context and generate (cached 4h per vault, process-wide)
        var contents: [(title: String, body: String)] = []
        for note in recent.prefix(10) {
            do {
                let doc = try await provider.readNote(at: note.url)
                let title = doc.frontmatter.title ?? note.name.replacingOccurrences(of: ".md", with: "")
                contents.append((title: title, body: doc.body))
            } catch {
                // Skip
            }
        }

        briefingLoading = true
        let service = DashboardBriefingService(providerRegistry: AIProviderRegistry.shared)
        do {
            briefing = try await service.generateWeeklyBriefing(recentNoteContents: contents, vaultRoot: vaultRoot)
        } catch {
            briefing = nil
        }
        briefingLoading = false
    }

    private func toggleTask(_ item: DashboardTaskItem) {
        togglingTaskID = item.id
        let toggleService = DashboardTaskToggleService()
        Task {
            do {
                _ = try await toggleService.toggleTask(item, toCompleted: true)
                await MainActor.run {
                    actionItems.removeAll { $0.id == item.id }
                    taskToggledSuccessfully.toggle()
                }
            } catch {
                await MainActor.run { togglingTaskID = nil }
            }
            await MainActor.run { togglingTaskID = nil }
        }
    }
}

// MARK: - Jump Back In Card

private struct JumpBackInCard: View {
    let note: FileNode
    let onTap: () -> Void

    private static let iconColors: [Color] = [QuartzColors.accent, QuartzColors.noteBlue, QuartzColors.canvasPurple]

    var body: some View {
        Button {
            QuartzFeedback.selection()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    let colorIndex = abs(note.id.hashValue) % Self.iconColors.count
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((Self.iconColors[colorIndex]).opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.subheadline)
                                .foregroundStyle(Self.iconColors[colorIndex])
                        }
                    Spacer()
                    Text(note.metadata.modifiedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(note.frontmatter?.title ?? note.name.replacingOccurrences(of: ".md", with: ""))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                Text(String(localized: "Tap to open", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                if let tags = note.frontmatter?.tags.prefix(2), !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(tags), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(QuartzColors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(QuartzColors.accent.opacity(0.12)))
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 200, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}
