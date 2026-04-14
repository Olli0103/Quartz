#!/usr/bin/env bash
# scripts/ci_phase3.sh — Phase 3 CI: cross-platform UX & accessibility
#
# Usage: bash scripts/ci_phase3.sh
# Local iteration slices:
#   bash scripts/test_quartzkit_phase3.sh
#   bash scripts/test_ui_macos_smoke.sh
#   bash scripts/test_ui_iphone_matrix.sh
#   bash scripts/test_ui_ipad_matrix.sh
# Exit code: 0 = success, 1 = failure
set -euo pipefail

PACKAGE_PATH="QuartzKit"
MACOS_RESULT_BUNDLE="/tmp/QuartzUITests_macOS.xcresult"
IPHONE_RESULT_BUNDLE="/tmp/QuartzUITests_iPhone.xcresult"
IPAD_RESULT_BUNDLE="/tmp/QuartzUITests_iPad.xcresult"
MACOS_UI_LOG="reports/ui_matrix_macos.log"
IPHONE_UI_LOG="reports/ui_matrix_ios.log"
IPAD_UI_LOG="reports/ui_matrix_ipados.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Clean up heal category tracker from previous runs
rm -f /tmp/quartz_heal_categories.txt
rm -rf "$MACOS_RESULT_BUNDLE" "$IPHONE_RESULT_BUNDLE" "$IPAD_RESULT_BUNDLE"

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
fail() { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }

reset_result_bundle() {
    local bundle_path="$1"
    if [ -e "$bundle_path" ]; then
        rm -rf "$bundle_path"
    fi
}

run_xcodebuild_to_log() {
    local log_path="$1"
    shift

    if "$@" >"$log_path" 2>&1; then
        tail -n 20 "$log_path"
        return 0
    fi

    tail -n 40 "$log_path"
    return 1
}

extract_simulator_id() {
    local line="$1"
    echo "$line" | sed -nE 's/.*\(([A-F0-9-]+)\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' | head -1 | xargs
}

stable_simulator_lines() {
    local family="$1"
    xcrun simctl list devices available 2>/dev/null | grep -F "$family" | grep -E '\((Booted|Shutdown)\)[[:space:]]*$' || true
}

available_simulator_id() {
    local preferred="$1"
    local family="$2"
    local line=""

    if [ -n "$preferred" ]; then
        line=$(xcrun simctl list devices available 2>/dev/null | grep -F "$preferred (" | grep -E '\((Booted|Shutdown)\)[[:space:]]*$' | head -1 || true)
    fi
    if [ -z "$line" ] && [ -n "$family" ]; then
        line=$(stable_simulator_lines "$family" | grep -E '\(Booted\)[[:space:]]*$' | head -1 || true)
    fi
    if [ -z "$line" ] && [ -n "$family" ]; then
        line=$(stable_simulator_lines "$family" | grep -E '\(Shutdown\)[[:space:]]*$' | head -1 || true)
    fi
    if [ -n "$line" ]; then
        extract_simulator_id "$line"
    fi
}

prepare_simulator() {
    local sim_id="$1"
    local bundle_id="${2:-olli.QuartzNotes}"

    xcrun simctl boot "$sim_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$sim_id" -b >/dev/null 2>&1 || return 1
    xcrun simctl terminate "$sim_id" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$sim_id" "$bundle_id" >/dev/null 2>&1 || true
}

prepared_simulator_id() {
    local preferred="$1"
    local family="$2"
    local primary_id=""
    local candidate_line=""
    local candidate_id=""

    primary_id=$(available_simulator_id "$preferred" "$family")
    if [ -n "$primary_id" ] && prepare_simulator "$primary_id"; then
        echo "$primary_id"
        return 0
    fi

    while IFS= read -r candidate_line; do
        candidate_id=$(extract_simulator_id "$candidate_line")
        if [ -z "$candidate_id" ] || [ "$candidate_id" = "$primary_id" ]; then
            continue
        fi
        if prepare_simulator "$candidate_id"; then
            echo "$candidate_id"
            return 0
        fi
    done < <(stable_simulator_lines "$family")

    return 1
}

