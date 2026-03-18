import Testing
import Foundation
@testable import QuartzKit

// MARK: - FileNode Tests

@Suite("FileNode")
struct FileNodeTests {
    let testURL = URL(fileURLWithPath: "/vault/notes/test.md")

    @Test("isFolder returns true for folder type")
    func isFolder() {
        let folder = FileNode(name: "Folder", url: testURL, nodeType: .folder)
        #expect(folder.isFolder)
        #expect(!folder.isNote)
    }

    @Test("isNote returns true for note type")
    func isNote() {
        let note = FileNode(name: "Note.md", url: testURL, nodeType: .note)
        #expect(note.isNote)
        #expect(!note.isFolder)
    }

    @Test("Children default to nil")
    func childrenNil() {
        let node = FileNode(name: "test.md", url: testURL, nodeType: .note)
        #expect(node.children == nil)
    }

    @Test("Folder with children")
    func folderWithChildren() {
        let child1 = FileNode(name: "a.md", url: testURL.appendingPathComponent("a.md"), nodeType: .note)
        let child2 = FileNode(name: "b.md", url: testURL.appendingPathComponent("b.md"), nodeType: .note)
        let folder = FileNode(
            name: "Notes",
            url: testURL,
            nodeType: .folder,
            children: [child1, child2]
        )

        #expect(folder.children?.count == 2)
        #expect(folder.children?[0].name == "a.md")
    }

    @Test("Metadata defaults are reasonable")
    func metadataDefaults() {
        let meta = FileMetadata()
        #expect(meta.fileSize == 0)
        #expect(!meta.isEncrypted)
    }

    @Test("Frontmatter can be attached")
    func frontmatterAttached() {
        let fm = Frontmatter(title: "My Note", tags: ["swift"])
        let node = FileNode(name: "test.md", url: testURL, nodeType: .note, frontmatter: fm)
        #expect(node.frontmatter?.title == "My Note")
        #expect(node.frontmatter?.tags == ["swift"])
    }

    @Test("Node types cover all cases")
    func allNodeTypes() {
        let types: [NodeType] = [.folder, .note, .asset, .canvas]
        #expect(types.count == 4)

        let assetNode = FileNode(name: "image.png", url: testURL, nodeType: .asset)
        #expect(!assetNode.isFolder)
        #expect(!assetNode.isNote)

        let canvasNode = FileNode(name: "drawing", url: testURL, nodeType: .canvas)
        #expect(!canvasNode.isFolder)
        #expect(!canvasNode.isNote)
    }

    @Test("IDs are unique")
    func uniqueIDs() {
        let a = FileNode(name: "a.md", url: testURL, nodeType: .note)
        let b = FileNode(name: "b.md", url: testURL, nodeType: .note)
        #expect(a.id != b.id)
    }
}

// MARK: - NoteDocument Tests

@Suite("NoteDocument")
struct NoteDocumentTests {
    let testURL = URL(fileURLWithPath: "/vault/notes/test.md")

    @Test("displayName uses frontmatter title when available")
    func displayNameWithTitle() {
        let note = NoteDocument(
            fileURL: testURL,
            frontmatter: Frontmatter(title: "My Custom Title"),
            body: "Content"
        )
        #expect(note.displayName == "My Custom Title")
    }

    @Test("displayName falls back to filename")
    func displayNameFallback() {
        let note = NoteDocument(fileURL: testURL, body: "Content")
        #expect(note.displayName == "test")
    }

    @Test("Default values are correct")
    func defaults() {
        let note = NoteDocument(fileURL: testURL)
        #expect(note.body.isEmpty)
        #expect(!note.isDirty)
        #expect(note.canvasData == nil)
        #expect(note.lastSyncedAt == nil)
    }

    @Test("isDirty can be toggled")
    func isDirty() {
        var note = NoteDocument(fileURL: testURL, isDirty: true)
        #expect(note.isDirty)
        note.isDirty = false
        #expect(!note.isDirty)
    }

    @Test("Body and frontmatter are mutable")
    func mutableFields() {
        var note = NoteDocument(fileURL: testURL)
        note.body = "# Hello\nNew content"
        note.frontmatter.title = "Updated"
        note.frontmatter.tags = ["tag1", "tag2"]

        #expect(note.body.contains("Hello"))
        #expect(note.frontmatter.title == "Updated")
        #expect(note.frontmatter.tags.count == 2)
    }

    @Test("Canvas data can be attached")
    func canvasData() {
        let data = Data([0x01, 0x02, 0x03])
        let note = NoteDocument(fileURL: testURL, canvasData: data)
        #expect(note.canvasData?.count == 3)
    }
}

// MARK: - VaultConfig Tests

@Suite("VaultConfig")
struct VaultConfigTests {
    let rootURL = URL(fileURLWithPath: "/vaults/my-vault")

