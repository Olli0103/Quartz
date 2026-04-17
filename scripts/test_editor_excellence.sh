#!/usr/bin/env bash
# Developer slice: Editor Excellence gate for Phase 4.5.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

PACKAGE_PATH="${PACKAGE_PATH:-QuartzKit}"
LOG_PATH="${LOG_PATH:-reports/editor_excellence.log}"
IOS_LOG_PATH="${IOS_LOG_PATH:-reports/editor_excellence_ios.log}"
IPADOS_LOG_PATH="${IPADOS_LOG_PATH:-reports/editor_excellence_ipados.log}"
MACOS_UI_LOG_PATH="${MACOS_UI_LOG_PATH:-reports/editor_excellence_ui_macos.log}"
IOS_UI_LOG_PATH="${IOS_UI_LOG_PATH:-reports/editor_excellence_ui_ios.log}"
IPADOS_UI_LOG_PATH="${IPADOS_UI_LOG_PATH:-reports/editor_excellence_ui_ipados.log}"
IOS_RESULT_BUNDLE="${IOS_RESULT_BUNDLE:-/tmp/QuartzKitEditor_iPhone.xcresult}"
IPADOS_RESULT_BUNDLE="${IPADOS_RESULT_BUNDLE:-/tmp/QuartzKitEditor_iPad.xcresult}"
MACOS_UI_RESULT_BUNDLE="${MACOS_UI_RESULT_BUNDLE:-/tmp/QuartzEditorShell_macOS.xcresult}"
IOS_UI_RESULT_BUNDLE="${IOS_UI_RESULT_BUNDLE:-/tmp/QuartzEditorShell_iPhone.xcresult}"
IPADOS_UI_RESULT_BUNDLE="${IPADOS_UI_RESULT_BUNDLE:-/tmp/QuartzEditorShell_iPad.xcresult}"
IPHONE_PREFERRED_SIMULATOR="${IPHONE_PREFERRED_SIMULATOR:-iPhone 17 Pro}"
IPAD_PREFERRED_SIMULATOR="${IPAD_PREFERRED_SIMULATOR:-iPad Pro 13-inch (M5)}"
EDITOR_FILTER="${EDITOR_FILTER:-SyntaxVisibilityModeTests|EditorPasteNormalizationTests|EditorSemanticDocumentTests|EditorReality(Corpus|Roundtrip|Snapshot)Tests|EditorRenderingRegressionTests|EditorLiveMutationRegressionTests|EditorPerformanceBudgetTests|IncrementalASTPatchingTests|TextKitRenderingTests|LiveTableRenderingTests|EditorUndoBundleTests|EditorMutationTransactionTests}"
RECORD_FLAG_PATH="${RECORD_FLAG_PATH:-/tmp/quartz_record_editor_snapshots.flag}"
PACKAGE_SCHEME_TEST_ACTION_ERROR="Scheme QuartzKit is not currently configured for the test action."

MACOS_EDITOR_SHELL_TESTS=(
    "QuartzUITests/macOSEditorShellUITests/testEditorPreservesEditsAcrossNoteSwitching"
    "QuartzUITests/macOSEditorShellUITests/testKeyboardBoldActionAppliesMarkdownInline"
    "QuartzUITests/macOSEditorShellUITests/testCommandFindInNoteOpensEditorScopedFindBar"
    "QuartzUITests/macOSEditorShellUITests/testCommandSearchNotesRemainsSeparateFromFindInNote"
    "QuartzUITests/macOSEditorShellUITests/testToolbarLinkActionInsertsMarkdownTemplate"
    "QuartzUITests/macOSEditorShellUITests/testTypingWikiLinkTriggerShowsSuggestionsAndInsertsLinkedNote"
    "QuartzUITests/macOSEditorShellUITests/testToolbarBoldActionAppliesMarkdownInline"
    "QuartzUITests/macOSEditorShellUITests/testToolbarCheckboxActionInsertsTaskPrefix"
    "QuartzUITests/macOSEditorShellUITests/testToolbarTableActionInsertsMarkdownTable"
    "QuartzUITests/macOSEditorShellUITests/testToolbarMermaidActionWrapsCurrentLineInFence"
    "QuartzUITests/macOSEditorShellUITests/testToolbarBoldActionWrapsCurrentSelection"
    "QuartzUITests/macOSEditorShellUITests/testPasteAndUndoRedoCommandsRoundTripEditorState"
    "QuartzUITests/macOSEditorShellUITests/testEditorContextRestoresAcrossRelaunchWithoutReset"
)

