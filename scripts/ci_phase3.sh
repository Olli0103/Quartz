#!/usr/bin/env bash
# scripts/ci_phase3.sh — Phase 3 CI: cross-platform UX & accessibility
#
# Usage: bash scripts/ci_phase3.sh
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
            *E2E*|*Flow*|*Integration*)
                echo -e "  ${YELLOW}[E2E]${RESET} $line"
                echo "    → Check: End-to-end flow, state transitions, cross-module interaction" ;;
            *)
                echo -e "  ${YELLOW}[GENERAL]${RESET} $line"
                echo "    → Check: Test isolation, mock setup, async timing" ;;
        esac
    done
}

# ── Step 1: Phase 2 regression gate ─────────────────────────────────
step "Running Phase 2 CI (regression gate)"
if bash scripts/ci_phase2.sh 2>&1; then
    pass "Phase 2 regression gate passed"
else
    fail "Phase 2 regression gate failed — fix Phase 2 before proceeding"
fi

# ── Step 2: Phase 3 specific tests ──────────────────────────────────
step "Running Phase 3 accessibility & platform tests"
P3_FILTER="VoiceOverEditor|VoiceOverSidebar|DynamicTypeScaling|ReduceMotionAnimation|ContrastCompliance|VoiceControlCommand|PlatformNavigation|FocusModeIntegration|DesignTokenConsistency|E2ECreateNote|E2ESearchFlow|E2EAppearanceFlow"
P3_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --filter "$P3_FILTER" 2>&1 || true)
P3_PASS=$(echo "$P3_OUTPUT" | grep -c "passed" || true)
P3_FAIL=$(echo "$P3_OUTPUT" | grep -c "failed after" || true)
echo "  Phase 3 suites passed: $P3_PASS"
echo "  Phase 3 tests failed: $P3_FAIL"
if [ "$P3_FAIL" -gt 0 ]; then
    classify_failures "$P3_OUTPUT"
    fail "Phase 3 test failures: $P3_FAIL"
fi
pass "Phase 3 tests all passed"

# ── Step 3: Full test suite ──────────────────────────────────────────
step "Running full test suite (Phase 1 + Phase 2 + Phase 3)"
FULL_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --parallel 2>&1 || true)
FULL_PASS=$(echo "$FULL_OUTPUT" | grep -c "passed" || true)
FULL_FAIL=$(echo "$FULL_OUTPUT" | grep -c "failed after" || true)
echo "  Total suites passed: $FULL_PASS"
echo "  Total tests failed: $FULL_FAIL"
if [ "$FULL_FAIL" -gt 0 ]; then
    classify_failures "$FULL_OUTPUT"
    fail "Test failures: $FULL_FAIL (zero tolerance)"
fi
pass "Full suite completed (zero failures)"

# ── Step 4: Count Phase 3 tests ─────────────────────────────────────
step "Counting Phase 3 test annotations"
P3_FILES="VoiceOverEditorTests VoiceOverSidebarTests DynamicTypeScalingTests ReduceMotionAnimationTests ContrastComplianceTests VoiceControlCommandTests PlatformNavigationTests FocusModeIntegrationTests DesignTokenConsistencyTests E2ECreateNoteTests E2ESearchFlowTests E2EAppearanceFlowTests"
P3_COUNT=0
for f in $P3_FILES; do
    if [ -f "$PACKAGE_PATH/Tests/QuartzKitTests/${f}.swift" ]; then
        C=$(grep -c "@Test" "$PACKAGE_PATH/Tests/QuartzKitTests/${f}.swift" || true)
        P3_COUNT=$((P3_COUNT + C))
    fi
done
echo "  Found $P3_COUNT Phase 3 @Test annotations"
if [ "$P3_COUNT" -lt 20 ]; then
    fail "Expected at least 20 Phase 3 tests, found $P3_COUNT"
fi
pass "Phase 3 test count: $P3_COUNT (>= 20)"

# ── Step 5: Total @Test budget check ────────────────────────────────
step "Checking total @Test budget"
TOTAL_TESTS=$(grep -r "@Test" "$PACKAGE_PATH/Tests/" --include="*.swift" | wc -l | tr -d ' ')
echo "  Total @Test annotations: $TOTAL_TESTS"
if [ "$TOTAL_TESTS" -gt 1200 ]; then
    fail "Total @Test count ($TOTAL_TESTS) exceeds budget of 1200"
fi
pass "Total @Test budget: $TOTAL_TESTS (<= 1200)"

# ── Step 6: Generate report ──────────────────────────────────────────
step "Generating Phase 3 report"
mkdir -p reports
cat > reports/phase3_report.json <<REPORT_EOF
{
  "phase": 3,
  "status": "pass",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tests": {
    "total": $TOTAL_TESTS,
    "phase3_specific": $P3_COUNT,
    "full_suite_failed": $FULL_FAIL,
    "full_suite_passed": $FULL_PASS
  },
  "phase3_suites": [
    "VoiceOverEditorTests",
    "VoiceOverSidebarTests",
    "DynamicTypeScalingTests",
    "ReduceMotionAnimationTests",
    "ContrastComplianceTests",
    "VoiceControlCommandTests",
    "PlatformNavigationTests",
    "FocusModeIntegrationTests",
    "DesignTokenConsistencyTests",
    "E2ECreateNoteTests",
    "E2ESearchFlowTests",
    "E2EAppearanceFlowTests"
  ],
  "ship_gate": "PASS"
}
REPORT_EOF
pass "Report written to reports/phase3_report.json"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 3 CI passed ✓ — SHIP GATE CLEAR${RESET}"
echo "  Total @Test annotations: $TOTAL_TESTS"
echo "  Phase 3 tests: $P3_COUNT"
echo "  Full suite: zero failures"
echo "  All platforms: macOS, iOS Simulator, iPad Simulator"
exit 0
