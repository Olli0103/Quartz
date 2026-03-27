# Test Coverage Analysis for Quartz

**Date**: 2026-03-24
**Analyzed by**: Claude Code

---

## 1. Test Organization

### Test Locations

| Location | Purpose | Framework |
|----------|---------|-----------|
| `QuartzKit/Tests/QuartzKitTests/` | Unit tests for QuartzKit package | Swift Testing (`@Test`, `@Suite`) + XCTest |
| `QuartzTests/` | App-level integration tests | Swift Testing (`@Test`, `@Suite`) |
| `QuartzUITests/` | UI automation tests | XCTest (`XCUIApplication`) |

### Test Targets

1. **QuartzKitTests** (32 test files)
   - Primary unit test target for the QuartzKit Swift Package
   - Uses Swift Testing framework (modern `@Test` macro syntax)
   - Also includes XCTest for performance metrics

2. **QuartzTests** (2 test files)
   - App-level tests including `QuartzTests.swift` and `QuartzPerformanceTests.swift`
   - Tests ServiceContainer, AppearanceManager, FocusModeManager
   - Performance tests with XCTMetrics (CPU, Memory, Clock)

3. **QuartzUITests** (2 test files)
   - UI automation tests for onboarding, welcome screen
   - Accessibility tests (Dynamic Type, Reduce Motion, High Contrast)
   - Launch performance tests

### Test Infrastructure

