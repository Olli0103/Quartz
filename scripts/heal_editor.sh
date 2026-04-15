#!/usr/bin/env bash
# scripts/heal_editor.sh — Self-heal diagnostics for the Editor Excellence track.
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
OUTPUT_PATH="${2:-reports/self_heal/editor.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RERUN_LOG="/tmp/quartz_editor_heal.log"
EDITOR_SOURCE_DIRS=(
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor"
    "$PACKAGE_PATH/Sources/QuartzKit/Presentation/Editor"
)
REALITY_FIXTURE_DIR="$PACKAGE_PATH/Tests/QuartzKitTests/EditorRealityCorpus"
SNAPSHOT_ROOT_DIR="$PACKAGE_PATH/Tests/QuartzKitTests/__Snapshots__"
LIVE_TEST_FILES=(
    "$PACKAGE_PATH/Tests/QuartzKitTests/EditorLiveMutationRegressionTests.swift"
    "$PACKAGE_PATH/Tests/QuartzKitTests/EditorLiveMutationMobileRegressionTests.swift"
)
PERF_TEST_FILE="$PACKAGE_PATH/Tests/QuartzKitTests/EditorPerformanceBudgetTests.swift"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

mkdir -p "$(dirname "$OUTPUT_PATH")"
cd "$REPO_ROOT"

step "[HEAL:EDITOR] Running editor self-heal diagnostics"

if [ -f "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift" ]; then
    echo "  ✓ MarkdownASTHighlighter.swift exists"
else
    echo "  ✗ MarkdownASTHighlighter.swift missing"
    exit 1
fi

LINEAR_ANIMATION_COUNT=$(rg -n "\\.linear\\(" "${EDITOR_SOURCE_DIRS[@]}" 2>/dev/null | wc -l | tr -d ' ')
LINEAR_ANIMATION_COUNT=${LINEAR_ANIMATION_COUNT:-0}

UNSAFE_CONCURRENCY_PATTERN_COUNT=$(rg -n "@unchecked Sendable|@preconcurrency|try! await|DispatchQueue\\.main\\.async" \
    "${EDITOR_SOURCE_DIRS[@]}" 2>/dev/null | wc -l | tr -d ' ')
UNSAFE_CONCURRENCY_PATTERN_COUNT=${UNSAFE_CONCURRENCY_PATTERN_COUNT:-0}

TEXTKIT2_WIRING_REFS=$(rg -n "MarkdownTextKit2Stack\\.makeContentManager|MarkdownTextKit2Stack\\.wireTextKit2" \
    "$PACKAGE_PATH/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift" 2>/dev/null | wc -l | tr -d ' ')
TEXTKIT2_WIRING_REFS=${TEXTKIT2_WIRING_REFS:-0}

CONCEALMENT_RULE_REFS=$(rg -n "overlayVisibilityBehavior|concealWhenInactive|alwaysVisible" \
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift" \
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor/EditorSession.swift" 2>/dev/null | wc -l | tr -d ' ')
CONCEALMENT_RULE_REFS=${CONCEALMENT_RULE_REFS:-0}

