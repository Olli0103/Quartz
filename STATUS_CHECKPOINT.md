# Quartz Checkpoint

Date: 2026-04-14

Current state:
- Phase 4 is complete.
- The authoritative full-gate artifact is green in `reports/phase4_report.json`.
- Phase 4.5 editor rebuild is in progress and the macOS editor slice is materially stronger.
- Landed in the worktree:
  - reality corpus + roundtrip harness for known editor regressions
  - macOS editor snapshots for heading/paragraph drift and concealment behavior
  - token-aware `hiddenUntilCaret` instead of line-aware reveal logic
  - live mounted editor regression tests for:
    - programmatic edit snapshot sync
    - list continuation selection stability through rehighlighting
    - mutation-origin preservation through delegate echo
    - native Return after heading dropping to paragraph typing attributes
- The focused macOS editor proof is green:
  - `swift test --package-path QuartzKit --filter 'EditorReality(Corpus|Roundtrip|Snapshot)Tests|EditorRenderingRegressionTests|EditorLiveMutationRegressionTests'`
  - result: `22 tests, 0 failures`

Next focus:
```bash
# Continue Phase 4.5 from the editor live-edit path.
# Highest-value next steps:
# 1. live paste / multi-paragraph mutation stability
# 2. undo/redo coverage on mounted editor flows where appropriate
# 3. iPhone/iPad parity for the editor snapshot/live harness
```
