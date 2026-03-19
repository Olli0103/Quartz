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

/// Single row in the sidebar for a FileNode.
public struct FileNodeRow: View {
    public let node: FileNode
    @Environment(\.appearanceManager) private var appearance

    public init(node: FileNode) {
        self.node = node
    }

    public var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.body.weight(node.isFolder ? .semibold : .regular))
                    .lineLimit(1)

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

    private var accessibilityDescription: String {
        var parts = [displayName]
        parts.append(node.isFolder
            ? String(localized: "Folder", bundle: .module)
            : String(localized: "Note", bundle: .module))
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
        case .folder: "folder.fill"
        case .note: "doc.text.fill"
        case .asset: "photo.fill"
        case .canvas: "scribble.variable"
        }
    }

    private var iconColor: Color {
        switch node.nodeType {
        case .folder: appearance.accentColor.opacity(0.7)
        case .note: appearance.accentColor.opacity(0.5)
        case .asset: QuartzColors.assetOrange
        case .canvas: QuartzColors.canvasPurple
        }
    }
}
