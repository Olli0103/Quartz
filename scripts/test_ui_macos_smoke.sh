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
MACOS_UI_DERIVED_DATA_PATH="${MACOS_UI_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/QuartzUITestDerivedDataAdhoc}"
MACOS_UI_XCODEBUILD_SIGNING_ARGS=(
    -derivedDataPath "$MACOS_UI_DERIVED_DATA_PATH"
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=
    CODE_SIGN_IDENTITY=-
    AD_HOC_CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
    CODE_SIGN_ENTITLEMENTS=
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    PROVISIONING_PROFILE_SPECIFIER=
    PROVISIONING_PROFILE=
)

step "Running macOS UI smoke tests"
echo "  Log: $LOG_PATH"
echo "  Result bundle: $RESULT_BUNDLE"
echo "  DerivedData: $MACOS_UI_DERIVED_DATA_PATH"

# Full macOS editor-shell coverage now includes the toolbar visibility matrix and
# representative action matrix. Focused proofs on this host already exceed the
# old 15-minute wrapper timeout, so give this smoke lane enough budget to finish.
export XCODEBUILD_TEST_TIMEOUT_SECONDS="${XCODEBUILD_TEST_TIMEOUT_SECONDS:-2700}"

if ! ensure_macos_ui_automation_available "$LOG_PATH"; then
    echo "Host automation mode is disabled; continuing to the real macOS XCTest launch/attach probe." | tee -a "$LOG_PATH"
fi

terminate_conflicting_macos_app_processes
reset_result_bundle "$RESULT_BUNDLE"

if run_xcodebuild_to_log "$LOG_PATH" \
    xcodebuild test -scheme Quartz \
        -parallel-testing-enabled NO \
        -destination "platform=macOS" \
        -only-testing:QuartzUITests/macOSSmokeUITests \
        -only-testing:QuartzUITests/macOSEditorShellUITests \
        -resultBundlePath "$RESULT_BUNDLE" \
        "${MACOS_UI_XCODEBUILD_SIGNING_ARGS[@]}"; then
    pass "macOS UI smoke tests passed"
else
    fail "macOS UI smoke tests failed"
fi
