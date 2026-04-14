# Quartz Checkpoint

Date: 2026-04-14

Current state:
- Phase 4 is complete.
- The authoritative full-gate artifact is green in `reports/phase4_report.json`.
- Phase 4.5 editor rebuild is in progress.
- The macOS editor slice is materially stronger, but mobile parity is still a hard blocker.
- Landed in the worktree:
  - reality corpus + roundtrip harness for known editor regressions
  - macOS editor snapshots for heading/paragraph drift and concealment behavior
  - token-aware `hiddenUntilCaret` instead of line-aware reveal logic
  - live mounted editor regression tests for:
    - programmatic edit snapshot sync
    - list continuation selection stability through rehighlighting
    - mutation-origin preservation through delegate echo
    - native Return after heading dropping to paragraph typing attributes
    - mounted undo/redo roundtrip without AppKit undo corruption
    - mounted bold-formatting stability through forced highlight
    - heading-to-paragraph formatting roundtrip with clean body typing state
  - dedicated editor gate and self-heal path:
    - `bash scripts/test_editor_excellence.sh`
    - `bash scripts/ci_phase4_5_editor.sh`
    - `bash scripts/heal_editor.sh`
- The focused macOS editor proof is green:
  - `swift test --package-path QuartzKit --filter 'EditorReality(Corpus|Roundtrip|Snapshot)Tests|EditorRenderingRegressionTests|EditorLiveMutationRegressionTests'`
  - result: `26 tests, 0 failures`

Next focus:
```bash
# Continue Phase 4.5 from the editor parity path.
# Highest-value next steps:
# 1. iPhone parity for the editor snapshot/live harness
# 2. iPad parity for the editor snapshot/live harness
# 3. mobile live-mutation parity for formatting, paste, undo/redo, and typing context
# 4. productized paste normalization policy informed by the competitive intake rules
```
