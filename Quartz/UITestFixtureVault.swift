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

        // Write fixture notes
        try "# Welcome\n\nThis is a test note for UI testing.\n".write(
            to: baseDir.appending(path: "Welcome.md"),
            atomically: true,
            encoding: .utf8
        )

        try "# Todo\n\n- [ ] First task\n- [x] Completed task\n- [ ] Third task\n".write(
            to: baseDir.appending(path: "Todo.md"),
            atomically: true,
            encoding: .utf8
        )

        try "# Project A\n\nProject details and notes go here.\n".write(
            to: projectsDir.appending(path: "Project A.md"),
            atomically: true,
            encoding: .utf8
        )

        return VaultConfig(name: "UI Test Vault", rootURL: baseDir)
    }

    /// Removes the fixture vault directory if it exists.
    static func cleanup() {
        try? FileManager.default.removeItem(at: baseDir)
    }
}
