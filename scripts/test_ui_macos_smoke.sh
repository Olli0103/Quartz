#!/usr/bin/env bash
# Developer slice: macOS UI smoke only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

LOG_PATH="${LOG_PATH:-reports/ui_matrix_macos.log}"
RESULT_BUNDLE="${RESULT_BUNDLE:-/tmp/QuartzUITests_macOS.xcresult}"

step "Running macOS UI smoke tests"
echo "  Log: $LOG_PATH"
echo "  Result bundle: $RESULT_BUNDLE"

terminate_conflicting_macos_app_processes
reset_result_bundle "$RESULT_BUNDLE"

if run_xcodebuild_to_log "$LOG_PATH" \
    xcodebuild test -scheme Quartz \
        -parallel-testing-enabled NO \
        -destination "platform=macOS" \
        -only-testing:QuartzUITests/macOSSmokeUITests \
        -resultBundlePath "$RESULT_BUNDLE"; then
    pass "macOS UI smoke tests passed"
else
    fail "macOS UI smoke tests failed"
fi
