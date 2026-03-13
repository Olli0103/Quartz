import Foundation

/// Typ eines Eintrags im Vault-Dateibaum.
public enum NodeType: String, Codable, Sendable {
    case folder
    case note
    case asset
    case canvas
}
