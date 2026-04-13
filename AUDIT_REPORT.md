# Gatekeeper Audit: Phase 4 — Audio Intelligence & Scan-to-Markdown

## 🛑 PASS / FAIL STATUS (Make this explicit in huge text)

# ❌ FAIL

Phase 4 is not passable yet. The shell/report provenance issues called out in the earlier audit are largely remediated, macOS smoke coverage is now green again, and the onboarding/accessibility logic failures were reduced to zero reproducible code failures. The remaining blocker is a simulator install/clone flake in the iPhone UI leg plus the absence of a fresh full Phase 4 green artifact from current HEAD.

## 🔍 Discovered Violations (List every shortcut, lazy test, and architectural breach)

### 1. Phase 4 still lacks a fresh end-to-end green artifact from current HEAD
- [`reports/phase4_report.json`](/Users/I533181/Developments/Quartz/reports/phase4_report.json) is still `fail`.
- The most recent full Phase 4 rerun never reached a final regenerated green artifact after the latest onboarding/mock-vault fixes, the simulator target update, and the serial UI-runner fix.

### 2. The remaining blocker is now the iPhone simulator execution path, not the earlier shell/report shortcuts
- `scripts/ci_phase4.sh` now invokes the real lower-phase regression gates, xcodebuild UI legs, coverage extraction, and self-healing hooks.
- `scripts/ci_phase4.sh` now targets the newer `iPhone 17` simulator instead of the stale `iPhone 16 Pro` runtime in this environment.
- `scripts/ci_phase3.sh` and `scripts/ci_phase4.sh` now force `-parallel-testing-enabled NO` for Quartz UI matrix runs so Xcode does not shard UI tests across cloned simulators.
- `scripts/ci_phase2.sh` and `scripts/ci_phase3.sh` were corrected so they no longer reject the tree because later-phase suites exist or because an arbitrary `@Test` ceiling was exceeded.
- Current remaining failure evidence is dominated by simulator install flake (`IXErrorDomain` / `Failed to locate promise`) during the iPhone UI run, not by a reproduced app-behavior regression.

### 3. Onboarding UI tests were launching with the wrong contract
- The UI test plan globally injected `--mock-vault`, so first-launch onboarding tests were skipping onboarding entirely.
- Fix applied: [`QuartzApp.swift`](/Users/I533181/Developments/Quartz/Quartz/QuartzApp.swift) now honors `--force-onboarding` over `--mock-vault`, and [`QuartzUITests.swift`](/Users/I533181/Developments/Quartz/QuartzUITests/QuartzUITests.swift) uses that flag for onboarding/accessibility first-launch coverage.
- Focused verification on the updated tree showed `WelcomeScreenTests`, `OnboardingFlowTests`, and `AccessibilityUITests` all reaching runtime, with 8 of 9 cases passing and the lone failure attributed by the `.xcresult` to simulator app-install failure rather than a UI assertion.

### 4. Mock-vault workspace launch was still too indirect for deterministic smoke tests
- UI smoke tests depended on bookmark restoration races instead of opening the fixture vault directly.
- Fix applied: [`QuartzApp.swift`](/Users/I533181/Developments/Quartz/Quartz/QuartzApp.swift) now persists the fixture vault path, and [`ContentView.swift`](/Users/I533181/Developments/Quartz/Quartz/ContentView.swift) opens the fixture vault directly on `--mock-vault` launches.
- Result: focused macOS smoke coverage now passes locally end-to-end.

### 5. Strict-concurrency cleanup improved, but the UI matrix remains the ship gate
- The earlier scan-flow escape hatch in [`DocumentScannerView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/DocumentScannerView.swift) was removed.
- Actor teardown now uses `MainActor.assumeIsolated` in the affected stores/session types instead of ineffective `nonisolated(unsafe)` markers.
- Phase 1 is green again with zero concurrency diagnostics in [`reports/phase1_report.json`](/Users/I533181/Developments/Quartz/reports/phase1_report.json).

### 6. Accessibility layout on onboarding was hardened, but the final serial iPhone rerun still needs to be captured
- [`OnboardingView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Onboarding/OnboardingView.swift) now compresses spacing for accessibility Dynamic Type and improves the welcome CTA's accessibility hint.
- Focused SwiftPM onboarding coverage passed after this change.
- The remaining evidence gap is a clean serial iPhone UI artifact, not a known layout assertion.

### 7. Snapshot proof is materially better but still not enough without the final UI rerun
- The Phase 4 snapshot matrix now includes macOS, iOS, and iPadOS baselines in [`__Snapshots__/Phase4SnapshotMatrixTests`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/__Snapshots__/Phase4SnapshotMatrixTests).
- The full Phase 4 gate still needs a fresh passing report from current HEAD to make that evidence authoritative.

## 🔨 Remediation Orders (Direct terminal commands for Claude Code to fix the violations)

```bash
# 1. Re-run the full Phase 4 gate from the current tree
bash scripts/ci_phase4.sh

# 2. If the gate still stops in the iPhone UI matrix, verify the serial iPhone path directly
xcodebuild test-without-building -scheme Quartz -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,id=700E29D0-5317-4D0A-A39A-9BB73A62E952' \
  -only-testing:QuartzUITests/WelcomeScreenTests \
  -only-testing:QuartzUITests/OnboardingFlowTests \
  -only-testing:QuartzUITests/AccessibilityUITests

# 3. Verify direct mock-vault workspace launch on macOS
xcodebuild test -scheme Quartz -destination 'platform=macOS' \
  -only-testing:QuartzUITests/macOSSmokeUITests

# 4. Inspect the last focused iPhone xcresult if install flake reappears
xcrun xcresulttool get object --legacy \
  --path '/Users/I533181/Library/Developer/Xcode/DerivedData/Quartz-dxdgbevcngpjbfeajptuwkhctcba/Logs/Test/Test-Quartz-2026.04.13_11-36-24-+0200.xcresult' \
  --format json

# 5. Regenerate the Phase 4 report only after the UI matrix is green
cat reports/phase4_report.json
git diff -- reports/phase4_report.json AUDIT_REPORT.md
```
