#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Latest Note Widget

/// Timeline entry for the "Latest Note" widget.
public struct LatestNoteEntry: TimelineEntry, Sendable {
    public let date: Date
    public let noteTitle: String
    public let notePreview: String
    public let noteURL: URL?

    public init(date: Date, noteTitle: String, notePreview: String, noteURL: URL?) {
        self.date = date
        self.noteTitle = noteTitle
        self.notePreview = notePreview
        self.noteURL = noteURL
    }

    nonisolated(unsafe) public static let placeholder = LatestNoteEntry(
        date: .now,
        noteTitle: String(localized: "My Note", bundle: .module),
        notePreview: String(localized: "Start writing to see your latest note here…", bundle: .module),
        noteURL: nil
    )
}

/// Timeline provider for the Latest Note widget.
public struct LatestNoteProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> LatestNoteEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (LatestNoteEntry) -> Void) {
        completion(.placeholder)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<LatestNoteEntry>) -> Void) {
        let entry: LatestNoteEntry

        if let vaultRoot = UserDefaults(suiteName: "group.app.quartz.shared")?.url(forKey: "activeVaultURL"),
           let latestNote = Self.findLatestNote(in: vaultRoot) {
            entry = latestNote
        } else {
            entry = .placeholder
        }

        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }

    /// Finds the most recently modified .md file in the vault.
    private static func findLatestNote(in vaultRoot: URL) -> LatestNoteEntry? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var latestURL: URL?
        var latestDate: Date = .distantPast

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified > latestDate else { continue }
            latestDate = modified
            latestURL = fileURL
        }

        guard let url = latestURL else { return nil }

        let title = url.deletingPathExtension().lastPathComponent
        let preview = Self.readNotePreview(from: url)

        return LatestNoteEntry(
            date: latestDate,
            noteTitle: title,
            notePreview: preview,
            noteURL: url
        )
    }

    /// Reads the first 100 characters of note body content (after frontmatter).
    /// Called from WidgetKit's TimelineProvider which runs on a background thread —
    /// synchronous file I/O is acceptable here (not a UI-thread concern).
    private static func readNotePreview(from url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8))?
            .components(separatedBy: "---").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(100)
            .description ?? ""
    }
}

/// View for the Latest Note widget (lock screen + home screen).
public struct LatestNoteWidgetView: View {
    let entry: LatestNoteEntry
    @Environment(\.widgetFamily) var family

    public init(entry: LatestNoteEntry) {
        self.entry = entry
    }

    public var body: some View {
        widgetContent
            .widgetURL(deepLinkURL)
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch family {
        case .accessoryInline:
            Text(entry.noteTitle)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.noteTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(entry.notePreview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(String(localized: "Latest Note", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.noteTitle)
                    .font(.callout.bold())
                    .lineLimit(2)
                Text(entry.notePreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer()
            }
            .padding()

        case .systemMedium:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.tint)
                        Text(String(localized: "Latest Note", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.noteTitle)
                        .font(.callout.bold())
                        .lineLimit(2)
                    Text(entry.notePreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                    Spacer()
                }
                Spacer()
            }
            .padding()

        default:
            Text(entry.noteTitle)
        }
    }

    /// Deep-link URL for tapping the widget.
    private var deepLinkURL: URL? {
        guard let noteURL = entry.noteURL else { return nil }
        var components = URLComponents()
        components.scheme = "quartz"
        components.host = "note"
        components.path = "/\(noteURL.lastPathComponent)"
        return components.url
    }
}

// MARK: - Quick Capture Widget

/// Timeline entry for Quick Capture (static).
public struct QuickCaptureEntry: TimelineEntry {
    public let date: Date

    public init(date: Date = .now) {
        self.date = date
    }
}

/// Timeline provider for the Quick Capture widget.
public struct QuickCaptureProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry()
    }

    public func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        let entry = QuickCaptureEntry()
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

/// View for the Quick Capture widget.
public struct QuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) var family

    public init() {}

    public var body: some View {
        quickCaptureContent
            .widgetURL(URL(string: "quartz://new"))
    }

    @ViewBuilder
    private var quickCaptureContent: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.and.pencil")
                    .font(.title3)
            }

        case .systemSmall:
            VStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(String(localized: "Quick Note", bundle: .module))
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .systemMedium:
            // Enhanced: three capture buttons (Text, Audio, Camera)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        Text(String(localized: "Quick Capture", bundle: .module))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "One tap to capture", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                HStack(spacing: 12) {
                    #if canImport(AppIntents)
                    Button(intent: CreateNoteIntent()) {
                        captureButton(icon: "square.and.pencil", label: String(localized: "Text", bundle: .module), color: QuartzColors.accent)
                    }
                    .buttonStyle(.plain)

                    Button(intent: CaptureAudioIntent()) {
                        captureButton(icon: "mic.fill", label: String(localized: "Audio", bundle: .module), color: Color.red)
                    }
                    .buttonStyle(.plain)
                    #else
                    Link(destination: URL(string: "quartz://new")!) {
                        captureButton(icon: "square.and.pencil", label: String(localized: "Text", bundle: .module), color: QuartzColors.accent)
                    }
                    Link(destination: URL(string: "quartz://audio")!) {
                        captureButton(icon: "mic.fill", label: String(localized: "Audio", bundle: .module), color: Color.red)
                    }
                    #endif

                    Link(destination: URL(string: "quartz://scan")!) {
                        captureButton(icon: "doc.viewfinder", label: String(localized: "Scan", bundle: .module), color: Color.blue)
                    }
                }
            }
            .padding(12)

        default:
            Image(systemName: "square.and.pencil")
        }
    }

    private func captureButton(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(color.gradient)
                        .shadow(color: color.opacity(0.3), radius: 4, y: 2)
                )
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Pinned Notes Widget

