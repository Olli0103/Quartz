#!/usr/bin/env bash
# scripts/ci_phase4.sh — Phase 4 CI: Audio Intelligence & Scan-to-Markdown
# Local iteration slices:
#   bash scripts/test_quartzkit_phase4_focus.sh
#   bash scripts/test_quartzkit_full_suite.sh
#   bash scripts/test_ui_macos_smoke.sh
#   bash scripts/test_ui_iphone_matrix.sh
#   bash scripts/test_ui_ipad_matrix.sh
#   bash scripts/test_macos_coverage.sh
set -euo pipefail

PACKAGE_PATH="QuartzKit"
REPORT_PATH="reports/phase4_report.json"
HEAL_LOG="reports/phase4_heal_log.txt"
SELF_HEAL_DIR="reports/self_heal"
PHASE3_GATE_LOG="reports/phase4_phase3_gate.log"
PHASE4_SWIFTPM_LOG="reports/phase4_swiftpm_phase4.log"
FULL_SWIFTPM_LOG="reports/phase4_swiftpm_full.log"
MACOS_UI_LOG="reports/ui_matrix_macos.log"
IPHONE_UI_LOG="reports/ui_matrix_ios.log"
IPAD_UI_LOG="reports/ui_matrix_ipados.log"
MACOS_RESULT_BUNDLE="/tmp/QuartzPhase4-macOS.xcresult"
MACOS_COVERAGE_RESULT_BUNDLE="/tmp/QuartzPhase4-macOS-coverage.xcresult"
IPHONE_RESULT_BUNDLE="/tmp/QuartzPhase4-iPhone.xcresult"
IPAD_RESULT_BUNDLE="/tmp/QuartzPhase4-iPad.xcresult"
COVERAGE_REPORT="reports/phase4_coverage.txt"
MACOS_COVERAGE_LOG="reports/phase4_coverage_macos.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

STATUS="fail"
FAIL_REASON=""
PHASE3_GATE="fail"
PHASE4_SWIFTPM_FAIL=0
PHASE4_SWIFTPM_PASS=0
FULL_SWIFTPM_FAIL=0
FULL_SWIFTPM_PASS=0
MACOS_TEST_STATUS="fail"
IPHONE_TEST_STATUS="not_run"
IPAD_TEST_STATUS="not_run"
UI_PASS=0
UI_FAIL=0
UI_SKIP=0
COVERAGE_STATUS="missing"
HEAL_RAN="false"
HEAL_ARTIFACTS=""

mkdir -p reports "$SELF_HEAL_DIR"
rm -f /tmp/quartz_heal_categories.txt "$HEAL_LOG" "$REPORT_PATH" "$COVERAGE_REPORT"
rm -f "$MACOS_COVERAGE_LOG"
rm -rf "$MACOS_RESULT_BUNDLE" "$MACOS_COVERAGE_RESULT_BUNDLE" "$IPHONE_RESULT_BUNDLE" "$IPAD_RESULT_BUNDLE"

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }
fail() {
    FAIL_REASON="$1"
    echo -e "${RED}${BOLD}✗ $1${RESET}"
    exit 1
}

reset_result_bundle() {
    local bundle_path="$1"
    if [ -e "$bundle_path" ]; then
        rm -rf "$bundle_path"
    fi
}

