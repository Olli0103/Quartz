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

# Clean up heal category tracker from previous runs
rm -f /tmp/quartz_heal_categories.txt

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
fail() { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }

# ── Self-Healing: Failure Classification ─────────────────────────────
HEAL_CATEGORIES=""

classify_failures() {
    local output="$1"
    echo -e "${YELLOW}${BOLD}Failure Classification:${RESET}"
    echo "$output" | grep -E "failed after|Test Case.*failed" | while read -r line; do
        case "$line" in
            *Editor*|*AST*|*Highlight*|*Cursor*|*IME*|*WritingTools*)
                echo -e "  ${YELLOW}[EDITOR]${RESET} $line"
                echo "    → Check: EditorSession, MarkdownASTHighlighter, MarkdownTextView"
                echo "EDITOR" >> /tmp/quartz_heal_categories.txt ;;
            *Vault*|*Sync*|*Persist*|*Conflict*|*Bookmark*|*iCloud*|*Version*)
                echo -e "  ${YELLOW}[PERSISTENCE]${RESET} $line"
                echo "    → Check: VaultProvider, VaultAccessManager, VersionHistoryService" ;;
            *VoiceOver*|*Accessibility*|*DynamicType*|*Contrast*|*ReduceMotion*)
                echo -e "  ${YELLOW}[ACCESSIBILITY]${RESET} $line"
                echo "    → Check: Accessibility labels, Dynamic Type scaling, animation preferences"
                echo "ACCESSIBILITY" >> /tmp/quartz_heal_categories.txt ;;
            *Performance*|*Budget*|*Latency*|*Memory*)
                echo -e "  ${YELLOW}[PERFORMANCE]${RESET} $line"
                echo "    → Check: Parse timing, memory allocation, main thread budget"
                echo "PERFORMANCE" >> /tmp/quartz_heal_categories.txt ;;
            *Sidebar*|*Navigation*|*DragDrop*|*FileNode*)
                echo -e "  ${YELLOW}[NAVIGATION]${RESET} $line"
                echo "    → Check: SidebarViewModel, WorkspaceStore, NavigationSplitView" ;;
            *E2E*|*Flow*|*Integration*)
                echo -e "  ${YELLOW}[E2E]${RESET} $line"
                echo "    → Check: End-to-end flow, state transitions, cross-module interaction" ;;
            *UI*|*UITests*|*XCUITest*|*Screenshot*|*Launch*|*Smoke*)
                echo -e "  ${YELLOW}[UI_MATRIX]${RESET} $line"
                echo "    → Check: Mock vault loading, accessibility identifiers, simulator availability"
                echo "UI_MATRIX" >> /tmp/quartz_heal_categories.txt ;;
            *)
                echo -e "  ${YELLOW}[GENERAL]${RESET} $line"
                echo "    → Check: Test isolation, mock setup, async timing" ;;
        esac
    done
}

# Self-healing: invoke heal scripts for classified failure categories
run_self_healing() {
    if [ ! -f /tmp/quartz_heal_categories.txt ]; then
        return 0
    fi

    local categories
    categories=$(sort -u /tmp/quartz_heal_categories.txt)
    rm -f /tmp/quartz_heal_categories.txt

    echo -e "\n${BOLD}→ Running self-healing scripts...${RESET}"
    mkdir -p reports

    for cat in $categories; do
        case "$cat" in
            EDITOR)
                if [ -x scripts/heal_editor.sh ]; then
                    echo "  Running heal_editor.sh..."
                    bash scripts/heal_editor.sh "$PACKAGE_PATH" 2>&1 | tee -a reports/self_heal.log || true
                fi ;;
            ACCESSIBILITY)
                if [ -x scripts/heal_accessibility.sh ]; then
                    echo "  Running heal_accessibility.sh..."
                    bash scripts/heal_accessibility.sh "$PACKAGE_PATH" 2>&1 | tee -a reports/self_heal.log || true
                fi ;;
            PERFORMANCE)
                if [ -x scripts/heal_performance.sh ]; then
                    echo "  Running heal_performance.sh..."
                    bash scripts/heal_performance.sh "$PACKAGE_PATH" 2>&1 | tee -a reports/self_heal.log || true
                fi ;;
            UI_MATRIX)
                if [ -x scripts/heal_ui_matrix.sh ]; then
                    echo "  Running heal_ui_matrix.sh..."
                    bash scripts/heal_ui_matrix.sh 2>&1 | tee -a reports/self_heal.log || true
                fi ;;
        esac
    done

    echo -e "${GREEN}Self-healing complete — see reports/self_heal.log${RESET}"
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
P3_FAIL=$(echo "$P3_OUTPUT" | grep -cE "failed after|Test Case.*failed" || true)
echo "  Phase 3 suites passed: $P3_PASS"
echo "  Phase 3 tests failed: $P3_FAIL"
if [ "$P3_FAIL" -gt 0 ]; then
    classify_failures "$P3_OUTPUT"
    run_self_healing
    fail "Phase 3 test failures: $P3_FAIL"
