import Foundation

/// Creates vault structures from predefined templates.
public actor VaultTemplateService {
    private let fileManager = FileManager.default
    private let writer = CoordinatedFileWriter.shared

    public init() {}

    /// Creates the folder structure for a template in the vault.
    public func applyTemplate(_ template: VaultTemplate, to vaultRoot: URL) throws {
        switch template {
        case .para:
            try createPARAStructure(in: vaultRoot)
        case .zettelkasten:
            try createZettelkastenStructure(in: vaultRoot)
        case .custom:
            break
        }
    }

    /// Creates a Daily Note for today.
    public func createDailyNote(in vaultRoot: URL) throws -> URL {
        let dailyFolder = vaultRoot.appending(path: "Daily Notes")
        try writer.createDirectory(at: dailyFolder)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(formatter.string(from: Date())).md"
        let fileURL = dailyFolder.appending(path: fileName)

        guard !fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return fileURL
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .full
        displayFormatter.locale = Locale.current

        let content = """
        ---
        title: \(displayFormatter.string(from: Date()))
        tags: [daily]
        created: \(ISO8601DateFormatter().string(from: Date()))
        modified: \(ISO8601DateFormatter().string(from: Date()))
        template: daily
        ---

        ## Tasks

        - [ ]

        ## Notes


        ## Journal


        """

        guard let data = content.data(using: .utf8) else {
            throw FileSystemError.encodingFailed(fileURL)
        }
        try writer.write(data, to: fileURL)
        return fileURL
    }

    /// Creates a note from a template.
    public func createFromTemplate(
        _ templateType: NoteTemplate,
        named name: String,
        in folder: URL
    ) throws -> URL {
        let fileName = name.hasSuffix(".md") ? name : "\(name).md"
        let fileURL = folder.appending(path: fileName)

        let content = templateType.content(title: name.replacingOccurrences(of: ".md", with: ""))
        guard let data = content.data(using: .utf8) else {
            throw FileSystemError.encodingFailed(fileURL)
        }
        try writer.write(data, to: fileURL)
        return fileURL
    }

    // MARK: - Private Structure Creators

    private func createPARAStructure(in root: URL) throws {
        let folders = [
            String(localized: "1 Projects", bundle: .module),
            String(localized: "2 Areas", bundle: .module),
            String(localized: "3 Resources", bundle: .module),
            String(localized: "4 Archive", bundle: .module),
            String(localized: "Daily Notes", bundle: .module),
            String(localized: "Templates", bundle: .module),
        ]
        for folder in folders {
            try writer.createDirectory(at: root.appending(path: folder))
        }

        // Create README
        let readme = """
        ---
        title: Welcome to your Vault
        tags: [meta]
        created: \(ISO8601DateFormatter().string(from: Date()))
        modified: \(ISO8601DateFormatter().string(from: Date()))
        ---

        # Welcome to Quartz

        Your vault is organized using the **PARA** method:

        - **1 Projects** – Active projects with a deadline
        - **2 Areas** – Ongoing areas of responsibility
        - **3 Resources** – Topics of interest, reference material
        - **4 Archive** – Completed or inactive items

        Use `Daily Notes` for your daily journal and `Templates` for reusable note templates.
        """

        if let readmeData = readme.data(using: .utf8) {
            try writer.write(readmeData, to: root.appending(path: "Welcome.md"))
        }
    }

    private func createZettelkastenStructure(in root: URL) throws {
        let folders = [
            String(localized: "Fleeting Notes", bundle: .module),
            String(localized: "Literature Notes", bundle: .module),
            String(localized: "Permanent Notes", bundle: .module),
            String(localized: "Projects", bundle: .module),
            String(localized: "Daily Notes", bundle: .module),
        ]
        for folder in folders {
            try writer.createDirectory(at: root.appending(path: folder))
        }

        let readme = """
        ---
        title: Welcome to your Zettelkasten
        tags: [meta]
        created: \(ISO8601DateFormatter().string(from: Date()))
        modified: \(ISO8601DateFormatter().string(from: Date()))
        ---

        # Welcome to your Zettelkasten

        - **Fleeting Notes** – Quick captures, raw ideas
        - **Literature Notes** – Notes from books, articles, podcasts
        - **Permanent Notes** – Refined, atomic ideas in your own words
        - **Projects** – Output-oriented collections

        Use `[[wiki-links]]` to connect your notes and build a knowledge graph.
        """

        if let readmeData = readme.data(using: .utf8) {
            try writer.write(readmeData, to: root.appending(path: "Welcome.md"))
        }
    }
}

// MARK: - Note Templates

/// Predefined note templates.
public enum NoteTemplate: String, CaseIterable, Sendable {
    case blank
    case daily
    case meeting
    case zettel
    case project

    public var displayName: String {
        switch self {
        case .blank: String(localized: "Blank Note", bundle: .module)
        case .daily: String(localized: "Daily Note", bundle: .module)
        case .meeting: String(localized: "Meeting Notes", bundle: .module)
        case .zettel: String(localized: "Zettelkasten Note", bundle: .module)
        case .project: String(localized: "Project Brief", bundle: .module)
        }
    }

    public var icon: String {
        switch self {
        case .blank: "doc"
        case .daily: "calendar"
        case .meeting: "person.3"
        case .zettel: "brain"
        case .project: "folder"
        }
    }

    func content(title: String) -> String {
        let now = ISO8601DateFormatter().string(from: Date())

        switch self {
        case .blank:
            return """
            ---
            title: \(title)
            tags: []
            created: \(now)
            modified: \(now)
            ---


            """

        case .daily:
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return """
            ---
            title: \(formatter.string(from: Date()))
            tags: [daily]
            created: \(now)
            modified: \(now)
            template: daily
            ---

            ## Tasks

            - [ ]

            ## Notes


            ## Journal


            """

        case .meeting:
            return """
            ---
            title: \(title)
            tags: [meeting]
            created: \(now)
            modified: \(now)
            template: meeting
            ---

            ## Attendees

            -

            ## Agenda

            1.

            ## Notes


            ## Action Items

            - [ ]

            """

        case .zettel:
            return """
            ---
            title: \(title)
            tags: []
            created: \(now)
            modified: \(now)
            template: zettelkasten
            ---

            ## Idea


            ## Source


            ## Connections

            - [[]]

            """

        case .project:
            return """
            ---
            title: \(title)
            tags: [project]
            created: \(now)
            modified: \(now)
            template: project
            ---

            ## Goal


            ## Timeline


            ## Tasks

            - [ ]

            ## Notes


            ## Resources

            -

            """
        }
    }
}