write_report() {
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    cat > "$REPORT_PATH" <<REPORT_EOF
{
  "phase": 4,
  "status": "$STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "$commit_hash",
  "failure_reason": "$FAIL_REASON",
  "regression_gate": {
    "phase3": "$PHASE3_GATE",
    "log": "$PHASE3_GATE_LOG"
  },
  "swiftpm": {
    "phase4_failures": $PHASE4_SWIFTPM_FAIL,
    "phase4_pass_markers": $PHASE4_SWIFTPM_PASS,
    "phase4_log": "$PHASE4_SWIFTPM_LOG",
    "full_suite_failures": $FULL_SWIFTPM_FAIL,
    "full_suite_pass_markers": $FULL_SWIFTPM_PASS,
    "full_suite_log": "$FULL_SWIFTPM_LOG"
  },
  "xcodebuild": {
    "macOS": "$MACOS_TEST_STATUS",
    "iPhone": "$IPHONE_TEST_STATUS",
    "iPad": "$IPAD_TEST_STATUS",
    "coverage": "$COVERAGE_STATUS",
    "coverage_report": "$COVERAGE_REPORT",
    "coverage_log": "$MACOS_COVERAGE_LOG",
    "result_bundles": {
      "macOS": "$MACOS_RESULT_BUNDLE",
      "macOSCoverage": "$MACOS_COVERAGE_RESULT_BUNDLE",
      "iPhone": "$IPHONE_RESULT_BUNDLE",
      "iPad": "$IPAD_RESULT_BUNDLE"
    }
  },
  "ui_matrix": {
    "passed": $UI_PASS,
    "failed": $UI_FAIL,
    "skipped": $UI_SKIP,
    "logs": [
      "$MACOS_UI_LOG",
      "$IPHONE_UI_LOG",
      "$IPAD_UI_LOG"
    ]
  },
  "self_healing": {
    "ran": $HEAL_RAN,
    "log": "$HEAL_LOG",
    "artifacts": "$HEAL_ARTIFACTS"
  }
}
REPORT_EOF
}

trap write_report EXIT

classify_failures() {
    local output="$1"
    echo -e "${YELLOW}${BOLD}Failure Classification:${RESET}"

    {
        echo "# Phase 4 Self-Healing Matrix Execution Log"
        echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
    } > "$HEAL_LOG"

    while IFS= read -r line; do
        case "$line" in
            *Snapshot*|*__Snapshots__*|*pixel-diff*)
                echo "SNAPSHOTS" >> /tmp/quartz_heal_categories.txt
                echo "  [SNAPSHOTS] $line"
                echo "[SNAPSHOTS] $line" >> "$HEAL_LOG"
                ;;
            *Streaming*|*Transcri*|*Speech*|*concurrency*|*Sendable*|*MainActor*|*automation\ mode*)
                echo "CONCURRENCY" >> /tmp/quartz_heal_categories.txt
                echo "  [CONCURRENCY] $line"
                echo "[CONCURRENCY] $line" >> "$HEAL_LOG"
                ;;
            *State*|*Persist*|*Transcript*|*Meeting*|*Hardware*|*Capability*|*TextKit*|*Editor*)
                echo "STATE" >> /tmp/quartz_heal_categories.txt
                echo "  [STATE] $line"
                echo "[STATE] $line" >> "$HEAL_LOG"
                ;;
            *Sync*|*bookmark*|*Bookmark*|*iCloud*|*coordinator*)
                echo "SYNC" >> /tmp/quartz_heal_categories.txt
                echo "  [SYNC] $line"
                echo "[SYNC] $line" >> "$HEAL_LOG"
                ;;
            *Performance*|*Budget*|*Memory*|*Latency*|*RSS*|*P95*|*Audio*)
                echo "PERFORMANCE" >> /tmp/quartz_heal_categories.txt
                echo "  [PERFORMANCE] $line"
                echo "[PERFORMANCE] $line" >> "$HEAL_LOG"
                ;;
            *Accessibility*|*VoiceOver*|*DynamicType*|*ReduceMotion*|*Contrast*)
                echo "ACCESSIBILITY" >> /tmp/quartz_heal_categories.txt
                echo "  [ACCESSIBILITY] $line"
                echo "[ACCESSIBILITY] $line" >> "$HEAL_LOG"
                ;;
            *UITests*|*XCUITest*|*Simulator*|*CoreSimulator*|*QuartzUITests*)
                echo "UI_MATRIX" >> /tmp/quartz_heal_categories.txt
                echo "  [UI_MATRIX] $line"
                echo "[UI_MATRIX] $line" >> "$HEAL_LOG"
                ;;
        esac
    done < <(printf '%s\n' "$output" | grep -E "failed after|Test Case .* failed|\\*\\* TEST FAILED \\*\\*|error:|Timed out while enabling automation mode|CoreSimulatorService")
}