terminate_conflicting_macos_app_processes() {
    local pid=""

    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        kill "$pid" >/dev/null 2>&1 || true
        sleep 1
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    done < <(ps -ax -o pid=,command= | grep '/Quartz.app/Contents/MacOS/Quartz' | awk '{print $1}' || true)
}

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

# ── Step 3: Lower-phase full-suite coverage ──────────────────────────
step "Reusing Phase 2 full-suite regression coverage"
FULL_PASS=0
FULL_FAIL=0
echo "  Phase 2 regression gate already executed the package-wide suite"
pass "Inherited lower-phase full-suite coverage"

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

# ── Step 5: Total @Test inventory ───────────────────────────────────
step "Recording total @Test inventory"
TOTAL_TESTS=$(grep -r "@Test" "$PACKAGE_PATH/Tests/" --include="*.swift" | wc -l | tr -d ' ')
echo "  Total @Test annotations: $TOTAL_TESTS"
pass "Total @Test inventory recorded: $TOTAL_TESTS"

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

# ── Step 6a: Cross-platform compilation gate ─────────────────────────
# Proves the code compiles for all target platforms (iOS, iPadOS, macOS).
# This is critical when simulators may not be available for test execution.
step "Cross-platform compilation gate (build-for-testing)"
BUILD_GATE_PASS=0
BUILD_GATE_FAIL=0

if command -v xcodebuild &>/dev/null; then
    # macOS build — already verified by SPM tests above, but compile UI target too
    echo "  Building for macOS..."
    if xcodebuild build -scheme Quartz -destination 'platform=macOS' -quiet 2>&1 | tail -3; then
        BUILD_GATE_PASS=$((BUILD_GATE_PASS + 1))
        pass "  macOS build succeeded"
    else
        BUILD_GATE_FAIL=$((BUILD_GATE_FAIL + 1))
        echo -e "  ${RED}macOS build failed${RESET}"
    fi

    # iOS build (compilation only — does not require a booted simulator)
    if xcodebuild -showsdks 2>/dev/null | grep -q "iphonesimulator"; then
        echo "  Building for iOS Simulator..."
        # Use generic destination — compiles without needing a specific simulator
        if xcodebuild build -scheme Quartz \
            -destination 'generic/platform=iOS Simulator' \
            -quiet 2>&1 | tail -3; then
            BUILD_GATE_PASS=$((BUILD_GATE_PASS + 1))
            pass "  iOS Simulator build succeeded (compilation verified)"
        else
            BUILD_GATE_FAIL=$((BUILD_GATE_FAIL + 1))
            echo -e "  ${RED}iOS Simulator build failed${RESET}"
        fi
    else
        echo "  iOS Simulator SDK not installed — compilation gate skipped"
    fi

    echo "  Compilation gate: $BUILD_GATE_PASS passed, $BUILD_GATE_FAIL failed"
    if [ "$BUILD_GATE_FAIL" -gt 0 ]; then
        fail "Cross-platform compilation gate failed — code does not compile on all platforms"
    fi
    pass "Cross-platform compilation gate: $BUILD_GATE_PASS platforms"
else
    echo "  xcodebuild not available — compilation gate skipped (SPM macOS only)"
fi

# ── Step 6b: UI Test Matrix ──────────────────────────────────────────
step "Running UI test matrix (xcodebuild)"
UI_PASS=0
UI_FAIL=0
UI_SKIP=0