REALITY_FIXTURE_COUNT=$(find "$REALITY_FIXTURE_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
REALITY_FIXTURE_COUNT=${REALITY_FIXTURE_COUNT:-0}

SNAPSHOT_BASELINE_COUNT=$(find "$SNAPSHOT_ROOT_DIR" -maxdepth 2 -type f -name '*.png' \
    \( -path '*/EditorRealitySnapshotTests/*' -o -path '*/EditorRealityMobileSnapshotTests/*' \) \
    2>/dev/null | wc -l | tr -d ' ')
SNAPSHOT_BASELINE_COUNT=${SNAPSHOT_BASELINE_COUNT:-0}

LIVE_MUTATION_TEST_COUNT=$(rg -n "^\\s*func test" "${LIVE_TEST_FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')
LIVE_MUTATION_TEST_COUNT=${LIVE_MUTATION_TEST_COUNT:-0}

PERFORMANCE_BUDGET_ASSERTION_COUNT=$(rg -n "16ms|P95|main thread|frame budget|memory" "$PERF_TEST_FILE" 2>/dev/null | wc -l | tr -d ' ')
PERFORMANCE_BUDGET_ASSERTION_COUNT=${PERFORMANCE_BUDGET_ASSERTION_COUNT:-0}
MACOS_UI_AUTOMATION_REQUIRES_AUTH="false"

if command -v automationmodetool >/dev/null 2>&1 && macos_ui_automation_requires_authentication; then
    MACOS_UI_AUTOMATION_REQUIRES_AUTH="true"
fi

if bash "$SCRIPT_DIR/test_editor_excellence.sh" >"$RERUN_LOG" 2>&1; then
    RERUN_STATUS="pass"
    RERUN_EXIT=0
else
    RERUN_STATUS="fail"
    RERUN_EXIT=1
fi

cat > "$OUTPUT_PATH" <<JSON
{
  "category": "editor",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "matrix": "config/editor_self_healing_matrix.json",
  "linearity_violations": $LINEAR_ANIMATION_COUNT,
  "unsafe_concurrency_patterns": $UNSAFE_CONCURRENCY_PATTERN_COUNT,
  "textkit2_wiring_references": $TEXTKIT2_WIRING_REFS,
  "concealment_rule_references": $CONCEALMENT_RULE_REFS,
  "reality_fixture_count": $REALITY_FIXTURE_COUNT,
  "snapshot_baseline_count": $SNAPSHOT_BASELINE_COUNT,
  "live_mutation_test_count": $LIVE_MUTATION_TEST_COUNT,
  "performance_budget_assertion_count": $PERFORMANCE_BUDGET_ASSERTION_COUNT,
  "macos_ui_automation_requires_authentication": $MACOS_UI_AUTOMATION_REQUIRES_AUTH,
  "rerun_status": "$RERUN_STATUS",
  "rerun_log": "$RERUN_LOG"
}
JSON

echo "  linears: $LINEAR_ANIMATION_COUNT"
echo "  unsafe concurrency patterns: $UNSAFE_CONCURRENCY_PATTERN_COUNT"
echo "  TextKit 2 wiring refs: $TEXTKIT2_WIRING_REFS"
echo "  concealment refs: $CONCEALMENT_RULE_REFS"
echo "  reality fixtures: $REALITY_FIXTURE_COUNT"
echo "  snapshot baselines: $SNAPSHOT_BASELINE_COUNT"
echo "  live mutation tests: $LIVE_MUTATION_TEST_COUNT"
echo "  performance assertions: $PERFORMANCE_BUDGET_ASSERTION_COUNT"
echo "  macOS UI automation requires auth: $MACOS_UI_AUTOMATION_REQUIRES_AUTH"
echo "  rerun status: $RERUN_STATUS"

if [ "$LINEAR_ANIMATION_COUNT" -gt 0 ] || \
   [ "$UNSAFE_CONCURRENCY_PATTERN_COUNT" -gt 0 ] || \
   [ "$TEXTKIT2_WIRING_REFS" -lt 2 ] || \
   [ "$CONCEALMENT_RULE_REFS" -lt 6 ] || \
   [ "$REALITY_FIXTURE_COUNT" -lt 3 ] || \
   [ "$SNAPSHOT_BASELINE_COUNT" -lt 15 ] || \
   [ "$LIVE_MUTATION_TEST_COUNT" -lt 20 ] || \
   [ "$PERFORMANCE_BUDGET_ASSERTION_COUNT" -lt 4 ] || \
   [ "$MACOS_UI_AUTOMATION_REQUIRES_AUTH" = "true" ] || \
   [ "$RERUN_EXIT" -ne 0 ]; then
    fail "[HEAL:EDITOR] Blocking editor diagnostics found"
fi

pass "[HEAL:EDITOR] Editor diagnostics are within expected thresholds"
