import Foundation
import NaturalLanguage
import Accelerate
import CryptoKit
import os

// MARK: - Embedding Entry

/// An entry in the vector index.
public struct EmbeddingEntry: Codable, Sendable {
    public let noteID: UUID
    public let chunkIndex: Int
    public let chunkText: String
    public let embedding: [Float]
    public let lastUpdated: Date

    public init(noteID: UUID, chunkIndex: Int, chunkText: String, embedding: [Float], lastUpdated: Date = Date()) {
        self.noteID = noteID
        self.chunkIndex = chunkIndex
        self.chunkText = chunkText
        self.embedding = embedding
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Vector Embedding Service

/// Service for local vector embeddings and semantic search.
///
/// Uses `NLEmbedding` for on-device embeddings and
/// `Accelerate` for efficient cosine similarity.
/// Stored as a binary index in `.quartz/embeddings.idx`.
///
/// **Memory Management:**
/// - For vaults with 10k+ notes, consider enabling `compactMode`
/// - Embeddings are ~2KB each; 10k chunks ≈ 20MB RAM
/// - `compactIndex()` removes chunk text to reduce memory
/// - Call `loadIndex()` after memory warnings to reload minimal state
public actor VectorEmbeddingService {
    private var index: [EmbeddingEntry] = []
    private let indexURL: URL
    private let chunkSize: Int
    private let language: NLLanguage
    private let logger = Logger(subsystem: "com.quartz", category: "Embeddings")

    /// Maximum recommended entries before performance degrades.
    /// At ~2KB per entry, 50k entries ≈ 100MB RAM.
    public static let recommendedMaxEntries = 50_000

    /// Dimension of the embedding vectors.
    public var embeddingDimension: Int { 512 }

    /// Estimated memory usage in bytes.
    public var estimatedMemoryUsage: Int {
        // UUID: 16 bytes, chunkIndex: 8, lastUpdated: 8
        // embedding: 512 * 4 = 2048 bytes
        // chunkText: variable, assume ~200 chars average
        let baseSize = 16 + 8 + 8 + 2048
        let textSize = index.reduce(0) { $0 + $1.chunkText.utf8.count }
        return index.count * baseSize + textSize
    }

    public init(
        vaultURL: URL,
        chunkSize: Int = 512,
        language: NLLanguage = .english
    ) {
        self.indexURL = Self.indexFileURL(for: vaultURL)
        self.chunkSize = chunkSize
        self.language = language
    }

    /// Canonical embedding index URL. Diagnostics and the loader must use this
    /// same helper so path contradictions are diagnosable rather than inferred.
    public static func indexFileURL(for vaultURL: URL) -> URL {
        CanonicalNoteIdentity.canonicalFileURL(for: vaultURL)
            .appending(path: ".quartz", directoryHint: .isDirectory)
            .appending(path: "embeddings.idx")
    }

    public var indexFileURL: URL { indexURL }

    private static func isLikelyICloudURL(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.contains("/Library/Mobile Documents/")
            || path.contains("com~apple~CloudDocs")
    }

    private static func hasOtherPersistedQuartzState(near indexURL: URL) -> Bool {
        let directory = indexURL.deletingLastPathComponent()
        let knownFiles = [
            "preview-cache.json",
            "search-index.json",
            "ai_index.json",
            "recovery_journal.json"
        ]
        return knownFiles.contains { name in
            FileManager.default.fileExists(
                atPath: directory.appending(path: name).path(percentEncoded: false)
            )
        }
    }

    /// Detects the dominant language of a text using NLLanguageRecognizer.
    /// Falls back to the configured default language if detection fails.
    private func detectLanguage(for text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? language
    }

    // MARK: - Index Management

    // Binary format version for forward compatibility.
    private static let formatVersion: UInt32 = 1

    /// Loads the embedding index from disk (binary format).
    public func loadIndex() throws {
        let path = indexURL.path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path)
        QuartzDiagnostics.info(
            category: "Embeddings",
            "loadIndex pathCheck exists=\(exists) path=\(path)"
        )

        guard exists else {
            index = []
            logger.info("loadIndex: no index file found, starting fresh")
            if Self.isLikelyICloudURL(indexURL),
               Self.hasOtherPersistedQuartzState(near: indexURL) {
                let message = "Persisted embedding index is unavailable at load time for an iCloud-backed vault: \(path)"
                QuartzDiagnostics.warning(
                    category: "Embeddings",
                    "loadIndex deferred path=\(path) reason=iCloudIndexUnavailable action=skipSweepAndRetryLater"
                )
                throw EmbeddingIndexError.indexUnavailable(message)
            }
            QuartzDiagnostics.info(
                category: "Embeddings",
                "loadIndex missing path=\(path) reason=noPersistedIndexFound action=rebuildMayCreateFileLater"
            )
            return
        }

        let data = try CoordinatedFileWriter.shared.read(from: indexURL)
        do {
            index = try Self.decodeBinary(data)
        } catch {
            index = []
            logger.error("loadIndex: rejected \(self.indexURL.lastPathComponent, privacy: .public) bytes=\(data.count) reason=\(error.localizedDescription, privacy: .public)")
            QuartzDiagnostics.error(
                category: "Embeddings",
                "loadIndex rejected bytes=\(data.count) reason=\(error.localizedDescription) path=\(indexURL.path(percentEncoded: false))"
            )
            throw error
        }
        let uniqueNotes = Set(index.map(\.noteID)).count
        logger.info("loadIndex: loaded \(self.index.count) chunks from \(uniqueNotes) notes bytes=\(data.count)")
        QuartzDiagnostics.info(
            category: "Embeddings",
            "loadIndex loaded chunks=\(index.count) notes=\(uniqueNotes) bytes=\(data.count) path=\(indexURL.path(percentEncoded: false))"
        )
    }

    /// Saves the embedding index to disk (binary format).
    public func saveIndex() throws {
        let dir = indexURL.deletingLastPathComponent()
        try CoordinatedFileWriter.shared.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = Self.encodeBinary(index)
        try CoordinatedFileWriter.shared.write(data, to: indexURL)
    }

    // MARK: - Binary Serialization

    /// Encodes entries into a compact binary representation.
    ///
    /// Format per entry:
    /// - 16 bytes: UUID
    /// - 8 bytes: chunkIndex (Int, little-endian)
    /// - 8 bytes: lastUpdated (TimeInterval, little-endian)
    /// - 4 bytes: embeddingCount (UInt32, little-endian)
    /// - N×4 bytes: embedding floats (little-endian)
    /// - 4 bytes: chunkText byte length (UInt32, little-endian)
    /// - M bytes: chunkText UTF-8
    private static func encodeBinary(_ entries: [EmbeddingEntry]) -> Data {
        var data = Data()
        // Header: version + entry count
        var version = formatVersion.littleEndian
        data.append(Data(bytes: &version, count: 4))
        var count = UInt32(entries.count).littleEndian
        data.append(Data(bytes: &count, count: 4))

        for entry in entries {
            // UUID (16 bytes)
            let uuid = entry.noteID.uuid
            withUnsafeBytes(of: uuid) { data.append(contentsOf: $0) }

            // chunkIndex (8 bytes)
            var chunkIndex = Int64(entry.chunkIndex).littleEndian
            data.append(Data(bytes: &chunkIndex, count: 8))

            // lastUpdated as TimeInterval (8 bytes)
            var timestamp = entry.lastUpdated.timeIntervalSinceReferenceDate.bitPattern.littleEndian
            data.append(Data(bytes: &timestamp, count: 8))

            // embedding count + floats
            var embCount = UInt32(entry.embedding.count).littleEndian
            data.append(Data(bytes: &embCount, count: 4))
            for var f in entry.embedding {
                var bits = f.bitPattern.littleEndian
                data.append(Data(bytes: &bits, count: 4))
            }

            // chunkText as UTF-8
            let textData = Data(entry.chunkText.utf8)
            var textLen = UInt32(textData.count).littleEndian
            data.append(Data(bytes: &textLen, count: 4))
            data.append(textData)
        }

        return data
    }

    private static func decodeBinary(_ data: Data) throws -> [EmbeddingEntry] {
        var offset = 0

        func read<T>(_ type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else {
                throw EmbeddingIndexError.corruptedIndex
            }
            let value = data[offset..<offset+size].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            offset += size
            return value
        }

        let version = UInt32(littleEndian: try read(UInt32.self))
        guard version == formatVersion else {
            throw EmbeddingIndexError.unsupportedVersion(version)
        }

        let count = Int(UInt32(littleEndian: try read(UInt32.self)))
        if count == 0, offset != data.count {
            throw EmbeddingIndexError.trailingDataAfterDeclaredEntries(
                declaredEntries: count,
                trailingBytes: data.count - offset
            )
        }
        var entries: [EmbeddingEntry] = []
        entries.reserveCapacity(count)

        for _ in 0..<count {
            // UUID
            let uuidTuple: uuid_t = try read(uuid_t.self)
            let noteID = UUID(uuid: uuidTuple)

            // chunkIndex
            let chunkIndex = Int(Int64(littleEndian: try read(Int64.self)))

            // lastUpdated
            let timestampBits = UInt64(littleEndian: try read(UInt64.self))
            let lastUpdated = Date(timeIntervalSinceReferenceDate: Double(bitPattern: timestampBits))

            // embedding
            let embCount = Int(UInt32(littleEndian: try read(UInt32.self)))
            guard embCount > 0, embCount <= 4096 else {
                throw EmbeddingIndexError.invalidEmbeddingDimension(embCount)
            }
            var embedding: [Float] = []
            embedding.reserveCapacity(embCount)
            for _ in 0..<embCount {
                let bits = UInt32(littleEndian: try read(UInt32.self))
                embedding.append(Float(bitPattern: bits))
            }

            // chunkText
            let textLen = Int(UInt32(littleEndian: try read(UInt32.self)))
            guard offset + textLen <= data.count else {
                throw EmbeddingIndexError.corruptedIndex
            }
            let chunkText = String(decoding: data[offset..<offset+textLen], as: UTF8.self)
            offset += textLen

            entries.append(EmbeddingEntry(
                noteID: noteID,
                chunkIndex: chunkIndex,
                chunkText: chunkText,
                embedding: embedding,
                lastUpdated: lastUpdated
            ))
        }

        guard offset == data.count else {
            throw EmbeddingIndexError.trailingDataAfterDeclaredEntries(
                declaredEntries: count,
                trailingBytes: data.count - offset
            )
        }

        return entries
    }

    /// Maximum content size for indexing (500 KB). Larger documents are truncated.
    private static let maxIndexableContentSize = 500_000

    /// Indexes a note: chunk text → generate embeddings → store in index.
    public func indexNote(noteID: UUID, content: String) throws {
        // Remove old entries
        let removedCount = index.filter { $0.noteID == noteID }.count
        index.removeAll { $0.noteID == noteID }

        guard !content.isEmpty else {
            logger.debug("indexNote: empty content for \(noteID), skipped")
            return
        }

        // Truncate very large documents to prevent excessive memory usage
        let truncated = content.count > Self.maxIndexableContentSize
            ? String(content.prefix(Self.maxIndexableContentSize))
            : content

        // Split text into chunks
        let chunks = chunkText(truncated)

        // Generate embeddings
        var addedCount = 0
        for (i, chunk) in chunks.enumerated() {
            if let embedding = generateEmbedding(for: chunk) {
                let entry = EmbeddingEntry(
                    noteID: noteID,
                    chunkIndex: i,
                    chunkText: chunk,
                    embedding: embedding
                )
                index.append(entry)
                addedCount += 1
            }
        }

        logger.debug("indexNote: \(noteID) — \(chunks.count) chunks, \(addedCount) embedded (removed \(removedCount) old). Total index: \(self.index.count)")
    }

    /// Removes all embeddings for a note.
    public func removeNote(_ noteID: UUID) {
        index.removeAll { $0.noteID == noteID }
    }

    // MARK: - Semantic Search

    /// Searches for semantically similar chunks.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Maximum number of results
    ///   - threshold: Minimum cosine similarity (0.0-1.0)
    /// - Returns: Sorted results (highest similarity first)
    public func search(
        query: String,
        limit: Int = 10,
        threshold: Float = 0.3
    ) -> [SearchResult] {
        guard let queryEmbedding = generateEmbedding(for: query) else {
            logger.warning("search: failed to generate embedding for query, returning empty")
            QuartzDiagnostics.warning(
                category: "Embeddings",
                "Search failed to generate embedding for query; returning empty result"
            )
            return []
        }

        var results: [SearchResult] = []

        for entry in index {
            let similarity = cosineSimilarity(queryEmbedding, entry.embedding)
            if similarity >= threshold {
                results.append(SearchResult(
                    entry: entry,
                    similarity: similarity
                ))
            }
        }

        let sorted = results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }

        let uniqueNotes = Set(sorted.map(\.entry.noteID)).count
        let topScore = sorted.first?.similarity ?? 0
        logger.debug("search: query='\(query.prefix(50))' index=\(self.index.count) threshold=\(threshold) matches=\(results.count) returned=\(sorted.count) uniqueNotes=\(uniqueNotes) topScore=\(topScore)")

        return sorted
    }

