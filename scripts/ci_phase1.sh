#!/usr/bin/env bash
# scripts/ci_phase1.sh — Phase 1 CI: build + test for QuartzKit
#
# Usage: bash scripts/ci_phase1.sh
# Exit code: 0 = success, 1 = failure
set -euo pipefail

PACKAGE_PATH="QuartzKit"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
fail() { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }

# ── Self-Healing: Failure Classification ─────────────────────────────
classify_failures() {
    local output="$1"
    echo -e "${YELLOW}${BOLD}Failure Classification:${RESET}"
    echo "$output" | grep "failed after" | while read -r line; do
        case "$line" in
            *Editor*|*AST*|*Highlight*|*Cursor*|*IME*|*WritingTools*)
                echo -e "  ${YELLOW}[EDITOR]${RESET} $line"
                echo "    → Check: EditorSession, MarkdownASTHighlighter, MarkdownTextView" ;;
            *Vault*|*Sync*|*Persist*|*Conflict*|*Bookmark*|*iCloud*|*Version*)
                echo -e "  ${YELLOW}[PERSISTENCE]${RESET} $line"
                echo "    → Check: VaultProvider, VaultAccessManager, VersionHistoryService" ;;
            *VoiceOver*|*Accessibility*|*DynamicType*|*Contrast*|*ReduceMotion*)
                echo -e "  ${YELLOW}[ACCESSIBILITY]${RESET} $line"
                echo "    → Check: Accessibility labels, Dynamic Type scaling, animation preferences" ;;
            *Performance*|*Budget*|*Latency*|*Memory*)
                echo -e "  ${YELLOW}[PERFORMANCE]${RESET} $line"
                echo "    → Check: Parse timing, memory allocation, main thread budget" ;;
            *Sidebar*|*Navigation*|*DragDrop*|*FileNode*)
                echo -e "  ${YELLOW}[NAVIGATION]${RESET} $line"
                echo "    → Check: SidebarViewModel, WorkspaceStore, NavigationSplitView" ;;
            *)
                echo -e "  ${YELLOW}[GENERAL]${RESET} $line"
                echo "    → Check: Test isolation, mock setup, async timing" ;;
        esac
    done
}

# ── Step 1: Package build (macOS) ────────────────────────────────────
step "Building QuartzKit (macOS debug)"
if swift build --package-path "$PACKAGE_PATH" 2>&1; then
    pass "macOS package build succeeded"
else
    fail "macOS package build failed"
fi

# ── Step 2: Cross-platform app builds ────────────────────────────────
step "Building app target (cross-platform matrix)"

echo "  Building for macOS..."
if xcodebuild build -scheme Quartz -destination 'platform=macOS' -quiet 2>&1; then
    pass "macOS app build succeeded"
else
    fail "macOS app build failed"
fi

echo "  Building for iOS Simulator..."
if xcodebuild build -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1; then
    pass "iOS Simulator build succeeded"
else
    fail "iOS Simulator build failed"
fi

echo "  Building for iPad Simulator..."
if xcodebuild build -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -quiet 2>&1; then
    pass "iPad Simulator build succeeded"
else
    fail "iPad Simulator build failed"
fi

# ── Step 3: Run test suite ───────────────────────────────────────────
step "Running QuartzKit tests (parallel)"
TEST_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --parallel 2>&1 || true)
PASS_COUNT=$(echo "$TEST_OUTPUT" | grep -c "passed" || true)
FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -c "failed after" || true)
echo "  Suites passed: $PASS_COUNT"
echo "  Tests failed: $FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    classify_failures "$TEST_OUTPUT"
    fail "Test failures: $FAIL_COUNT (zero tolerance)"
fi
pass "Tests completed (zero failures)"

# ── Step 4: Count tests ─────────────────────────────────────────────
step "Counting test annotations"
TEST_COUNT=$(grep -r "@Test" "$PACKAGE_PATH/Tests/" --include="*.swift" | wc -l | tr -d ' ')
echo "  Found $TEST_COUNT @Test annotations"
if [ "$TEST_COUNT" -lt 100 ]; then
    fail "Expected at least 100 tests, found $TEST_COUNT"
fi
pass "Test count: $TEST_COUNT (>= 100)"

# ── Step 5: Check for concurrency warnings (ZERO TOLERANCE) ─────────
step "Checking for concurrency warnings"
BUILD_OUTPUT=$(swift build --package-path "$PACKAGE_PATH" 2>&1 || true)
CONCURRENCY_WARNINGS=$(echo "$BUILD_OUTPUT" | grep -c "Sendable\|data race\|actor-isolated" || true)
echo "  Concurrency-related diagnostics: $CONCURRENCY_WARNINGS"
if [ "$CONCURRENCY_WARNINGS" -gt 0 ]; then
    fail "Concurrency warnings detected: $CONCURRENCY_WARNINGS (zero tolerance)"
fi
pass "Concurrency check: 0 warnings"

# ── Step 6: Generate report ──────────────────────────────────────────
step "Generating Phase 1 report"
mkdir -p reports
cat > reports/phase1_report.json <<REPORT_EOF
{
  "phase": 1,
  "status": "pass",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tests": {
    "total": $TEST_COUNT,
    "failed": $FAIL_COUNT,
    "passed": $PASS_COUNT
  },
  "platforms": {
    "macOS": "built",
    "iOS_sim": "built",
    "iPad_sim": "built"
  },
  "concurrency_warnings": $CONCURRENCY_WARNINGS
}
REPORT_EOF
pass "Report written to reports/phase1_report.json"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 1 CI passed ✓${RESET}"
echo "  Tests: $TEST_COUNT (zero failures)"
echo "  Platforms: macOS, iOS Simulator, iPad Simulator"
echo "  Concurrency warnings: $CONCURRENCY_WARNINGS"
exit 0
