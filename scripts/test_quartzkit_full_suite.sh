#!/usr/bin/env bash
# Developer slice: full QuartzKit suite with authoritative serial retry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

PACKAGE_PATH="${PACKAGE_PATH:-QuartzKit}"
LOG_PATH="${LOG_PATH:-reports/quartzkit_full_suite.log}"
TMP_OUTPUT="$(mktemp -t quartzkit-full-suite.XXXXXX.log)"

cleanup() {
    rm -f "$TMP_OUTPUT"
}
trap cleanup EXIT

has_swiftpm_helper_crash() {
    local output="$1"
    printf '%s\n' "$output" | grep -q "swiftpm-testing-helper.*unexpected signal code 10"
}

has_successful_swift_test_completion() {
    local output="$1"
    printf '%s\n' "$output" | grep -qE "Test run with [0-9]+ tests? in [0-9]+ suites? passed after"
}

run_capture() {
    local mode="$1"
    shift
    step "Running QuartzKit full suite ($mode)"
    if "$@" >"$TMP_OUTPUT" 2>&1; then
        cat "$TMP_OUTPUT"
        return 0
    fi
    cat "$TMP_OUTPUT"
    return 1
}

authoritative_output=""
authoritative_status=0

set +e
run_capture "parallel" swift test --package-path "$PACKAGE_PATH" --parallel
parallel_status=$?
set -e
parallel_output="$(cat "$TMP_OUTPUT")"
parallel_fail_count=$(printf '%s\n' "$parallel_output" | grep -cE "failed after|Test Case .* failed" || true)

if [ "$parallel_status" -eq 0 ] && [ "$parallel_fail_count" -eq 0 ]; then
    authoritative_output="$parallel_output"
    authoritative_status=0
else
    echo "  Parallel run was not authoritative; retrying serially..."
    set +e
    run_capture "serial retry" swift test --package-path "$PACKAGE_PATH" --no-parallel
    authoritative_status=$?
    set -e
    authoritative_output="$(cat "$TMP_OUTPUT")"
fi

printf '%s\n' "$authoritative_output" > "$LOG_PATH"
authoritative_fail_count=$(printf '%s\n' "$authoritative_output" | grep -cE "failed after|Test Case .* failed" || true)

echo "  Log: $LOG_PATH"
echo "  Failure markers: $authoritative_fail_count"

if [ "$authoritative_fail_count" -gt 0 ]; then
    fail "QuartzKit full suite reported test failures"
fi

if [ "$authoritative_status" -ne 0 ] && has_swiftpm_helper_crash "$authoritative_output"; then
    if has_successful_swift_test_completion "$authoritative_output"; then
        pass "QuartzKit full suite passed after helper crash noise"
        exit 0
    fi
    fail "QuartzKit full suite failed due to SwiftPM helper crash"
fi

if [ "$authoritative_status" -ne 0 ]; then
    fail "QuartzKit full suite failed"
fi

pass "QuartzKit full suite passed"