IPHONE_EDITOR_SHELL_TESTS=(
    "QuartzUITests/iPhoneEditorShellUITests/testEditingSurvivesBackgroundForeground"
    "QuartzUITests/iPhoneEditorShellUITests/testCompactToolbarBoldActionAppliesMarkdownInline"
    "QuartzUITests/iPhoneEditorShellUITests/testCompactToolbarLinkActionInsertsMarkdownTemplate"
    "QuartzUITests/iPhoneEditorShellUITests/testTypingWikiLinkTriggerShowsSuggestionsAndInsertsLinkedNote"
    "QuartzUITests/iPhoneEditorShellUITests/testCompactToolbarCheckboxActionInsertsTaskPrefix"
    "QuartzUITests/iPhoneEditorShellUITests/testCompactToolbarTableActionInsertsMarkdownTable"
    "QuartzUITests/iPhoneEditorShellUITests/testCompactToolbarMermaidActionWrapsCurrentLineInFence"
    "QuartzUITests/iPhoneEditorShellUITests/testToolbarFindButtonOpensEditorScopedFindBar"
)

IPAD_EDITOR_SHELL_TESTS=(
    "QuartzUITests/iPadEditorShellUITests/testSplitViewEditingSurvivesNoteSwitching"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewToolbarBoldActionAppliesMarkdownInline"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewToolbarLinkActionInsertsMarkdownTemplate"
    "QuartzUITests/iPadEditorShellUITests/testTypingWikiLinkTriggerShowsSuggestionsAndInsertsLinkedNote"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewToolbarCheckboxActionInsertsTaskPrefix"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewToolbarTableActionInsertsMarkdownTable"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewToolbarMermaidActionWrapsCurrentLineInFence"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewHeadingMenuRoundTripAppliesAndRemovesHeadingSyntax"
    "QuartzUITests/iPadEditorShellUITests/testSplitViewFindButtonOpensEditorScopedFindBar"
)

cleanup_record_flag() {
    if [ "${RECORD_FLAG_CREATED:-0}" = "1" ]; then
        rm -f "$RECORD_FLAG_PATH"
    fi
}

trap cleanup_record_flag EXIT

if [ "${QUARTZ_RECORD_EDITOR_SNAPSHOTS:-0}" = "1" ]; then
    rm -f "$RECORD_FLAG_PATH"
    touch "$RECORD_FLAG_PATH"
    RECORD_FLAG_CREATED=1
fi

run_package_editor_matrix() {
    local simulator_id="$1"
    local log_path="$2"
    local result_bundle="$3"
    local snapshot_suite="$4"
    local live_suite="$5"
    local package_root="$REPO_ROOT/$PACKAGE_PATH"

    run_xcodebuild_in_workdir_to_log "$package_root" "$log_path" \
        xcodebuild test -scheme QuartzKit \
            -parallel-testing-enabled NO \
            -destination-timeout 60 \
            -destination "platform=iOS Simulator,id=$simulator_id" \
            -only-testing:"QuartzKitTests/$snapshot_suite" \
            -only-testing:"QuartzKitTests/$live_suite"
}

run_editor_shell_ui_matrix() {
    local destination="$1"
    local log_path="$2"
    local result_bundle="$3"
    shift 3
    local test_identifiers=("$@")
    local xcodebuild_args=(
        xcodebuild test -scheme Quartz
            -parallel-testing-enabled NO
            -destination-timeout 60
            -destination "$destination"
            -resultBundlePath "$result_bundle"
    )

    reset_result_bundle "$result_bundle"
    for test_identifier in "${test_identifiers[@]}"; do
        xcodebuild_args+=("-only-testing:$test_identifier")
    done

    run_xcodebuild_to_log "$log_path" "${xcodebuild_args[@]}"
}

