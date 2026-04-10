#if canImport(Vision) && canImport(PencilKit)
import Testing
import Foundation
import CoreGraphics
@testable import QuartzKit

@Suite("Phase4ScanAccessibility")
struct Phase4ScanAccessibilityTests {

    // MARK: - OCRError Descriptions

    @Test("OCRError.renderingFailed has non-empty localized description")
    func renderingFailedDescription() {
        let error = HandwritingOCRService.OCRError.renderingFailed
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("OCRError.recognitionFailed has non-empty localized description")
    func recognitionFailedDescription() {
        let error = HandwritingOCRService.OCRError.recognitionFailed("test failure")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("test failure"))
    }

    @Test("OCRError.noTextFound has non-empty localized description")
    func noTextFoundDescription() {
        let error = HandwritingOCRService.OCRError.noTextFound
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    // MARK: - OCRMarkdownMapper

    @Test("OCRMarkdownMapper empty observations returns empty string")
    func mapperEmptyObservations() async {
        let mapper = OCRMarkdownMapper()
        let result = await mapper.mapToMarkdown([])
        #expect(result.isEmpty)
    }

    @Test("OCRMarkdownMapper single observation returns non-empty")
    func mapperSingleObservation() async {
        let mapper = OCRMarkdownMapper()
        let obs = HandwritingOCRService.TextObservation(
            text: "Hello World",
            confidence: 0.95,
            boundingBox: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.03)
        )
        let result = await mapper.mapToMarkdown([obs])
        #expect(!result.isEmpty)
        #expect(result.contains("Hello World"))
    }

    @Test("OCRMarkdownMapper convenience method matches direct call")
    func mapperConvenienceMatch() async {
        let mapper = OCRMarkdownMapper()
        let observations = [
            HandwritingOCRService.TextObservation(text: "Line 1", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "Line 2", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.8, width: 0.5, height: 0.03)),
        ]
        let ocrResult = HandwritingOCRService.OCRResult(
            fullText: "Line 1\nLine 2",
            observations: observations
        )

        let direct = await mapper.mapToMarkdown(observations)
        let convenience = await mapper.mapToMarkdown(ocrResult)
        #expect(direct == convenience)
    }

    // MARK: - OCR Mapper Bullet Detection

    @Test("OCRMarkdownMapper detects mixed bullet styles")
    func mapperMixedBullets() async {
        let mapper = OCRMarkdownMapper()
        let observations = [
            HandwritingOCRService.TextObservation(text: "- Dash item", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "• Bullet item", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.8, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "* Star item", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.7, width: 0.5, height: 0.03)),
        ]

        let result = await mapper.mapToMarkdown(observations)
        // All should normalize to "- " prefix
        let lines = result.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(lines.count == 3)
        #expect(result.contains("- Dash item"))
        #expect(result.contains("- Bullet item"))
        #expect(result.contains("- Star item"))
    }

    // MARK: - OCR Mapper Heading Detection

    @Test("OCRMarkdownMapper detects H1 and H2 by bounding box height")
    func mapperHeadingDetection() async {
        let mapper = OCRMarkdownMapper()
        // median height will be computed from all observations
        // Heights: [0.12, 0.05, 0.03, 0.03, 0.03] → sorted: [0.03, 0.03, 0.03, 0.05, 0.12] → median = heights[2] = 0.03
        // H1: ratio >= 2.1 (0.12/0.03 = 4.0) ✓
        // H2: ratio >= 1.4 (0.05/0.03 = 1.67) ✓
        // Normal: 0.03/0.03 = 1.0
        let observations = [
            HandwritingOCRService.TextObservation(text: "Main Title", confidence: 0.95, boundingBox: CGRect(x: 0, y: 0.9, width: 0.8, height: 0.12)),
            HandwritingOCRService.TextObservation(text: "Subtitle", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.8, width: 0.6, height: 0.05)),
            HandwritingOCRService.TextObservation(text: "Normal line 1", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.7, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "Normal line 2", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.6, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "Normal line 3", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.03)),
        ]

        let result = await mapper.mapToMarkdown(observations)
        #expect(result.contains("# Main Title"))
        #expect(result.contains("## Subtitle"))
        // Normal lines should not have heading prefix
        #expect(result.contains("Normal line 1"))
    }

    // MARK: - OCR Mapper Table Detection

    @Test("OCRMarkdownMapper detects tab-separated table rows")
    func mapperTableDetection() async {
        let mapper = OCRMarkdownMapper()
        let observations = [
            HandwritingOCRService.TextObservation(text: "Name\tAge\tRole", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.9, width: 0.8, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "Alice\t30\tEngineer", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.8, width: 0.8, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "Bob\t25\tDesigner", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.7, width: 0.8, height: 0.03)),
        ]

        let result = await mapper.mapToMarkdown(observations)
        #expect(result.contains("|"))
        #expect(result.contains("---"))
        #expect(result.contains("Name"))
        #expect(result.contains("Alice"))
    }

    // MARK: - OCR Mapper Numbered List

    @Test("OCRMarkdownMapper detects numbered lists")
    func mapperNumberedList() async {
        let mapper = OCRMarkdownMapper()
        let observations = [
            HandwritingOCRService.TextObservation(text: "1. First item", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "2. Second item", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.8, width: 0.5, height: 0.03)),
            HandwritingOCRService.TextObservation(text: "3. Third item", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.7, width: 0.5, height: 0.03)),
        ]

        let result = await mapper.mapToMarkdown(observations)
        #expect(result.contains("1. First item"))
        #expect(result.contains("2. Second item"))
        #expect(result.contains("3. Third item"))
    }
}
#endif
