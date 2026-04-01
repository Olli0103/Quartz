import Foundation

// MARK: - Audio Metering Buffer (Per CODEX.md F8)

/// Thread-safe ring buffer for audio metering samples.
///
/// **Per CODEX.md F8:** Unbounded array growth was identified as a memory risk
/// for long recording sessions. This ring buffer provides:
/// - Fixed memory footprint regardless of session length
/// - O(1) append and O(1) access to recent samples
/// - Thread-safe via actor isolation
///
/// At 12Hz metering for 60 minutes = 43,200 samples.
/// With ring buffer capacity of 1000, memory stays constant at ~4KB.
public actor AudioMeteringBuffer {

    // MARK: - Configuration

    /// Default capacity for metering history.
    public static let defaultCapacity = 1000

    // MARK: - State

    private var buffer: [Float]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int

    // MARK: - Statistics

    /// Total samples received (may exceed capacity).
    public private(set) var totalSamplesReceived: Int = 0

    /// Peak level seen in current session.
    public private(set) var sessionPeakLevel: Float = 0

    // MARK: - Init

    /// Creates a new metering buffer with the specified capacity.
    ///
    /// - Parameter capacity: Maximum number of samples to retain.
    public init(capacity: Int = defaultCapacity) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    // MARK: - Append

    /// Appends a new metering sample to the buffer.
    ///
    /// If the buffer is full, the oldest sample is evicted.
    public func append(_ level: Float) {
        buffer[head] = level
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
        totalSamplesReceived += 1

        if level > sessionPeakLevel {
            sessionPeakLevel = level
        }
    }

    /// Appends multiple samples efficiently.
    public func append(contentsOf levels: [Float]) {
        for level in levels {
            append(level)
        }
    }

    // MARK: - Access

    /// Returns the most recent `n` samples in chronological order.
    ///
    /// - Parameter n: Number of samples to return (clamped to available count).
    /// - Returns: Array of samples, oldest first.
    public func recent(_ n: Int) -> [Float] {
        let actualCount = min(n, count)
        guard actualCount > 0 else { return [] }

        var result = [Float]()
        result.reserveCapacity(actualCount)

        // Start from (head - actualCount) and wrap around
        var index = (head - actualCount + capacity) % capacity
        for _ in 0..<actualCount {
            result.append(buffer[index])
            index = (index + 1) % capacity
        }

        return result
    }

    /// Returns all samples currently in the buffer.
    public func all() -> [Float] {
        recent(count)
    }

    /// The most recent sample, or 0 if empty.
    public var latest: Float {
        guard count > 0 else { return 0 }
        let index = (head - 1 + capacity) % capacity
        return buffer[index]
    }

    /// Number of samples currently in the buffer.
    public var sampleCount: Int {
        count
    }

    /// Whether the buffer is at capacity.
    public var isFull: Bool {
        count >= capacity
    }

    // MARK: - Statistics

    /// Computes the average level of recent samples.
    public func averageLevel(samples: Int = 100) -> Float {
        let recentSamples = recent(samples)
        guard !recentSamples.isEmpty else { return 0 }
        return recentSamples.reduce(0, +) / Float(recentSamples.count)
    }

    /// Computes the RMS (root mean square) level of recent samples.
    public func rmsLevel(samples: Int = 100) -> Float {
        let recentSamples = recent(samples)
        guard !recentSamples.isEmpty else { return 0 }
        let sumOfSquares = recentSamples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(recentSamples.count))
    }

    // MARK: - Reset

    /// Clears the buffer and resets statistics.
    public func reset() {
        head = 0
        count = 0
        totalSamplesReceived = 0
        sessionPeakLevel = 0
        // No need to zero the buffer - old data is inaccessible
    }
}

// MARK: - Background Metering Processor

/// Processes audio metering updates off the main thread.
///
/// **Per CODEX.md F8:** Metering was processed on MainActor at 12Hz,
/// causing typing jitter during recording. This processor:
/// - Runs metering calculations on a background actor
/// - Batches updates to reduce main thread overhead
/// - Throttles UI updates to configurable rate (default 30Hz)
public actor AudioMeteringProcessor {

    // MARK: - Configuration

    /// Minimum interval between UI updates (in seconds).
    public let uiUpdateInterval: TimeInterval

    // MARK: - State

    private let buffer: AudioMeteringBuffer
    private var lastUIUpdate: Date = .distantPast
    private var pendingUIUpdate: ((Float, Float) -> Void)?

    // MARK: - Init

    /// Creates a new metering processor.
    ///
    /// - Parameters:
    ///   - bufferCapacity: Capacity for the metering ring buffer.
    ///   - uiUpdateInterval: Minimum seconds between UI callbacks (default 1/30).
    public init(
        bufferCapacity: Int = AudioMeteringBuffer.defaultCapacity,
        uiUpdateInterval: TimeInterval = 1.0 / 30.0
    ) {
        self.buffer = AudioMeteringBuffer(capacity: bufferCapacity)
        self.uiUpdateInterval = uiUpdateInterval
    }

    // MARK: - Processing

    /// Processes a raw metering sample from AVAudioRecorder.
    ///
    /// - Parameters:
    ///   - averagePower: Average power in dB (typically -160 to 0).
    ///   - peakPower: Peak power in dB.
    ///   - onUIUpdate: Callback for UI updates (throttled, called on MainActor).
    public func processSample(
        averagePower: Float,
        peakPower: Float,
        onUIUpdate: @escaping @MainActor @Sendable (Float, Float) -> Void
    ) async {
        // Normalize to 0-1 range
        let normalizedAvg = normalizeLevel(averagePower)
        let normalizedPeak = normalizeLevel(peakPower)

        // Store in ring buffer
        await buffer.append(normalizedAvg)

        // Throttle UI updates
        let now = Date()
        if now.timeIntervalSince(lastUIUpdate) >= uiUpdateInterval {
            lastUIUpdate = now

            // Dispatch to main actor for UI update
            await MainActor.run {
                onUIUpdate(normalizedAvg, normalizedPeak)
            }
        }
    }

    /// Returns recent samples for waveform visualization.
    public func recentSamples(_ count: Int) async -> [Float] {
        await buffer.recent(count)
    }

    /// Returns session statistics.
    public func sessionStats() async -> (totalSamples: Int, peakLevel: Float, avgLevel: Float) {
        let total = await buffer.totalSamplesReceived
        let peak = await buffer.sessionPeakLevel
        let avg = await buffer.averageLevel()
        return (total, peak, avg)
    }

    /// Resets the processor for a new recording session.
    public func reset() async {
        await buffer.reset()
        lastUIUpdate = .distantPast
    }

    // MARK: - Private

    private func normalizeLevel(_ level: Float) -> Float {
        let minDB: Float = -60
        let clampedLevel = max(level, minDB)
        return (clampedLevel - minDB) / abs(minDB)
    }
}