if command -v xcodebuild &>/dev/null; then
    # macOS UI tests
    echo "  Running macOS UI tests..."
    terminate_conflicting_macos_app_processes
    reset_result_bundle "$MACOS_RESULT_BUNDLE"
    if run_xcodebuild_to_log "$MACOS_UI_LOG" \
        xcodebuild test -scheme Quartz \
            -parallel-testing-enabled NO \
            -destination 'platform=macOS' \
            -only-testing:QuartzUITests/macOSSmokeUITests \
            -resultBundlePath "$MACOS_RESULT_BUNDLE"; then
        UI_PASS=$((UI_PASS + 1))
        pass "  macOS UI tests passed"
    else
        UI_FAIL=$((UI_FAIL + 1))
        echo -e "  ${RED}macOS UI tests failed${RESET}"
        classify_failures "$(cat "$MACOS_UI_LOG")"
    fi

    # iPhone UI tests (if simulator available)
    if xcrun simctl list devices available 2>/dev/null | grep -q "iPhone"; then
        IPHONE_SIM_ID=$(prepared_simulator_id "iPhone 16 Pro" "iPhone" || true)
        if [ -z "$IPHONE_SIM_ID" ]; then
            UI_FAIL=$((UI_FAIL + 1))
            echo -e "  ${RED}iPhone UI tests failed${RESET}"
            echo "  No stable iPhone simulator was ready for UI testing"
        else
            echo "  Running iPhone UI tests on simulator id: $IPHONE_SIM_ID"
            reset_result_bundle "$IPHONE_RESULT_BUNDLE"
            if run_xcodebuild_to_log "$IPHONE_UI_LOG" \
                xcodebuild test -scheme Quartz \
                    -parallel-testing-enabled NO \
                    -destination "platform=iOS Simulator,id=$IPHONE_SIM_ID" \
                    -only-testing:QuartzUITests/WelcomeScreenTests \
                    -only-testing:QuartzUITests/OnboardingFlowTests \
                    -only-testing:QuartzUITests/AccessibilityUITests \
                    -only-testing:QuartzUITests/PerformanceUITests \
                    -only-testing:QuartzUITests/iOSPhoneSmokeUITests; then
                UI_PASS=$((UI_PASS + 1))
                PLATFORMS_TESTED="$PLATFORMS_TESTED,iOS_Simulator"
                pass "  iPhone UI tests passed"
            else
                UI_FAIL=$((UI_FAIL + 1))
                echo -e "  ${RED}iPhone UI tests failed${RESET}"
                classify_failures "$(cat "$IPHONE_UI_LOG")"
            fi
        fi
    else
        UI_SKIP=$((UI_SKIP + 1))
        echo "  iPhone simulator not available — skipped"
    fi

    # iPad UI tests (if simulator available)
    if xcrun simctl list devices available 2>/dev/null | grep -q "iPad"; then
        IPAD_SIM_ID=$(prepared_simulator_id "iPad Pro 13-inch (M5)" "iPad" || true)
        if [ -z "$IPAD_SIM_ID" ]; then
            UI_FAIL=$((UI_FAIL + 1))
            echo -e "  ${RED}iPad UI tests failed${RESET}"
            echo "  No stable iPad simulator was ready for UI testing"
        else
            echo "  Running iPad UI tests on simulator id: $IPAD_SIM_ID"
            reset_result_bundle "$IPAD_RESULT_BUNDLE"
            if run_xcodebuild_to_log "$IPAD_UI_LOG" \
                xcodebuild test -scheme Quartz \
                    -parallel-testing-enabled NO \
                    -destination "platform=iOS Simulator,id=$IPAD_SIM_ID" \
                    -only-testing:QuartzUITests/iPadSmokeUITests; then
                UI_PASS=$((UI_PASS + 1))
                PLATFORMS_TESTED="$PLATFORMS_TESTED,iPadOS_Simulator"
                pass "  iPad UI tests passed"
            else
                UI_FAIL=$((UI_FAIL + 1))
                echo -e "  ${RED}iPad UI tests failed${RESET}"
                classify_failures "$(cat "$IPAD_UI_LOG")"
            fi
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
NONISOLATED_UNSAFE_COUNT=$(rg -o 'nonisolated\(unsafe\)' "$PACKAGE_PATH/Sources/QuartzKit" 2>/dev/null | wc -l | tr -d ' ')

