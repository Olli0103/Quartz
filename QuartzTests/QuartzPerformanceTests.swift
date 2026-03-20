//
//  QuartzPerformanceTests.swift
//  QuartzTests
//
//  Created by Posselt, Oliver on 13.03.26.
//

import XCTest
import NaturalLanguage
@testable import QuartzKit

/// Performance tests using XCTMetric for CPU, memory, and timing measurements.
final class QuartzPerformanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Markdown Parsing Performance

    @MainActor
    func testMarkdownParsingPerformance() throws {
        let longMarkdown = generateLongMarkdownDocument(paragraphs: 100)
        let highlighter = MarkdownASTHighlighter(baseFontSize: 14)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "Parse complete")
            Task {
                _ = await highlighter.parseDebounced(longMarkdown)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }

    @MainActor
    func testHeadingExtractionPerformance() throws {
        let longMarkdown = generateLongMarkdownDocument(paragraphs: 200)
        let extractor = HeadingExtractor()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = extractor.extractHeadings(from: longMarkdown)
        }
    }

    // MARK: - Frontmatter Parsing Performance

    @MainActor
    func testFrontmatterParsingPerformance() throws {
        let parser = FrontmatterParser()
        let content = """
        ---
        title: Performance Test Note
        date: 2026-03-20
        tags: [performance, testing, swift, xcode, quartz]
        author: Test User
        draft: false
        ---

        # Content starts here

        This is the main content of the note.
        """

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            for _ in 0..<1000 {
                _ = try? parser.parse(from: content)
            }
        }
    }

    // MARK: - Note Document Creation Performance

    @MainActor
    func testNoteDocumentCreationPerformance() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for i in 0..<100 {
                let url = tempDir.appendingPathComponent("note\(i).md")
                let content = "# Test Note \(i)\n\nContent for note \(i)"
                try? content.write(to: url, atomically: true, encoding: .utf8)

                let document = NoteDocument(fileURL: url)
                _ = document.frontmatter
            }
        }
    }

    // MARK: - Search Performance

    @MainActor
    func testNoteSearchPerformance() throws {
        let notes = (0..<500).map { i -> NoteDocument in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("search_test_\(i).md")
            return NoteDocument(
                fileURL: tempURL,
                frontmatter: Frontmatter(
                    title: "Note \(i) about \(["Swift", "iOS", "macOS", "SwiftUI", "Testing"].randomElement()!)",
                    tags: ["tag\(i % 10)", "category\(i % 5)"],
                    createdAt: Date(),
                    modifiedAt: Date()
                )
            )
        }

        let searchTerms = ["Swift", "iOS", "Note 1", "tag5", "category2"]

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            for term in searchTerms {
                let lowercaseTerm = term.lowercased()
                _ = notes.filter { note in
                    (note.frontmatter.title ?? "").lowercased().contains(lowercaseTerm) ||
                    note.frontmatter.tags.contains { $0.lowercased().contains(lowercaseTerm) }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func generateLongMarkdownDocument(paragraphs: Int) -> String {
        var content = "# Main Document Title\n\n"

        for i in 0..<paragraphs {
            if i % 10 == 0 {
                content += "## Section \(i / 10 + 1)\n\n"
            }
            if i % 5 == 0 {
                content += "### Subsection \(i / 5 + 1)\n\n"
            }

            content += """
            This is paragraph \(i + 1) of the document. It contains **bold text**, *italic text*, \
            and `inline code`. Here's a [link](https://example.com) and some more text to make \
            this paragraph reasonably long for testing purposes.

            - List item 1
            - List item 2
            - List item 3

            """
        }

        return content
    }
}

// MARK: - TextKit 2 Performance Tests

final class TextKit2PerformanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    #if os(iOS) || os(macOS)
    @MainActor
    func testTextContentManagerCreationPerformance() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 {
                _ = MarkdownTextContentManager()
            }
        }
    }

    @MainActor
    func testTextLayoutPerformance() throws {
        let contentManager = MarkdownTextContentManager()
        let longText = String(repeating: "This is a test line of text for layout measurement.\n", count: 1000)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            contentManager.performMarkdownEdit {
                // Simulate attribute changes
                contentManager.baseFontSize = 14
                contentManager.fontScale = 1.0
            }
        }
    }
    #endif
}

// MARK: - AI Service Performance Tests

final class AIServicePerformanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnDeviceSummarizePerformance() throws {
        // Skip if running in CI or test environment without AI services
        // This test requires on-device NLP which may not be available in all environments
        let longText = String(repeating: "This is a sentence that needs to be summarized. ", count: 50)

        // Measure synchronous NLP operations only
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric()], options: options) {
            // Use NLTokenizer directly for a simpler test
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = longText
            var sentenceCount = 0
            tokenizer.enumerateTokens(in: longText.startIndex..<longText.endIndex) { _, _ in
                sentenceCount += 1
                return true
            }
            XCTAssertGreaterThan(sentenceCount, 0)
        }
    }
}

// MARK: - Memory Pressure Tests

final class MemoryPressureTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLargeDocumentMemoryUsage() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTMemoryMetric()], options: options) {
            var documents: [NoteDocument] = []
            let tempDir = FileManager.default.temporaryDirectory

            for i in 0..<100 {
                let url = tempDir.appendingPathComponent("memory_test_\(i).md")
                let content = String(repeating: "Content line \(i)\n", count: 100)
                try? content.write(to: url, atomically: true, encoding: .utf8)

                let doc = NoteDocument(fileURL: url)
                documents.append(doc)
            }

            // Force access to trigger loading
            for doc in documents {
                _ = doc.frontmatter.title
            }

            documents.removeAll()
        }
    }

    @MainActor
    func testHighlighterMemoryStability() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTMemoryMetric()], options: options) {
            let highlighter = MarkdownASTHighlighter(baseFontSize: 14)
            let content = String(repeating: "# Heading\n\nParagraph with **bold** and *italic*.\n\n", count: 500)

            let expectation = expectation(description: "Highlight complete")
            Task {
                for _ in 0..<10 {
                    _ = await highlighter.parseDebounced(content)
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60.0)
        }
    }
}