    /// Number of indexed chunks.
    public var entryCount: Int { index.count }

    /// Number of unique notes in the index.
    public var indexedNoteCount: Int { Set(index.map(\.noteID)).count }

    /// All indexed note IDs.
    public var indexedNoteIDs: Set<UUID> {
        Set(index.map(\.noteID))
    }

    /// Why a note needs embedding work during a sweep.
    public enum PendingReason: String, Sendable {
        case neverIndexed
        case modifiedAfterIndex
        case missingModificationDate
    }

    /// Returns the pending reason for a note, or `nil` when the persisted index is current.
    public func pendingReason(
        for url: URL,
        vaultRoot: URL,
        modificationDate mtime: Date?
    ) -> PendingReason? {
        let stableID = Self.stableNoteID(for: url, vaultRoot: vaultRoot)
        let lastIndexed = lastIndexedDate(for: stableID)
        guard let mtime else {
            return .missingModificationDate
        }
        guard let lastIndexed else {
            return .neverIndexed
        }
        return mtime <= lastIndexed ? nil : .modifiedAfterIndex
    }

    // MARK: - Memory Management

    /// Index health status for memory monitoring.
    public enum IndexHealth: Sendable {
        case healthy
        case warning(reason: String)
        case critical(reason: String)
    }

    /// Checks index health and returns status with recommendations.
    public func checkIndexHealth() -> IndexHealth {
        let count = index.count
        let memoryMB = estimatedMemoryUsage / (1024 * 1024)

        if count > Self.recommendedMaxEntries {
            return .critical(reason: "Index has \(count) entries (>\(Self.recommendedMaxEntries)). Consider compacting or pruning.")
        }

        if memoryMB > 80 {
            return .critical(reason: "Memory usage ~\(memoryMB)MB. Consider compacting to reduce footprint.")
        }

        if count > Self.recommendedMaxEntries / 2 {
            return .warning(reason: "Index approaching limits (\(count)/\(Self.recommendedMaxEntries)). Monitor memory usage.")
        }

        if memoryMB > 40 {
            return .warning(reason: "Memory usage ~\(memoryMB)MB. Consider enabling compact mode for large vaults.")
        }

        return .healthy
    }

