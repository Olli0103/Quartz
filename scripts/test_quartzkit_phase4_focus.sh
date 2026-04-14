#!/usr/bin/env bash
# Developer slice: focused Phase 4 SwiftPM suites only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/ui_test_helpers.sh"

cd "$REPO_ROOT"
mkdir -p reports

PACKAGE_PATH="${PACKAGE_PATH:-QuartzKit}"
LOG_PATH="${LOG_PATH:-reports/phase4_swiftpm_phase4.log}"
P4_FILTER="${P4_FILTER:-Phase4AudioMemoryBudget|Phase4AudioInterruption|Phase4HardwareCapability|Phase4E2EFlow|Phase4LiveCapsuleAccessibility|Phase4ScanAccessibility|Phase4StreamingTranscription|Phase4TypedEventing|AudioPipelineIntegration|DiarizationMapping|LanguageDetection|RecorderCompactUI|Phase4ProductionHotPath|Phase4ProcessRSS|Phase4P95Latency|Phase4IntegratedWorkload|Phase4Editor|Phase4SnapshotMatrix}"

step "Running focused Phase 4 SwiftPM suites"
echo "  Log: $LOG_PATH"
echo "  Filter: $P4_FILTER"

if swift test --package-path "$PACKAGE_PATH" --filter "$P4_FILTER" 2>&1 | tee "$LOG_PATH"; then
    pass "Focused Phase 4 SwiftPM suites passed"
else
    fail "Focused Phase 4 SwiftPM suites failed"
fi
