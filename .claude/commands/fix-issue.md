---
description: Full implementation cycle - research, diagnose, implement, verify
argument-hint: <issue description>
allowed-tools: Agent, Read, Write, Edit, Grep, Glob, Bash, WebSearch, WebFetch
---

# Fix Issue: $ARGUMENTS

## Full Cycle Protocol

This command runs the complete fix cycle. Use for non-trivial issues.

### Phase 1: Research (DO FIRST)

1. **Identify the domain**:
   - Editor issue? → textkit-editor-specialist
   - Sidebar issue? → swiftui-navigation-specialist
   - Design issue? → apple-design-specialist
   - AI issue? → apple-ai-specialist
   - Accessibility? → accessibility-auditor
   - Platform-specific? → platform-specialist

2. **Spawn researcher agent** to verify Apple documentation

3. **Document findings** in `docs/research/`

### Phase 2: Diagnose

1. **Read current implementation**
2. **Compare against Apple docs**
3. **Identify root cause**
4. **Define exact expected behavior**

### Phase 3: Implement

1. **Make minimal fix** following Apple pattern
2. **Preserve accessibility**
3. **Add tests if possible**
4. **Build and verify**

### Phase 4: Verify

1. **Test on all platforms**:
   - iOS (iPhone)
   - iPadOS (iPad)
   - macOS

2. **Accessibility check**:
   - VoiceOver
   - Dynamic Type
   - Reduce Motion

3. **Document results**

## Output

Complete report with:
- Research findings
- Root cause diagnosis
- Implementation changes
- Verification results
- Any remaining issues
