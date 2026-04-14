#!/usr/bin/env bash
# Developer slice: Phase 3 SwiftPM accessibility and platform tests only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

PACKAGE_PATH="${PACKAGE_PATH:-QuartzKit}"
LOG_PATH="${LOG_PATH:-reports/phase3_swiftpm.log}"
P3_FILTER="${P3_FILTER:-VoiceOverEditor|VoiceOverSidebar|DynamicTypeScaling|ReduceMotionAnimation|ContrastCompliance|VoiceControlCommand|PlatformNavigation|FocusModeIntegration|DesignTokenConsistency|E2ECreateNote|E2ESearchFlow|E2EAppearanceFlow}"

step "Running Phase 3 SwiftPM slice"
echo "  Log: $LOG_PATH"
echo "  Filter: $P3_FILTER"

if swift test --package-path "$PACKAGE_PATH" --filter "$P3_FILTER" 2>&1 | tee "$LOG_PATH"; then
    pass "Phase 3 SwiftPM slice passed"
else
    fail "Phase 3 SwiftPM slice failed"
fi