step "Running editor excellence gate"
echo "  Log: $LOG_PATH"
echo "  Filter: $EDITOR_FILTER"

if swift test --package-path "$PACKAGE_PATH" --filter "$EDITOR_FILTER" 2>&1 | tee "$LOG_PATH"; then
    pass "Editor excellence gate passed"
else
    fail "Editor excellence gate failed"
fi

step "Running iPhone editor parity"
IPHONE_SIM_ID="$(prepared_simulator_id "$IPHONE_PREFERRED_SIMULATOR" "iPhone" || true)"
if [ -z "$IPHONE_SIM_ID" ]; then
    fail "No stable iPhone simulator was ready for editor parity"
fi
echo "  Using iPhone simulator id: $IPHONE_SIM_ID"
if run_package_editor_matrix \
    "$IPHONE_SIM_ID" \
    "$IOS_LOG_PATH" \
    "$IOS_RESULT_BUNDLE" \
    "EditorRealitySnapshotTests_iPhone" \
    "EditorLiveMutationRegressionTests_iOS"; then
    pass "iPhone editor parity passed"
elif grep -q "$PACKAGE_SCHEME_TEST_ACTION_ERROR" "$IOS_LOG_PATH"; then
    fail "iPhone editor parity blocked: QuartzKit scheme has no xcodebuild test action for simulator parity"
else
    fail "iPhone editor parity failed"
fi

step "Running iPad editor parity"
IPAD_SIM_ID="$(prepared_simulator_id "$IPAD_PREFERRED_SIMULATOR" "iPad" || true)"
if [ -z "$IPAD_SIM_ID" ]; then
    fail "No stable iPad simulator was ready for editor parity"
fi
echo "  Using iPad simulator id: $IPAD_SIM_ID"
if run_package_editor_matrix \
    "$IPAD_SIM_ID" \
    "$IPADOS_LOG_PATH" \
    "$IPADOS_RESULT_BUNDLE" \
    "EditorRealitySnapshotTests_iPad" \
    "EditorLiveMutationRegressionTests_iPadOS"; then
    pass "iPad editor parity passed"
elif grep -q "$PACKAGE_SCHEME_TEST_ACTION_ERROR" "$IPADOS_LOG_PATH"; then
    fail "iPad editor parity blocked: QuartzKit scheme has no xcodebuild test action for simulator parity"
else
    fail "iPad editor parity failed"
fi

step "Running macOS editor shell UI coverage"
if ! ensure_macos_ui_automation_available "$MACOS_UI_LOG_PATH"; then
    fail "macOS editor shell UI coverage is blocked by host UI automation setup"
fi

terminate_conflicting_macos_app_processes
if run_editor_shell_ui_matrix \
    "platform=macOS" \
    "$MACOS_UI_LOG_PATH" \
    "$MACOS_UI_RESULT_BUNDLE" \
    "${MACOS_EDITOR_SHELL_TESTS[@]}"; then
    pass "macOS editor shell UI coverage passed"
else
    fail "macOS editor shell UI coverage failed"
fi

step "Running iPhone editor shell UI coverage"
if run_editor_shell_ui_matrix \
    "platform=iOS Simulator,id=$IPHONE_SIM_ID" \
    "$IOS_UI_LOG_PATH" \
    "$IOS_UI_RESULT_BUNDLE" \
    "${IPHONE_EDITOR_SHELL_TESTS[@]}"; then
    pass "iPhone editor shell UI coverage passed"
else
    fail "iPhone editor shell UI coverage failed"
fi

step "Running iPad editor shell UI coverage"
if run_editor_shell_ui_matrix \
    "platform=iOS Simulator,id=$IPAD_SIM_ID" \
    "$IPADOS_UI_LOG_PATH" \
    "$IPADOS_UI_RESULT_BUNDLE" \
    "${IPAD_EDITOR_SHELL_TESTS[@]}"; then
    pass "iPad editor shell UI coverage passed"
else
    fail "iPad editor shell UI coverage failed"
fi
