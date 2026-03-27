---
description: Diagnose sidebar issues (selection, drag-drop, navigation) with documentation verification
allowed-tools: Agent, Read, Grep, Glob, WebSearch, WebFetch
---

# Diagnose Sidebar Issue

## Protocol

1. **Read current implementation**:
   - `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
   - `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarViewModel.swift`
   - `QuartzKit/Sources/QuartzKit/Domain/Models/FileNode.swift`
   - `Quartz/ContentView.swift`

2. **Spawn swiftui-navigation-specialist agent** to:
   - Verify our NavigationSplitView usage
   - Check List(selection:) binding patterns
   - Review drag-drop implementation
   - Compare against Apple documentation

3. **Identify specific issues**:
   - Selection not working?
   - Drag not starting?
   - Drop not triggering?
   - Selection lost on refresh?
   - Platform-specific behavior?

4. **Create diagnosis report**:
   - Root cause with evidence
   - Apple's documented approach
   - Platform differences
   - Minimal fix recommendation

## Output

DO NOT modify code yet.
Return diagnosis with:
- Root cause
- Apple-verified fix approach
- Platform-specific testing plan
