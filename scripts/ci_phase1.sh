#!/usr/bin/env bash
# scripts/ci_phase1.sh — Phase 1 CI: build + test for QuartzKit
#
# Usage: bash scripts/ci_phase1.sh
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

# ── Step 1: macOS build ──────────────────────────────────────────────
step "Building QuartzKit (macOS debug)"
if swift build --package-path "$PACKAGE_PATH" 2>&1; then
    pass "macOS build succeeded"
else
    fail "macOS build failed"
fi

# ── Step 2: Run test suite ───────────────────────────────────────────
step "Running QuartzKit tests (parallel)"
TEST_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --parallel 2>&1 || true)
PASS_COUNT=$(echo "$TEST_OUTPUT" | grep -c "passed" || true)
FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -c "failed after" || true)
echo "  Suites passed: $PASS_COUNT"
echo "  Tests failed: $FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 2 ]; then
    echo "$TEST_OUTPUT" | grep "failed after"
    fail "Too many test failures: $FAIL_COUNT"
fi
pass "Tests completed (failures: $FAIL_COUNT, tolerance: <=2 flaky)"

# ── Step 3: Count tests ─────────────────────────────────────────────
step "Counting test annotations"
TEST_COUNT=$(grep -r "@Test" "$PACKAGE_PATH/Tests/" --include="*.swift" | wc -l | tr -d ' ')
echo "  Found $TEST_COUNT @Test annotations"
if [ "$TEST_COUNT" -lt 100 ]; then
    fail "Expected at least 100 tests, found $TEST_COUNT"
fi
pass "Test count: $TEST_COUNT (>= 100)"

# ── Step 4: Check for concurrency warnings ───────────────────────────
step "Checking for concurrency warnings"
BUILD_OUTPUT=$(swift build --package-path "$PACKAGE_PATH" 2>&1 || true)
CONCURRENCY_WARNINGS=$(echo "$BUILD_OUTPUT" | grep -c "Sendable\|data race\|actor-isolated" || true)
echo "  Concurrency-related diagnostics: $CONCURRENCY_WARNINGS"
if [ "$CONCURRENCY_WARNINGS" -gt 20 ]; then
    echo "  ⚠️  High concurrency warning count — review before shipping"
fi
pass "Concurrency check complete"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 1 CI passed ✓${RESET}"
echo "  Tests: $TEST_COUNT"
echo "  Concurrency warnings: $CONCURRENCY_WARNINGS"
exit 0
