import Foundation
import QuartzKit

/// Creates a temporary vault with known fixture content for deterministic UI testing.
///
/// Triggered by the `--mock-vault` launch argument. The vault is created
/// in `/tmp` and automatically opened, bypassing the vault picker flow.
enum UITestFixtureVault {

    /// Root directory for UI test fixture vaults.
    private static let baseDir = FileManager.default.temporaryDirectory
        .appending(path: "QuartzUITest", directoryHint: .isDirectory)

    /// Creates a fixture vault and returns its configuration.
    ///
    /// The vault contains:
    /// - `Welcome.md` — a simple note
    /// - `Todo.md` — a task list note
    /// - `Projects/` folder with `Project A.md`
    @discardableResult
    static func create() throws -> VaultConfig {
        let fm = FileManager.default

        // Clean previous fixture if it exists
        if fm.fileExists(atPath: baseDir.path(percentEncoded: false)) {
            try fm.removeItem(at: baseDir)
        }

        // Create vault root + subfolders
        let projectsDir = baseDir.appending(path: "Projects", directoryHint: .isDirectory)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        // Write fixture notes.
        // NSFileCoordinator (CoordinatedFileWriter) is unnecessary for ephemeral /tmp
        // test fixtures — coordinated access protects against iCloud conflicts on
        // production vault I/O, which does not apply here.
        try writeFixture("# Welcome\n\nThis is a test note for UI testing.\n",
                         to: baseDir.appending(path: "Welcome.md"))

        try writeFixture("# Todo\n\n- [ ] First task\n- [x] Completed task\n- [ ] Third task\n",
                         to: baseDir.appending(path: "Todo.md"))

        try writeFixture("# Project A\n\nProject details and notes go here.\n",
                         to: projectsDir.appending(path: "Project A.md"))

        try writeFixture(makeReleaseNotesFixture(),
                         to: baseDir.appending(path: "Release Notes.md"))

        return VaultConfig(name: "UI Test Vault", rootURL: baseDir)
    }

    /// Removes the fixture vault directory if it exists.
    static func cleanup() {
        try? FileManager.default.removeItem(at: baseDir)
    }

    /// Writes fixture content directly to a /tmp path.
    ///
    /// NSFileCoordinator is unnecessary for ephemeral test fixtures that live
    /// outside the production vault directory. Coordinated access is reserved
    /// for production vault I/O where iCloud conflict avoidance matters.
    private static func writeFixture(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func makeReleaseNotesFixture() -> String {
        let repeatedSection = """
        ## Writing Workflow

        This paragraph is deliberately long so UI coverage exercises a realistic existing note instead of a tiny synthetic fixture. The release notes note is meant to behave like a user-authored markdown document with headings, paragraphs, and enough structure for formatting regressions to show up around inserted blocks.

        ### Formatting Guarantees

        Quartz should preserve heading styling, body text layout, and list rendering even when the user inserts structural markdown like tables into an already-authored note.

        """

        return """
        # Release Notes

        This note exists specifically for shell-level formatting coverage.

        \(String(repeating: repeatedSection + "\n", count: 12))
        """
    }
}
