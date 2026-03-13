#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

// MARK: - Latest Note Widget

/// Timeline Entry für das "Latest Note" Widget.
public struct LatestNoteEntry: TimelineEntry {
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

    public static let placeholder = LatestNoteEntry(
        date: .now,
        noteTitle: "My Note",
        notePreview: "Start writing to see your latest note here…",
        noteURL: nil
    )
}

/// Timeline Provider für das Latest Note Widget.
public struct LatestNoteProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> LatestNoteEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (LatestNoteEntry) -> Void) {
        completion(.placeholder)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<LatestNoteEntry>) -> Void) {
        // In der echten Implementierung: Vault lesen und neueste Notiz finden
        let entry = LatestNoteEntry.placeholder
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}

/// View für das Latest Note Widget (Lockscreen + Home Screen).
public struct LatestNoteWidgetView: View {
    let entry: LatestNoteEntry
    @Environment(\.widgetFamily) var family

    public init(entry: LatestNoteEntry) {
        self.entry = entry
    }

    public var body: some View {
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
                    Text("Latest Note")
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
                        Text("Latest Note")
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
}

// MARK: - Quick Capture Widget

/// Timeline Entry für Quick Capture (statisch).
public struct QuickCaptureEntry: TimelineEntry {
    public let date: Date

    public init(date: Date = .now) {
        self.date = date
    }
}

/// Timeline Provider für das Quick Capture Widget.
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

/// View für das Quick Capture Widget.
public struct QuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) var family

    public init() {}

    public var body: some View {
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
                Text("Quick Note")
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            Image(systemName: "square.and.pencil")
        }
    }
}

// MARK: - Pinned Notes Widget

/// Timeline Entry für Pinned Notes.
public struct PinnedNotesEntry: TimelineEntry {
    public let date: Date
    public let notes: [PinnedNote]

    public init(date: Date, notes: [PinnedNote]) {
        self.date = date
        self.notes = notes
    }

    public static let placeholder = PinnedNotesEntry(
        date: .now,
        notes: [
            PinnedNote(title: "Meeting Notes", icon: "doc.text"),
            PinnedNote(title: "Shopping List", icon: "checklist"),
            PinnedNote(title: "Project Ideas", icon: "lightbulb"),
        ]
    )
}

/// Eine gepinnte Notiz im Widget.
public struct PinnedNote: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let icon: String

    public init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }
}

/// View für das Pinned Notes Widget (Medium/Large).
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
                Text("Pinned Notes")
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
