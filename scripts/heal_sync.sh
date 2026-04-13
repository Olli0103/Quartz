#!/usr/bin/env bash
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
OUTPUT_PATH="${2:-reports/self_heal/sync.json}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

PERSISTENCE_REFS=$(rg -n "TranscriptPersistenceService|MeetingCaptureOrchestrator|CoordinatedFileWriter\.shared" \
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Audio" 2>/dev/null | wc -l | tr -d ' ')
BOOKMARK_REFS=$(rg -n "lastVault|bookmark|restoreLastVault" \
    Quartz QuartzKit/Sources/QuartzKit/Domain/Vault 2>/dev/null | wc -l | tr -d ' ')

if swift test --package-path "$PACKAGE_PATH" --filter "Transcript|Persistence|Meeting|Sync" >/tmp/quartz_phase4_sync_heal.log 2>&1; then
    RERUN_STATUS="pass"
    RERUN_EXIT=0
else
    RERUN_STATUS="fail"
    RERUN_EXIT=1
fi

cat > "$OUTPUT_PATH" <<JSON
{
  "category": "sync",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "persistence_references": $PERSISTENCE_REFS,
  "bookmark_references": $BOOKMARK_REFS,
  "rerun_status": "$RERUN_STATUS",
  "rerun_log": "/tmp/quartz_phase4_sync_heal.log"
}
JSON

if [ "$PERSISTENCE_REFS" -lt 3 ] || [ "$BOOKMARK_REFS" -lt 3 ] || [ "$RERUN_EXIT" -ne 0 ]; then
    exit 1
fi
