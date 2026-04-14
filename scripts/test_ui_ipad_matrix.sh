#!/usr/bin/env bash
# Developer slice: iPad UI matrix only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

LOG_PATH="${LOG_PATH:-reports/ui_matrix_ipados.log}"
RESULT_BUNDLE="${RESULT_BUNDLE:-/tmp/QuartzUITests_iPad.xcresult}"
PREFERRED_SIMULATOR="${PREFERRED_SIMULATOR:-iPad Pro 13-inch (M5)}"
SIMULATOR_FAMILY="${SIMULATOR_FAMILY:-iPad}"

step "Running iPad UI matrix"
echo "  Log: $LOG_PATH"
echo "  Result bundle: $RESULT_BUNDLE"
echo "  Preferred simulator: $PREFERRED_SIMULATOR"

SIM_ID="$(prepared_simulator_id "$PREFERRED_SIMULATOR" "$SIMULATOR_FAMILY" || true)"
if [ -z "$SIM_ID" ]; then
    fail "No stable iPad simulator was ready for UI testing"
fi

echo "  Using simulator id: $SIM_ID"
reset_result_bundle "$RESULT_BUNDLE"

if run_xcodebuild_to_log "$LOG_PATH" \
    xcodebuild test -scheme Quartz \
        -parallel-testing-enabled NO \
        -destination "platform=iOS Simulator,id=$SIM_ID" \
        -resultBundlePath "$RESULT_BUNDLE" \
        -only-testing:QuartzUITests/iPadSmokeUITests; then
    pass "iPad UI matrix passed"
else
    fail "iPad UI matrix failed"
fi
