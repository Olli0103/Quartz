import Foundation

/// Background actor that parses vault notes for `- [ ]` tasks without blocking the main thread.
///
/// Offloads file I/O and regex parsing to keep the UI responsive.
public actor DashboardTaskActor {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Parses open tasks from the given note URLs. Call from a background context.
    public func parseOpenTasks(from noteURLs: [URL]) async -> [DashboardTaskItem] {
        var allTasks: [DashboardTaskItem] = []
        for url in noteURLs {
            do {
                let doc = try await vaultProvider.readNote(at: url)
                let title = doc.frontmatter.title ?? url.deletingPathExtension().lastPathComponent
                let tasks = TaskItemParser.parseOpenTasks(from: doc.body, noteURL: url, noteTitle: title)
                allTasks.append(contentsOf: tasks)
            } catch {
                // Skip failed reads
            }
        }
        return allTasks
    }
}
