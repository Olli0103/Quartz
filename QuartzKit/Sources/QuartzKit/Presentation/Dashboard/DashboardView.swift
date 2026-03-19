#if os(macOS)
import SwiftUI

/// macOS Dashboard: Brain Garden hero, Recent Notes, Quick Capture.
/// Matches the "Quartz Second Brain" design with card-based layout.
public struct DashboardView: View {
    let sidebarViewModel: SidebarViewModel?
    let onSelectNote: (URL) -> Void
    let onNewNote: () -> Void
    let onExploreGraph: () -> Void

    private static let background = Color(hex: 0xFDFBF8)
    private static let navyButton = Color(hex: 0x1E3A5F)
    private static let cardRadius: CGFloat = 20

    public init(
        sidebarViewModel: SidebarViewModel?,
        onSelectNote: @escaping (URL) -> Void,
        onNewNote: @escaping () -> Void,
        onExploreGraph: @escaping () -> Void
    ) {
        self.sidebarViewModel = sidebarViewModel
        self.onSelectNote = onSelectNote
        self.onNewNote = onNewNote
        self.onExploreGraph = onExploreGraph
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection

                brainGardenCard

                recentNotesSection

                bottomCardsRow
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Self.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Dashboard", bundle: .module))
                .font(.system(size: 28, weight: .bold))
            Text(String(localized: "Nurturing your digital connections.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Brain Garden Hero

    private var brainGardenCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "KNOWLEDGE GRAPH", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuartzColors.accent)
                    .textCase(.uppercase)
                Text(String(localized: "Brain Garden", bundle: .module))
                    .font(.title2.weight(.bold))
                Text("\(nodeCount) " + String(localized: "connected nodes", bundle: .module) + ". " + String(localized: "Your mental network is growing.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 12)
                Button {
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
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Minimal graph visual
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

    // MARK: - Recent Notes

    private var recentNotesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "Recent Notes", bundle: .module))
                    .font(.headline)
                Spacer()
                Button(String(localized: "View all", bundle: .module)) {
                    // Could navigate to All Notes
                }
                .font(.subheadline)
                .foregroundStyle(QuartzColors.accent)
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentNotes) { note in
                        RecentNoteCard(note: note, onTap: { onSelectNote(note.url) })
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
            pinnedThoughtCard
            quickCaptureCard
        }
    }

    private var pinnedThoughtCard: some View {
        HStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [QuartzColors.canvasPurple.opacity(0.3), QuartzColors.noteBlue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 80)
                .overlay {
                    Image(systemName: "lightbulb.fill")
                        .font(.title)
                        .foregroundStyle(QuartzColors.canvasPurple)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                    Text(String(localized: "PINNED THOUGHT", bundle: .module))
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                }
                .foregroundStyle(QuartzColors.canvasPurple)
                Text(String(localized: "The Architecture of Silence", bundle: .module))
                    .font(.headline)
                Text(String(localized: "A moment of clarity in the noise of daily life.", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

// MARK: - Recent Note Card

private struct RecentNoteCard: View {
    let note: FileNode
    let onTap: () -> Void

    private static let iconColors: [Color] = [QuartzColors.accent, QuartzColors.noteBlue, QuartzColors.canvasPurple]

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((Self.iconColors[note.id.hashValue % 3]).opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.subheadline)
                                .foregroundStyle(Self.iconColors[note.id.hashValue % 3])
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