    @Test("Default storage type is local")
    func defaultStorageType() {
        let config = VaultConfig(name: "Test", rootURL: rootURL)
        #expect(config.storageType == .local)
    }

    @Test("Default values are correct")
    func defaults() {
        let config = VaultConfig(name: "Test", rootURL: rootURL)
        #expect(!config.isDefault)
        #expect(!config.encryptionEnabled)
        #expect(config.templateStructure == nil)
        #expect(config.syncConfig == nil)
    }

    @Test("All storage types exist")
    func storageTypes() {
        let local = VaultConfig(name: "Local", rootURL: rootURL, storageType: .local)
        let icloud = VaultConfig(name: "Cloud", rootURL: rootURL, storageType: .iCloudDrive)
        let webdav = VaultConfig(name: "WebDAV", rootURL: rootURL, storageType: .webdav)

        #expect(local.storageType == .local)
        #expect(icloud.storageType == .iCloudDrive)
        #expect(webdav.storageType == .webdav)
    }

    @Test("Template structures")
    func templates() {
        let para = VaultConfig(name: "P", rootURL: rootURL, templateStructure: .para)
        let zettel = VaultConfig(name: "Z", rootURL: rootURL, templateStructure: .zettelkasten)
        let custom = VaultConfig(name: "C", rootURL: rootURL, templateStructure: .custom)

        #expect(para.templateStructure == .para)
        #expect(zettel.templateStructure == .zettelkasten)
        #expect(custom.templateStructure == .custom)
    }

    @Test("Equatable works by ID")
    func equatable() {
        let id = UUID()
        let a = VaultConfig(id: id, name: "A", rootURL: rootURL)
        let b = VaultConfig(id: id, name: "A", rootURL: rootURL)
        #expect(a == b)
    }

    @Test("SyncConfig defaults")
    func syncConfigDefaults() {
        let sync = SyncConfig()
        #expect(sync.webdavURL == nil)
        #expect(sync.syncInterval == 300)
    }

    @Test("SyncConfig with WebDAV")
    func syncConfigWebDAV() {
        let sync = SyncConfig(
            webdavURL: URL(string: "https://dav.example.com")!,
            syncInterval: 60
        )
        #expect(sync.webdavURL?.host == "dav.example.com")
        #expect(sync.syncInterval == 60)
    }
}

// MARK: - Frontmatter Tests

@Suite("Frontmatter")
struct FrontmatterTests {
    @Test("Default values")
    func defaults() {
        let fm = Frontmatter()
        #expect(fm.title == nil)
        #expect(fm.tags.isEmpty)
        #expect(fm.aliases.isEmpty)
        #expect(fm.template == nil)
        #expect(fm.ocrText == nil)
        #expect(fm.linkedNotes.isEmpty)
        #expect(fm.customFields.isEmpty)
        #expect(!fm.isEncrypted)
    }

    @Test("Full initialization")
    func fullInit() {
        let fm = Frontmatter(
            title: "Test",
            tags: ["a", "b"],
            aliases: ["alias1"],
            template: "daily",
            ocrText: "Scanned text",
            linkedNotes: ["Other Note"],
            customFields: ["key": "value"],
            isEncrypted: true
        )

        #expect(fm.title == "Test")
        #expect(fm.tags == ["a", "b"])
        #expect(fm.aliases == ["alias1"])
        #expect(fm.template == "daily")
        #expect(fm.ocrText == "Scanned text")
        #expect(fm.linkedNotes == ["Other Note"])
        #expect(fm.customFields["key"] == "value")
        #expect(fm.isEncrypted)
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = Frontmatter(title: "Same", tags: ["x"])
        let b = Frontmatter(title: "Same", tags: ["x"])
        #expect(a == b)
    }

    @Test("Mutable fields")
    func mutable() {
        var fm = Frontmatter()
        fm.title = "New Title"
        fm.tags.append("newtag")
        fm.customFields["status"] = "draft"

        #expect(fm.title == "New Title")
        #expect(fm.tags == ["newtag"])
        #expect(fm.customFields["status"] == "draft")
    }
}

// MARK: - Feature Tests

@Suite("Feature")
struct FeatureTests {
    @Test("All features are covered")
    func allFeatures() {
        #expect(Feature.allCases.count == 13)
    }

    @Test("Feature has rawValue")
    func rawValues() {
        #expect(Feature.markdownEditor.rawValue == "markdownEditor")
        #expect(Feature.aiChat.rawValue == "aiChat")
        #expect(Feature.speakerDiarization.rawValue == "speakerDiarization")
    }

    @Test("FeatureTier values")
    func tiers() {
        #expect(FeatureTier.free.rawValue == "free")
    }
}
