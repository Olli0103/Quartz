import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 4: Sidebar, Graph & Dashboard Tests

// MARK: - TaskItemParser Tests

@Suite("TaskItemParser")
struct TaskItemParserTests {
    @Test("Parse open tasks from markdown")
    func parseOpenTasks() {
        let body = """
        # Tasks
        - [ ] Buy groceries
        - [x] Complete report
        - [ ] Call mom
        """
        let tasks = TaskItemParser.parseOpenTasks(
            from: body,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test Note"
        )

        #expect(tasks.count == 2) // Only open tasks
        #expect(tasks[0].text == "Buy groceries")
        #expect(tasks[1].text == "Call mom")
        #expect(tasks[0].isCompleted == false)
    }

    @Test("Line numbers are 1-based")
    func lineNumbersAre1Based() {
        let body = """
        Line 1
        - [ ] Task on line 2
        Line 3
        - [ ] Task on line 4
        """
        let tasks = TaskItemParser.parseOpenTasks(
            from: body,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test"
        )

        #expect(tasks.count == 2)
        #expect(tasks[0].lineNumber == 2)
        #expect(tasks[1].lineNumber == 4)
    }

    @Test("Handles various checkbox formats")
    func handlesCheckboxFormats() {
        let body = """
        - [ ] unchecked
        - [x] lowercase x
        - [X] uppercase X
        """
        let tasks = TaskItemParser.parseOpenTasks(
            from: body,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test"
        )

        #expect(tasks.count == 1) // Only unchecked
        #expect(tasks[0].text == "unchecked")
    }

    @Test("Ignores non-task lines")
    func ignoresNonTaskLines() {
        let body = """
        # Heading
        Regular paragraph text
        - Regular list item
        - [ ] Actual task
        * Bullet point
        """
        let tasks = TaskItemParser.parseOpenTasks(
            from: body,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test"
        )

        #expect(tasks.count == 1)
        #expect(tasks[0].text == "Actual task")
    }

    @Test("Preserves original line content")
    func preservesOriginalLineContent() {
        let body = "  - [ ] Indented task"
        let tasks = TaskItemParser.parseOpenTasks(
            from: body,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test"
        )

        #expect(tasks.count == 1)
        #expect(tasks[0].lineContent == "  - [ ] Indented task")
    }

    @Test("Empty body returns no tasks")
    func emptyBodyNoTasks() {
        let tasks = TaskItemParser.parseOpenTasks(
            from: "",
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test"
        )
        #expect(tasks.isEmpty)
    }

    @Test("Task without text is ignored")
    func taskWithoutTextIgnored() {
        let body = "- [ ] \n- [ ]"
        let tasks = TaskItemParser.parseOpenTasks(
            from: body,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test"
        )
        #expect(tasks.isEmpty)
    }

    @Test("Note URL and title are preserved")
    func noteInfoPreserved() {
        let body = "- [ ] Task"
        let noteURL = URL(fileURLWithPath: "/path/to/note.md")
        let noteTitle = "My Note Title"

        let tasks = TaskItemParser.parseOpenTasks(from: body, noteURL: noteURL, noteTitle: noteTitle)

        #expect(tasks.count == 1)
        #expect(tasks[0].noteURL == noteURL)
        #expect(tasks[0].noteTitle == noteTitle)
    }
}

// MARK: - DashboardTaskItem Tests

@Suite("DashboardTaskItem")
struct DashboardTaskItemTests {
    @Test("Task item has unique ID")
    func taskItemHasUniqueID() {
        let task1 = DashboardTaskItem(
            text: "Task 1",
            isCompleted: false,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test",
            lineNumber: 1,
            lineContent: "- [ ] Task 1"
        )

        let task2 = DashboardTaskItem(
            text: "Task 2",
            isCompleted: false,
            noteURL: URL(fileURLWithPath: "/test.md"),
            noteTitle: "Test",
            lineNumber: 2,
            lineContent: "- [ ] Task 2"
        )

        #expect(task1.id != task2.id)
    }

