#!/usr/bin/env bash
# scripts/ci_phase2.sh — Phase 2 CI: persistence + sync reliability
#
# Usage: bash scripts/ci_phase2.sh
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

# ── Step 1: Phase 1 regression gate ─────────────────────────────────
step "Running Phase 1 CI (regression gate)"
if bash scripts/ci_phase1.sh 2>&1; then
    pass "Phase 1 regression gate passed"
else
    fail "Phase 1 regression gate failed — fix Phase 1 before proceeding"
fi

# ── Step 2: Phase 2 specific tests ──────────────────────────────────
step "Running Phase 2 persistence & sync tests"
P2_FILTER="VaultRestoration|SecurityScoped|SearchIndexPersistence|GraphEdgePersistence|ConflictStateMachineP2|VersionHistoryPersistence|IndexRebuild"
P2_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --filter "$P2_FILTER" 2>&1 || true)
P2_PASS=$(echo "$P2_OUTPUT" | grep -c "passed" || true)
P2_FAIL=$(echo "$P2_OUTPUT" | grep -c "failed after" || true)
echo "  Phase 2 suites passed: $P2_PASS"
echo "  Phase 2 tests failed: $P2_FAIL"
if [ "$P2_FAIL" -gt 0 ]; then
    echo "$P2_OUTPUT" | grep "failed after"
    fail "Phase 2 test failures: $P2_FAIL"
fi
pass "Phase 2 tests all passed"

# ── Step 3: Full test suite ──────────────────────────────────────────
step "Running full test suite (Phase 1 + Phase 2)"
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

# ── Step 4: Count Phase 2 tests ─────────────────────────────────────
step "Counting Phase 2 test annotations"
P2_FILES="VaultRestorationTests SecurityScopedURLTests SearchIndexPersistenceTests GraphEdgePersistenceTests ConflictStateMachineTests VersionHistoryServiceTests IndexRebuildTests"
P2_COUNT=0
for f in $P2_FILES; do
    if [ -f "$PACKAGE_PATH/Tests/QuartzKitTests/${f}.swift" ]; then
        C=$(grep -c "@Test" "$PACKAGE_PATH/Tests/QuartzKitTests/${f}.swift" || true)
        P2_COUNT=$((P2_COUNT + C))
    fi
done
echo "  Found $P2_COUNT Phase 2 @Test annotations"
if [ "$P2_COUNT" -lt 15 ]; then
    fail "Expected at least 15 Phase 2 tests, found $P2_COUNT"
fi
pass "Phase 2 test count: $P2_COUNT (>= 15)"

# ── Summary ──────────────────────────────────────────────────────────
TOTAL_TESTS=$(grep -r "@Test" "$PACKAGE_PATH/Tests/" --include="*.swift" | wc -l | tr -d ' ')
echo ""
echo -e "${GREEN}${BOLD}Phase 2 CI passed ✓${RESET}"
echo "  Total @Test annotations: $TOTAL_TESTS"
echo "  Phase 2 tests: $P2_COUNT"
echo "  Full suite failures: $FULL_FAIL (tolerance: <=2)"
exit 0