**Build & Run**:
```bash
# Run QuartzKit package tests
cd QuartzKit && swift test

# Run app tests via Xcode
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Schemes**:
- `Quartz` - Main app scheme (includes QuartzTests, QuartzUITests)
- `QuartzKit` - Package scheme (includes QuartzKitTests)

---

## 2. Current Test Coverage

### Components WITH Tests (32 QuartzKit test files)

| Component | Test File | Test Count | Quality |
|-----------|-----------|------------|---------|
| **MarkdownListContinuation** | `MarkdownListContinuationTests.swift` | 27 tests | Excellent |
| **Editor Integration** | `EditorIntegrationTests.swift` | 26 tests | Good |
| **SidebarViewModel** | `ViewModelTests.swift` | 12 tests | Good |
| **NoteEditorViewModel** | `ViewModelTests.swift` | 10 tests | Good |
| **SidebarDragDrop** | `SidebarDragDropTests.swift` | 17 tests | Good |
| MarkdownFormatter | `MarkdownFormatterTests.swift` | 19 tests | Excellent |
| FrontmatterParser | `FrontmatterParserTests.swift` | 7 tests | Good |
| MarkdownRenderer | `MarkdownRendererTests.swift` | 12 tests | Good |
| TagExtractor | `TagExtractorTests.swift` | 12 tests | Good |
| WikiLinkExtractor | `WikiLinkExtractorTests.swift` | 13 tests | Good |
| FileWatcher | `FileWatcherTests.swift` | 4 tests | Basic |
| SearchIndex | `SearchIndexTests.swift` | 10 tests | Good |
| CloudSyncService | `CloudSyncServiceTests.swift` | 6 tests | Basic |
| BiometricAuthService | `BiometricAuthServiceTests.swift` | 4 tests | Basic |
| VectorEmbedding | `VectorEmbeddingBinaryTests.swift` | 6 tests | Good |

### Components WITHOUT Tests (Gaps)

| Component | File | Risk | Priority |
|-----------|------|------|----------|
| **MarkdownASTHighlighter** | `MarkdownASTHighlighter.swift` | HIGH | P0 |
| **MarkdownTextView** | `MarkdownTextView.swift` | HIGH | P0 |
| **MarkdownTextContentManager** | `MarkdownTextContentManager.swift` | HIGH | P1 |
| **SidebarView** | `SidebarView.swift` | MEDIUM | P1 |
| ContentView | `ContentView.swift` | MEDIUM | P2 |
| ContentViewModel | `ContentViewModel.swift` | MEDIUM | P2 |
| FileSystemVaultProvider | `FileSystemVaultProvider.swift` | MEDIUM | P2 |
| FolderManagementUseCase | `FolderManagementUseCase.swift` | MEDIUM | P2 |
| HeadingExtractor | `HeadingExtractor.swift` | LOW | P3 |

---

## 3. Recently Modified Components Analysis

Based on `git status`, these files were recently modified:

### Editor Components (MODIFIED)

| File | Has Tests? | Test Quality | Gap Analysis |
|------|------------|--------------|--------------|
| `MarkdownTextView.swift` | NO DIRECT | Indirect via EditorIntegration | Missing: TextKit 2 lifecycle, selection handling, IME |
| `MarkdownASTHighlighter.swift` | NO | Only performance tests | Missing: Span generation, range conversion, color themes |
| `NoteEditorViewModel.swift` | YES | Good | Covered: load, save, dirty state |

**Recommendation**: MarkdownASTHighlighter is a critical gap. It's tested indirectly via performance tests but has no unit tests for:
- `sourceRangeToNSRange()` conversion logic
- `HighlightSpan` generation for different markdown elements
- Background parsing behavior
- Version tracking for stale highlight rejection

### Sidebar Components (MODIFIED)

| File | Has Tests? | Test Quality | Gap Analysis |
|------|------------|--------------|--------------|
| `SidebarView.swift` | PARTIAL | Drag/drop logic tested | Missing: SwiftUI view behavior, navigation binding |
| `SidebarViewModel.swift` | YES | Good | Covered: loadTree, search, tags, create/delete |
| `ContentView.swift` | NO | - | Missing: NavigationSplitView selection, state restoration |
| `ContentViewModel.swift` | NO | - | Missing: All functionality |

**Recommendation**: SidebarViewModel has good coverage. SidebarView logic is tested via `SidebarDragDropTests.swift` which extracts validation logic into pure functions - this is good practice.

### Other Modified Files

| File | Has Tests? | Notes |
|------|------------|-------|
| `FileSystemVaultProvider.swift` | NO | Only MockVaultProvider is tested |
| `HeadingExtractor.swift` | NO | Only performance test exists |
| `FolderManagementUseCase.swift` | NO | No tests |
| `Localizable.xcstrings` | N/A | Localization file |

---

## 4. Test Quality Assessment

### Strengths

1. **Modern Testing Framework**: Uses Swift Testing (`@Test`, `@Suite`) which is Apple's recommended approach
2. **Proper Test Isolation**: Tests use `MockVaultProvider` and temporary directories
3. **Behavior-Focused**: Tests focus on observable behavior, not implementation details
4. **Performance Testing**: XCTMetrics used for CPU, memory, timing measurements
5. **Edge Case Coverage**: Tests include Unicode, emoji, edge cases
6. **UI Tests**: Accessibility tests verify Dynamic Type, Reduce Motion support

### Weaknesses

1. **No Tests for TextKit 2 Components**: The core editor stack (MarkdownTextContentManager, highlighting) lacks unit tests
2. **Indirect View Testing**: SwiftUI views tested indirectly via ViewModels
3. **Missing Integration Tests**: No tests for full note editing flow (open -> edit -> save -> reload)
4. **No Snapshot Tests**: Visual regression testing not present
5. **Limited Error Path Testing**: Happy path focus, less coverage of error scenarios

### Apple Testing Best Practices Compliance

| Practice | Status | Notes |
|----------|--------|-------|
| Swift Testing framework | YES | Using `@Test`, `@Suite` |
| Async test support | YES | `async` tests used properly |
| Test isolation | YES | MockVaultProvider, temp directories |
| Descriptive test names | YES | `@Test("description")` syntax |
| XCTMetrics for perf | YES | Clock, CPU, Memory metrics |
| UI test accessibility | YES | Dynamic Type, Reduce Motion tested |
| `@MainActor` annotation | YES | Used where needed |

---

## 5. Specific Gap Analysis for Modified Components

### MarkdownListContinuation (Heavily Modified)

**Coverage**: EXCELLENT

Tests in `MarkdownListContinuationTests.swift` cover:
- Bullet continuation (dash, asterisk, plus)
- Numbered list incrementation
- Checkbox continuation
- Empty line exit behavior
- Indentation preservation
- Blockquote continuation
- Cursor position in middle of line
- Multi-line context
- Unicode and emoji content

**Missing**:
- Tab-based indentation edge cases
- Very long list sequences
- Mixed list types in same document

### MarkdownTextView (Heavily Modified)

**Coverage**: POOR

No direct tests. EditorIntegrationTests tests the `MarkdownListContinuation` engine, not the UITextView/NSTextView integration.

**Missing Tests**:
- `textView(_:shouldChangeTextIn:replacementText:)` behavior
- Selection preservation during highlighting
- Typing attributes preservation
- IME/dictation compatibility
- Undo/redo integration
- TextKit 2 content manager lifecycle

### SidebarView/SidebarViewModel (Modified)

**Coverage**: GOOD

`ViewModelTests.swift` covers:
- loadTree populates fileTree
- searchText filtering
- Tag filtering and collection
- Create/delete note operations

`SidebarDragDropTests.swift` covers:
- Self-drop rejection
- Circular dependency detection
- Batch validation
- Destination URL generation

**Missing Tests**:
- Expand/collapse state persistence
- Sort order changes
- Recent files tracking
- Keyboard navigation (macOS)

### MarkdownASTHighlighter (Modified)

**Coverage**: POOR

Only performance tests in `QuartzPerformanceTests.swift`:
```swift
func testMarkdownParsingPerformance()
func testHighlighterMemoryStability()
```

**Missing Tests**:
- `sourceRangeToNSRange()` for various source locations
- `HighlightSpan` generation for headings, bold, italic, code, links
- Color theme application
- Background parsing cancellation
- Debounce behavior
- Version tracking

---

## 6. Recommended Test Improvements

### Priority 0 (Immediate - Before Next Release)

1. **Add MarkdownASTHighlighter Unit Tests**
   ```swift
   @Suite("MarkdownASTHighlighter")
   struct MarkdownASTHighlighterTests {
       @Test("sourceRangeToNSRange converts correctly")
       @Test("Heading spans have correct font scale")
       @Test("Bold spans have correct traits")
       @Test("Code spans use monospaced font")
       @Test("Parsing is debounced")
       @Test("Stale highlights are rejected")
   }
   ```

2. **Add TextKit 2 Integration Tests**
   ```swift
   @Suite("MarkdownTextContentManager")
   struct MarkdownTextContentManagerTests {
       @Test("performMarkdownEdit batches attribute changes")
       @Test("Selection is preserved during highlight update")
       @Test("Typing attributes are preserved after highlighting")
   }
   ```

### Priority 1 (Soon)

3. **Add ContentViewModel Tests**
   ```swift
   @Suite("ContentViewModel")
   struct ContentViewModelTests {
       @Test("State restoration on relaunch")
       @Test("Selection binding syncs with sidebar")
       @Test("Dashboard toggle persists")
   }
   ```

4. **Add FileSystemVaultProvider Tests**
   - File watching behavior
   - Concurrent read/write handling
   - Error recovery

### Priority 2 (Next Sprint)

5. **Add Snapshot Tests for Key Views**
   - SidebarView in different states
   - Editor with various markdown content
   - Dashboard layout

6. **Add Integration Test Suite**
   - Full note lifecycle: create -> edit -> save -> close -> reopen
   - Search and filter workflow
   - Drag-drop reorganization

---

## 7. Test Infrastructure Recommendations

### Mock Infrastructure

The project has a good `MockVaultProvider` in `ViewModelTests.swift`. Consider:
- Moving to shared test utilities file
- Adding `MockHighlighter` for editor tests
- Adding `MockFileWatcher` for reactive tests

### Test Helpers to Add

```swift
// TestHelpers.swift
enum TestFixtures {
    static let simpleMarkdown = "# Title\n\nParagraph"
    static let complexMarkdown = """
    # Heading 1
    ## Heading 2
    - [ ] Task
    - [x] Done
    **bold** *italic* `code`
    """
}

