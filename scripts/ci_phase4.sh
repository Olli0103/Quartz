#!/usr/bin/env bash
# scripts/ci_phase4.sh — Phase 4 CI: Audio Intelligence & Scan-to-Markdown
#
# Usage: bash scripts/ci_phase4.sh
# Exit code: 0 = success, 1 = failure
set -euo pipefail

PACKAGE_PATH="QuartzKit"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Clean up heal category tracker from previous runs
rm -f /tmp/quartz_heal_categories.txt

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
fail() { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }

# ── Self-Healing: Failure Classification ─────────────────────────────
classify_failures() {
    local output="$1"
    echo -e "${YELLOW}${BOLD}Failure Classification:${RESET}"
    echo "$output" | grep -E "failed after|Test Case.*failed" | while read -r line; do
        case "$line" in
            *Audio*|*Capture*|*Metering*|*RingBuffer*|*Chunk*)
                echo -e "  ${YELLOW}[AUDIO]${RESET} $line"
                echo "    → Check: AVAudioEngineCaptureService, AudioChunkRingBuffer, AudioRecordingService"
                echo "AUDIO" >> /tmp/quartz_heal_categories.txt ;;
            *Transcri*|*Speech*|*Language*|*Diariz*)
                echo -e "  ${YELLOW}[TRANSCRIPTION]${RESET} $line"
                echo "    → Check: StreamingTranscriptionService, SpeakerDiarizationService, LanguageDetector"
                echo "TRANSCRIPTION" >> /tmp/quartz_heal_categories.txt ;;
            *OCR*|*Scan*|*Handwriting*|*Markdown*Mapper*)
                echo -e "  ${YELLOW}[OCR]${RESET} $line"
                echo "    → Check: OCRMarkdownMapper, HandwritingOCRService, VisionKit integration"
                echo "OCR" >> /tmp/quartz_heal_categories.txt ;;
            *Meeting*|*Minutes*|*Persist*|*Transcript*)
                echo -e "  ${YELLOW}[PERSISTENCE]${RESET} $line"
                echo "    → Check: MeetingMinutesService, TranscriptPersistenceService, CoordinatedFileWriter"
                echo "PERSISTENCE" >> /tmp/quartz_heal_categories.txt ;;
            *Accessibility*|*VoiceOver*|*ReduceMotion*|*Capsule*)
                echo -e "  ${YELLOW}[ACCESSIBILITY]${RESET} $line"
                echo "    → Check: LiveCapsuleOverlay, PulseModifier, accessibility labels"
                echo "ACCESSIBILITY" >> /tmp/quartz_heal_categories.txt ;;
            *Hardware*|*Capability*|*Microphone*|*Camera*)
                echo -e "  ${YELLOW}[HARDWARE]${RESET} $line"
                echo "    → Check: HardwareCapability, platform conditionals, AVAudioSession availability"
                echo "HARDWARE" >> /tmp/quartz_heal_categories.txt ;;
            *Performance*|*Budget*|*Memory*|*Latency*)
                echo -e "  ${YELLOW}[PERFORMANCE]${RESET} $line"
                echo "    → Check: Ring buffer memory budget, 60-min session tests, main thread budget"
                echo "PERFORMANCE" >> /tmp/quartz_heal_categories.txt ;;
            *)
                echo -e "  ${YELLOW}[GENERAL]${RESET} $line"
                echo "    → Check: Test isolation, mock setup, async timing" ;;
        esac
    done
}

# ── Step 1: Phase 3 regression gate ─────────────────────────────────
step "Running Phase 3 CI (regression gate)"
if bash scripts/ci_phase3.sh 2>&1; then
    pass "Phase 3 regression gate passed"
else
    fail "Phase 3 regression gate failed — fix Phase 3 before proceeding"
fi

# ── Step 2: Phase 4 specific tests ──────────────────────────────────
step "Running Phase 4 audio & scan tests"
P4_FILTER="Phase4AudioMemoryBudget|Phase4AudioInterruption|Phase4HardwareCapability|Phase4E2EFlow|Phase4LiveCapsuleAccessibility|Phase4ScanAccessibility|Phase4StreamingTranscription|AudioPipelineIntegration|DiarizationMapping|LanguageDetection|RecorderCompactUI"
P4_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --filter "$P4_FILTER" 2>&1 || true)
P4_PASS=$(echo "$P4_OUTPUT" | grep -c "passed" || true)
P4_FAIL=$(echo "$P4_OUTPUT" | grep -cE "failed after|Test Case.*failed" || true)
echo "  Phase 4 suites passed: $P4_PASS"
echo "  Phase 4 tests failed: $P4_FAIL"
if [ "$P4_FAIL" -gt 0 ]; then
    classify_failures "$P4_OUTPUT"
    fail "Phase 4 test failures: $P4_FAIL"
fi
pass "Phase 4 tests all passed"

