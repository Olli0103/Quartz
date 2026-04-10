import Foundation

/// Sendable wrapper for audio PCM data.
///
/// Copies raw float samples from non-Sendable `AVAudioPCMBuffer` so they
/// can cross actor boundaries safely.
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Float
    public let frameCount: Int
    public let timestamp: TimeInterval

    public init(samples: [Float], sampleRate: Float, frameCount: Int, timestamp: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.timestamp = timestamp
    }

    /// Duration in seconds.
    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(frameCount) / TimeInterval(sampleRate)
    }

    /// Approximate memory footprint in bytes.
    public var memorySizeBytes: Int {
        samples.count * MemoryLayout<Float>.size
    }
}

/// Fixed-capacity ring buffer for streaming audio chunks.
///
/// Provides bounded memory for long recording sessions. Default config
/// (120 chunks × 500ms at 44.1kHz mono) uses ~10MB steady-state.
///
/// - Linear: OLL-34 (AVAudioEngine capture graph with ring-buffer chunking)
public actor AudioChunkRingBuffer {

    private var buffer: [AudioChunk?]
    private var head: Int = 0
    private var count: Int = 0
    public let capacity: Int
    public let chunkDuration: TimeInterval

    /// Total chunks ever received (may exceed capacity).
    public private(set) var totalChunksReceived: Int = 0

    public init(capacity: Int = 120, chunkDuration: TimeInterval = 0.5) {
        self.capacity = capacity
        self.chunkDuration = chunkDuration
        self.buffer = [AudioChunk?](repeating: nil, count: capacity)
    }

    /// Appends a chunk, evicting the oldest if at capacity.
    public func append(_ chunk: AudioChunk) {
        buffer[head] = chunk
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
        totalChunksReceived += 1
    }

    /// Drains all chunks in chronological order and clears the buffer.
    public func drain() -> [AudioChunk] {
        let result = recent(count)
        reset()
        return result
    }

    /// Returns the most recent `n` chunks in chronological order.
    public func recent(_ n: Int) -> [AudioChunk] {
        let actualCount = min(n, count)
        guard actualCount > 0 else { return [] }

        var result = [AudioChunk]()
        result.reserveCapacity(actualCount)

        var index = (head - actualCount + capacity) % capacity
        for _ in 0..<actualCount {
            if let chunk = buffer[index] {
                result.append(chunk)
            }
            index = (index + 1) % capacity
        }
        return result
    }

    /// The most recent chunk, or nil if empty.
    public var latest: AudioChunk? {
        guard count > 0 else { return nil }
        let index = (head - 1 + capacity) % capacity
        return buffer[index]
    }

    /// Number of chunks currently stored.
    public var chunkCount: Int { count }

    /// Whether the buffer is at capacity.
    public var isFull: Bool { count >= capacity }

    /// Approximate memory used by stored samples.
    public var currentMemoryBytes: Int {
        var total = 0
        let start = (head - count + capacity) % capacity
        for i in 0..<count {
            let idx = (start + i) % capacity
            total += buffer[idx]?.memorySizeBytes ?? 0
        }
        return total
    }

    /// Clears all chunks and resets counters.
    public func reset() {
        for i in 0..<capacity {
            buffer[i] = nil
        }
        head = 0
        count = 0
        totalChunksReceived = 0
    }
}
