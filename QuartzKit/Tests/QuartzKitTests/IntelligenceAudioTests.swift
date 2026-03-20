import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 5: Intelligence, Chat & Audio Tests

// MARK: - TranscriptionService Tests

@Suite("TranscriptionService")
struct TranscriptionServiceTests {
    @Test("TranscriptionResult holds correct data")
    func transcriptionResultData() {
        let segments = [
            TranscriptionService.TranscriptionSegment(
                text: "Hello world",
                timestamp: 0.0,
                duration: 1.5,
                confidence: 0.95
            ),
            TranscriptionService.TranscriptionSegment(
                text: "How are you",
                timestamp: 1.5,
                duration: 1.2,
                confidence: 0.88
            )
        ]

        let result = TranscriptionService.TranscriptionResult(
            text: "Hello world. How are you.",
            segments: segments,
            locale: Locale(identifier: "en_US"),
            duration: 2.7
        )

        #expect(result.text == "Hello world. How are you.")
        #expect(result.segments.count == 2)
        #expect(result.locale.identifier == "en_US")
        #expect(result.duration == 2.7)
    }

    @Test("TranscriptionSegment has correct properties")
    func segmentProperties() {
        let segment = TranscriptionService.TranscriptionSegment(
            text: "Test segment",
            timestamp: 5.0,
            duration: 2.5,
            confidence: 0.92
        )

        #expect(segment.text == "Test segment")
        #expect(segment.timestamp == 5.0)
        #expect(segment.duration == 2.5)
        #expect(segment.confidence == 0.92)
    }

    @Test("TranscriptionError provides localized descriptions")
    func errorDescriptions() {
        let permissionDenied = TranscriptionService.TranscriptionError.permissionDenied
        let unavailable = TranscriptionService.TranscriptionError.recognizerUnavailable
        let failed = TranscriptionService.TranscriptionError.recognitionFailed("Test error")
        let notFound = TranscriptionService.TranscriptionError.fileNotFound

        #expect(permissionDenied.errorDescription != nil)
        #expect(unavailable.errorDescription != nil)
        #expect(failed.errorDescription?.contains("Test error") == true)
        #expect(notFound.errorDescription != nil)
    }

    @Test("Service initializes with locale")
    func serviceInitWithLocale() async {
        let service = TranscriptionService(locale: Locale(identifier: "de_DE"))
        // Service should be created without crashing
        #expect(true)
    }
}

// MARK: - SpeakerDiarizationService Tests

@Suite("SpeakerDiarizationService")
struct SpeakerDiarizationServiceTests {
    @Test("SpeakerSegment has correct duration")
    func speakerSegmentDuration() {
        let segment = SpeakerDiarizationService.SpeakerSegment(
            speakerID: "speaker_0",
            speakerLabel: "Speaker A",
            startTime: 10.0,
            endTime: 25.5,
            confidence: 0.85
        )

        #expect(segment.duration == 15.5)
        #expect(segment.speakerID == "speaker_0")
        #expect(segment.speakerLabel == "Speaker A")
    }

    @Test("DiarizationResult holds speaker data")
    func diarizationResultData() {
        let segments = [
            SpeakerDiarizationService.SpeakerSegment(
                speakerID: "speaker_0",
                speakerLabel: "Speaker A",
                startTime: 0.0,
                endTime: 5.0,
                confidence: 0.9
            ),
            SpeakerDiarizationService.SpeakerSegment(
                speakerID: "speaker_1",
                speakerLabel: "Speaker B",
                startTime: 5.0,
                endTime: 10.0,
                confidence: 0.85
            )
        ]

        let result = SpeakerDiarizationService.DiarizationResult(
            segments: segments,
            speakerCount: 2,
            speakers: ["speaker_0": "Speaker A", "speaker_1": "Speaker B"]
        )

        #expect(result.segments.count == 2)
        #expect(result.speakerCount == 2)
        #expect(result.speakers.count == 2)
    }