# Determine status from actual test results
# PASS requires: zero test failures, zero build failures, AND zero UI skips.
# All three platforms (macOS, iOS, iPadOS) must have runtime test results.
# Compilation-only is NOT sufficient — skipped runtimes hard-fail the gate.
if [ "$FULL_FAIL" -eq 0 ] && [ "$UI_FAIL" -eq 0 ] && [ "$BUILD_GATE_FAIL" -eq 0 ] && [ "$UI_SKIP" -eq 0 ]; then
    PHASE3_STATUS="pass"
    SHIP_GATE="PASS — all platforms tested and compiled"
elif [ "$FULL_FAIL" -eq 0 ] && [ "$UI_FAIL" -eq 0 ] && [ "$BUILD_GATE_FAIL" -eq 0 ]; then
    PHASE3_STATUS="fail"
    SHIP_GATE="FAIL — $UI_SKIP UI runtime(s) skipped; all platforms must be tested"
elif [ "$FULL_FAIL" -eq 0 ] && [ "$BUILD_GATE_FAIL" -eq 0 ]; then
    PHASE3_STATUS="fail"
    SHIP_GATE="FAIL — $UI_FAIL UI platform(s) failed"
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
  "compilation_gate": {
    "passed": $BUILD_GATE_PASS,
    "failed": $BUILD_GATE_FAIL,
    "note": "Proves code compiles for all target platforms (macOS + iOS Simulator) even when runtime simulators are unavailable"
  },
  "ui_test_matrix": {
    "passed": $UI_PASS,
    "failed": $UI_FAIL,
    "skipped": $UI_SKIP
  },
  "concurrency_tests": {
    "nonisolated_unsafe_count": $NONISOLATED_UNSAFE_COUNT
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
    "E2EAppearanceFlowTests",
    "TextKit2GateTests",
    "EditorPerformanceBudgetTests"
  ],
  "platforms_detected": "$PLATFORMS_DETECTED",
  "platforms_compilation_verified": "$BUILD_GATE_PASS platform(s)",
  "platforms_actually_tested": "$PLATFORMS_TESTED",
  "ship_gate": "$SHIP_GATE"
}
REPORT_EOF

cat > reports/platform_matrix.json <<MATRIX_EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "platforms_detected": "$(echo $PLATFORMS_DETECTED | tr ',' '", "')",
  "platforms_compilation_verified": "$BUILD_GATE_PASS platform(s)",
  "platforms_actually_tested": "$(echo $PLATFORMS_TESTED | tr ',' '", "')",
  "spm_tests": "macOS (arm64)",
  "xcodebuild_available": $(command -v xcodebuild &>/dev/null && echo true || echo false),
  "compilation_gate": {
    "passed": $BUILD_GATE_PASS,
    "failed": $BUILD_GATE_FAIL
  },
  "ui_test_matrix": {
    "passed": $UI_PASS,
    "failed": $UI_FAIL,
    "skipped": $UI_SKIP
  },
  "textkit2_gate_test": "TextKit2GateTests — verifies NSTextLayoutManager pipeline on both #if os(iOS) and #if os(macOS) paths",
  "notes": "Compilation gate proves code builds for all target platforms. SPM tests cover data model and logic layers. UI smoke tests run via xcodebuild. TextKit2GateTests prove no legacy TextKit 1 fallback on any platform."
}
MATRIX_EOF
pass "Reports written to reports/"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 3 CI completed — $SHIP_GATE${RESET}"
echo "  Total @Test annotations: $TOTAL_TESTS"
echo "  Phase 3 tests: $P3_COUNT"
echo "  Full suite failures: $FULL_FAIL"
echo "  Compilation gate: $BUILD_GATE_PASS passed, $BUILD_GATE_FAIL failed"
echo "  UI matrix: $UI_PASS passed, $UI_FAIL failed, $UI_SKIP skipped"
echo "  Platforms actually tested: $PLATFORMS_TESTED"
if [ "$PHASE3_STATUS" = "pass" ]; then
    exit 0
fi
exit 1
