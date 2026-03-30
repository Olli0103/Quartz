import SwiftUI

// MARK: - Dashboard Command Center

/// Premium macOS vault dashboard using Liquid Glass (regularMaterial) containers.
/// Features: Quick Capture, AI Briefing, Serendipity, Recent Notes, Action Items, Activity Heatmap.
public struct DashboardView: View {
    let sidebarViewModel: SidebarViewModel?
    let vaultProvider: (any VaultProviding)?
    let onSelectNote: (URL) -> Void
    let onNewNote: () -> Void
    let onExploreGraph: () -> Void
    var onRecordVoiceNote: (() -> Void)? = nil
    var onRecordMeetingMinutes: (() -> Void)? = nil
    var onQuickCapture: ((String) -> Void)? = nil

    @State private var briefing: String?
    @State private var briefingLoading = false
    @State private var actionItems: [DashboardTaskItem] = []
    @State private var actionItemsLoading = false
    @State private var togglingTaskID: UUID?
    @State private var taskToggledSuccessfully = false
    @State private var quickCaptureText = ""
    @State private var quickCaptureSent = false
    @State private var serendipityNote: FileNode?
    @State private var hoveredHeatmapDay: HeatmapDay?

    public init(
        sidebarViewModel: SidebarViewModel?,
        vaultProvider: (any VaultProviding)? = nil,
        onSelectNote: @escaping (URL) -> Void,
        onNewNote: @escaping () -> Void,
        onExploreGraph: @escaping () -> Void,
        onRecordVoiceNote: (() -> Void)? = nil,
        onRecordMeetingMinutes: (() -> Void)? = nil,
        onQuickCapture: ((String) -> Void)? = nil
    ) {
        self.sidebarViewModel = sidebarViewModel
        self.vaultProvider = vaultProvider
        self.onSelectNote = onSelectNote
        self.onNewNote = onNewNote
        self.onExploreGraph = onExploreGraph
        self.onRecordVoiceNote = onRecordVoiceNote
        self.onRecordMeetingMinutes = onRecordMeetingMinutes
        self.onQuickCapture = onQuickCapture
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                headerRow
                statsRow
                quickCaptureBar
                briefingAndSerendipityRow
                contentColumns
                heatmapPane
            }
            .padding(36)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .quartzAmbientShellBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.success, trigger: taskToggledSuccessfully)
        .sensoryFeedback(.success, trigger: quickCaptureSent)
        .task {
            pickSerendipityNote()
            await loadDashboardData()
        }
    }

    // MARK: - Header (Greeting + Toolbar Buttons)

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeBasedGreeting)
                    .font(.largeTitle.bold())
                Text(currentDateString)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            ControlGroup {
                Button {
                    QuartzFeedback.primaryAction()
                    onNewNote()
                } label: {
                    Label(String(localized: "New Note", bundle: .module), systemImage: "square.and.pencil")
                }

                Button {
                    QuartzFeedback.primaryAction()
                    onExploreGraph()
                } label: {
                    Label(String(localized: "Graph", bundle: .module), systemImage: "brain.head.profile")
                }

                if let onVoice = onRecordVoiceNote {
                    Button {
                        QuartzFeedback.primaryAction()
                        onVoice()
                    } label: {
                        Label(String(localized: "Voice", bundle: .module), systemImage: "mic")
                    }
                }

                if let onMeeting = onRecordMeetingMinutes {
                    Button {
                        QuartzFeedback.primaryAction()
                        onMeeting()
                    } label: {
                        Label(String(localized: "Meeting", bundle: .module), systemImage: "person.2")
                    }
                }
            }
            .controlGroupStyle(.navigation)
            .controlSize(.large)
        }
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "Good Morning", bundle: .module)
        case 12..<17: return String(localized: "Good Afternoon", bundle: .module)
        default: return String(localized: "Good Evening", bundle: .module)
        }
    }

    private var currentDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statBlock("\(noteCount)", label: String(localized: "Notes", bundle: .module))
            Divider().frame(height: 36).padding(.horizontal, 28)
            statBlock("\(folderCount)", label: String(localized: "Folders", bundle: .module))
            Divider().frame(height: 36).padding(.horizontal, 28)
            statBlock("\(actionItems.count)", label: String(localized: "Open Tasks", bundle: .module))
            if writingStreak > 0 {
                Divider().frame(height: 36).padding(.horizontal, 28)
                streakBlock
            }
            Spacer()
        }
    }

    private func statBlock(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(writingStreak)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(writingStreak == 1
                 ? String(localized: "Day Streak", bundle: .module)
                 : String(localized: "Day Streak", bundle: .module))
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(writingStreak) day writing streak")
    }

    // MARK: - Quick Capture Bar

    private var quickCaptureBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                String(localized: "What's on your mind? Press Enter to append to Daily Note…", bundle: .module),
                text: $quickCaptureText
            )
            .textFieldStyle(.plain)
            .font(.body)
            .onSubmit { submitQuickCapture() }

            if !quickCaptureText.isEmpty {
                Button {
                    submitQuickCapture()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Send quick capture", bundle: .module))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassPane()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Quick capture", bundle: .module))
    }

    private func submitQuickCapture() {
        let text = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        QuartzFeedback.primaryAction()
        onQuickCapture?(text)
        quickCaptureText = ""
        quickCaptureSent.toggle()
    }

    // MARK: - Briefing + Serendipity Row

    private var briefingAndSerendipityRow: some View {
        HStack(alignment: .top, spacing: 24) {
            briefingPane
            serendipityPane
                .frame(width: 280)
        }
    }

    // MARK: - AI Briefing Pane

    private var briefingPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            glassSectionHeader("AI BRIEFING", icon: "sparkles")

            if briefingLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Generating your briefing…", bundle: .module))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if let briefing {
                Text(briefing)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
            } else {
                Text(String(localized: "Configure an AI provider in Settings to enable daily briefings from your recent notes.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane()
    }

    // MARK: - Serendipity Pane

    private var serendipityPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            glassSectionHeader("SERENDIPITY", icon: "shuffle")

            if let note = serendipityNote {
                let title = note.frontmatter?.title ?? note.name.replacingOccurrences(of: ".md", with: "")
                Button {
                    QuartzFeedback.selection()
                    onSelectNote(note.url)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(relativeDate(note.metadata.modifiedAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(QuartzAnimation.soft) {
                        pickSerendipityNote()
                    }
                } label: {
                    Label(String(localized: "Shuffle", bundle: .module), systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                Text(String(localized: "Not enough notes yet.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane()
    }

    private func pickSerendipityNote() {
        let allNotes = collectAllNotes(from: sidebarViewModel?.fileTree ?? [])
        guard !allNotes.isEmpty else { serendipityNote = nil; return }

        // Try "on this day" (1 year ago) first
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let onThisDay = allNotes.first { note in
            calendar.isDate(note.metadata.modifiedAt, inSameDayAs: oneYearAgo)
        }
        serendipityNote = onThisDay ?? allNotes.randomElement()
    }

    // MARK: - Two-Column Content

    private var contentColumns: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                recentNotesPane
                if !pinnedNotes.isEmpty {
                    pinnedNotesPane
                } else {
                    actionItemsPane
                }
            }
            if !pinnedNotes.isEmpty {
                actionItemsPane
            }
        }
    }

    // MARK: - Recent Notes (Glass Pane)

    private var recentNotesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            glassSectionHeader("RECENT NOTES", icon: nil)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if recentNotes.isEmpty {
                Text(String(localized: "No recent notes.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recentNotes.prefix(8).enumerated()), id: \.element.id) { index, note in
                        if index > 0 {
                            Divider().padding(.leading, 50)
                        }
                        Button {
                            QuartzFeedback.selection()
                            onSelectNote(note.url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                    .accessibilityHidden(true)
                                Text(note.frontmatter?.title ?? note.name.replacingOccurrences(of: ".md", with: ""))
                                    .font(.body)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Text(relativeDate(note.metadata.modifiedAt))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane()
    }

    // MARK: - Pinned / Favorite Notes (Glass Pane)

    private var pinnedNotesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            glassSectionHeader("PINNED NOTES", icon: nil)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pinnedNotes.prefix(6).enumerated()), id: \.element.id) { index, note in
                    if index > 0 {
                        Divider().padding(.leading, 50)
                    }
                    Button {
                        QuartzFeedback.selection()
                        onSelectNote(note.url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(note.frontmatter?.title ?? note.name.replacingOccurrences(of: ".md", with: ""))
                                .font(.body)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 4)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
        }
        .glassPane()
    }

    // MARK: - Action Items (Glass Pane)

    private var actionItemsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                glassSectionHeader("ACTION ITEMS", icon: nil)
                if !actionItems.isEmpty {
                    Text("\(actionItems.count)")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if actionItemsLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Loading tasks…", bundle: .module))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else if actionItems.isEmpty {
                Text(String(localized: "No open tasks. Add `- [ ]` items to your notes.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(actionItems.prefix(10).enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 50)
                        }
                        HStack(spacing: 10) {
                            Button {
                                QuartzFeedback.toggle()
                                toggleTask(item)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.body.weight(.light))
                                    .foregroundStyle(.primary.opacity(0.5))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(togglingTaskID == item.id)
                            .accessibilityLabel(String(localized: "Complete task", bundle: .module))
                            .accessibilityAddTraits(.isButton)

                            Button {
                                QuartzFeedback.selection()
                                onSelectNote(item.noteURL)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                        .font(.body)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text(item.noteTitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane()
    }

    // MARK: - Activity Heatmap (Momentum)

    private var heatmapPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            glassSectionHeader("MOMENTUM", icon: "flame")

            let data = heatmapData
            let weeks = stride(from: 0, to: data.count, by: 7).map { i in
                Array(data[i..<min(i + 7, data.count)])
            }
            let weekCount = weeks.count
            let gap: CGFloat = 3
            let rows: CGFloat = 7

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let cellSize = max(4, (totalWidth - gap * CGFloat(weekCount - 1)) / CGFloat(weekCount))

                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(QuartzColors.accent.opacity(day.opacity))
                                    .frame(width: cellSize, height: cellSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(hoveredHeatmapDay?.date == day.date ? 0.4 : 0), lineWidth: 1)
                                    )
                                    .onHover { hovering in
                                        hoveredHeatmapDay = hovering ? day : nil
                                    }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: {
                // Calculate height: 7 rows * cellSize + 6 gaps
                // Estimate cellSize from max width ~880 (920 - 40 padding)
                let estimatedCell = max(4, (860 - 3 * CGFloat(weeks.count - 1)) / CGFloat(weeks.count))
                return rows * estimatedCell + (rows - 1) * gap
            }())

            HStack(spacing: 16) {
                if let hovered = hoveredHeatmapDay {
                    Text(heatmapTooltip(for: hovered))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .transition(.opacity)
                } else {
                    Text(String(localized: "26 weeks", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                HStack(spacing: 2) {
                    Text(String(localized: "Less", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach([0.08, 0.25, 0.5, 0.75, 1.0], id: \.self) { opacity in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(QuartzColors.accent.opacity(opacity))
                            .frame(width: 10, height: 10)
                    }
                    Text(String(localized: "More", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: hoveredHeatmapDay?.date)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane()
    }

    private struct HeatmapDay {
        let date: Date
        let count: Int
        let opacity: Double
    }

    private func heatmapTooltip(for day: HeatmapDay) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let dateStr = df.string(from: day.date)
        if day.count == 0 {
            return "\(dateStr) — no edits"
        } else if day.count == 1 {
            return "\(dateStr) — 1 note edited"
        } else {
            return "\(dateStr) — \(day.count) notes edited"
        }
    }

    private var heatmapData: [HeatmapDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let allNotes = collectAllNotes(from: sidebarViewModel?.fileTree ?? [])

        // Bucket modification dates by day offset (0 = today, 181 = 26 weeks ago)
        var counts = [Int: Int]()
        for note in allNotes {
            let noteDay = calendar.startOfDay(for: note.metadata.modifiedAt)
            let diff = calendar.dateComponents([.day], from: noteDay, to: today).day ?? 0
            if diff >= 0, diff < 182 {
                counts[diff, default: 0] += 1
            }
        }

        let maxCount = max(counts.values.max() ?? 1, 1)

        // Build array from 89 days ago → today (left to right)
        return (0..<182).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let count = counts[daysAgo] ?? 0
            let intensity: Double
            if count == 0 {
                intensity = 0.08
            } else {
                // Map to 0.25 – 1.0 range
                intensity = 0.25 + 0.75 * (Double(count) / Double(maxCount))
            }
            return HeatmapDay(date: date, count: count, opacity: intensity)
        }
    }

    // MARK: - Shared Helpers

    private func glassSectionHeader(_ title: String, icon: String?) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .tracking(1.0)
        }
        .foregroundStyle(.secondary)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var recentNotes: [FileNode] {
        sidebarViewModel?.recentNotes(limit: 8) ?? []
    }

    private var pinnedNotes: [FileNode] {
        guard let vm = sidebarViewModel else { return [] }
        let allNotes = collectFlatNotes(from: vm.fileTree)
        return allNotes.filter { vm.isFavorite($0.url) }
            .sorted { $0.metadata.modifiedAt > $1.metadata.modifiedAt }
    }

    /// Calculates the number of consecutive days (ending today or yesterday)
    /// that the user has modified at least one note.
    private var writingStreak: Int {
        guard let vm = sidebarViewModel else { return 0 }
        let allNotes = collectFlatNotes(from: vm.fileTree)
        guard !allNotes.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Collect unique days that had modifications
        var activeDays = Set<Int>() // days offset from today (0 = today, 1 = yesterday, etc.)
        for note in allNotes {
            let noteDay = calendar.startOfDay(for: note.metadata.modifiedAt)
            let daysAgo = calendar.dateComponents([.day], from: noteDay, to: today).day ?? 0
            if daysAgo >= 0 {
                activeDays.insert(daysAgo)
            }
        }

        // Count consecutive days starting from today (or yesterday if nothing today yet)
        let startDay = activeDays.contains(0) ? 0 : (activeDays.contains(1) ? 1 : -1)
        guard startDay >= 0 else { return 0 }

        var streak = 0
        var day = startDay
        while activeDays.contains(day) {
            streak += 1
            day += 1
        }
        return streak
    }

    private func collectFlatNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote { result.append(node) }
            if let c = node.children { result.append(contentsOf: collectFlatNotes(from: c)) }
        }
        return result
    }

    private var noteCount: Int {
        guard let vm = sidebarViewModel else { return 0 }
        return countNodes(vm.fileTree, where: \.isNote)
    }

    private var folderCount: Int {
        guard let vm = sidebarViewModel else { return 0 }
        return countNodes(vm.fileTree, where: \.isFolder)
    }

    private func countNodes(_ nodes: [FileNode], where predicate: (FileNode) -> Bool) -> Int {
        var count = 0
        for n in nodes {
            if predicate(n) { count += 1 }
            if let c = n.children { count += countNodes(c, where: predicate) }
        }
        return count
    }

    private func collectAllNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for n in nodes {
            if n.isNote { result.append(n) }
            if let c = n.children { result.append(contentsOf: collectAllNotes(from: c)) }
        }
        return result
    }

    // MARK: - Data Loading

    private func loadDashboardData() async {
        guard let provider = vaultProvider, let vm = sidebarViewModel, let vaultRoot = vm.vaultRootURL else { return }

        let recent = vm.recentNotes(limit: 15)
        guard !recent.isEmpty else { return }

        actionItemsLoading = true
        let taskActor = DashboardTaskActor(vaultProvider: provider)
        let allTasks = await taskActor.parseOpenTasks(from: recent.map(\.url))
        actionItems = allTasks
        actionItemsLoading = false

        var contents: [(title: String, body: String)] = []
        for note in recent.prefix(10) {
            do {
                let doc = try await provider.readNote(at: note.url)
                let title = doc.frontmatter.title ?? note.name.replacingOccurrences(of: ".md", with: "")
                contents.append((title: title, body: doc.body))
            } catch {}
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
            } catch {}
            await MainActor.run { togglingTaskID = nil }
        }
    }
}

// MARK: - Liquid Glass Pane (Accessibility-Aware)

private struct GlassPaneModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let highContrast = reduceTransparency || contrast == .increased
        content
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(highContrast ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(highContrast ? 0.2 : 0.08), lineWidth: highContrast ? 1 : 0.5)
            )
            .shadow(color: .black.opacity(highContrast ? 0 : 0.04), radius: 6, y: 2)
    }
}

private extension View {
    func glassPane() -> some View {
        modifier(GlassPaneModifier())
    }
}
