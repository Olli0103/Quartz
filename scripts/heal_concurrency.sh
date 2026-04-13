#!/usr/bin/env bash
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
OUTPUT_PATH="${2:-reports/self_heal/concurrency.json}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

UNSAFE_COUNT=$(rg -n "@unchecked Sendable|DispatchQueue\.main\.async|@preconcurrency|try! await" \
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Audio" \
    "$PACKAGE_PATH/Sources/QuartzKit/Presentation/Editor" 2>/dev/null | wc -l | tr -d ' ')
UNSAFE_COUNT=${UNSAFE_COUNT:-0}

if swift test --package-path "$PACKAGE_PATH" --filter "Phase4StreamingTranscription|Phase4TypedEventing|Phase4LiveCapsuleAccessibility" >/tmp/quartz_phase4_concurrency_heal.log 2>&1; then
    RERUN_STATUS="pass"
    RERUN_EXIT=0
else
    RERUN_STATUS="fail"
    RERUN_EXIT=1
fi

cat > "$OUTPUT_PATH" <<JSON
{
  "category": "concurrency",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "unsafe_pattern_count": $UNSAFE_COUNT,
  "rerun_status": "$RERUN_STATUS",
  "rerun_log": "/tmp/quartz_phase4_concurrency_heal.log"
}
JSON

if [ "$UNSAFE_COUNT" -gt 0 ] || [ "$RERUN_EXIT" -ne 0 ]; then
    exit 1
fi