    /// Compacts the index by clearing chunk text to reduce memory.
    /// After compacting, search results will only return note IDs (no preview text).
    /// The index remains fully functional for similarity search.
    public func compactIndex() {
        let beforeMemory = estimatedMemoryUsage
        index = index.map { entry in
            EmbeddingEntry(
                noteID: entry.noteID,
                chunkIndex: entry.chunkIndex,
                chunkText: "", // Clear text to save memory
                embedding: entry.embedding,
                lastUpdated: entry.lastUpdated
            )
        }
        let afterMemory = estimatedMemoryUsage
        let savedMB = (beforeMemory - afterMemory) / (1024 * 1024)
        logger.info("compactIndex: cleared chunk text, saved ~\(savedMB)MB")
    }

    /// Prunes the oldest entries to reduce index size.
    /// Keeps the most recently updated entries up to the specified limit.
    /// - Parameter keepCount: Maximum entries to retain (default: recommendedMaxEntries)
    public func pruneOldestEntries(keepCount: Int = recommendedMaxEntries) {
        guard index.count > keepCount else { return }

        let beforeCount = index.count
        // Sort by lastUpdated descending, keep newest
        let sorted = index.sorted { $0.lastUpdated > $1.lastUpdated }
        index = Array(sorted.prefix(keepCount))
        let removedCount = beforeCount - index.count
        logger.info("pruneOldestEntries: removed \(removedCount) old entries, kept \(self.index.count)")
    }

