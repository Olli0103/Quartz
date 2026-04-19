import Foundation
import XCTest
@testable import QuartzKit

final class KnowledgeGraphLifecycleTests: XCTestCase {

    @MainActor
    func testSidebarRenameInvalidatesExplicitRelationships() async throws {
        let fixture = try TestVaultFixture.make(name: "kg3-rename")
        defer { fixture.teardown() }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(fixture.config)

        try await waitUntil("initial explicit relationships hydrate") {
            await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
        }

        viewModel.openNote(at: fixture.sourceURL)
        try await waitUntil("source note opens with outgoing link") {
            viewModel.editorSession?.note?.fileURL == CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL)
                && viewModel.inspectorStore.outgoingLinks.first?.noteURL == CanonicalNoteIdentity.canonicalFileURL(for: fixture.targetURL)
        }

        let renamedURL = fixture.rootURL.appending(path: "Renamed Target.md")
        let sidebar = try XCTUnwrap(viewModel.sidebarViewModel)
        await sidebar.rename(at: fixture.targetURL, to: "Renamed Target")

        try await waitUntil("rename invalidates stale outgoing/backlink state") {
            let oldBacklinks = await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
            let newBacklinks = await viewModel.graphEdgeStore.backlinks(for: renamedURL)
            return viewModel.inspectorStore.outgoingLinks.isEmpty
                && oldBacklinks.isEmpty
                && newBacklinks.isEmpty
        }
    }

    @MainActor
    func testSidebarMoveRepairsExplicitRelationships() async throws {
        let fixture = try TestVaultFixture.make(name: "kg3-sidebar-move")
        defer { fixture.teardown() }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(fixture.config)

        try await waitUntil("initial backlinks hydrate") {
            await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
        }

        viewModel.openNote(at: fixture.sourceURL)
        try await waitUntil("source note opens") {
            viewModel.inspectorStore.outgoingLinks.first?.noteURL == CanonicalNoteIdentity.canonicalFileURL(for: fixture.targetURL)
        }

        let sidebar = try XCTUnwrap(viewModel.sidebarViewModel)
        let movedURL = fixture.archiveURL.appending(path: fixture.targetURL.lastPathComponent)
        let moved = await sidebar.move(at: fixture.targetURL, to: fixture.archiveURL)
        XCTAssertTrue(moved)

        try await waitUntil("move repairs outgoing links and backlinks") {
            let movedBacklinks = await viewModel.graphEdgeStore.backlinks(for: movedURL)
            let oldBacklinks = await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
            return viewModel.inspectorStore.outgoingLinks.first?.noteURL == CanonicalNoteIdentity.canonicalFileURL(for: movedURL)
                && movedBacklinks.contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
                && oldBacklinks.isEmpty
        }
    }

    @MainActor
    func testOpenNoteFilePresenterMoveRepairsExplicitRelationships() async throws {
        let fixture = try TestVaultFixture.make(name: "kg3-open-move")
        defer { fixture.teardown() }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(fixture.config)

        try await waitUntil("initial explicit relationships hydrate") {
            await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
        }

        viewModel.openNote(at: fixture.targetURL)
        try await waitUntil("target note opens") {
            viewModel.editorSession?.note?.fileURL == CanonicalNoteIdentity.canonicalFileURL(for: fixture.targetURL)
        }

        let movedURL = fixture.archiveURL.appending(path: fixture.targetURL.lastPathComponent)
        let presenter = NoteFilePresenter(url: fixture.targetURL)
        defer { presenter.invalidate() }

        try FileManager.default.moveItem(at: fixture.targetURL, to: movedURL)
        let session = try XCTUnwrap(viewModel.editorSession)
        session.filePresenter(presenter, didMoveFrom: fixture.targetURL, to: movedURL)

        try await waitUntil("file presenter move repairs backlinks and session identity") {
            let movedBacklinks = await viewModel.graphEdgeStore.backlinks(for: movedURL)
            let oldBacklinks = await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
            return session.note?.fileURL == CanonicalNoteIdentity.canonicalFileURL(for: movedURL)
                && movedBacklinks.contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
                && oldBacklinks.isEmpty
        }
    }

    @MainActor
    func testOpenNoteFilePresenterDeleteInvalidatesExplicitRelationships() async throws {
        let fixture = try TestVaultFixture.make(name: "kg3-open-delete")
        defer { fixture.teardown() }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(fixture.config)

        try await waitUntil("initial backlinks hydrate") {
            await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
        }

        viewModel.openNote(at: fixture.targetURL)
        try await waitUntil("target note opens") {
            viewModel.editorSession?.note?.fileURL == CanonicalNoteIdentity.canonicalFileURL(for: fixture.targetURL)
        }

        let presenter = NoteFilePresenter(url: fixture.targetURL)
        defer { presenter.invalidate() }

        try FileManager.default.removeItem(at: fixture.targetURL)
        let session = try XCTUnwrap(viewModel.editorSession)
        try await session.filePresenterWillDelete(presenter)

        try await waitUntil("delete invalidates stale explicit relationships") {
            (await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)).isEmpty
        }

        viewModel.openNote(at: fixture.sourceURL)
        try await waitUntil("source note outgoing links are invalidated after delete") {
            viewModel.inspectorStore.outgoingLinks.isEmpty
        }
    }

    @MainActor
    func testRelaunchRestoresExplicitRelationshipsWithoutGraphView() async throws {
        let fixture = try TestVaultFixture.make(name: "kg3-relaunch")
        defer { fixture.teardown() }

        let firstViewModel = makeContentViewModel()
        firstViewModel.loadVault(fixture.config)
        try await waitUntil("first launch hydrates explicit relationships") {
            await firstViewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
        }

        let relaunchedViewModel = makeContentViewModel()
        relaunchedViewModel.loadVault(fixture.config)
        try await waitUntil("relaunch hydrates explicit relationships without graph view") {
            await relaunchedViewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))
        }
    }

    @MainActor
    func testVaultLoadPersistsExplicitRelationshipsWithoutOpeningGraphView() async throws {
        let fixture = try TestVaultFixture.make(name: "kg4-persist")
        defer { fixture.teardown() }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(fixture.config)

        try await waitUntil("explicit relationships hydrate and persist") {
            let backlinksReady = await viewModel.graphEdgeStore.backlinks(for: fixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: fixture.sourceURL))

            let cache = GraphCache(vaultRoot: fixture.rootURL)
            let noteURLs = Self.collectNoteURLs(from: viewModel.sidebarViewModel?.fileTree ?? [])
            let fingerprint = cache.computeFingerprint(for: noteURLs)
            let snapshot = cache.loadExplicitRelationshipSnapshotIfValid(fingerprint: fingerprint)
            return backlinksReady && snapshot?.references.count == 1
        }
    }

    @MainActor
    func testVaultSwitchClearsStaleExplicitRelationships() async throws {
        let firstFixture = try TestVaultFixture.make(name: "kg3-vault-a")
        let secondFixture = try TestVaultFixture.make(name: "kg3-vault-b", linkBody: "This second vault does not contain explicit links.")
        defer {
            firstFixture.teardown()
            secondFixture.teardown()
        }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(firstFixture.config)
        try await waitUntil("first vault hydrates explicit relationships") {
            await viewModel.graphEdgeStore.backlinks(for: firstFixture.targetURL)
                .contains(CanonicalNoteIdentity.canonicalFileURL(for: firstFixture.sourceURL))
        }

        viewModel.loadVault(secondFixture.config)
        try await waitUntil("vault switch clears stale explicit state") {
            let oldBacklinks = await viewModel.graphEdgeStore.backlinks(for: firstFixture.targetURL)
            let allLinkedURLs = await viewModel.graphEdgeStore.allLinkedURLs
            return oldBacklinks.isEmpty && allLinkedURLs.isEmpty
        }
    }

    @MainActor
    private func makeContentViewModel() -> ContentViewModel {
        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        ServiceContainer.shared.reset()
        ServiceContainer.shared.bootstrap(vaultProvider: provider, frontmatterParser: parser)
        return ContentViewModel(appState: AppState())
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(10),
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for \(description)")
        throw CancellationError()
    }

    private static func collectNoteURLs(from nodes: [FileNode]) -> [URL] {
        var urls: [URL] = []
        for node in nodes {
            if node.isNote {
                urls.append(node.url)
            }
            if let children = node.children {
                urls.append(contentsOf: collectNoteURLs(from: children))
            }
        }
        return urls
    }
}

private struct TestVaultFixture {
    let rootURL: URL
    let archiveURL: URL
    let sourceURL: URL
    let targetURL: URL
    let config: VaultConfig

    static func make(name: String, linkBody: String = "See [[Target]] before launch.") throws -> TestVaultFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "Quartz-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let archiveURL = rootURL.appending(path: "Archive", directoryHint: .isDirectory)
        let sourceURL = rootURL.appending(path: "Source.md")
        let targetURL = rootURL.appending(path: "Target.md")

        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        try linkBody.write(to: sourceURL, atomically: true, encoding: .utf8)
        try "# Target\n".write(to: targetURL, atomically: true, encoding: .utf8)

        return TestVaultFixture(
            rootURL: rootURL,
            archiveURL: archiveURL,
            sourceURL: sourceURL,
            targetURL: targetURL,
            config: VaultConfig(name: name, rootURL: rootURL)
        )
    }

    @MainActor
    func teardown() {
        try? FileManager.default.removeItem(at: rootURL)
        ServiceContainer.shared.reset()
    }
}