fi
pass "Phase 3 tests all passed"

# ── Step 3: Full test suite ──────────────────────────────────────────
step "Running full test suite (Phase 1 + Phase 2 + Phase 3)"
FULL_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --parallel 2>&1 || true)
FULL_PASS=$(echo "$FULL_OUTPUT" | grep -c "passed" || true)
FULL_FAIL=$(echo "$FULL_OUTPUT" | grep -cE "failed after|Test Case.*failed" || true)
echo "  Total suites passed: $FULL_PASS"
echo "  Total tests failed: $FULL_FAIL"
if [ "$FULL_FAIL" -gt 0 ]; then
    classify_failures "$FULL_OUTPUT"
    run_self_healing
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

# ── Step 6: Platform matrix verification ──────────────────────────────
step "Verifying platform matrix"
# Platforms are only added after verified test execution (Step 6b)
PLATFORMS_TESTED="macOS"
PLATFORMS_DETECTED="macOS"
if command -v xcodebuild &>/dev/null; then
    echo "  xcodebuild available — checking simulator SDKs"
    if xcodebuild -showsdks 2>/dev/null | grep -q "iphonesimulator"; then
        PLATFORMS_DETECTED="$PLATFORMS_DETECTED,iOS_Simulator,iPadOS_Simulator"
    fi
else
    echo "  xcodebuild not available — SPM-only testing (macOS)"
    echo "  NOTE: Full ADA-grade platform matrix requires Xcode UI tests"
fi
pass "Platform detection: $PLATFORMS_DETECTED"

# ── Step 6b: UI Test Matrix ──────────────────────────────────────────
step "Running UI test matrix (xcodebuild)"
UI_PASS=0
UI_FAIL=0
UI_SKIP=0

if command -v xcodebuild &>/dev/null; then
    # macOS UI tests
    echo "  Running macOS UI tests..."
    MACOS_UI_OUTPUT=$(xcodebuild test -scheme Quartz \
        -destination 'platform=macOS' \
        -only-testing:QuartzUITests \
        -resultBundlePath /tmp/QuartzUITests_macOS.xcresult \
        2>&1 || true)
    echo "$MACOS_UI_OUTPUT" | tail -5
    if echo "$MACOS_UI_OUTPUT" | grep -q "** TEST SUCCEEDED **"; then
        UI_PASS=$((UI_PASS + 1))
        pass "  macOS UI tests passed"
    else
        UI_FAIL=$((UI_FAIL + 1))
        echo -e "  ${RED}macOS UI tests failed${RESET}"
        classify_failures "$MACOS_UI_OUTPUT"
    fi

    # iPhone UI tests (if simulator available)
    if xcrun simctl list devices available 2>/dev/null | grep -q "iPhone"; then
        IPHONE_SIM=$(xcrun simctl list devices available 2>/dev/null | grep "iPhone" | head -1 | sed 's/(.*//' | xargs)
        echo "  Running iPhone UI tests on: $IPHONE_SIM"
        IPHONE_UI_OUTPUT=$(xcodebuild test -scheme Quartz \
            -destination "platform=iOS Simulator,name=$IPHONE_SIM" \
            -only-testing:QuartzUITests \
            -resultBundlePath /tmp/QuartzUITests_iPhone.xcresult \
            2>&1 || true)
        echo "$IPHONE_UI_OUTPUT" | tail -5
        if echo "$IPHONE_UI_OUTPUT" | grep -q "** TEST SUCCEEDED **"; then
            UI_PASS=$((UI_PASS + 1))
            PLATFORMS_TESTED="$PLATFORMS_TESTED,iOS_Simulator"
            pass "  iPhone UI tests passed"
        else
            UI_FAIL=$((UI_FAIL + 1))
            echo -e "  ${RED}iPhone UI tests failed${RESET}"
            classify_failures "$IPHONE_UI_OUTPUT"
        fi
    else
        UI_SKIP=$((UI_SKIP + 1))
        echo "  iPhone simulator not available — skipped"
    fi

    # iPad UI tests (if simulator available)
    if xcrun simctl list devices available 2>/dev/null | grep -q "iPad"; then
        IPAD_SIM=$(xcrun simctl list devices available 2>/dev/null | grep "iPad" | head -1 | sed 's/(.*//' | xargs)
        echo "  Running iPad UI tests on: $IPAD_SIM"
        IPAD_UI_OUTPUT=$(xcodebuild test -scheme Quartz \
            -destination "platform=iOS Simulator,name=$IPAD_SIM" \
            -only-testing:QuartzUITests \
            -resultBundlePath /tmp/QuartzUITests_iPad.xcresult \
            2>&1 || true)
        echo "$IPAD_UI_OUTPUT" | tail -5
        if echo "$IPAD_UI_OUTPUT" | grep -q "** TEST SUCCEEDED **"; then
            UI_PASS=$((UI_PASS + 1))
            PLATFORMS_TESTED="$PLATFORMS_TESTED,iPadOS_Simulator"
            pass "  iPad UI tests passed"
        else
            UI_FAIL=$((UI_FAIL + 1))
            echo -e "  ${RED}iPad UI tests failed${RESET}"
            classify_failures "$IPAD_UI_OUTPUT"
        fi
    else
        UI_SKIP=$((UI_SKIP + 1))
        echo "  iPad simulator not available — skipped"
    fi

    echo "  UI matrix: $UI_PASS passed, $UI_FAIL failed, $UI_SKIP skipped"
    if [ "$UI_FAIL" -gt 0 ]; then
        run_self_healing
        fail "UI test matrix failures: $UI_FAIL"
    fi
    pass "UI test matrix: $UI_PASS platforms passed"
