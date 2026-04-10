import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4AudioMemoryBudget")
struct Phase4AudioMemoryBudgetTests {

    // MARK: - AudioChunkRingBuffer Bounds

    @Test("Ring buffer never exceeds capacity")
    func ringBufferCapacityBound() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        for i in 0..<30 {
            let chunk = AudioChunk(samples: [Float](repeating: Float(i), count: 100), sampleRate: 44100, frameCount: 100, timestamp: Double(i) * 0.5)
            await buffer.append(chunk)
        }
        #expect(await buffer.chunkCount == 10)
        #expect(await buffer.isFull)
        #expect(await buffer.totalChunksReceived == 30)
    }

    @Test("Ring buffer memory stays under 12MB for default config")
    func ringBufferDefaultMemoryBound() async {
        let buffer = AudioChunkRingBuffer(capacity: 120, chunkDuration: 0.5)
        let samplesPerChunk = 22050
        for i in 0..<120 {
            let chunk = AudioChunk(samples: [Float](repeating: 0.1, count: samplesPerChunk), sampleRate: 44100, frameCount: samplesPerChunk, timestamp: Double(i) * 0.5)
            await buffer.append(chunk)
        }
        let memoryMB = Double(await buffer.currentMemoryBytes) / (1024 * 1024)
        #expect(memoryMB < 12, "Ring buffer memory \(memoryMB)MB should be under 12MB")
        #expect(await buffer.chunkCount == 120)
    }

    @Test("Ring buffer stays constant after exceeding capacity")
    func ringBufferMemoryConstantAfterFull() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        let samplesPerChunk = 1000
        for i in 0..<10 {
            let chunk = AudioChunk(samples: [Float](repeating: 0.1, count: samplesPerChunk), sampleRate: 44100, frameCount: samplesPerChunk, timestamp: Double(i) * 0.5)
            await buffer.append(chunk)
        }
        let memoryAtCapacity = await buffer.currentMemoryBytes
        for i in 10..<110 {
            let chunk = AudioChunk(samples: [Float](repeating: 0.1, count: samplesPerChunk), sampleRate: 44100, frameCount: samplesPerChunk, timestamp: Double(i) * 0.5)
            await buffer.append(chunk)
        }
        let memoryAfterOverflow = await buffer.currentMemoryBytes
        #expect(memoryAtCapacity == memoryAfterOverflow)
    }

    @Test("Ring buffer drain returns chunks in chronological order")
    func ringBufferDrainOrder() async {
        let buffer = AudioChunkRingBuffer(capacity: 5, chunkDuration: 0.5)
        for i in 0..<5 {
            let chunk = AudioChunk(samples: [Float(i)], sampleRate: 44100, frameCount: 1, timestamp: Double(i))
            await buffer.append(chunk)
        }
        let drained = await buffer.drain()
        #expect(drained.count == 5)
        for i in 0..<5 { #expect(drained[i].timestamp == Double(i)) }
        #expect(await buffer.chunkCount == 0)
    }

    @Test("Ring buffer recent returns newest chunks")
    func ringBufferRecentChunks() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        for i in 0..<10 {
            let chunk = AudioChunk(samples: [Float(i)], sampleRate: 44100, frameCount: 1, timestamp: Double(i))
            await buffer.append(chunk)
        }
        let recent3 = await buffer.recent(3)
        #expect(recent3.count == 3)
        #expect(recent3[0].timestamp == 7.0)
        #expect(recent3[2].timestamp == 9.0)
    }

    @Test("Ring buffer reset clears all state")
    func ringBufferReset() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        for i in 0..<5 {
            await buffer.append(AudioChunk(samples: [Float(i)], sampleRate: 44100, frameCount: 1, timestamp: Double(i) * 0.5))
        }
        #expect(await buffer.chunkCount == 5)
        await buffer.reset()
        #expect(await buffer.chunkCount == 0)
        #expect(await buffer.totalChunksReceived == 0)
        #expect(await buffer.latest == nil)
        #expect(await buffer.currentMemoryBytes == 0)
    }

    @Test("Ring buffer latest returns nil when empty")
    func ringBufferLatestEmpty() async {
        let buffer = AudioChunkRingBuffer(capacity: 10, chunkDuration: 0.5)
        #expect(await buffer.latest == nil)
    }

    @Test("AudioChunk is Sendable and copies data correctly")
    func audioChunkSendable() {
        let chunk = AudioChunk(samples: [0.1, 0.2, 0.3], sampleRate: 44100, frameCount: 3, timestamp: 1.5)
        #expect(chunk.samples == [0.1, 0.2, 0.3])
        #expect(chunk.memorySizeBytes == 3 * MemoryLayout<Float>.size)
    }

    @Test("AudioChunk duration calculation is correct")
    func audioChunkDuration() {
        let chunk = AudioChunk(samples: [Float](repeating: 0.0, count: 22050), sampleRate: 44100, frameCount: 22050, timestamp: 0)
        #expect(abs(chunk.duration - 0.5) < 0.001)
    }

    @Test("60-minute simulated session stays within memory budget")
    func sixtyMinuteSessionMemoryBudget() async {
        let buffer = AudioChunkRingBuffer(capacity: 120, chunkDuration: 0.5)
        let samplesPerChunk = 22050
        for i in 0..<7200 {
            let chunk = AudioChunk(samples: [Float](repeating: 0.05, count: samplesPerChunk), sampleRate: 44100, frameCount: samplesPerChunk, timestamp: Double(i) * 0.5)
            await buffer.append(chunk)
            if i % 1000 == 0 {
                let memoryMB = Double(await buffer.currentMemoryBytes) / (1024 * 1024)
                #expect(memoryMB < 15)
            }
        }
        #expect(await buffer.chunkCount == 120)
        #expect(await buffer.totalChunksReceived == 7200)
    }

    @Test("Capture service initializes in idle state")
    func captureServiceIdleState() async {
        let service = AVAudioEngineCaptureService()
        #expect(await service.state == .idle)
        #expect(await service.capturedDuration == 0)
    }

    @Test("Capture service rejects operations in wrong state")
    func captureServiceInvalidState() async {
        let service = AVAudioEngineCaptureService()
        await service.pauseCapture()
        #expect(await service.state == .idle)
        do {
            _ = try await service.stopCapture()
            #expect(Bool(false), "Should have thrown")
        } catch { }
    }
}