# ── Step 3: Full test suite ──────────────────────────────────────────
step "Running full test suite (Phase 1 + Phase 2 + Phase 3 + Phase 4)"
FULL_OUTPUT=$(swift test --package-path "$PACKAGE_PATH" --parallel 2>&1 || true)
FULL_PASS=$(echo "$FULL_OUTPUT" | grep -c "passed" || true)
FULL_FAIL=$(echo "$FULL_OUTPUT" | grep -cE "failed after|Test Case.*failed" || true)
echo "  Total suites passed: $FULL_PASS"
echo "  Total tests failed: $FULL_FAIL"
if [ "$FULL_FAIL" -gt 0 ]; then
    classify_failures "$FULL_OUTPUT"
    fail "Test failures: $FULL_FAIL (zero tolerance)"
fi
pass "Full suite completed (zero failures)"

# ── Step 4: Count Phase 4 @Test annotations ─────────────────────────
step "Counting Phase 4 @Test annotations"
P4_COUNT=0
for f in "$PACKAGE_PATH"/Tests/QuartzKitTests/Phase4*.swift; do
    if [ -f "$f" ]; then
        C=$(grep -c "@Test" "$f" || true)
        P4_COUNT=$((P4_COUNT + C))
    fi
done
echo "  Found $P4_COUNT Phase 4 @Test annotations"
if [ "$P4_COUNT" -lt 30 ]; then
    fail "Expected at least 30 Phase 4 @Test annotations, found $P4_COUNT"
fi
pass "Phase 4 @Test count: $P4_COUNT (>= 30)"

# ── Step 5: Total @Test budget check ────────────────────────────────
step "Checking total @Test budget"
TOTAL_TESTS=$(grep -r "@Test" "$PACKAGE_PATH/Tests/" --include="*.swift" | wc -l | tr -d ' ')
echo "  Total @Test annotations: $TOTAL_TESTS"
if [ "$TOTAL_TESTS" -gt 1200 ]; then
    fail "Total @Test count ($TOTAL_TESTS) exceeds budget of 1200"
fi
pass "Total @Test budget: $TOTAL_TESTS (<= 1200)"

# ── Step 6: Source file verification ─────────────────────────────────
step "Verifying Phase 4 source files exist"
P4_SOURCES=(
    "Domain/Audio/AudioChunkRingBuffer.swift"
    "Domain/Audio/AVAudioEngineCaptureService.swift"
    "Domain/Audio/HardwareCapability.swift"
    "Domain/Audio/LanguageDetector.swift"
    "Domain/Audio/MeetingCaptureOrchestrator.swift"
    "Domain/Audio/StreamingTranscriptionService.swift"
    "Domain/Audio/TranscriptPersistenceService.swift"
    "Domain/Audio/MeetingMinutesService.swift"
    "Domain/Audio/SpeakerDiarizationService.swift"
    "Domain/OCR/OCRMarkdownMapper.swift"
    "Presentation/Audio/LiveCapsuleOverlay.swift"
)
MISSING=0
for src in "${P4_SOURCES[@]}"; do
    if [ ! -f "$PACKAGE_PATH/Sources/QuartzKit/$src" ]; then
        echo -e "  ${RED}MISSING: $src${RESET}"
        MISSING=$((MISSING + 1))
    fi
done
if [ "$MISSING" -gt 0 ]; then
    fail "$MISSING Phase 4 source files missing"
fi
pass "All Phase 4 source files present"

# ── Step 7: Generate reports ──────────────────────────────────────────
step "Generating Phase 4 report"
mkdir -p reports

cat > reports/phase4_report.json <<REPORT_EOF
{
  "phase": 4,
  "status": "pass",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tests": {
    "total": $TOTAL_TESTS,
    "phase4_specific": $P4_COUNT,
    "full_suite_failed": $FULL_FAIL,
    "full_suite_passed": $FULL_PASS
  },
  "phase4_suites": [
    "Phase4AudioMemoryBudgetTests",
    "Phase4AudioInterruptionTests",
    "Phase4HardwareCapabilityTests",
    "Phase4E2EFlowTests",
    "Phase4LiveCapsuleAccessibilityTests",
    "Phase4ScanAccessibilityTests",
    "Phase4AudioCaptureTests",
    "Phase4AudioPerformanceTests",
    "Phase4EditorTests",
    "Phase4SidebarDashboardTests",
    "Phase4TypedEventingTests"
  ],
  "linear_issues_covered": [
    "OLL-34: AVAudioEngine capture graph",
    "OLL-35: Streaming ASR with SFSpeechRecognizer",
    "OLL-36: Speaker diarization (K-Means + Accelerate)",
    "OLL-37: Meeting minutes templates",
    "OLL-38: Transcript persistence as markdown",
    "OLL-39: Live capsule overlay UI",
    "OLL-40: Handwriting OCR service",
    "OLL-41: OCR-to-Markdown mapping engine",
    "OLL-42: VisionKit document scanning",
    "OLL-43: Audio recording service",
    "OLL-44: Language detection",
    "OLL-45: Meeting capture orchestrator",
    "OLL-61: Hardware capability gating",
    "OLL-62: Audio interruption handling",
    "OLL-63: Capture service state machine",
    "OLL-64: Ring buffer memory budget"
  ]
}
REPORT_EOF
pass "Report written to reports/phase4_report.json"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Phase 4 CI completed — PASS${RESET}"
echo "  Total @Test annotations: $TOTAL_TESTS"
echo "  Phase 4 @Test count: $P4_COUNT"
echo "  Full suite failures: $FULL_FAIL"
exit 0
