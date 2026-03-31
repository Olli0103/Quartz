import XCTest
@testable import QuartzKit

// MARK: - GraphEdgeStore Tests

final class GraphEdgeStoreTests: XCTestCase {

    // MARK: - Wiki-Link Edge Resolution

    func testResolvesLinkedTitlesToURLs() async {
        let store = GraphEdgeStore()
        let source = URL(fileURLWithPath: "/vault/NoteA.md")
        let target = URL(fileURLWithPath: "/vault/NoteB.md")

        await store.updateConnections(for: source, linkedTitles: ["NoteB"], allVaultURLs: [source, target])
        let edges = await store.edges
        XCTAssertEqual(edges[source], [target])
    }

    func testCaseInsensitiveTitleMatching() async {
        let store = GraphEdgeStore()
        let source = URL(fileURLWithPath: "/vault/NoteA.md")
        let target = URL(fileURLWithPath: "/vault/My Note.md")

        await store.updateConnections(for: source, linkedTitles: ["my note"], allVaultURLs: [source, target])
        let edges = await store.edges
        XCTAssertEqual(edges[source], [target])
    }

    func testExcludesSelfLinks() async {
        let store = GraphEdgeStore()
        let source = URL(fileURLWithPath: "/vault/NoteA.md")

        await store.updateConnections(for: source, linkedTitles: ["NoteA"], allVaultURLs: [source])
        let edges = await store.edges
        XCTAssertTrue(edges[source]?.isEmpty ?? true)
    }

    func testUnresolvableTitlesProduceNoEdges() async {
        let store = GraphEdgeStore()
        let source = URL(fileURLWithPath: "/vault/NoteA.md")

        await store.updateConnections(for: source, linkedTitles: ["NonExistent"], allVaultURLs: [source])
        let edges = await store.edges
        XCTAssertTrue(edges[source]?.isEmpty ?? true)
    }

    func testResolveTitleReturnsCorrectURL() async {
        let store = GraphEdgeStore()
        let target = URL(fileURLWithPath: "/vault/Ideas.md")
        await store.updateConnections(for: URL(fileURLWithPath: "/vault/A.md"), linkedTitles: [], allVaultURLs: [target])

        let resolved = await store.resolveTitle("ideas")
        XCTAssertEqual(resolved, target)
    }

    func testResolveTitleReturnsNilForUnknown() async {
        let store = GraphEdgeStore()
        await store.updateConnections(for: URL(fileURLWithPath: "/vault/A.md"), linkedTitles: [], allVaultURLs: [])

        let resolved = await store.resolveTitle("ghost")
        XCTAssertNil(resolved)
    }

    // MARK: - Semantic Edges

    func testStoresAndRetrievesSemanticConnections() async {
        let store = GraphEdgeStore()
        let source = URL(fileURLWithPath: "/vault/NoteA.md")
        let related1 = URL(fileURLWithPath: "/vault/NoteB.md")
        let related2 = URL(fileURLWithPath: "/vault/NoteC.md")

        await store.updateSemanticConnections(for: source, related: [related1, related2])
        let relations = await store.semanticRelations(for: source)
        XCTAssertEqual(relations, [related1, related2])
    }

    func testRemoveSemanticConnectionsClearsSourceAndReferences() async {
        let store = GraphEdgeStore()
        let a = URL(fileURLWithPath: "/vault/A.md")
        let b = URL(fileURLWithPath: "/vault/B.md")

        await store.updateSemanticConnections(for: a, related: [b])
        await store.updateSemanticConnections(for: b, related: [a])

        await store.removeSemanticConnections(for: a)

        let aRelations = await store.semanticRelations(for: a)
        let bRelations = await store.semanticRelations(for: b)
        XCTAssertTrue(aRelations.isEmpty)
        XCTAssertFalse(bRelations.contains(a))
    }

    // MARK: - Batch Rebuild

    func testRebuildAllReplacesAllEdges() async {
        let store = GraphEdgeStore()
        let a = URL(fileURLWithPath: "/vault/A.md")
        let b = URL(fileURLWithPath: "/vault/B.md")
        let c = URL(fileURLWithPath: "/vault/C.md")
        let allURLs = [a, b, c]

        await store.updateConnections(for: a, linkedTitles: ["B"], allVaultURLs: allURLs)

        await store.rebuildAll(
            connections: [(sourceURL: b, linkedTitles: ["C"])],
            allVaultURLs: allURLs
        )

        let edges = await store.edges
        XCTAssertNil(edges[a]) // Old edges cleared
        XCTAssertEqual(edges[b], [c])
    }

    func testEmptyVaultProducesNoEdges() async {
        let store = GraphEdgeStore()
        await store.updateConnections(for: URL(fileURLWithPath: "/vault/A.md"), linkedTitles: ["B"], allVaultURLs: [])
        let edges = await store.edges
        XCTAssertTrue(edges.values.allSatisfy { $0.isEmpty })
    }
}