/// Timeline entry for Pinned Notes.
public struct PinnedNotesEntry: TimelineEntry, Sendable {
    public let date: Date
    public let notes: [PinnedNote]

    public init(date: Date, notes: [PinnedNote]) {
        self.date = date
        self.notes = notes
    }

    nonisolated(unsafe) public static let placeholder = PinnedNotesEntry(
        date: .now,
        notes: [
            PinnedNote(title: String(localized: "Meeting Notes", bundle: .module), icon: "doc.text"),
            PinnedNote(title: String(localized: "Shopping List", bundle: .module), icon: "checklist"),
            PinnedNote(title: String(localized: "Project Ideas", bundle: .module), icon: "lightbulb"),
        ]
    )
}

/// A pinned note in the widget.
public struct PinnedNote: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let icon: String

    public init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }
}

/// View for the Pinned Notes widget (medium/large).
public struct PinnedNotesWidgetView: View {
    let entry: PinnedNotesEntry

    public init(entry: PinnedNotesEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "Pinned Notes", bundle: .module))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(entry.notes.prefix(4)) { note in
                HStack(spacing: 8) {
                    Image(systemName: note.icon)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .frame(width: 16)
                    Text(note.title)
                        .font(.callout)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Recent Notes (medium, interactive)

/// One row in the Recent Notes widget (path is relative to vault root).
public struct RecentNoteItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let relativePath: String
    public let modified: Date

    public init(id: String, title: String, relativePath: String, modified: Date) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.modified = modified
    }
}

/// Timeline entry: up to three most recently modified Markdown files.
public struct RecentNotesEntry: TimelineEntry, Sendable {
    public let date: Date
    public let notes: [RecentNoteItem]

    public init(date: Date, notes: [RecentNoteItem]) {
        self.date = date
        self.notes = notes
    }

    nonisolated(unsafe) public static let placeholder = RecentNotesEntry(
        date: .now,
        notes: [
            RecentNoteItem(id: "1", title: String(localized: "Meeting Notes", bundle: .module), relativePath: "Meeting.md", modified: .now),
            RecentNoteItem(id: "2", title: String(localized: "Ideas", bundle: .module), relativePath: "Ideas.md", modified: .now),
            RecentNoteItem(id: "3", title: String(localized: "Journal", bundle: .module), relativePath: "Journal.md", modified: .now),
        ]
    )
}

