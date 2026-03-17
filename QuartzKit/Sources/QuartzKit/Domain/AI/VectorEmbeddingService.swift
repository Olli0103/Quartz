import Foundation
import NaturalLanguage
@preconcurrency import Accelerate

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
public actor VectorEmbeddingService {
    private var index: [EmbeddingEntry] = []
    private let indexURL: URL
    private let chunkSize: Int
    private let language: NLLanguage

    /// Dimension of the embedding vectors.
    public var embeddingDimension: Int { 512 }

    public init(
        vaultURL: URL,
        chunkSize: Int = 512,
        language: NLLanguage = .english
    ) {
        self.indexURL = vaultURL
            .appending(path: ".quartz")
            .appending(path: "embeddings.idx")
        self.chunkSize = chunkSize
        self.language = language
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
        guard FileManager.default.fileExists(atPath: indexURL.path()) else {
            index = []
            return
        }

        let data = try Data(contentsOf: indexURL, options: .mappedIfSafe)
        index = try Self.decodeBinary(data)
    }

    /// Saves the embedding index to disk (binary format).
    public func saveIndex() throws {
        let dir = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = Self.encodeBinary(index)
        try data.write(to: indexURL, options: .atomic)
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

        return entries
    }

    /// Maximum content size for indexing (500 KB). Larger documents are truncated.
    private static let maxIndexableContentSize = 500_000

    /// Indexes a note: chunk text → generate embeddings → store in index.
    public func indexNote(noteID: UUID, content: String) throws {
        // Remove old entries
        index.removeAll { $0.noteID == noteID }

        guard !content.isEmpty else { return }

        // Truncate very large documents to prevent excessive memory usage
        let truncated = content.count > Self.maxIndexableContentSize
            ? String(content.prefix(Self.maxIndexableContentSize))
            : content

        // Split text into chunks
        let chunks = chunkText(truncated)

        // Embeddings erzeugen
        for (i, chunk) in chunks.enumerated() {
            if let embedding = generateEmbedding(for: chunk) {
                let entry = EmbeddingEntry(
                    noteID: noteID,
                    chunkIndex: i,
                    chunkText: chunk,
                    embedding: embedding
                )
                index.append(entry)
            }
        }
    }

    /// Entfernt alle Embeddings einer Notiz.
    public func removeNote(_ noteID: UUID) {
        index.removeAll { $0.noteID == noteID }
    }

    // MARK: - Semantic Search

    /// Sucht semantisch ähnliche Chunks.
    ///
    /// - Parameters:
    ///   - query: Die Suchanfrage
    ///   - limit: Maximale Anzahl Ergebnisse
    ///   - threshold: Minimale Cosine Similarity (0.0-1.0)
    /// - Returns: Sortierte Ergebnisse (höchste Similarity zuerst)
    public func search(
        query: String,
        limit: Int = 10,
        threshold: Float = 0.3
    ) -> [SearchResult] {
        guard let queryEmbedding = generateEmbedding(for: query) else {
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

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    /// Anzahl der indexierten Chunks.
    public var entryCount: Int { index.count }

    /// Alle indexierten Notiz-IDs.
    public var indexedNoteIDs: Set<UUID> {
        Set(index.map(\.noteID))
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

    /// Teilt Text in Chunks von ca. `chunkSize` Zeichen auf.
    private func chunkText(_ text: String) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentLength = 0

        for word in words {
            if currentLength + word.count + 1 > chunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: " "))
                // Overlap: letzte 20% behalten
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

    /// Erzeugt ein Embedding mit NLEmbedding.
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

    /// Berechnet Cosine Similarity via Accelerate Framework.
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

    public var errorDescription: String? {
        switch self {
        case .corruptedIndex:
            String(localized: "The embedding index file is corrupted.", bundle: .module)
        case .unsupportedVersion(let v):
            String(localized: "Unsupported embedding index version: \(v)", bundle: .module)
        }
    }
}
