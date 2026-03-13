import SwiftUI

/// Einzelne Zeile in der Sidebar für einen FileNode.
public struct FileNodeRow: View {
    public let node: FileNode

    public init(node: FileNode) {
        self.node = node
    }

    public var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .lineLimit(1)

                if node.isNote {
                    Text(node.metadata.modifiedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
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
        case .canvas: "pencil.tip.crop.circle.fill"
        }
    }

    private var iconColor: Color {
        switch node.nodeType {
        case .folder: .accentColor
        case .note: .primary
        case .asset: .orange
        case .canvas: .purple
        }
    }
}
