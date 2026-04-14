#!/usr/bin/env bash
# Developer slice: macOS QuartzTests coverage only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

LOG_PATH="${LOG_PATH:-reports/phase4_coverage_macos.log}"
RESULT_BUNDLE="${RESULT_BUNDLE:-/tmp/QuartzPhase4-macOS-coverage.xcresult}"
COVERAGE_REPORT="${COVERAGE_REPORT:-reports/phase4_coverage.txt}"

step "Running macOS coverage slice"
echo "  Log: $LOG_PATH"
echo "  Result bundle: $RESULT_BUNDLE"
echo "  Coverage report: $COVERAGE_REPORT"

reset_result_bundle "$RESULT_BUNDLE"
rm -f "$COVERAGE_REPORT"

if run_xcodebuild_to_log "$LOG_PATH" \
    xcodebuild test -scheme Quartz \
        -parallel-testing-enabled NO \
        -destination "platform=macOS" \
        -only-testing:QuartzTests \
        -enableCodeCoverage YES \
        -resultBundlePath "$RESULT_BUNDLE" \
    && [ -d "$RESULT_BUNDLE" ] \
    && xcrun xccov view --report "$RESULT_BUNDLE" > "$COVERAGE_REPORT" 2>/dev/null; then
    pass "macOS coverage slice passed"
else
    fail "macOS coverage slice failed"
fi