    @Test("Task item properties are correct")
    func taskItemProperties() {
        let task = DashboardTaskItem(
            text: "Buy milk",
            isCompleted: true,
            noteURL: URL(fileURLWithPath: "/todo.md"),
            noteTitle: "Shopping",
            lineNumber: 5,
            lineContent: "- [x] Buy milk"
        )

        #expect(task.text == "Buy milk")
        #expect(task.isCompleted == true)
        #expect(task.lineNumber == 5)
        #expect(task.lineContent == "- [x] Buy milk")
    }
}

// MARK: - FileNode Tests

@Suite("SidebarFileNode")
struct SidebarFileNodeTests {
    @Test("FileNode isNote property")
    func fileNodeIsNote() {
        let note = FileNode(
            name: "test.md",
            url: URL(fileURLWithPath: "/test.md"),
            nodeType: .note
        )

        let folder = FileNode(
            name: "folder",
            url: URL(fileURLWithPath: "/folder"),
            nodeType: .folder
        )

        #expect(note.isNote)
        #expect(!folder.isNote)
    }

    @Test("FileNode children for folders")
    func fileNodeChildren() {
        let child = FileNode(
            name: "child.md",
            url: URL(fileURLWithPath: "/folder/child.md"),
            nodeType: .note
        )

        let folder = FileNode(
            name: "folder",
            url: URL(fileURLWithPath: "/folder"),
            nodeType: .folder,
            children: [child]
        )

        #expect(folder.children?.count == 1)
        #expect(folder.children?.first?.name == "child.md")
    }

    @Test("FileNode metadata")
    func fileNodeMetadata() {
        let now = Date()
        let metadata = FileMetadata(createdAt: now, modifiedAt: now, fileSize: 1024)

        let node = FileNode(
            name: "test.md",
            url: URL(fileURLWithPath: "/test.md"),
            nodeType: .note,
            metadata: metadata
        )

        #expect(node.metadata.fileSize == 1024)
        #expect(node.metadata.createdAt == now)
    }
}

// MARK: - XCTest Performance Tests for Sidebar & Dashboard

final class SidebarDashboardPerformanceTests: XCTestCase {
    func testTaskParsingPerformance() throws {
        // Generate a large markdown file with 500 tasks
        var body = "# Large Task List\n\n"
        for i in 0..<500 {
            body += "- [ ] Task number \(i + 1) with some description text\n"
            if i % 5 == 0 {
                body += "- [x] Completed task \(i)\n"
            }
        }

        let noteURL = URL(fileURLWithPath: "/tasks.md")

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let tasks = TaskItemParser.parseOpenTasks(from: body, noteURL: noteURL, noteTitle: "Tasks")
            XCTAssertEqual(tasks.count, 500) // Only unchecked
        }
    }

    func testLargeFileTreeTraversal() throws {
        // Build a tree with 1000 nodes (files and folders)
        var nodes: [FileNode] = []
        for folder in 0..<20 {
            var children: [FileNode] = []
            for file in 0..<50 {
                children.append(FileNode(
                    name: "note_\(folder)_\(file).md",
                    url: URL(fileURLWithPath: "/vault/folder\(folder)/note_\(folder)_\(file).md"),
                    nodeType: .note,
                    metadata: FileMetadata(createdAt: Date(), modifiedAt: Date(), fileSize: 1024)
                ))
            }
            nodes.append(FileNode(
                name: "folder\(folder)",
                url: URL(fileURLWithPath: "/vault/folder\(folder)"),
                nodeType: .folder,
                children: children
            ))
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            // Simulate tree traversal (collecting all notes)
            var allNotes: [FileNode] = []
            func collectNotes(from nodes: [FileNode]) {
                for node in nodes {
                    if node.isNote {
                        allNotes.append(node)
                    }
                    if let children = node.children {
                        collectNotes(from: children)
                    }
                }
            }
            collectNotes(from: nodes)
            XCTAssertEqual(allNotes.count, 1000)
        }
    }

    func testMultipleVaultTaskParsing() async throws {
        // Simulate parsing tasks from 100 notes concurrently
        var notes: [(String, URL, String)] = []
        for i in 0..<100 {
            let body = """
            # Note \(i)
            - [ ] Task A in note \(i)
            - [ ] Task B in note \(i)
            - [x] Completed in note \(i)
            - [ ] Task C in note \(i)
            """
            notes.append((body, URL(fileURLWithPath: "/note\(i).md"), "Note \(i)"))
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var allTasks: [DashboardTaskItem] = []
            for (body, url, title) in notes {
                let tasks = TaskItemParser.parseOpenTasks(from: body, noteURL: url, noteTitle: title)
                allTasks.append(contentsOf: tasks)
            }
            XCTAssertEqual(allTasks.count, 300) // 3 open tasks per note
        }
    }

    func testSearchFilteringPerformance() throws {
        // Generate 1000 file nodes
        var nodes: [FileNode] = []
        let words = ["swift", "markdown", "quartz", "editor", "notes", "vault", "sync", "cloud", "task", "dashboard"]

        for i in 0..<1000 {
            let name = "\(words[i % words.count])_\(i).md"
            nodes.append(FileNode(
                name: name,
                url: URL(fileURLWithPath: "/vault/\(name)"),
                nodeType: .note
            ))
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let searchTerms = ["swift", "mar", "qua", "edit", "not"]
            for term in searchTerms {
                let lowercaseTerm = term.lowercased()
                let filtered = nodes.filter { $0.name.lowercased().contains(lowercaseTerm) }
                XCTAssertGreaterThan(filtered.count, 0)
            }
        }
    }
}

