import SwiftUI

/// Sidebar row icon size – compact for cleaner sidebar.
private var fileNodeIconSize: CGFloat {
    #if os(macOS)
    14
    #else
    12
    #endif
}

/// Sidebar row metadata font – larger on macOS.
private var fileNodeMetadataFont: Font {
    #if os(macOS)
    .subheadline
    #else
    .caption
    #endif
}

/// Formats a date as relative time (e.g. "24 min ago") without ticking every second.
/// SwiftUI's Text(date, style: .relative) updates continuously; this gives a stable display.
private func relativeTimeString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.formattingContext = .standalone
    return formatter.localizedString(for: date, relativeTo: Date())
}

/// Single row in the sidebar for a FileNode (embedded in `SidebarTreeNode` within the sidebar `List`).
public struct FileNodeRow: View {
    public let node: FileNode
    @Environment(\.appearanceManager) private var appearance

    public init(node: FileNode) {
        self.node = node
    }

    public var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.body.weight(node.isFolder ? .semibold : .regular))
                        .lineLimit(1)

                    // Cloud status indicator for iCloud files
                    if node.isNote {
                        cloudStatusIndicator
                        conflictIndicator
                    }
                }

                if node.isNote {
                    Text(relativeTimeString(from: node.metadata.modifiedAt))
                        .font(fileNodeMetadataFont)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: iconName)
                .font(.system(size: fileNodeIconSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: fileNodeIconSize + 4)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Shows cloud status for iCloud files that need downloading.
    @ViewBuilder
    private var cloudStatusIndicator: some View {
        switch node.metadata.cloudStatus {
        case .evicted:
            Image(systemName: "icloud.and.arrow.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Not downloaded from iCloud", bundle: .module))
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .font(.caption2)
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
                .accessibilityLabel(String(localized: "Downloading from iCloud", bundle: .module))
        case .local, .downloaded:
            EmptyView()
        }
    }

    /// Shows a warning badge when the file has unresolved iCloud sync conflicts.
    @ViewBuilder
    private var conflictIndicator: some View {
        if node.metadata.hasConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityLabel(String(localized: "Has sync conflict", bundle: .module))
        }
    }

    private var accessibilityDescription: String {
        var parts = [displayName]
        switch node.nodeType {
        case .folder:
            parts.append(String(localized: "Folder", bundle: .module))
        case .note:
            parts.append(String(localized: "Note", bundle: .module))
            parts.append(relativeTimeString(from: node.metadata.modifiedAt))
            // Include cloud status for VoiceOver
            switch node.metadata.cloudStatus {
            case .evicted:
                parts.append(String(localized: "Not downloaded from iCloud", bundle: .module))
            case .downloading:
                parts.append(String(localized: "Downloading from iCloud", bundle: .module))
            case .local, .downloaded:
                break
            }
            // Include conflict warning for VoiceOver
            if node.metadata.hasConflict {
                parts.append(String(localized: "Has sync conflict", bundle: .module))
            }
        case .asset:
            parts.append(String(localized: "Attachment", bundle: .module))
        case .canvas:
            parts.append(String(localized: "Canvas", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }

    private var displayName: String {
        if node.isNote {
            return node.name.replacingOccurrences(of: ".md", with: "")
        }
        return node.name
    }

    private var iconName: String {
        switch node.nodeType {
        case .folder: "folder"
        case .note: "doc.text"
        case .asset: "photo"
        case .canvas: "scribble.variable"
        }
    }

    private var iconColor: Color {
        .primary
    }
}
