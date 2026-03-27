---
description: Research Apple API/pattern before implementing. MANDATORY before any significant change.
argument-hint: <topic e.g. "TextKit 2 selection preservation" or "NavigationSplitView drag-drop">
allowed-tools: Agent, WebSearch, WebFetch, Read
---

# Research Apple API: $ARGUMENTS

## Protocol

You MUST complete this research before writing any implementation code.

1. **Spawn the apple-platform-researcher agent** to:
   - Search developer.apple.com for official documentation
   - Find relevant WWDC 2024/2025 sessions
   - Locate Apple sample code
   - Check Swift Evolution if relevant

2. **Document findings** including:
   - Official API documentation links
   - WWDC session references
   - Code patterns from Apple
   - Version requirements (iOS/macOS minimum)
   - Platform differences
   - Accessibility implications

3. **Save research** to `docs/research/$ARGUMENTS.md`

4. **Return summary** with:
   - Verified pattern (code)
   - What NOT to do (common mistakes)
   - How to test correctness

## Output

DO NOT write implementation code.
Return research findings only.
Implementation happens AFTER research is verified.