extension XCTestCase {
    func makeTempVault() throws -> URL { ... }
    func cleanupTempVault(_ url: URL) { ... }
}
```

### CI Integration

Currently no visible CI configuration. Recommend:
- GitHub Actions workflow for `swift test` on PRs
- Xcode Cloud for UI tests on device
- Coverage reporting (Codecov/Coveralls)

---

## 8. Summary

### Overall Test Health: GOOD (with gaps)

| Category | Score | Notes |
|----------|-------|-------|
| Unit Test Coverage | 7/10 | Good for models/ViewModels, poor for editor/highlighting |
| Test Quality | 8/10 | Modern framework, proper isolation |
| Performance Testing | 8/10 | XCTMetrics used appropriately |
| UI Testing | 6/10 | Basic flows covered, no visual regression |
| Integration Testing | 4/10 | Limited end-to-end coverage |

### Critical Gaps for Recently Modified Code

| Component | Gap Severity | Action Required |
|-----------|--------------|-----------------|
| MarkdownASTHighlighter | HIGH | Add comprehensive unit tests |
| MarkdownTextView | HIGH | Add TextKit 2 integration tests |
| ContentViewModel | MEDIUM | Add state management tests |

### Files to Prioritize for Testing

1. `/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift`
2. `/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextView.swift`
3. `/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextContentManager.swift`
4. `/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift`

---

## Appendix: Test File Inventory

### QuartzKit/Tests/QuartzKitTests/ (32 files)

```
BiometricAuthServiceTests.swift
CloudSyncServiceTests.swift
DomainModelTests.swift
EditorHardeningTests.swift
EditorIntegrationTests.swift
FileSystemHardeningTests.swift
FileWatcherTests.swift
FrontmatterParserTests.swift
IntelligenceAudioTests.swift
LiquidGlassHIGTests.swift
MarkdownFormatterTests.swift
MarkdownListContinuationTests.swift
MarkdownRendererTests.swift
Phase1OnboardingSecurityTests.swift
Phase2FileSystemTests.swift
Phase3EditorTests.swift
Phase4SidebarDashboardTests.swift
Phase5IntelligenceAudioTests.swift
Phase6SystemIntegrationTests.swift
Phase7LiquidGlassHIGTests.swift
Phase8ADAStoreKitTests.swift
QuartzKitTests.swift
SearchIndexTests.swift
SettingsSecurityTests.swift
SidebarDashboardTests.swift
SidebarDragDropTests.swift
StoreKitTests.swift
TagExtractorTests.swift
VectorEmbeddingBinaryTests.swift
ViewModelTests.swift
WikiLinkExtractorTests.swift
AccessibilityStoreKitTests.swift
```

### QuartzTests/ (2 files)

```
QuartzTests.swift
QuartzPerformanceTests.swift
```

### QuartzUITests/ (2 files)

```
QuartzUITests.swift
QuartzUITestsLaunchTests.swift
```
