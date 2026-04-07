import Testing
import Foundation
@testable import QuartzKit

// MARK: - Share Extension Capture Tests
//
// Validates share sheet content reception and note creation.
// Complements QuickNoteViewTests (basic capture + markdown) with:
// - Full SharedItem variant coverage (image, mixed-no-url)
// - Inbox append to existing file
// - Image asset writing to assets/ folder
// - Title sanitization (slashes, newlines)
// - YAML special-character escaping
// - SharedItem.previewIcon SF Symbol mapping
//
// Note: Phase6SystemIntegrationTests has a lightweight ShareExtensionTests suite;
// this file tests the actual production ShareCaptureUseCase and SharedItem types.

@Suite("ShareExtensionCapture")
struct ShareExtensionCaptureTests {

    // MARK: - Helpers

    private func makeTempVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - SharedItem Markdown Content

    @Test("SharedItem.image markdownContent renders with and without caption")
    func imageMarkdownContent() {
        let withCaption = SharedItem.image(Data(), caption: "A photo", assetPath: "assets/img.png")
        #expect(withCaption.markdownContent.contains("![A photo](assets/img.png)"))
        #expect(withCaption.markdownContent.contains("A photo"),
            "Caption should appear as text below the image")

        let withoutCaption = SharedItem.image(Data(), caption: nil, assetPath: "assets/img.png")
        #expect(withoutCaption.markdownContent.contains("![Captured Image](assets/img.png)"))

        let noPath = SharedItem.image(Data(), caption: nil, assetPath: nil)
        #expect(noPath.markdownContent.contains("attachment.png"),
            "Missing asset path should fall back to attachment.png")
    }

    @Test("SharedItem.mixed without URL renders text only")
    func mixedWithoutURL() {
        let item = SharedItem.mixed(text: "Just a note", url: nil)
        #expect(item.markdownContent == "Just a note")
    }

    @Test("SharedItem.previewIcon returns correct SF Symbols for all cases")
    func previewIcons() {
        #expect(SharedItem.text("t").previewIcon == "text.quote")
        #expect(SharedItem.url(URL(string: "https://x.com")!, title: nil).previewIcon == "link")
        #expect(SharedItem.image(Data(), caption: nil).previewIcon == "photo")
        #expect(SharedItem.mixed(text: "", url: nil).previewIcon == "doc.text")
    }

    // MARK: - Inbox Append

    @Test("Inbox append adds entry to existing Inbox.md")
    func inboxAppendExisting() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()

        // First capture creates Inbox.md
        let url1 = try useCase.capture(.text("First"), in: root, mode: .inbox)
        let content1 = try String(contentsOf: url1, encoding: .utf8)
        #expect(content1.contains("First"))

        // Second capture appends to existing Inbox.md
        let url2 = try useCase.capture(.text("Second"), in: root, mode: .inbox)
        #expect(url2 == url1, "Should write to the same Inbox.md file")

        let content2 = try String(contentsOf: url2, encoding: .utf8)
        #expect(content2.contains("First"), "Original content should be preserved")
        #expect(content2.contains("Second"), "New content should be appended")
        #expect(content2.contains("---"), "Entries should be separated by a divider")
    }

    // MARK: - New Note Creation

    @Test("New note title sanitizes slashes and newlines")
    func titleSanitization() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()

        // Slash replaced with dash
        let url1 = try useCase.capture(.text("content"), in: root, mode: .newNote(title: "A/B"))
        #expect(url1.lastPathComponent == "A-B.md",
            "Slashes in title should be replaced with dashes")

        // Newline replaced with space
        let url2 = try useCase.capture(.text("content"), in: root, mode: .newNote(title: "Line1\nLine2"))
        #expect(url2.lastPathComponent == "Line1 Line2.md",
            "Newlines in title should be replaced with spaces")
    }

    @Test("New note YAML escapes special characters in title")
    func yamlEscaping() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()

        let url = try useCase.capture(.text("body"), in: root, mode: .newNote(title: "Title: With Colon"))
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("\"Title: With Colon\"") || content.contains("Title\\: With Colon"),
            "YAML special characters in title should be escaped or quoted")
    }

    @Test("New note with .md suffix does not double-extend")
    func noDoubleMdExtension() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()
        let url = try useCase.capture(.text("data"), in: root, mode: .newNote(title: "Already.md"))
        #expect(url.lastPathComponent == "Already.md",
            "Title ending in .md should not become Already.md.md")
    }

    // MARK: - Image Asset Writing

    @Test("Image capture writes PNG to assets/ folder")
    func imageAssetWriting() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes

        let url = try useCase.capture(
            .image(imageData, caption: "Screenshot"),
            in: root,
            mode: .newNote(title: "ImageNote")
        )

        // Note should be created
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let noteContent = try String(contentsOf: url, encoding: .utf8)
        #expect(noteContent.contains("Screenshot"), "Caption should appear in note")
        #expect(noteContent.contains("assets/capture-"), "Note should reference asset path")

        // Asset file should exist in assets/ folder
        let assetsDir = root.appending(path: "assets")
        let assetFiles = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path(percentEncoded: false))
        #expect(assetFiles.count == 1, "Should have exactly one asset file")
        #expect(assetFiles.first?.hasPrefix("capture-") == true)
        #expect(assetFiles.first?.hasSuffix(".png") == true)
    }

    // MARK: - URL Capture

    @Test("URL without title uses host as display text")
    func urlWithoutTitle() {
        let item = SharedItem.url(URL(string: "https://developer.apple.com/docs")!, title: nil)
        let md = item.markdownContent
        #expect(md.contains("[developer.apple.com]"),
            "URL without title should use host as link text")
        #expect(md.contains("(https://developer.apple.com/docs)"))
    }

    // MARK: - Frontmatter Correctness

    @Test("New note frontmatter contains required fields")
    func frontmatterFields() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()
        let url = try useCase.capture(.text("Hello"), in: root, mode: .newNote(title: "Meta"))
        let content = try String(contentsOf: url, encoding: .utf8)

        #expect(content.contains("title:"), "Frontmatter should contain title")
        #expect(content.contains("tags:"), "Frontmatter should contain tags")
        #expect(content.contains("created:"), "Frontmatter should contain created date")
        #expect(content.contains("modified:"), "Frontmatter should contain modified date")
        #expect(content.contains("[capture]"), "Tags should include 'capture'")
    }

    @Test("Inbox note frontmatter contains inbox tag")
    func inboxFrontmatter() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()
        let url = try useCase.capture(.text("entry"), in: root, mode: .inbox)
        let content = try String(contentsOf: url, encoding: .utf8)

        #expect(content.contains("[inbox, capture]"),
            "Inbox frontmatter should have both inbox and capture tags")
        #expect(content.contains("# Inbox"), "Inbox should have heading")
    }
}