else
    echo "  xcodebuild not available — UI test matrix skipped"
    echo "  NOTE: Full UI test matrix requires Xcode"
    UI_SKIP=3
fi

# ── Step 7: Generate reports ──────────────────────────────────────────
step "Generating Phase 3 report"
mkdir -p reports

# Determine status from actual test results (Violation 5 fix: no hardcoded PASS)
if [ "$FULL_FAIL" -eq 0 ] && [ "$UI_FAIL" -eq 0 ] && [ "$UI_SKIP" -eq 0 ]; then
    PHASE3_STATUS="pass"
    SHIP_GATE="PASS"
elif [ "$FULL_FAIL" -eq 0 ] && [ "$UI_FAIL" -eq 0 ]; then
    PHASE3_STATUS="partial"
    SHIP_GATE="PARTIAL — $UI_SKIP UI platform(s) skipped"
elif [ "$FULL_FAIL" -eq 0 ]; then
    PHASE3_STATUS="partial"
    SHIP_GATE="PARTIAL — $UI_FAIL UI platform(s) failed"
else
    PHASE3_STATUS="fail"
    SHIP_GATE="FAIL"
fi

cat > reports/phase3_report.json <<REPORT_EOF
{
  "phase": 3,
  "status": "$PHASE3_STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tests": {
    "total": $TOTAL_TESTS,
    "phase3_specific": $P3_COUNT,
    "full_suite_failed": $FULL_FAIL,
    "full_suite_passed": $FULL_PASS
  },
  "ui_test_matrix": {
    "passed": $UI_PASS,
    "failed": $UI_FAIL,
    "skipped": $UI_SKIP
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
  "platforms_detected": "$PLATFORMS_DETECTED",
  "platforms_actually_tested": "$PLATFORMS_TESTED",
  "ship_gate": "$SHIP_GATE"
}
REPORT_EOF

cat > reports/platform_matrix.json <<MATRIX_EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "platforms_detected": "$(echo $PLATFORMS_DETECTED | tr ',' '", "')",
  "platforms_actually_tested": "$(echo $PLATFORMS_TESTED | tr ',' '", "')",
  "spm_tests": "macOS (arm64)",
  "xcodebuild_available": $(command -v xcodebuild &>/dev/null && echo true || echo false),
  "ui_test_matrix": {
    "passed": $UI_PASS,
    "failed": $UI_FAIL,
    "skipped": $UI_SKIP
  },
  "notes": "SPM tests cover data model and logic layers. UI smoke tests run via xcodebuild. Only platforms with verified test passes are listed in platforms_actually_tested."
}
MATRIX_EOF
pass "Reports written to reports/"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 3 CI completed — $SHIP_GATE${RESET}"
echo "  Total @Test annotations: $TOTAL_TESTS"
echo "  Phase 3 tests: $P3_COUNT"
echo "  Full suite failures: $FULL_FAIL"
echo "  UI matrix: $UI_PASS passed, $UI_FAIL failed, $UI_SKIP skipped"
echo "  Platforms actually tested: $PLATFORMS_TESTED"
if [ "$PHASE3_STATUS" = "fail" ]; then
    exit 1
fi
exit 0