    /// Clears the entire index from memory (does not delete file).
    /// Call `loadIndex()` to reload from disk.
    public func unloadIndex() {
        let count = index.count
        index = []
        logger.info("unloadIndex: cleared \(count) entries from memory")
    }

    /// Returns the most recent index date for a note (from its chunks).
    /// Used for incremental indexing: skip if file mtime is not newer.
    public func lastIndexedDate(for noteID: UUID) -> Date? {
        index.filter { $0.noteID == noteID }.map(\.lastUpdated).max()
    }

    /// Finds note IDs semantically similar to the given note.
    /// Uses the note's first chunk as query; returns other notes' IDs sorted by max similarity.
    /// Used for AI-assisted graph linking.
    public func findSimilarNoteIDs(
        for noteID: UUID,
        limit: Int = 5,
        threshold: Float = 0.35
    ) -> [UUID] {
        let sourceChunks = index.filter { $0.noteID == noteID }.sorted(by: { $0.chunkIndex < $1.chunkIndex })
        guard let firstChunk = sourceChunks.first else { return [] }

        var noteScores: [UUID: Float] = [:]
        for entry in index where entry.noteID != noteID {
            let sim = cosineSimilarity(firstChunk.embedding, entry.embedding)
            if sim >= threshold {
                let current = noteScores[entry.noteID] ?? 0
                noteScores[entry.noteID] = max(current, sim)
            }
        }

        return noteScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    /// Returns chunk text from notes semantically similar to the given note.
    /// Used for Vault Memory (RAG) context in AI writing tools.
    public func getContextChunksForSimilarNotes(
        to noteID: UUID,
        limit: Int = 5,
        maxChunksPerNote: Int = 2,
        threshold: Float = 0.35
    ) -> [String] {
        let similarIDs = findSimilarNoteIDs(for: noteID, limit: limit, threshold: threshold)
        var chunks: [String] = []
        for id in similarIDs {
            let noteChunks = index
                .filter { $0.noteID == id }
                .sorted { $0.chunkIndex < $1.chunkIndex }
                .prefix(maxChunksPerNote)
                .map(\.chunkText)
            chunks.append(contentsOf: noteChunks)
        }
        return chunks
    }

    // MARK: - Stable Note ID

    /// Derives a deterministic UUID from a note's relative path within the vault.
    /// This ensures the same file always maps to the same UUID across app launches,
    /// unlike `FileNode.id` which is regenerated each time the tree is built.
    public static func stableNoteID(for url: URL, vaultRoot: URL) -> UUID {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let canonicalVaultRoot = CanonicalNoteIdentity.canonicalFileURL(for: vaultRoot)
        let notePath = canonicalURL.path(percentEncoded: false)
        let rootPath = canonicalVaultRoot.path(percentEncoded: false)
        let relative: String
        if notePath == rootPath {
            relative = "/"
        } else if notePath.hasPrefix(rootPath + "/") {
            relative = String(notePath.dropFirst(rootPath.count))
        } else {
            relative = notePath
        }
        let hash = SHA256.hash(data: Data(relative.utf8))
        let bytes = Array(hash.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2],  bytes[3],  bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Search Result

    public struct SearchResult: Sendable {
        public let entry: EmbeddingEntry
        public let similarity: Float

        public init(entry: EmbeddingEntry, similarity: Float) {
            self.entry = entry
            self.similarity = similarity
        }
    }

    // MARK: - Private

    /// Splits text into chunks of approximately `chunkSize` characters.
    private func chunkText(_ text: String) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentLength = 0

        for word in words {
            if currentLength + word.count + 1 > chunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: " "))
                // Overlap: keep last 20%
                let overlapCount = max(1, currentChunk.count / 5)
                currentChunk = Array(currentChunk.suffix(overlapCount))
                currentLength = currentChunk.joined(separator: " ").count
            }
            currentChunk.append(word)
            currentLength += word.count + 1
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }

        return chunks
    }

    /// Generates an embedding using NLEmbedding.
    /// Uses per-language caching to support automatic language detection.
    private var embeddingCache: [NLLanguage: NLEmbedding] = [:]

    private func getEmbedding(for lang: NLLanguage) -> NLEmbedding? {
        if let cached = embeddingCache[lang] { return cached }
        let embedding = NLEmbedding.sentenceEmbedding(for: lang)
        if let embedding { embeddingCache[lang] = embedding }
        return embedding
    }

    private func generateEmbedding(for text: String) -> [Float]? {
        let detectedLang = detectLanguage(for: text)
        guard let embedding = getEmbedding(for: detectedLang),
              let vector = embedding.vector(for: text) else {
            // Fallback to configured default language
            guard let fallback = getEmbedding(for: language),
                  let vector = fallback.vector(for: text) else {
                return nil
            }
            return vector.map { Float($0) }
        }
        return vector.map { Float($0) }
    }

    /// Computes cosine similarity via the Accelerate framework.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}

// MARK: - Errors

public enum EmbeddingIndexError: LocalizedError, Sendable {
    case corruptedIndex
    case unsupportedVersion(UInt32)
    case indexUnavailable(String)
    case invalidEmbeddingDimension(Int)
    case trailingDataAfterDeclaredEntries(declaredEntries: Int, trailingBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .corruptedIndex:
            String(localized: "The embedding index file is corrupted.", bundle: .module)
        case .unsupportedVersion(let v):
            String(localized: "Unsupported embedding index version: \(v)", bundle: .module)
        case .indexUnavailable(let reason):
            reason
        case .invalidEmbeddingDimension(let dimension):
            String(localized: "Invalid embedding vector dimension in index: \(dimension)", bundle: .module)
        case .trailingDataAfterDeclaredEntries(let declaredEntries, let trailingBytes):
            String(localized: "Embedding index declared \(declaredEntries) entries but contains \(trailingBytes) trailing bytes.", bundle: .module)
        }
    }
}
