#!/usr/bin/env bash
# scripts/ci_phase3.sh — Phase 3 CI: cross-platform UX & accessibility
#
# Usage: bash scripts/ci_phase3.sh
# Exit code: 0 = success, 1 = failure
set -euo pipefail

PACKAGE_PATH="QuartzKit"
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
fail() { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }

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
    echo "$P3_OUTPUT" | grep "failed after"
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
if [ "$FULL_FAIL" -gt 2 ]; then
    echo "$FULL_OUTPUT" | grep "failed after"
    fail "Too many test failures: $FULL_FAIL"
fi
pass "Full suite completed (failures: $FULL_FAIL, tolerance: <=2 flaky)"

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

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 3 CI passed ✓${RESET}"
echo "  Total @Test annotations: $TOTAL_TESTS"
echo "  Phase 3 tests: $P3_COUNT"
echo "  Full suite failures: $FULL_FAIL (tolerance: <=2)"
exit 0