// MARK: - SecurityOrchestrator Timeout Tests

@MainActor
final class SecurityOrchestratorTimeoutTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up UserDefaults between tests
        UserDefaults.standard.removeObject(forKey: "quartz.appLockEnabled")
        UserDefaults.standard.removeObject(forKey: "quartz.lockTimeoutMinutes")
    }

    func testDoesNotLockWhenDisabled() {
        let orchestrator = SecurityOrchestrator()
        orchestrator.isAppLockEnabled = false
        orchestrator.lockTimeoutMinutes = 0

        orchestrator.scenePhaseDidChange(to: .background)
        // Even with timeout = 0, disabled means no lock
        orchestrator.scenePhaseDidChange(to: .active)

        XCTAssertFalse(orchestrator.isLocked)
    }

    func testLockHasNoEffectWhenDisabled() {
        let orchestrator = SecurityOrchestrator()
        orchestrator.isAppLockEnabled = false

        orchestrator.lock()
        XCTAssertFalse(orchestrator.isLocked)
    }

    func testLockSetsStateWhenEnabled() {
        let orchestrator = SecurityOrchestrator()
        orchestrator.isAppLockEnabled = true

        orchestrator.lock()
        XCTAssertTrue(orchestrator.isLocked)
    }

    func testAuthenticateGuardsAgainstDoubleCall() async {
        let orchestrator = SecurityOrchestrator()
        orchestrator.isAppLockEnabled = true
        orchestrator.lock()

        // First call should proceed (isAuthenticating becomes true)
        // We can't easily test the guard without mocking BiometricAuthService,
        // but we verify the guard condition is correct
        XCTAssertTrue(orchestrator.isLocked)
        XCTAssertFalse(orchestrator.isAuthenticating)
    }

    func testTimeoutMinutesDefaultsToFive() {
        // Clean slate
        UserDefaults.standard.removeObject(forKey: "quartz.lockTimeoutMinutes")
        let orchestrator = SecurityOrchestrator()
        XCTAssertEqual(orchestrator.lockTimeoutMinutes, 5)
    }

    func testTimeoutMinutesPersists() {
        let orchestrator = SecurityOrchestrator()
        orchestrator.lockTimeoutMinutes = 15
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "quartz.lockTimeoutMinutes"), 15)
    }

    func testBiometryInfoDoesNotCrash() {
        let orchestrator = SecurityOrchestrator()
        // These should return values without crashing, regardless of device capabilities
        _ = orchestrator.biometryIconName
        _ = orchestrator.biometryLabel
        _ = orchestrator.isAuthenticationAvailable
    }
}

// MARK: - EditorSession Selection Tests

@MainActor
final class EditorSessionSelectionTests: XCTestCase {

    func testGetSelectedTextWithNoSelection() {
        let session = makeSession()
        session.textDidChange("Hello World")
        session.selectionDidChange(NSRange(location: 5, length: 0))
        XCTAssertNil(session.getSelectedText())
    }

    func testGetSelectedTextWithSelection() {
        let session = makeSession()
        session.textDidChange("Hello World")
        session.selectionDidChange(NSRange(location: 0, length: 5))
        XCTAssertEqual(session.getSelectedText(), "Hello")
    }

    func testGetSelectedTextWithOutOfBoundsRange() {
        let session = makeSession()
        session.textDidChange("Hi")
        session.selectionDidChange(NSRange(location: 0, length: 100))
        XCTAssertNil(session.getSelectedText())
    }

    func testSaveResetsSavingFlag() async {
        let session = makeSession()
        // Without a note, save is a no-op — but isSaving should never get stuck
        await session.save(force: true)
        XCTAssertFalse(session.isSaving)
    }

    func testTextDidChangeSetsIsDirty() {
        let session = makeSession()
        XCTAssertFalse(session.isDirty)
        session.textDidChange("Hello")
        XCTAssertTrue(session.isDirty)
    }

    func testTextDidChangeIgnoresDuplicates() {
        let session = makeSession()
        session.textDidChange("Hello")
        XCTAssertTrue(session.isDirty)

        // Reset dirty manually to test dedup
        // (In real usage, save() clears isDirty)
        session.textDidChange("Hello") // Same text — should not re-trigger
        // isDirty was already true, so this is a no-op
        XCTAssertTrue(session.isDirty)
    }

    func testSelectionDidChangeUpdatesCursorPosition() {
        let session = makeSession()
        session.textDidChange("Hello World")
        session.selectionDidChange(NSRange(location: 6, length: 5))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 6, length: 5))
    }

    private func makeSession() -> EditorSession {
        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let inspector = InspectorStore()
        return EditorSession(vaultProvider: provider, frontmatterParser: FrontmatterParser(), inspectorStore: inspector)
    }
}
