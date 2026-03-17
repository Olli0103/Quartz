import Foundation

/// Type of an entry in the vault file tree.
public enum NodeType: String, Codable, Sendable {
    case folder
    case note
    case asset
    case canvas
}
