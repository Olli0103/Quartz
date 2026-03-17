#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

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
        let preview = (try? String(contentsOf: url, encoding: .utf8))?
            .components(separatedBy: "---").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(100)
            .description ?? ""

        return LatestNoteEntry(
            date: latestDate,
            noteTitle: title,
            notePreview: preview,
            noteURL: url
        )
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
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text(String(localized: "Quick Note", bundle: .module))
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            Image(systemName: "square.and.pencil")
        }
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
#endif
