# Quartz Checkpoint

Date: 2026-04-14

Current state:
- Phase 4 is complete.
- The authoritative full-gate artifact is green in `reports/phase4_report.json`.
- Phase 4.5 editor rebuild is complete.
- The authoritative editor-gate artifact is green in `reports/editor_excellence_report.json`.
- Landed in the worktree:
  - reality corpus + roundtrip harness for known editor regressions
  - editor snapshots for macOS, iPhone, and iPad
  - token-aware `hiddenUntilCaret` instead of line-aware reveal logic
  - Bear-style `hiddenUntilCaret` default with explicit full-syntax toggle
  - `smart` and `raw` paste policy
  - semantic editor document + plan-based primary renderer
  - live mounted editor regression tests for:
    - programmatic edit snapshot sync
    - list continuation selection stability through rehighlighting
    - mutation-origin preservation through delegate echo
    - native Return after heading dropping to paragraph typing attributes
    - mounted undo/redo roundtrip without AppKit undo corruption
    - mounted bold-formatting stability through forced highlight
    - heading-to-paragraph formatting roundtrip with clean body typing state
    - multiline semantic list and paragraph transforms
    - line-aware code-fence and mermaid wrapping
  - dedicated editor gate and self-heal path:
    - `bash scripts/test_editor_excellence.sh`
    - `bash scripts/ci_phase4_5_editor.sh`
    - `bash scripts/heal_editor.sh`
- The editor ship gate is green:
  - `bash scripts/test_editor_excellence.sh`
  - `bash scripts/ci_phase4_5_editor.sh`
  - `reports/editor_excellence_report.json` => `pass`

Next focus:
```bash
# Phase 4.5 is closed. Phase 5 is unblocked.
# Keep the editor gate authoritative for follow-up editor changes:
bash scripts/test_editor_excellence.sh
bash scripts/ci_phase4_5_editor.sh
```
