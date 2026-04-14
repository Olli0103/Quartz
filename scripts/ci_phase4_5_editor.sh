#!/usr/bin/env bash
# scripts/ci_phase4_5_editor.sh — Dedicated CI gate for the Phase 4.5 editor rebuild.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports reports/self_heal

PACKAGE_PATH="${PACKAGE_PATH:-QuartzKit}"
REPORT_PATH="${REPORT_PATH:-reports/editor_excellence_report.json}"
LOG_PATH="${LOG_PATH:-reports/editor_excellence.log}"
HEAL_LOG="${HEAL_LOG:-reports/editor_excellence_heal.log}"
HEAL_OUTPUT="${HEAL_OUTPUT:-reports/self_heal/editor.json}"
MATRIX_PATH="${MATRIX_PATH:-config/editor_self_healing_matrix.json}"

STATUS="fail"
FAIL_REASON=""
HEAL_RAN="false"
HEAL_STATUS="not_run"

write_report() {
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    if ! git diff --quiet --ignore-submodules HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        commit_hash="${commit_hash}-dirty"
    fi

    cat > "$REPORT_PATH" <<JSON
{
  "track": "editor_excellence",
  "status": "$STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "$commit_hash",
  "failure_reason": "$FAIL_REASON",
  "gate_log": "$LOG_PATH",
  "self_healing": {
    "ran": $HEAL_RAN,
    "status": "$HEAL_STATUS",
    "matrix": "$MATRIX_PATH",
    "log": "$HEAL_LOG",
    "artifact": "$HEAL_OUTPUT"
  }
}
JSON
}

trap write_report EXIT

step "Phase 4.5 Editor Excellence CI"

if bash "$SCRIPT_DIR/test_editor_excellence.sh"; then
    STATUS="pass"
    pass "Editor excellence CI passed"
    exit 0
fi

FAIL_REASON="Editor excellence gate failed"
HEAL_RAN="true"

step "Running editor self-heal diagnostics"
if bash "$SCRIPT_DIR/heal_editor.sh" "$PACKAGE_PATH" "$HEAL_OUTPUT" 2>&1 | tee "$HEAL_LOG"; then
    HEAL_STATUS="pass"
else
    HEAL_STATUS="fail"
fi

step "Re-running editor excellence gate"
if bash "$SCRIPT_DIR/test_editor_excellence.sh"; then
    STATUS="pass"
    FAIL_REASON=""
    pass "Editor excellence CI recovered after diagnostics"
else
    fail "Editor excellence gate still failing after diagnostics"
fi
