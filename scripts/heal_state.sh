#!/usr/bin/env bash
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
OUTPUT_PATH="${2:-reports/self_heal/state.json}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

TEXTKIT_WIRING=$(rg -n "MarkdownTextKit2Stack\.makeContentManager|MarkdownTextKit2Stack\.wireTextKit2" \
    "$PACKAGE_PATH/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift" 2>/dev/null | wc -l | tr -d ' ')
COORDINATED_IO=$(rg -n "NSFileCoordinator|CoordinatedFileWriter\.shared" \
    "$PACKAGE_PATH/Sources/QuartzKit/Data/FileSystem/CoordinatedFileWriter.swift" \
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Audio/TranscriptPersistenceService.swift" 2>/dev/null | wc -l | tr -d ' ')
HARDWARE_MACROS=$(rg -n "#if os\(iOS\)|#if os\(macOS\)|#if canImport\(VisionKit\)" \
    "$PACKAGE_PATH/Sources/QuartzKit/Domain/Audio/HardwareCapability.swift" 2>/dev/null | wc -l | tr -d ' ')

if swift test --package-path "$PACKAGE_PATH" --filter "Phase4Editor|Phase4HardwareCapability|Phase4E2EFlow" >/tmp/quartz_phase4_state_heal.log 2>&1; then
    RERUN_STATUS="pass"
    RERUN_EXIT=0
else
    RERUN_STATUS="fail"
    RERUN_EXIT=1
fi

cat > "$OUTPUT_PATH" <<JSON
{
  "category": "state",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "textkit_wiring_references": $TEXTKIT_WIRING,
  "coordinated_io_references": $COORDINATED_IO,
  "hardware_macro_references": $HARDWARE_MACROS,
  "rerun_status": "$RERUN_STATUS",
  "rerun_log": "/tmp/quartz_phase4_state_heal.log"
}
JSON

if [ "$TEXTKIT_WIRING" -lt 4 ] || [ "$COORDINATED_IO" -lt 2 ] || [ "$HARDWARE_MACROS" -lt 3 ] || [ "$RERUN_EXIT" -ne 0 ]; then
    exit 1
fi
