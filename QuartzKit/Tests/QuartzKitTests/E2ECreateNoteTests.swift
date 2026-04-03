import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Create Note Flow Tests

@Suite("E2ECreateNote")
struct E2ECreateNoteTests {

    @Test("FileNode tree represents created note structure")
    func fileNodeTreeStructure() {
        let note = FileNode(
            name: "New Note.md",
            url: URL(fileURLWithPath: "/vault/New Note.md"),
            nodeType: .note
        )
        let folder = FileNode(
            name: "Projects",
            url: URL(fileURLWithPath: "/vault/Projects"),
            nodeType: .folder,
            children: [note]
        )

        #expect(folder.isFolder == true)
        #expect(folder.children?.count == 1)
        #expect(folder.children?.first?.name == "New Note.md")
        #expect(folder.children?.first?.isNote == true)
    }

    @Test("Frontmatter model supports tags and title")
    func frontmatterModel() {
        var fm = Frontmatter()
        fm.title = "Test Note"
        fm.tags = ["swift", "ios"]

        #expect(fm.title == "Test Note")
        #expect(fm.tags == ["swift", "ios"])

        // Empty frontmatter has empty tags array
        let empty = Frontmatter()
        #expect(empty.title == nil)
        #expect(empty.tags.isEmpty)
    }
}