run_self_healing() {
    if [ ! -f /tmp/quartz_heal_categories.txt ]; then
        return 0
    fi

    local categories artifact_paths=""
    categories=$(sort -u /tmp/quartz_heal_categories.txt)
    rm -f /tmp/quartz_heal_categories.txt
    HEAL_RAN="true"

    step "Running self-healing scripts"

    for category in $categories; do
        case "$category" in
            ACCESSIBILITY)
                bash scripts/heal_accessibility.sh "$PACKAGE_PATH" 2>&1 | tee -a "$HEAL_LOG" || true
                ;;
            CONCURRENCY)
                bash scripts/heal_concurrency.sh "$PACKAGE_PATH" "$SELF_HEAL_DIR/concurrency.json" 2>&1 | tee -a "$HEAL_LOG" || true
                artifact_paths="${artifact_paths}${artifact_paths:+,}concurrency.json"
                ;;
            PERFORMANCE)
                bash scripts/heal_performance.sh "$PACKAGE_PATH" 2>&1 | tee -a "$HEAL_LOG" || true
                ;;
            SNAPSHOTS)
                bash scripts/heal_snapshots.sh "$PACKAGE_PATH" "$SELF_HEAL_DIR/snapshots.json" 2>&1 | tee -a "$HEAL_LOG" || true
                artifact_paths="${artifact_paths}${artifact_paths:+,}snapshots.json"
                ;;
            STATE)
                bash scripts/heal_state.sh "$PACKAGE_PATH" "$SELF_HEAL_DIR/state.json" 2>&1 | tee -a "$HEAL_LOG" || true
                artifact_paths="${artifact_paths}${artifact_paths:+,}state.json"
                ;;
            SYNC)
                bash scripts/heal_sync.sh "$PACKAGE_PATH" "$SELF_HEAL_DIR/sync.json" 2>&1 | tee -a "$HEAL_LOG" || true
                artifact_paths="${artifact_paths}${artifact_paths:+,}sync.json"
                ;;
            UI_MATRIX)
                bash scripts/heal_ui_matrix.sh 2>&1 | tee -a "$HEAL_LOG" || true
                ;;
        esac
    done

    HEAL_ARTIFACTS="$artifact_paths"
    pass "Self-healing diagnostics completed"
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

has_swiftpm_helper_crash() {
    local output="$1"
    printf '%s\n' "$output" | grep -q "swiftpm-testing-helper.*unexpected signal code 10"
}

has_successful_swift_test_completion() {
    local output="$1"
    printf '%s\n' "$output" | grep -qE "Test run with [0-9]+ tests? in [0-9]+ suites? passed after"
}

run_swift_test_capture() {
    local __result_var="$1"
    shift

    local captured_output capture_status
    captured_output=$("$@" 2>&1)
    capture_status=$?

    printf -v "$__result_var" '%s' "$captured_output"
    return "$capture_status"
}