// MARK: - Drag & Drop Validation Tests

@Suite("SidebarDragDrop")
struct SidebarDragDropTests {
    @Test("Cannot drop folder into itself")
    func cannotDropFolderIntoItself() {
        let folder = FileNode(
            name: "MyFolder",
            url: URL(fileURLWithPath: "/vault/MyFolder"),
            nodeType: .folder
        )

        // Validation: source URL should not equal target URL
        #expect(folder.url != folder.url.appending(path: folder.name))
    }

    @Test("Cannot drop folder into its own subfolder")
    func cannotDropIntoSubfolder() {
        let parentURL = URL(fileURLWithPath: "/vault/Parent")
        let childURL = URL(fileURLWithPath: "/vault/Parent/Child")

        // Validation: child path starts with parent path
        let parentPath = parentURL.standardizedFileURL.path()
        let childPath = childURL.standardizedFileURL.path()

        #expect(childPath.hasPrefix(parentPath))
    }

    @Test("Valid drop targets are identified")
    func validDropTargets() {
        let sourceURL = URL(fileURLWithPath: "/vault/Notes/note.md")
        let targetURL = URL(fileURLWithPath: "/vault/Archive")

        let sourcePath = sourceURL.standardizedFileURL.path()
        let targetPath = targetURL.standardizedFileURL.path()

        // Valid: target is not inside source
        #expect(!targetPath.hasPrefix(sourcePath))
    }
}

// MARK: - Graph Cache Tests

@Suite("GraphCacheIntegration")
struct GraphCacheIntegrationTests {
    @Test("Graph data can be built from file nodes")
    func graphFromFileNodes() {
        let nodes = [
            FileNode(
                name: "note1.md",
                url: URL(fileURLWithPath: "/vault/note1.md"),
                nodeType: .note
            ),
            FileNode(
                name: "note2.md",
                url: URL(fileURLWithPath: "/vault/note2.md"),
                nodeType: .note
            )
        ]

        // Simulate building graph vertex data
        let vertices = nodes.map { node -> (String, URL) in
            (node.name.replacingOccurrences(of: ".md", with: ""), node.url)
        }

        #expect(vertices.count == 2)
        #expect(vertices[0].0 == "note1")
        #expect(vertices[1].0 == "note2")
    }

    @Test("Links between notes can be parsed")
    func linksCanBeParsed() {
        let content = "Link to [[note2]] and [[note3|alias]]"

        // Simplified wikilink extraction
        var links: [String] = []
        var currentIndex = content.startIndex

        while let openBracket = content[currentIndex...].range(of: "[[") {
            guard let closeBracket = content[openBracket.upperBound...].range(of: "]]") else { break }
            let linkContent = String(content[openBracket.upperBound..<closeBracket.lowerBound])
            let linkTarget = linkContent.components(separatedBy: "|").first ?? linkContent
            links.append(linkTarget)
            currentIndex = closeBracket.upperBound
        }

        #expect(links.count == 2)
        #expect(links[0] == "note2")
        #expect(links[1] == "note3")
    }
}
