# Quartz Checkpoint

Date: 2026-04-13

Current state:
- Phase 3 CI is green again.
- macOS, iPhone, and iPad UI matrix passed in `scripts/ci_phase3.sh`.
- Phase 4 `LiveCapsule` snapshot harness is fixed to force deterministic host appearance.
- Phase 4 macOS snapshot baselines were refreshed and `Phase4SnapshotMatrixTests` now pass.
- Phase 3 macOS snapshot harnesses were fixed the same way.
- `Phase3AccessibilityTraversalTests` pass.
- `Phase3SnapshotMatrixTests` baselines were refreshed and now pass.

Current blocker before final green Phase 4:
- Long full-suite `swift test --package-path QuartzKit` intermittently hits
  `swiftpm-testing-helper ... unexpected signal code 10`.
- `scripts/ci_phase1.sh` and `scripts/ci_phase4.sh` were patched to detect that
  specific helper crash and retry the full SwiftPM suite serially.
- Final end-to-end verification of the patched retry path is still pending.

Simulator note:
- `iPhone 16 Pro` was stuck in `Shutting Down` during this session.
- CI scripts now fall back to a stable available iPhone simulator when needed.

Next command after reboot:
```bash
bash scripts/ci_phase4.sh
```

If that passes:
- refresh `AUDIT_REPORT.md` if needed
- review `reports/phase4_report.json`

