# Editor Future Backlog

This backlog is intentionally separate from the completed M1-M5 work and the shipped in-note find/replace feature.

## Product Feature

### Now

- Richer backlinks workflow and performance
  - Tag: product feature
  - Priority: now
  - Notes: inspector surfacing is real, but backlink loading still depends on async vault scanning and the overall interlinking workflow is still basic

### Later

- True live typewriter mode
  - Tag: product feature
  - Priority: later
- Live preview mode
  - Tag: product feature
  - Priority: later
- Folding
  - Tag: product feature
  - Priority: later
- Callouts
  - Tag: product feature
  - Priority: later
- Link previews
  - Tag: product feature
  - Priority: later
- Long-form writing polish
  - Tag: product feature
  - Priority: later
- Regex search mode
  - Tag: product feature
  - Priority: later
- Whole-word search mode
  - Tag: product feature
  - Priority: later

## Performance

### Now

- Stabilize full-suite editor performance budgets under repository load
  - Tag: performance
  - Priority: now
  - Notes: focused reruns pass, but the full package test run still produces load-sensitive failures in editor performance suites

### Later

- Additional long-document profiling and cache tuning once repository-wide test stability improves
  - Tag: performance
  - Priority: later

## Polish

### Later

- In-note find/replace polish beyond the shipped baseline
  - Tag: polish
  - Priority: later
  - Notes: consider optional case sensitivity, optional whole-word controls, and stronger platform-specific interaction refinement
- Broader writing-environment calmness and micro-interaction finish
  - Tag: polish
  - Priority: later

### Optional

- Additional command/menu refinement once higher-priority product gaps close
  - Tag: polish
  - Priority: optional

## Infrastructure

### Now

- TextKit poison-pill circuit-breaker test follow-up
  - Tag: infrastructure
  - Priority: now
  - Notes: `TextKitPoisonPillTests.testCircuitRecovery` remains a deterministic red test outside the editor release slice

### Later

- Continue reducing repository-wide warning noise and test-environment coupling
  - Tag: infrastructure
  - Priority: later
- Review whether canonical path identity should eventually evolve toward a deeper file-identity model
  - Tag: infrastructure
  - Priority: later
  - Notes: not required for the shipped editor stabilization, but worth revisiting if future file-provider complexity increases

## Test Reliability

### Now

- Repo-wide non-editor test cleanup
  - Tag: test reliability
  - Priority: now
- Intelligence engine stress test stabilization
  - Tag: test reliability
  - Priority: now
  - Notes: `Status progress updates correctly during batch indexing` is still red in the full package suite
- iPhone shell UI host-launch flake containment
  - Tag: test reliability
  - Priority: now
  - Notes: one full-gate rerun timed out waiting for the note list; focused retry passed
- macOS shell UI harness hang containment
  - Tag: test reliability
  - Priority: now
  - Notes: a full `test_editor_excellence.sh` rerun stalled in the macOS shell coverage segment, while focused macOS shell tests still passed

### Later

- Broader host-sensitive UI test stabilization and simulator-environment hardening
  - Tag: test reliability
  - Priority: later

## Optional

- Future exploration of richer export/publishing polish after the current editor cycle is fully absorbed
  - Tag: product feature
  - Priority: optional