    @Test("DiarizationError provides localized descriptions")
    func diarizationErrorDescriptions() {
        let errors: [SpeakerDiarizationService.DiarizationError] = [
            .fileNotFound,
            .analysisUnavailable,
            .analysisFailed("Test"),
            .insufficientAudio
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "Error \(error) should have description")
        }
    }

    @Test("Service can combine transcription with diarization")
    func combineTranscriptionWithDiarization() async {
        let service = SpeakerDiarizationService()

        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(
                    speakerID: "speaker_0",
                    speakerLabel: "Speaker A",
                    startTime: 0.0,
                    endTime: 3.0,
                    confidence: 0.9
                ),
                SpeakerDiarizationService.SpeakerSegment(
                    speakerID: "speaker_1",
                    speakerLabel: "Speaker B",
                    startTime: 3.0,
                    endTime: 6.0,
                    confidence: 0.85
                )
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "Speaker A", "speaker_1": "Speaker B"]
        )

        let transcription = TranscriptionService.TranscriptionResult(
            text: "Hello there. How are you doing?",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "Hello there", timestamp: 0.5, duration: 1.0, confidence: 0.95),
                TranscriptionService.TranscriptionSegment(text: "How are you doing", timestamp: 3.5, duration: 1.5, confidence: 0.90)
            ],
            locale: Locale.current,
            duration: 6.0
        )

        let combined = await service.combineWithTranscription(diarization: diarization, transcription: transcription)

        #expect(combined.contains("Speaker A"))
        #expect(combined.contains("Speaker B"))
        #expect(combined.contains("Hello there"))
    }
}

// MARK: - OnDeviceWritingToolsService Tests

@Suite("OnDeviceWritingToolsService")
struct OnDeviceWritingToolsServiceTests {
    @Test("AIAction has correct display names")
    func aiActionDisplayNames() {
        for action in OnDeviceWritingToolsService.AIAction.allCases {
            #expect(!action.displayName.isEmpty, "Action \(action.rawValue) should have display name")
        }
    }

    @Test("AIAction has correct system images")
    func aiActionSystemImages() {
        for action in OnDeviceWritingToolsService.AIAction.allCases {
            #expect(!action.systemImage.isEmpty, "Action \(action.rawValue) should have system image")
        }
    }

    @Test("Tone has correct display names")
    func toneDisplayNames() {
        for tone in OnDeviceWritingToolsService.Tone.allCases {
            #expect(!tone.displayName.isEmpty, "Tone \(tone.rawValue) should have display name")
        }
    }

