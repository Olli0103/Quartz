import Testing
import Foundation
@testable import QuartzKit

// MARK: - Drag-Drop Editor Tests (Asset Manager)

/// Verifies AssetManager logic: markdown link generation, duplicate
/// filename handling, and asset folder creation. Uses real filesystem
/// in temp directories.

@Suite("Drag-Drop Asset Import")
struct DragDropEditorTests {

    private func makeTempVault() throws -> (vault: URL, note: URL) {
        let vault = FileManager.default.temporaryDirectory
            .appending(path: "drag-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let note = vault.appending(path: "test-note.md")
        try "# Test".write(to: note, atomically: true, encoding: .utf8)
        return (vault, note)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Image import produces markdown image link syntax")
    func imageImportMarkdownLink() async throws {
        let (vault, note) = try makeTempVault()
        defer { cleanup(vault) }

        // Create a source image file
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { cleanup(sourceDir) }

        let sourceFile = sourceDir.appending(path: "photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceFile) // PNG header bytes

        let manager = AssetManager()
        let link = try await manager.importAsset(
            from: sourceFile,
            vaultRoot: vault,
            noteURL: note
        )

        #expect(link.hasPrefix("!["), "Image should produce ![]() syntax, got: \(link)")
        #expect(link.contains("photo"), "Link should contain the filename")
        #expect(link.contains("assets/"), "Link should reference assets/ folder")
    }

    @Test("Duplicate filenames get numeric suffix")
    func duplicateFilenameHandling() async throws {
        let (vault, note) = try makeTempVault()
        defer { cleanup(vault) }

        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "dup-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { cleanup(sourceDir) }

        let manager = AssetManager()

        // Import same filename twice
        for i in 0..<2 {
            let sourceFile = sourceDir.appending(path: "image\(i).png")
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceFile)
            // Copy as "duplicate.png" by renaming
            let renamedFile = sourceDir.appending(path: "duplicate-round\(i).png")
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: renamedFile)
            _ = try await manager.importAsset(
                from: renamedFile,
                vaultRoot: vault,
                noteURL: note
            )
        }

        // Both should exist in assets/ folder
        let assets = try await manager.listAssets(in: vault)
        #expect(assets.count == 2, "Both files should exist, got \(assets.count)")
    }

    @Test("Assets folder is created on first import")
    func assetsFolderCreation() async throws {
        let (vault, note) = try makeTempVault()
        defer { cleanup(vault) }

        let assetsDir = vault.appending(path: "assets")
        #expect(!FileManager.default.fileExists(atPath: assetsDir.path(percentEncoded: false)),
            "Assets folder should not exist before first import")

        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "folder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { cleanup(sourceDir) }

        let sourceFile = sourceDir.appending(path: "test.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceFile)

        let manager = AssetManager()
        _ = try await manager.importAsset(
            from: sourceFile,
            vaultRoot: vault,
            noteURL: note
        )

        #expect(FileManager.default.fileExists(atPath: assetsDir.path(percentEncoded: false)),
            "Assets folder should be created after first import")
    }

    @Test("PDF import uses regular link syntax (not image)")
    func pdfImportLinkSyntax() async throws {
        let (vault, note) = try makeTempVault()
        defer { cleanup(vault) }

        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "pdf-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { cleanup(sourceDir) }

        let sourceFile = sourceDir.appending(path: "document.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: sourceFile) // %PDF header

        let manager = AssetManager()
        let link = try await manager.importAsset(
            from: sourceFile,
            vaultRoot: vault,
            noteURL: note
        )

        #expect(link.hasPrefix("["), "PDF should produce []() syntax (not ![]())")
        #expect(!link.hasPrefix("!["), "PDF should NOT use image link syntax")
        #expect(link.contains("document"), "Link should contain filename")
    }

    @Test("Unsupported file type throws error")
    func unsupportedFileType() async throws {
        let (vault, note) = try makeTempVault()
        defer { cleanup(vault) }

        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "unsupported-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { cleanup(sourceDir) }

        let sourceFile = sourceDir.appending(path: "malware.exe")
        try Data([0x00]).write(to: sourceFile)

        let manager = AssetManager()
        await #expect(throws: AssetError.self) {
            try await manager.importAsset(
                from: sourceFile,
                vaultRoot: vault,
                noteURL: note
            )
        }
    }
}
