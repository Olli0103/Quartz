import Foundation
import CoreGraphics
import CryptoKit

/// Persisted cache for the knowledge graph. Avoids rebuilding on every open.
///
/// Cache is stored at `{vault}/.quartz/graph-cache.json`.
/// Invalidated when any note's modification date changes.
public struct GraphCache: Sendable {
    private let cacheURL: URL

    public init(vaultRoot: URL) {
        cacheURL = vaultRoot
            .appending(path: ".quartz")
            .appending(path: "graph-cache.json")
    }

    /// Cached graph data.
    public struct CachedGraph: Codable, Sendable {
        public let nodes: [CachedNode]
        public let edges: [CachedEdge]
        public let fingerprint: String

        public struct CachedNode: Codable, Sendable {
            public let id: String
            public let title: String
            public let url: URL
            public let x: CGFloat
            public let y: CGFloat
            public let connectionCount: Int
            public let tags: [String]?
        }

        public struct CachedEdge: Codable, Sendable {
            public let from: String
            public let to: String
            public let isSemantic: Bool
        }
    }

    /// Computes a fingerprint from note URLs and modification dates.
    public func computeFingerprint(for noteURLs: [URL]) -> String {
        let fm = FileManager.default
        var pairs: [(String, TimeInterval)] = []
        for url in noteURLs {
            let mtime: TimeInterval
            if let attrs = try? fm.attributesOfItem(atPath: url.path(percentEncoded: false)),
               let date = attrs[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
            } else {
                mtime = 0
            }
            pairs.append((url.absoluteString, mtime))
        }
        pairs.sort { $0.0 < $1.0 }
        let data = pairs.flatMap { "\($0.0):\($0.1)".utf8 }
        let hash = SHA256.hash(data: Data(data))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Loads cached graph if fingerprint matches.
    public func loadIfValid(fingerprint: String) -> CachedGraph? {
        guard FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)) else { return nil }
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedGraph.self, from: data),
              cached.fingerprint == fingerprint else {
            return nil
        }
        return cached
    }

    /// Saves graph to cache.
    public func save(_ graph: CachedGraph) throws {
        let dir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(graph)
        try data.write(to: cacheURL, options: .atomic)
    }
}