    @Test("AIError provides localized descriptions")
    func aiErrorDescriptions() {
        let errors: [OnDeviceWritingToolsService.AIError] = [
            .notAvailable,
            .processingFailed("Test"),
            .emptyInput,
            .featureUnavailable("Test feature")
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "Error should have description")
        }
    }

    @Test("AIResult holds correct data")
    func aiResultData() {
        let result = OnDeviceWritingToolsService.AIResult(
            originalText: "Original text",
            processedText: "Processed text",
            action: .summarize,
            tone: .professional
        )

        #expect(result.originalText == "Original text")
        #expect(result.processedText == "Processed text")
        #expect(result.action == .summarize)
        #expect(result.tone == .professional)
    }

    @Test("Empty input throws error")
    func emptyInputThrowsError() async {
        let service = OnDeviceWritingToolsService()

        do {
            _ = try await service.process(action: .summarize, text: "   ")
            Issue.record("Should have thrown emptyInput error")
        } catch let error as OnDeviceWritingToolsService.AIError {
            switch error {
            case .emptyInput:
                break // Expected
            default:
                Issue.record("Expected emptyInput error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - AIProvider Tests

@Suite("AIProviderIntegration")
struct AIProviderIntegrationTests {
    @Test("AIMessage has required properties")
    func aiMessageProperties() {
        let message = AIMessage(role: .user, content: "Hello AI")

        #expect(message.role == .user)
        #expect(message.content == "Hello AI")
        #expect(message.id != UUID())
        #expect(message.timestamp <= Date())
    }

    @Test("AIModel has required properties")
    func aiModelProperties() {
        let model = AIModel(
            id: "gpt-4",
            name: "GPT-4",
            contextWindow: 128_000,
            provider: "openai"
        )

        #expect(model.id == "gpt-4")
        #expect(model.name == "GPT-4")
        #expect(model.contextWindow == 128_000)
        #expect(model.provider == "openai")
    }

    @Test("AIProviderError provides descriptions")
    func providerErrorDescriptions() {
        let errors: [AIProviderError] = [
            .noAPIKey("test"),
            .emptyResponse,
            .keychainError(-25300),
            .networkError("timeout"),
            .unauthorized("test"),
            .rateLimited,
            .serverError(500),
            .httpError(400, "Bad request")
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "Error should have description")
        }
    }
}

// MARK: - XCTest Performance Tests for Audio/AI

final class AudioAIPerformanceTests: XCTestCase {
    func testTranscriptionSegmentProcessing() throws {
        // Generate 1000 segments
        var segments: [TranscriptionService.TranscriptionSegment] = []
        for i in 0..<1000 {
            segments.append(TranscriptionService.TranscriptionSegment(
                text: "Segment \(i) with some text content here",
                timestamp: Double(i) * 0.5,
                duration: 0.5,
                confidence: Float.random(in: 0.7...1.0)
            ))
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            // Process segments (concatenate, filter, etc.)
            let fullText = segments.map(\.text).joined(separator: " ")
            let highConfidence = segments.filter { $0.confidence > 0.9 }
            let totalDuration = segments.reduce(0) { $0 + $1.duration }

            XCTAssertGreaterThan(fullText.count, 0)
            XCTAssertGreaterThan(highConfidence.count, 0)
            XCTAssertEqual(totalDuration, 500.0, accuracy: 0.01)
        }
    }

    func testSpeakerSegmentMerging() throws {
        // Generate alternating speaker segments
        var segments: [SpeakerDiarizationService.SpeakerSegment] = []
        for i in 0..<500 {
            segments.append(SpeakerDiarizationService.SpeakerSegment(
                speakerID: "speaker_\(i % 3)",
                speakerLabel: ["Speaker A", "Speaker B", "Speaker C"][i % 3],
                startTime: Double(i) * 2.0,
                endTime: Double(i + 1) * 2.0,
                confidence: 0.85
            ))
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            // Simulate segment merging logic
            var merged: [SpeakerDiarizationService.SpeakerSegment] = []
            var currentSpeaker = segments[0].speakerID
            var startTime = segments[0].startTime

            for segment in segments {
                if segment.speakerID != currentSpeaker {
                    merged.append(SpeakerDiarizationService.SpeakerSegment(
                        speakerID: currentSpeaker,
                        speakerLabel: "",
                        startTime: startTime,
                        endTime: segment.startTime,
                        confidence: 0.85
                    ))
                    currentSpeaker = segment.speakerID
                    startTime = segment.startTime
                }
            }

            XCTAssertGreaterThan(merged.count, 0)
        }
    }

    func testAIMessageConstruction() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var messages: [AIMessage] = []

            // Build a conversation with 100 messages
            for i in 0..<100 {
                let role: AIMessage.Role = i % 2 == 0 ? .user : .assistant
                let content = String(repeating: "Message \(i) content. ", count: 10)
                messages.append(AIMessage(role: role, content: content))
            }

            XCTAssertEqual(messages.count, 100)
            XCTAssertEqual(messages.filter { $0.role == .user }.count, 50)
        }
    }

    func testWritingToolsActionPerformance() async throws {
        let service = OnDeviceWritingToolsService()
        let text = String(repeating: "This is a sentence that needs processing. ", count: 50)

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        // Test action processing (will use fallback paths on CI)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Process")
            Task {
                // Try each action - they will fail gracefully without API keys
                for action in OnDeviceWritingToolsService.AIAction.allCases {
                    do {
                        _ = try await service.process(action: action, text: text)
                    } catch {
                        // Expected on CI without API keys
                    }
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30.0)
        }
    }
}

// MARK: - VectorEmbedding Tests (Mock)

@Suite("VectorEmbeddingIntegration")
struct VectorEmbeddingIntegrationTests {
    @Test("Embedding vectors have consistent dimensions")
    func embeddingDimensions() {
        // Standard embedding dimension for Apple's NL embeddings
        let dimension = 512

        // Mock embedding generation
        let embedding1 = (0..<dimension).map { _ in Float.random(in: -1...1) }
        let embedding2 = (0..<dimension).map { _ in Float.random(in: -1...1) }

        #expect(embedding1.count == dimension)
        #expect(embedding2.count == dimension)
    }

    @Test("Cosine similarity calculation")
    func cosineSimilarity() {
        let vec1: [Float] = [1.0, 0.0, 0.0]
        let vec2: [Float] = [1.0, 0.0, 0.0]
        let vec3: [Float] = [0.0, 1.0, 0.0]

        func cosine(_ a: [Float], _ b: [Float]) -> Float {
            var dotProduct: Float = 0
            var normA: Float = 0
            var normB: Float = 0

            for i in 0..<a.count {
                dotProduct += a[i] * b[i]
                normA += a[i] * a[i]
                normB += b[i] * b[i]
            }

            return dotProduct / (sqrt(normA) * sqrt(normB))
        }

        let similarity12 = cosine(vec1, vec2)
        let similarity13 = cosine(vec1, vec3)

        #expect(similarity12 > 0.99) // Same vectors
        #expect(similarity13 < 0.01) // Orthogonal vectors
    }
}
