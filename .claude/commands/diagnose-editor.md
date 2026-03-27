---
description: Diagnose editor issues (flickering, cursor jumping, list problems) with documentation verification
allowed-tools: Agent, Read, Grep, Glob, WebSearch, WebFetch
---

# Diagnose Editor Issue

## Protocol

1. **Read current implementation**:
   - `QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextView.swift`
   - `QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift`
   - `QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownListContinuation.swift`
   - `QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextContentManager.swift`

2. **Spawn textkit-editor-specialist agent** to:
   - Verify our TextKit 2 usage against Apple documentation
   - Identify deviations from documented patterns
   - Check for deprecated API usage
   - Review WWDC sessions on TextKit 2

3. **Identify specific issues**:
   - What symptom is occurring? (flicker, cursor jump, lost input, slow)
   - What code path causes it?
   - What does Apple documentation say to do?
   - What are we doing differently?

4. **Create diagnosis report**:
   - Root cause with evidence
   - Apple's documented approach
   - Minimal fix recommendation
   - Verification steps

## Output

DO NOT modify code yet.
Return diagnosis with:
- Root cause
- Apple-verified fix approach
- Test plan
