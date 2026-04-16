# Test Stabilization Plan

## Improvements Made

### Deterministic state isolation

- `TextKitCircuitBreaker` test coverage no longer depends on shared singleton state.
- Poison-pill and circuit-breaker tests now construct isolated breaker instances, which removes cross-test contamination under concurrent execution.

### Coordinator-specific observation

- `IntelligenceEngineCoordinator` now publishes status notifications through a stable coordinator-specific sender object.
- Stress tests subscribe only to the coordinator under test instead of listening to all engine notifications in process.
- Stress tests now await teardown and use condition polling instead of fixed sleeps.

### Harness timeout and reset behavior

- `scripts/lib/ui_test_helpers.sh` now runs `xcodebuild` through a hard timeout wrapper.
- On timeout, the harness now:
  - terminates stale runners
  - terminates stray app processes
  - resets simulator state
  - retries once

This prevents the old silent indefinite hang behavior.

### Zero-test protection

- The xcodebuild wrapper now treats `Executed 0 tests` as a failure instead of a success.
- This closes a false-green gap in the shell/UI harness.

### Shell UI filter integrity

- `scripts/test_editor_excellence.sh` now uses explicit method-level `-only-testing` identifiers for shell UI coverage instead of relying on class-level filters that could silently match nothing.

### Clear parity failure reporting

- The editor excellence script now surfaces the iOS parity blocker explicitly:
  - `QuartzKit` scheme has no runnable `xcodebuild test` action for simulator parity in the current configuration

## Why These Changes Were Needed

- Shared singleton state was making deterministic tests non-deterministic.
- Global notification observation was causing cross-test interference in the intelligence engine stress suite.
- The previous harness could hang without a reason, which is worse than a red test because it destroys triage velocity.
- A zero-test “success” is operationally invalid and had to be treated as a harness failure.
- The remaining parity blocker is configuration-level, so the script had to report that precisely instead of looking like another random UI stall.

## What Still Remains Risky

### 1. Package iOS parity configuration

`test_editor_excellence.sh` still cannot complete end-to-end because the current `QuartzKit` scheme is not configured for `xcodebuild test` on iOS simulator destinations.

This is not a silent failure anymore, but it is still a blocker to a fully green end-to-end gate.

### 2. Full-run performance budgets

`EditorPerformanceTests` and `EditorPerformanceBudgetTests` pass in focused reruns but can still fail in a saturated full `swift test` process.

That means:
- the editor is not obviously wrong
- the repository still has load-sensitive budget instability

### 3. iOS shell UI host sensitivity

Direct focused iOS shell UI execution remains host-sensitive on this machine. The harness is now stricter and more honest about that, but the underlying runtime sensitivity has not been fully eliminated.

## Recommended Follow-Up

### Now

- Decide how simulator parity should actually run:
  - add a real test action for the `QuartzKit` simulator parity path, or
  - move the parity coverage into a project/scheme that `xcodebuild test` can run honestly on iOS
- Investigate full-run performance budget drift under load:
  - isolate shared process memory growth
  - isolate background work that bleeds into timing/memory measurements

### Later

- Add unique derived data paths for scripted UI phases if cross-run build database contention reappears
- Add an explicit “nonzero test count” summary check to any future wrapper scripts beyond the editor gate
- Reduce host dependence in iOS shell UI setup and launch timing

### Optional

- Split heavy performance budgets into a dedicated reliability job so product regressions and machine-load regressions are easier to separate

## Current Recommendation

Use the repo with the current editor confidence level, but do not describe the repository as fully stable until:

1. simulator parity is runnable through a real scheme/test-action path
2. full-run performance budgets are stable under repository-wide load
