---
description: Implement a fix after research/diagnosis is complete. Requires prior research.
argument-hint: <issue description>
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Implement Fix: $ARGUMENTS

## Prerequisites

Before using this command, you MUST have:
1. Run `/research-api` or `/diagnose-editor` or `/diagnose-sidebar`
2. Documented the Apple-verified approach
3. Identified the specific fix

If you haven't done research first, STOP and run the appropriate research command.

## Implementation Protocol

1. **Verify research exists**:
   - Check `docs/research/` for relevant documentation
   - Confirm we have Apple-verified patterns

2. **Implement minimal fix**:
   - Change ONLY what's necessary
   - Follow the documented Apple pattern
   - Preserve existing correct behavior
   - Add comments citing documentation if non-obvious

3. **Maintain accessibility**:
   - Don't break existing accessibility
   - Add accessibility for new elements
   - Test with VoiceOver mentally

4. **Test the change**:
   - Build the project
   - Run relevant tests
   - Document manual test steps

## Output

After implementation:
- Summary of changes made
- Files modified
- Manual testing instructions
- What to verify on each platform
