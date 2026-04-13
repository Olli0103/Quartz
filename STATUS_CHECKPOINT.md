# Quartz Checkpoint

Date: 2026-04-13

Current state:
- The last full `scripts/ci_phase4.sh` attempt got all the way through the nested
  Phase 3 regression gate and returned `✓ Phase 3 regression gate passed`.
- The focused Phase 4 SwiftPM suites also returned green:
  `214` pass markers, `0` failure markers.
- The old TextKit circuit-breaker failure is fixed in
  `QuartzKit/Sources/QuartzKit/Infrastructure/CircuitBreaker/TextKitCircuitBreaker.swift`.
- The Phase 4 runner is hardened in `scripts/ci_phase4.sh`:
  it now writes real iPhone/iPad result bundle paths, detects actual test failures
  before helper-crash noise, and retries the full SwiftPM suite serially when the
  SwiftPM helper dies with signal 10.
- A real full-suite regression was then isolated to `Live Table Rendering`:
  `Table has header, divider, and body row styles`
  and `Table spans cover all table lines`.
- That table regression is patched in
  `QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift`
  by expanding `Markdown.Table` ranges to the full contiguous table block before
  emitting spans.
- Isolated verification after the patch:
  `swift test --package-path QuartzKit --filter LiveTableRenderingTests`
  now passes `5/5`.

Current blocker before final green Phase 4:
- The full end-to-end Phase 4 rerun was interrupted for checkpointing while it had
  restarted from the top. Final proof is still pending:
  the patched table renderer must be revalidated inside a fresh full
  `scripts/ci_phase4.sh` pass.
- `reports/phase4_report.json` is currently absent because the interrupted script
  removes and rewrites it during execution.

Simulator note:
- `iPhone 16 Pro` was online and used successfully in the last passing Phase 3/iPhone run.
- `iPad Pro 13-inch (M5)` also ran successfully during the last full Phase 3 gate.

Next command after reboot:
```bash
bash scripts/ci_phase4.sh
```

If that passes:
- refresh `AUDIT_REPORT.md` if needed
- review `reports/phase4_report.json`

If it fails again:
- inspect `reports/phase4_swiftpm_full.log` first
- the next most likely remaining debt is the non-fatal launch-screen warning in `Info.plist`
