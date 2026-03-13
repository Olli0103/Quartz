import SwiftUI

/// Einzelne Zeile in der Sidebar für einen FileNode.
/// Cleanes Design mit subtilen Farben und Typografie.
public struct FileNodeRow: View {
    public let node: FileNode

    public init(node: FileNode) {
        self.node = node
    }

    public var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.callout.weight(node.isFolder ? .semibold : .regular))
                    .lineLimit(1)

                if node.isNote {
                    HStack(spacing: 6) {
                        Text(node.metadata.modifiedAt, style: .relative)

                        if let tags = node.frontmatter?.tags, !tags.isEmpty {
                            Text("·")
                            Text(tags.prefix(2).joined(separator: ", "))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 22)
        }
        .padding(.vertical, 1)
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
        case .folder: QuartzColors.folderYellow
        case .note: QuartzColors.noteBlue
        case .asset: QuartzColors.assetOrange
        case .canvas: QuartzColors.canvasPurple
        }
    }
}
