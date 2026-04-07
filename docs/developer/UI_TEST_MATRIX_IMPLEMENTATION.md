# UI Test Matrix Implementation Guide (macOS + iOS + iPadOS)

This guide converts Quartz's existing UI tests into a real matrix gate that can run in CI.

## 1) Baseline status in this repo

- UI test target exists: `QuartzUITests`.
- Existing tests already cover welcome/onboarding/accessibility basics.
- Launch screenshot test exists in `QuartzUITestsLaunchTests`.

## 2) Create deterministic UI-test app mode

Add app launch arguments that force stable test state:

- `--uitesting`
- `--reset-state`
- `--mock-vault`
- `--disable-animations`

In app startup, branch on these arguments and:

1. clear persisted state,
2. load a fixture vault,
3. disable async background sync,
4. force a fixed locale/timezone if needed.

## 3) Add platform-scoped smoke suites

Create 3 suites (can be in one file with helpers):

- `QuartzUITests/iOSPhoneSmokeUITests.swift`
- `QuartzUITests/iPadSmokeUITests.swift`
- `QuartzUITests/macOSSmokeUITests.swift`

Each suite should verify:

1. launch to expected root view,
2. open vault / create note / edit note round trip,
3. one accessibility assertion (`isHittable`, label exists),
4. one screenshot attachment per major screen.

## 4) Add snapshot-style attachments (without extra framework)

Use XCTest attachments for now:

```swift
let shot = XCTAttachment(screenshot: app.screenshot())
shot.name = "iPad_Dashboard_Light"
shot.lifetime = .keepAlways
add(shot)
```

If adopting a snapshot framework later, keep these tests as fallback.

## 5) Run matrix destinations

Use three destinations in CI:

```bash
# iPhone
xcodebuild test -scheme Quartz \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:QuartzUITests

# iPad
xcodebuild test -scheme Quartz \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -only-testing:QuartzUITests

# macOS
xcodebuild test -scheme Quartz \
  -destination 'platform=macOS' \
  -only-testing:QuartzUITests
```

## 6) Make CI fail when UI evidence is missing

In `scripts/ci_phase3.sh`:

1. run the three UI test jobs above,
2. fail if any job fails,
3. fail if screenshot attachments are missing from test results,
4. emit `reports/phase3_ui_report.json` with pass/fail per platform.

## 7) Add an XCTest Plan for maintainability

Add `QuartzUITests.xctestplan` with configurations:

- `iPhone-Default`
- `iPad-Default`
- `macOS-Default`
- `Accessibility-XL` (Dynamic Type)

Use launch arguments/environment in each config instead of hard-coding in every test.

## 8) Minimal first ship gate

Ship-gate requirement (v1):

- ✅ `QuartzUITests` passes on all 3 destinations.
- ✅ At least 1 screenshot attachment per platform.
- ✅ At least 1 accessibility check per platform.
- ✅ JSON report artifact produced in `reports/`.

Then expand to richer flows and visual diffs.