run_swift_test_scope() {
    local label="$1"
    local filter="$2"
    local log_path="$3"
    local output fail_count pass_count helper_crashed=0 requires_serial_rerun=0 status=0

    step "$label"
    if [ -n "$filter" ]; then
        set +e
        run_swift_test_capture output swift test --package-path "$PACKAGE_PATH" --filter "$filter"
        status=$?
        set -e
    else
        set +e
        run_swift_test_capture output swift test --package-path "$PACKAGE_PATH" --parallel
        status=$?
        set -e
    fi
    pass_count=$(printf '%s\n' "$output" | grep -c "passed" || true)
    fail_count=$(printf '%s\n' "$output" | grep -cE "failed after|Test Case .* failed" || true)

    if [ -z "$filter" ]; then
        if [ "$status" -ne 0 ] && has_swiftpm_helper_crash "$output"; then
            helper_crashed=1
            echo "  Detected SwiftPM helper crash under parallel execution; retrying serially..."
            requires_serial_rerun=1
        elif [ "$status" -ne 0 ] || [ "$fail_count" -gt 0 ]; then
            echo "  Parallel full-suite result was not authoritative (exit: $status, failure markers: $fail_count); retrying serially..."
            requires_serial_rerun=1
        fi

        if [ "$requires_serial_rerun" -eq 1 ]; then
            set +e
            run_swift_test_capture output swift test --package-path "$PACKAGE_PATH" --no-parallel
            status=$?
            set -e
            pass_count=$(printf '%s\n' "$output" | grep -c "passed" || true)
            fail_count=$(printf '%s\n' "$output" | grep -cE "failed after|Test Case .* failed" || true)
        fi
    fi

    printf '%s\n' "$output" > "$log_path"
    echo "  pass markers: $pass_count"
    echo "  failure markers: $fail_count"

    if [ "$log_path" = "$PHASE4_SWIFTPM_LOG" ]; then
        PHASE4_SWIFTPM_PASS=$pass_count
        PHASE4_SWIFTPM_FAIL=$fail_count
    else
        FULL_SWIFTPM_PASS=$pass_count
        FULL_SWIFTPM_FAIL=$fail_count
    fi

    if [ "$fail_count" -gt 0 ]; then
        classify_failures "$output"
        run_self_healing
        fail "$label failed"
    fi

    if [ "$status" -ne 0 ] && has_swiftpm_helper_crash "$output"; then
        if has_successful_swift_test_completion "$output"; then
            echo "  Ignoring helper crash marker after successful Swift Testing completion."
        else
            classify_failures "$output"
            run_self_healing
            fail "$label failed due to SwiftPM helper crash"
        fi
    elif [ "$status" -ne 0 ]; then
        classify_failures "$output"
        run_self_healing
        fail "$label failed (swift test exit: $status)"
    fi

    pass "$label passed"
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

step "Running Phase 3 regression gate"
PHASE3_OUTPUT=$(bash scripts/ci_phase3.sh 2>&1 || true)
printf '%s\n' "$PHASE3_OUTPUT" > "$PHASE3_GATE_LOG"
if printf '%s\n' "$PHASE3_OUTPUT" | grep -q "Phase 3 CI completed — PASS"; then
    PHASE3_GATE="pass"
    pass "Phase 3 regression gate passed"
else
    classify_failures "$PHASE3_OUTPUT"
    run_self_healing
    fail "Phase 3 regression gate failed"
fi

P4_FILTER="Phase4AudioMemoryBudget|Phase4AudioInterruption|Phase4HardwareCapability|Phase4E2EFlow|Phase4LiveCapsuleAccessibility|Phase4ScanAccessibility|Phase4StreamingTranscription|Phase4TypedEventing|AudioPipelineIntegration|DiarizationMapping|LanguageDetection|RecorderCompactUI|Phase4ProductionHotPath|Phase4ProcessRSS|Phase4P95Latency|Phase4IntegratedWorkload|Phase4Editor|Phase4SnapshotMatrix"
run_swift_test_scope "Running focused Phase 4 SwiftPM suites" "$P4_FILTER" "$PHASE4_SWIFTPM_LOG"
run_swift_test_scope "Running full QuartzKit SwiftPM suite" "" "$FULL_SWIFTPM_LOG"

step "Running macOS UI smoke test"
terminate_conflicting_macos_app_processes
reset_result_bundle "$MACOS_RESULT_BUNDLE"
if run_xcodebuild_to_log "$MACOS_UI_LOG" \
    xcodebuild test -scheme Quartz \
        -destination "platform=macOS" \
        -only-testing:QuartzUITests/macOSSmokeUITests \
        -resultBundlePath "$MACOS_RESULT_BUNDLE"; then
    MACOS_TEST_STATUS="pass"
    UI_PASS=$((UI_PASS + 1))
    pass "macOS UI matrix passed"
else
    MACOS_TEST_STATUS="fail"
    UI_FAIL=$((UI_FAIL + 1))
    classify_failures "$(cat "$MACOS_UI_LOG")"
    run_self_healing
fi

step "Collecting macOS coverage report"
reset_result_bundle "$MACOS_COVERAGE_RESULT_BUNDLE"
if run_xcodebuild_to_log "$MACOS_COVERAGE_LOG" \
    xcodebuild test -scheme Quartz \
        -parallel-testing-enabled NO \
        -destination "platform=macOS" \
        -only-testing:QuartzTests \
        -enableCodeCoverage YES \
        -resultBundlePath "$MACOS_COVERAGE_RESULT_BUNDLE" \
    && [ -d "$MACOS_COVERAGE_RESULT_BUNDLE" ] \
    && xcrun xccov view --report "$MACOS_COVERAGE_RESULT_BUNDLE" > "$COVERAGE_REPORT" 2>/dev/null; then
    COVERAGE_STATUS="present"
    pass "Coverage report written to $COVERAGE_REPORT"
else
    COVERAGE_STATUS="missing"
    if [ -f "$MACOS_COVERAGE_LOG" ]; then
        classify_failures "$(cat "$MACOS_COVERAGE_LOG")"
        run_self_healing
    fi
fi

step "Running iPhone UI matrix"
IPHONE_SIM_ID=$(prepared_simulator_id "iPhone 16 Pro" "iPhone" || true)
if [ -z "$IPHONE_SIM_ID" ]; then
    UI_SKIP=$((UI_SKIP + 1))
    IPHONE_TEST_STATUS="skipped"
    echo "  iPhone simulator unavailable"
else
    reset_result_bundle "$IPHONE_RESULT_BUNDLE"
    if run_xcodebuild_to_log "$IPHONE_UI_LOG" \
        xcodebuild test -scheme Quartz \
            -parallel-testing-enabled NO \
            -destination "platform=iOS Simulator,id=$IPHONE_SIM_ID" \
            -resultBundlePath "$IPHONE_RESULT_BUNDLE" \
            -only-testing:QuartzUITests/WelcomeScreenTests \
            -only-testing:QuartzUITests/OnboardingFlowTests \
            -only-testing:QuartzUITests/AccessibilityUITests \
            -only-testing:QuartzUITests/PerformanceUITests \
            -only-testing:QuartzUITests/iOSPhoneSmokeUITests; then
        IPHONE_TEST_STATUS="pass"
        UI_PASS=$((UI_PASS + 1))
        pass "iPhone UI matrix passed on simulator id $IPHONE_SIM_ID"
    else
        IPHONE_TEST_STATUS="fail"
        UI_FAIL=$((UI_FAIL + 1))
        classify_failures "$(cat "$IPHONE_UI_LOG")"
        run_self_healing
    fi
fi

step "Running iPad UI matrix"
IPAD_SIM_ID=$(prepared_simulator_id "iPad Pro 13-inch (M5)" "iPad" || true)
if [ -z "$IPAD_SIM_ID" ]; then
    UI_SKIP=$((UI_SKIP + 1))
    IPAD_TEST_STATUS="skipped"
    echo "  iPad simulator unavailable"
else
    reset_result_bundle "$IPAD_RESULT_BUNDLE"
    if run_xcodebuild_to_log "$IPAD_UI_LOG" \
        xcodebuild test -scheme Quartz \
            -parallel-testing-enabled NO \
            -destination "platform=iOS Simulator,id=$IPAD_SIM_ID" \
            -resultBundlePath "$IPAD_RESULT_BUNDLE" \
            -only-testing:QuartzUITests/iPadSmokeUITests; then
        IPAD_TEST_STATUS="pass"
        UI_PASS=$((UI_PASS + 1))
        pass "iPad UI matrix passed on simulator id $IPAD_SIM_ID"
    else
        IPAD_TEST_STATUS="fail"
        UI_FAIL=$((UI_FAIL + 1))
        classify_failures "$(cat "$IPAD_UI_LOG")"
        run_self_healing
    fi
fi

if [ "$PHASE3_GATE" = "pass" ] \
    && [ "$PHASE4_SWIFTPM_FAIL" -eq 0 ] \
    && [ "$FULL_SWIFTPM_FAIL" -eq 0 ] \
    && [ "$UI_FAIL" -eq 0 ] \
    && [ "$UI_SKIP" -eq 0 ] \
    && [ "$COVERAGE_STATUS" = "present" ]; then
    STATUS="pass"
else
    STATUS="fail"
fi

write_report

step "Verifying report artifact"
if ! python3 -c "import json; json.load(open('$REPORT_PATH'))" >/dev/null 2>&1; then
    fail "Report artifact is not valid JSON"
fi
pass "Report artifact verified"

echo ""
if [ "$STATUS" = "pass" ]; then
    echo -e "${GREEN}${BOLD}Phase 4 CI completed — PASS${RESET}"
    exit 0
fi

if [ -z "$FAIL_REASON" ]; then
    FAIL_REASON="One or more Phase 4 gates failed"
fi
echo -e "${RED}${BOLD}Phase 4 CI completed — FAIL${RESET}"
echo "  Reason: $FAIL_REASON"
echo "  Report: $REPORT_PATH"
exit 1
