---
description: Verify feature works correctly on all target platforms
argument-hint: <feature e.g. "sidebar selection" or "editor highlighting">
allowed-tools: Agent, Read, Grep, Glob
---

# Platform Verification: $ARGUMENTS

## Protocol

1. **Spawn platform-specialist agent** to analyze:
   - iOS (iPhone) behavior and expectations
   - iPadOS (iPad) behavior including Stage Manager
   - macOS behavior including multi-window
   - visionOS behavior if applicable

2. **Check platform-specific code**:
   - Are #if os() conditionals correct?
   - Is behavior appropriate for each platform?
   - Are platform-specific APIs used correctly?

3. **Verify test matrix**:
   - [ ] iPhone (compact width)
   - [ ] iPad portrait (regular width)
   - [ ] iPad Split View (compact width)
   - [ ] iPad Stage Manager
   - [ ] Mac window (various sizes)
   - [ ] Mac full screen
   - [ ] visionOS window

4. **Generate verification plan**:
   - What to test on each platform
   - Expected behavior differences
   - Common failure modes
   - Platform-specific edge cases

## Output

Return platform verification plan with:
- Expected behavior per platform
- Test scenarios
- Known platform differences
- Code review findings
