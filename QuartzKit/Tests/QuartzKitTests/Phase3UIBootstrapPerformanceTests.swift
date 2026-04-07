import XCTest
@testable import QuartzKit

/// Performance gate tests for the UI bootstrap path.
///
/// Uses `measure` with `XCTClockMetric` and `XCTMemoryMetric` to enforce
/// budgets on the critical launch sequence:
/// - VaultConfig creation + Sendable transfer
/// - AppState initialization
/// - WorkspaceStore route transitions
/// - MarkdownPreviewView rendering setup
///
/// Failure thresholds are set to catch regressions, not micro-optimize.
final class Phase3UIBootstrapPerformanceTests: XCTestCase {

    // MARK: - VaultConfig Bootstrap Performance

    @MainActor
    func testVaultConfigCreationPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<1000 {
                let config = VaultConfig(
                    name: "Perf Test Vault",
                    rootURL: URL(fileURLWithPath: "/tmp/perf-vault")
                )
                _ = config.name
            }
        }
    }

    // MARK: - AppState Initialization Performance

    @MainActor
    func testAppStateInitPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 {
                let state = AppState()
                _ = state.currentVault
            }
        }
    }

    // MARK: - WorkspaceStore Route Transition Performance

    @MainActor
    func testWorkspaceStoreRouteTransitionPerformance() {
        let store = WorkspaceStore()

        measure(metrics: [XCTClockMetric()]) {
            for i in 0..<1000 {
                let url = URL(fileURLWithPath: "/tmp/note-\(i).md")
                store.setRoute(.note(url))
            }
        }
    }

    @MainActor
    func testWorkspaceStoreRapidDashboardTogglePerformance() {
        let store = WorkspaceStore()

        measure(metrics: [XCTClockMetric()]) {
            for i in 0..<500 {
                let url = URL(fileURLWithPath: "/tmp/toggle-\(i).md")
                store.setRoute(.note(url))
                store.setRoute(.dashboard)
            }
        }
    }

    // MARK: - Full Bootstrap Sequence Performance

    @MainActor
    func testFullBootstrapSequencePerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Simulate the full bootstrap path:
            // 1. Create vault config (like UITestFixtureVault.create())
            let config = VaultConfig(
                name: "Bootstrap Perf",
                rootURL: URL(fileURLWithPath: "/tmp/bootstrap-perf")
            )

            // 2. Initialize app state and assign vault
            let state = AppState()
            state.currentVault = config

            // 3. Create workspace store and set initial route
            let store = WorkspaceStore()
            let noteURL = config.rootURL.appendingPathComponent("Welcome.md")
            store.setRoute(.note(noteURL))

            // Verify state is coherent
            XCTAssertEqual(state.currentVault?.name, "Bootstrap Perf")
            XCTAssertEqual(store.route, .note(noteURL))
        }
    }

    // MARK: - Memory Budget Enforcement

    @MainActor
    func testBootstrapMemoryBudget() {
        // Measure baseline memory, perform bootstrap, measure delta.
        // Budget: bootstrap should not allocate more than 5MB of resident memory.
        let beforeInfo = memoryFootprint()

        var states: [AppState] = []
        var stores: [WorkspaceStore] = []

        for i in 0..<50 {
            let config = VaultConfig(
                name: "Memory Test \(i)",
                rootURL: URL(fileURLWithPath: "/tmp/mem-\(i)")
            )
            let state = AppState()
            state.currentVault = config

            let store = WorkspaceStore()
            store.setRoute(.note(config.rootURL.appendingPathComponent("Note.md")))

            states.append(state)
            stores.append(store)
        }

        let afterInfo = memoryFootprint()
        let deltaBytes = afterInfo - beforeInfo
        let deltaMB = Double(deltaBytes) / (1024 * 1024)

        // 50 bootstrap cycles should stay under 10MB total
        XCTAssertLessThan(deltaMB, 10.0,
                          "50 bootstrap cycles used \(String(format: "%.1f", deltaMB))MB — budget is 10MB")

        // Keep references alive until after measurement
        _ = states.count
        _ = stores.count
    }

    // MARK: - FileNode Tree Construction Performance

    @MainActor
    func testFileNodeTreeConstructionPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            // Simulate building a vault tree with 200 notes in 10 folders
            var folders: [FileNode] = []
            for folderIdx in 0..<10 {
                var children: [FileNode] = []
                for noteIdx in 0..<20 {
                    children.append(FileNode(
                        name: "note-\(noteIdx).md",
                        url: URL(fileURLWithPath: "/tmp/vault/folder-\(folderIdx)/note-\(noteIdx).md"),
                        nodeType: .note,
                        children: nil
                    ))
                }
                folders.append(FileNode(
                    name: "folder-\(folderIdx)",
                    url: URL(fileURLWithPath: "/tmp/vault/folder-\(folderIdx)"),
                    nodeType: .folder,
                    children: children
                ))
            }

            XCTAssertEqual(folders.count, 10)
            XCTAssertEqual(folders.flatMap { $0.children ?? [] }.count, 200)
        }
    }

    // MARK: - Helpers

    /// Returns current resident memory in bytes using mach_task_basic_info.
    private func memoryFootprint() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
