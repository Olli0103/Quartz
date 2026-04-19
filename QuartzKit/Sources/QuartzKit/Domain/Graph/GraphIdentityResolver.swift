import Foundation
import CryptoKit

// MARK: - Note Identity

/// Represents the identity of a note for graph resolution.
/// Encapsulates all the ways a note can be referenced: filename, title, aliases.
public struct NoteIdentity: Hashable, Sendable {
    public let url: URL
    public let filename: String
    public let frontmatterTitle: String?
    public let aliases: [String]
    public var tags: [String]

    public init(
        url: URL,
        filename: String,
        frontmatterTitle: String? = nil,
        aliases: [String] = [],
        tags: [String] = []
    ) {
        self.url = CanonicalNoteIdentity.canonicalFileURL(for: url)
        self.filename = filename
        self.frontmatterTitle = frontmatterTitle
        self.aliases = aliases
        self.tags = tags
    }

    /// Builds the canonical explicit-link identity for a note node in the vault tree.
    /// KG1 uses the note's canonical file URL as the one explicit note-to-note identity.
    public init(noteNode: FileNode) {
        self.init(
            url: noteNode.url,
            filename: noteNode.name.replacingOccurrences(of: ".md", with: ""),
            frontmatterTitle: noteNode.frontmatter?.title,
            aliases: noteNode.frontmatter?.aliases ?? [],
            tags: noteNode.frontmatter?.tags ?? []
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: NoteIdentity, rhs: NoteIdentity) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Graph Identity Resolver

/// Resolves wiki-link targets to note URLs with robust matching.
///
/// Supports:
/// - Exact filename match
/// - Frontmatter title match
/// - Alias match
/// - Case-insensitive matching
/// - Punctuation normalization (colons, underscores → spaces)
/// - Folder path resolution (e.g., `[[folder/note]]`)
/// - Fuzzy matching for typos (Levenshtein distance)
///
/// Thread-safe via actor isolation.
public actor GraphIdentityResolver {
    private var identities: [URL: NoteIdentity] = [:]
    private var nameIndex: [String: URL] = [:]
    private var pathIndex: [String: URL] = [:]
    private var tagIndex: [String: Set<URL>] = [:]

    public init() {}

    // MARK: - Registration

    /// Registers a note identity, indexing all resolution paths.
    public func register(_ identity: NoteIdentity) {
        identities[identity.url] = identity

        // Index by filename (normalized)
        let normalizedFilename = Self.normalize(identity.filename)
        nameIndex[normalizedFilename] = identity.url

        // Index by frontmatter title if present
        if let title = identity.frontmatterTitle {
            nameIndex[Self.normalize(title)] = identity.url
        }

        // Index by aliases
        for alias in identity.aliases {
            nameIndex[Self.normalize(alias)] = identity.url
        }

        // Index by full path and partial paths for folder resolution
        indexPaths(for: identity)

        // Index by tags
        for tag in identity.tags {
            tagIndex[tag.lowercased(), default: []].insert(identity.url)
        }
    }

    /// Indexes path variants for folder-prefixed wiki-link resolution.
    private func indexPaths(for identity: NoteIdentity) {
        let path = identity.url.path(percentEncoded: false)

        // Full path without extension
        let withoutExt = path.replacingOccurrences(of: ".md", with: "")
        pathIndex[Self.normalize(withoutExt)] = identity.url

        // Extract path components after vault root
        let components = withoutExt.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }

        // Index progressively shorter suffixes: "a/b/c", "b/c", "c"
        for startIndex in 0..<components.count {
            let suffix = components[startIndex...].joined(separator: "/")
            let normalized = Self.normalize(suffix)
            // Don't overwrite if already indexed (prefer shorter paths)
            if pathIndex[normalized] == nil {
                pathIndex[normalized] = identity.url
            }
        }
    }

    /// Unregisters a note identity.
    public func unregister(_ identity: NoteIdentity) {
        identities.removeValue(forKey: identity.url)

        // Clean up name index
        let normalizedFilename = Self.normalize(identity.filename)
        if nameIndex[normalizedFilename] == identity.url {
            nameIndex.removeValue(forKey: normalizedFilename)
        }

        if let title = identity.frontmatterTitle {
            let normalizedTitle = Self.normalize(title)
            if nameIndex[normalizedTitle] == identity.url {
                nameIndex.removeValue(forKey: normalizedTitle)
            }
        }

        for alias in identity.aliases {
            let normalizedAlias = Self.normalize(alias)
            if nameIndex[normalizedAlias] == identity.url {
                nameIndex.removeValue(forKey: normalizedAlias)
            }
        }

        // Clean up tag index
        for tag in identity.tags {
            tagIndex[tag.lowercased()]?.remove(identity.url)
        }
    }

    /// Renames a note, preserving backward compatibility by adding the old filename as an alias.
    ///
    /// **Per CODEX.md F5:** Atomic rename operation that:
    /// 1. Unregisters old identity
    /// 2. Registers new identity with old filename as additional alias
    /// 3. Updates all indices atomically
    ///
    /// - Parameters:
    ///   - oldURL: The original note URL
    ///   - newURL: The new note URL after rename
    ///   - newFilename: The new filename (without extension)
    ///   - frontmatterTitle: Optional frontmatter title (preserved or updated)
    ///   - existingAliases: Existing aliases to preserve
    ///   - tags: Tags to preserve
    public func rename(
        from oldURL: URL,
        to newURL: URL,
        newFilename: String,
        frontmatterTitle: String? = nil,
        existingAliases: [String] = [],
        tags: [String] = []
    ) {
        guard let oldIdentity = identities[oldURL] else { return }

        // Unregister old identity
        unregister(oldIdentity)

        // Create new identity with old filename as alias for backward compatibility
        var allAliases = existingAliases
        let oldFilename = oldIdentity.filename
        if !allAliases.contains(oldFilename) && oldFilename != newFilename {
            allAliases.append(oldFilename)
        }

        let newIdentity = NoteIdentity(
            url: newURL,
            filename: newFilename,
            frontmatterTitle: frontmatterTitle ?? oldIdentity.frontmatterTitle,
            aliases: allAliases,
            tags: tags.isEmpty ? oldIdentity.tags : tags
        )

        register(newIdentity)
    }

    // MARK: - Resolution

    /// Resolves a wiki-link target to a note URL.
    ///
    /// Resolution order:
    /// 1. Exact normalized name match (filename, title, alias)
    /// 2. Folder path match (e.g., `folder/note`)
    /// 3. Fuzzy match (if enabled, for typos)
    ///
    /// - Parameters:
    ///   - target: The wiki-link target text
    ///   - fuzzy: Enable fuzzy matching for close matches
    /// - Returns: The resolved note URL, or nil if not found
    public func resolve(_ target: String, fuzzy: Bool = false) -> URL? {
        let normalized = Self.normalize(target)

        // 1. Exact name match
        if let url = nameIndex[normalized] {
            return url
        }

        // 1b. Try with hyphens converted to spaces (common alternative)
        let hyphenToSpace = normalized.replacingOccurrences(of: "-", with: " ")
        if hyphenToSpace != normalized, let url = nameIndex[hyphenToSpace] {
            return url
        }

        // 2. Path match (for folder-prefixed links)
        if let url = pathIndex[normalized] {
            return url
        }

        // 3. Fuzzy matching
        if fuzzy {
            return fuzzyResolve(normalized)
        }

        return nil
    }

    /// Performs fuzzy resolution using Levenshtein distance.
    private func fuzzyResolve(_ normalizedTarget: String) -> URL? {
        let threshold = max(2, normalizedTarget.count / 5) // Allow ~20% error

        var bestMatch: (url: URL, distance: Int)?

        for (name, url) in nameIndex {
            let distance = Self.levenshteinDistance(normalizedTarget, name)
            if distance <= threshold {
                if bestMatch == nil || distance < bestMatch!.distance {
                    bestMatch = (url, distance)
                }
            }
        }

        return bestMatch?.url
    }

    // MARK: - Stable ID

    /// Returns a stable identifier for a note URL.
    /// Uses SHA256 hash of the path for consistency across sessions.
    public func stableID(for url: URL) -> String? {
        let path = url.path(percentEncoded: false)
        let hash = SHA256.hash(data: Data(path.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Tag Queries

    /// Returns all note URLs with a given tag.
    public func notesWithTag(_ tag: String) -> [URL] {
        Array(tagIndex[tag.lowercased()] ?? [])
    }

    /// Returns tags that appear in at least `minCount` notes.
    public func significantConcepts(minCount: Int) -> [String] {
        tagIndex.filter { $0.value.count >= minCount }.map(\.key)
    }

    // MARK: - Utility

    /// Returns all registered note URLs.
    public func allRegisteredURLs() -> [URL] {
        Array(identities.keys)
    }

    /// Returns the identity for a URL if registered.
    public func identity(for url: URL) -> NoteIdentity? {
        identities[url]
    }

    // MARK: - Normalization

    /// Normalizes text for comparison:
    /// 1. Lowercase
    /// 2. Replace punctuation (colons, underscores) with spaces
    /// 3. Remove non-alphanumeric except spaces and hyphens
    /// 4. Collapse whitespace
    /// 5. Trim
    public static func normalize(_ text: String) -> String {
        var result = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if result.lowercased().hasSuffix(".md") {
            result.removeLast(3)
        }

        // Replace common punctuation with spaces
        result = result.replacingOccurrences(of: ":", with: " ")
        result = result.replacingOccurrences(of: "_", with: " ")

        // Remove other punctuation (keep letters, numbers, spaces, hyphens)
        result = result.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
            scalar == " " ||
            scalar == "-" ||
            scalar == "/"
        }.map(String.init).joined()

        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Levenshtein Distance

    /// Calculates the Levenshtein edit distance between two strings.
    /// Used for fuzzy matching.
    public static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }
}
