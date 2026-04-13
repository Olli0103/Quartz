#!/usr/bin/env bash
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
OUTPUT_PATH="${2:-reports/self_heal/snapshots.json}"
SNAPSHOT_DIR="$PACKAGE_PATH/Tests/QuartzKitTests/__Snapshots__/Phase4SnapshotMatrixTests"
EXPECTED_CASES=11
EXPECTED_PLATFORMS=3
EXPECTED_TOTAL=$((EXPECTED_CASES * EXPECTED_PLATFORMS))

mkdir -p "$(dirname "$OUTPUT_PATH")"

MISSING_RECORD_MODE=$(rg -n "record:\s*\.missing" "$PACKAGE_PATH/Tests/QuartzKitTests/Phase4SnapshotMatrixTests.swift" 2>/dev/null | wc -l | tr -d ' ')
MISSING_RECORD_MODE=${MISSING_RECORD_MODE:-0}
BASELINE_COUNT=$(find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
BASELINE_COUNT=${BASELINE_COUNT:-0}

if swift test --package-path "$PACKAGE_PATH" --filter "Phase4SnapshotMatrixTests" >/tmp/quartz_phase4_snapshot_heal.log 2>&1; then
    RERUN_STATUS="pass"
    RERUN_EXIT=0
else
    RERUN_STATUS="fail"
    RERUN_EXIT=1
fi

cat > "$OUTPUT_PATH" <<JSON
{
  "category": "snapshots",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "record_missing_references": $MISSING_RECORD_MODE,
  "baseline_count": $BASELINE_COUNT,
  "expected_baseline_count": $EXPECTED_TOTAL,
  "rerun_status": "$RERUN_STATUS",
  "rerun_log": "/tmp/quartz_phase4_snapshot_heal.log"
}
JSON

if [ "$MISSING_RECORD_MODE" -gt 0 ] || [ "$BASELINE_COUNT" -lt "$EXPECTED_TOTAL" ] || [ "$RERUN_EXIT" -ne 0 ]; then
    exit 1
fi