/// Provider for the Recent Notes home screen widget.
public struct RecentNotesProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> RecentNotesEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (RecentNotesEntry) -> Void) {
        completion(.placeholder)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<RecentNotesEntry>) -> Void) {
        let entry: RecentNotesEntry
        let d = UserDefaults(suiteName: "group.app.quartz.shared")
        if let vaultRoot = d?.url(forKey: "activeVaultURL") ?? d?.url(forKey: "defaultVaultRoot") {
            let notes = Self.findRecentNotes(in: vaultRoot, limit: 3)
            entry = RecentNotesEntry(date: .now, notes: notes)
        } else {
            entry = RecentNotesEntry(date: .now, notes: [])
        }
        completion(Timeline(entries: [entry], policy: .atEnd))
    }

    private static func relativePath(vaultRoot: URL, fileURL: URL) -> String {
        let v = vaultRoot.standardizedFileURL.path(percentEncoded: false)
        let f = fileURL.standardizedFileURL.path(percentEncoded: false)
        guard f.hasPrefix(v) else { return fileURL.lastPathComponent }
        var rel = String(f.dropFirst(v.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }

    private static func findRecentNotes(in vaultRoot: URL, limit: Int) -> [RecentNoteItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var scored: [(url: URL, date: Date)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            scored.append((fileURL, modified))
        }
        scored.sort { $0.date > $1.date }
        return scored.prefix(limit).map { pair in
            let rel = relativePath(vaultRoot: vaultRoot, fileURL: pair.url)
            let title = pair.url.deletingPathExtension().lastPathComponent
            return RecentNoteItem(id: rel, title: title, relativePath: rel, modified: pair.date)
        }
    }
}

/// Medium home screen widget: three recent notes + new note (interactive on iOS 17+).
@available(iOS 17.0, macOS 14.0, *)
public struct RecentNotesWidgetView: View {
    let entry: RecentNotesEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: RecentNotesEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                VStack(alignment: .leading) {
                    Text(String(localized: "Recent Notes", bundle: .module))
                        .font(.caption.bold())
                    Text(entry.notes.first?.title ?? "—")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding()
            }
        }
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(QuartzColors.accent.opacity(0.07))
                .overlay {
                    ContainerRelativeShape()
                        .strokeBorder(QuartzColors.accent.opacity(0.25), lineWidth: 1)
                }
        }
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuartzColors.accent)
                    Text(String(localized: "Recent Notes", bundle: .module))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if entry.notes.isEmpty {
                    Text(String(localized: "No notes yet — tap + to create one.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entry.notes) { note in
                            #if canImport(AppIntents)
                            Button(intent: OpenNoteIntent(relativePath: note.relativePath)) {
                                noteRowLabel(note)
                            }
                            .buttonStyle(.plain)
                            #else
                            Link(destination: noteDeepLink(note)) {
                                noteRowLabel(note)
                            }
                            #endif
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            #if canImport(AppIntents)
            Button(intent: CreateNoteIntent()) {
                ZStack {
                    Circle()
                        .fill(QuartzColors.accent.gradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: QuartzColors.accent.opacity(0.35), radius: 6, y: 3)
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            #else
            Link(destination: URL(string: "quartz://new")!) {
                ZStack {
                    Circle()
                        .fill(QuartzColors.accent.gradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            #endif
        }
        .padding(12)
    }

    private func noteDeepLink(_ note: RecentNoteItem) -> URL {
        var url = URL(string: "quartz://note")!
        for segment in note.relativePath.split(separator: "/") where !segment.isEmpty {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    private func noteRowLabel(_ note: RecentNoteItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "doc.text.fill")
                .font(.caption2)
                .foregroundStyle(QuartzColors.noteBlue)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(note.modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Writing Streak Widget

/// Timeline entry for the Writing Streak widget.
/// Reads streak data from shared UserDefaults (App Group).
public struct WritingStreakEntry: TimelineEntry, Sendable {
    public let date: Date
    public let streakDays: Int
    public let totalNotes: Int
    public let todayWordCount: Int

    public init(date: Date, streakDays: Int, totalNotes: Int, todayWordCount: Int) {
        self.date = date
        self.streakDays = streakDays
        self.totalNotes = totalNotes
        self.todayWordCount = todayWordCount
    }

    nonisolated(unsafe) public static let placeholder = WritingStreakEntry(
        date: .now,
        streakDays: 7,
        totalNotes: 42,
        todayWordCount: 350
    )
}

/// Timeline provider for the Writing Streak widget.
public struct WritingStreakProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> WritingStreakEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (WritingStreakEntry) -> Void) {
        completion(loadEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<WritingStreakEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh at midnight to update streak
        let nextMidnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func loadEntry() -> WritingStreakEntry {
        let d = UserDefaults(suiteName: "group.app.quartz.shared")
        let streak = d?.integer(forKey: "quartz.widget.streakDays") ?? 0
        let totalNotes = d?.integer(forKey: "quartz.widget.totalNotes") ?? 0
        let todayWords = d?.integer(forKey: "quartz.widget.todayWordCount") ?? 0
        return WritingStreakEntry(
            date: .now,
            streakDays: streak,
            totalNotes: totalNotes,
            todayWordCount: todayWords
        )
    }
}

/// Writing Streak widget view — motivational stats on the Home Screen.
@available(iOS 17.0, macOS 14.0, *)
public struct WritingStreakWidgetView: View {
    let entry: WritingStreakEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: WritingStreakEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(.regularMaterial)
        }
        .widgetURL(URL(string: "quartz://dashboard"))
    }

    private var smallLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "Streak", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(entry.streakDays)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(entry.streakDays > 0 ? QuartzColors.accent : .secondary)

            Text(entry.streakDays == 1
                ? String(localized: "day", bundle: .module)
                : String(localized: "days", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            // Streak flame
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(entry.streakDays > 0 ? QuartzColors.accent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(entry.streakDays > 0 ? .orange : .secondary)
                }
                Text("\(entry.streakDays) \(entry.streakDays == 1 ? "day" : "days")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(entry.streakDays > 0 ? QuartzColors.accent : .secondary)
            }

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                statRow(icon: "doc.text.fill", label: String(localized: "Notes", bundle: .module), value: "\(entry.totalNotes)")
                statRow(icon: "character.cursor.ibeam", label: String(localized: "Today", bundle: .module), value: "\(entry.todayWordCount) \(String(localized: "words", bundle: .module))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // New note button
            #if canImport(AppIntents)
            Button(intent: CreateNoteIntent()) {
                newNoteCircle
            }
            .buttonStyle(.plain)
            #else
            Link(destination: URL(string: "quartz://new")!) {
                newNoteCircle
            }
            #endif
        }
        .padding(14)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private var newNoteCircle: some View {
        ZStack {
            Circle()
                .fill(QuartzColors.accent.gradient)
                .frame(width: 40, height: 40)
                .shadow(color: QuartzColors.accent.opacity(0.3), radius: 4, y: 2)
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}
#endif
