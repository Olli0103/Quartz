# Codex Project Memory: Quartz

Last updated: 2026-05-04

## Project Identity

Quartz is a native Apple markdown notes app with shared code in `QuartzKit` and the macOS app target in `Quartz`.

Primary paths:

- App project: `/Users/I533181/Development/Quartz/Quartz.xcodeproj`
- Shared package: `/Users/I533181/Development/Quartz/QuartzKit`
- Current working root: `/Users/I533181/Development/Quartz`

The active repo contains an `AGENTS.md` about Todoist that appears unrelated to Quartz. Treat `CLAUDE.md` as useful project context, but do not assume its Claude-specific tool instructions are available in Codex.

## Engineering Priorities

- Editing correctness comes first: no lost input, no stale saves, no cursor jumps, no source mutation from passive rendering.
- Local-first data safety is non-negotiable. Prefer blocking or replaying unsafe writes over optimistic persistence.
- Keep changes narrow and evidence-based. Avoid broad refactors unless the user explicitly asks.
- Do not run UI tests unless the user explicitly permits them.
- For Swift/AppKit/TextKit work, prefer focused non-UI unit tests and build output as verification.

## Verification Commands

The user-provided commands are:

```bash
swift build --package-path /Users/I533181/Development/Quartz/QuartzKit
swift test --package-path /Users/I533181/Development/Quartz/QuartzKit
xcodebuild -project /Users/I533181/Development/Quartz/Quartz.xcodeproj -scheme Quartz -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Current local caveat:

- `xcode-select -p` is `/Library/Developer/CommandLineTools`.
- The exact SwiftPM commands fail under Command Line Tools because the dependency `swiftui-math` needs Xcode SwiftUI macro plugins.
- The exact `xcodebuild` command fails under Command Line Tools because `xcodebuild` requires Xcode.
- Use this prefix for local verification unless the developer directory is changed globally:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path /Users/I533181/Development/Quartz/QuartzKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path /Users/I533181/Development/Quartz/QuartzKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project /Users/I533181/Development/Quartz/Quartz.xcodeproj -scheme Quartz -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Current Fix Context

Recent Build 107 smoke evidence showed:

- Version History snapshot creation worked, but lookup returned `snapshotFilesFound=0` for the same `versionLookupKey`.
- Stale save bytes could reach provider persistence before post-write side effects were blocked.
- AI could report plain `idle` after expired `providerSlow` backoff while pending work still existed.
- Autolink/source mutation was not proven in the latest smoke and was not prioritized beyond quick audit.

Recent changes made in this repo:

- `VersionHistoryService` now writes sidecar snapshot metadata with `noteIdentity`, `versionLookupKey`, `snapshotStorageKey`, original relative path, creation date, content length, and snapshot filename.
- Version lookup now uses canonical lookup keys such as `people<path:Georg.md>` for nested notes and raw filenames for root notes.
- Version lookup now emits precise diagnostics for storage directory, metadata read/write, lookup directory/key/hash, candidate matches/rejections, missing directories, missing metadata, key mismatch, and post-create verification.
- `EditorSession` now performs pre-write revision, identity, and checksum checks before provider writes when the stale condition is knowable.
- Post-write stale detection now records that stale bytes may already have persisted, blocks latest-revision and snapshot side effects, and schedules replay.
- `KnowledgeExtractionService` now distinguishes `retryableIdle`, `pendingBacklogIdle`, and `automaticScanScheduled` instead of publishing plain `idle` when pending backlog exists without a clear next action.

## Important Diagnostics Added

Version History:

- `version.snapshotStorageDirectory`
- `version.snapshotMetadataWritten`
- `version.snapshotMetadataRead`
- `version.snapshotLookupDirectory`
- `version.snapshotLookupKeyHash`
- `version.snapshotLookupStorageKey`
- `version.snapshotLookupCandidateCount`
- `version.snapshotLookupCandidateMatched`
- `version.snapshotLookupCandidateRejected`
- `version.snapshotLookupPostCreateVerified`
- `version.snapshotLookupPostCreateFailed`
- `version.snapshotDirectoryMissing`
- `version.snapshotMetadataMissing`
- `version.snapshotMetadataKeyMismatch`

Save flow:

- `save.preWriteRevisionCheckStarted`
- `save.preWriteRevisionCheckPassed`
- `save.preWriteRevisionRegressionBlocked`
- `save.staleSaveDroppedBeforeWrite`
- `save.preWriteIdentityMismatchBlocked`
- `save.preWriteChecksumMismatchBlocked`
- `save.postWriteStaleBytesMayHavePersisted`
- `save.replayScheduledAfterStaleWrite`
- `save.latestRevisionNotAdvancedDueToDirtyAfter`
- `save.snapshotSkippedDueToDirtyAfter`

AI indexing:

- `ai.pendingBacklogIdle`
- `ai.retryableIdle`
- `ai.automaticScanScheduledAfterBackoff`
- `ai.noAutomaticScanReason`
- `ai.retryNowScheduled`

## Verification Status As Of 2026-05-04

Passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

- `swift build --package-path /Users/I533181/Development/Quartz/QuartzKit`
- `swift test --package-path /Users/I533181/Development/Quartz/QuartzKit --filter VersionHistoryServiceTests`
- `swift test --package-path /Users/I533181/Development/Quartz/QuartzKit --filter VersionHistoryPersistence`
- `swift test --package-path /Users/I533181/Development/Quartz/QuartzKit --filter EditorSessionSaveFlowTests`
- `swift test --package-path /Users/I533181/Development/Quartz/QuartzKit --filter KnowledgeExtractionBudgetTests`
- `swift test --package-path /Users/I533181/Development/Quartz/QuartzKit --filter EmbeddingResumePersistence`
- `xcodebuild -project /Users/I533181/Development/Quartz/Quartz.xcodeproj -scheme Quartz -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

Full `swift test` is not currently green. The known remaining failures in the last full run were:

- `EditorRealitySnapshotTests`: visual snapshot baseline mismatches.
- `AutosaveReliabilityTests.saveRequestDuringActiveSaveIsReplayed`: one full-suite-only timing issue where `session.isSaving` was still `true`; the isolated test passed 10/10 and the Autosave Reliability suite passed 5/5.

The previous full-suite-only `KnowledgeExtractionBudgetTests.indexingControlsPublishVisibleState` failure was traced to asynchronous diagnostics delivery. The test now waits briefly for the required `ai.retryNowScheduled` diagnostic and still asserts the event is emitted.

Do not claim the full suite is green until these are resolved or clearly quarantined by project policy.

## Build 108+ Manual Smoke Checklist

- Confirm Build 108+ and new `appExecutableModifiedAt`.
- Reset diagnostics.
- Create a snapshot and immediately open Version History; expect `snapshotFilesFound > 0`.
- Reopen app and open Version History again; expect `snapshotFilesFound > 0`.
- Type rapidly in a noncritical note; expect no pre-write stale provider writes where stale state is knowable.
- If stale revision occurs, expect `blockedStage=preWrite` where possible.
- `dirtyAfter=true` must not advance `latestRevisionPersisted` or create a snapshot.
- AI must not show plain `idle` with pending backlog and no next action.
- Optional: verify passive autolink/highlight does not mutate source.

## Residual Risks

- Legacy nested-note snapshots without metadata may need migration if their old hash directory differs from the new canonical lookup key.
- Full-suite instability remains around visual snapshots and parallel AI/embedding tests.
- AI backlog usefulness is only partially verified: status clarity and Retry Now scheduling are covered, but large-backlog throughput still needs a real-vault smoke.
- Autolink source mutation remains plausible but unverified.
