---
description: Run accessibility audit on a feature or view
argument-hint: <feature or file e.g. "SidebarView" or "editor">
allowed-tools: Agent, Read, Grep, Glob
---

# Accessibility Audit: $ARGUMENTS

## Protocol

1. **Spawn accessibility-auditor agent** to review:
   - VoiceOver support (labels, hints, traits)
   - Dynamic Type (text scaling, layout adaptation)
   - Keyboard accessibility (focus, shortcuts)
   - Reduce Motion compliance
   - Reduce Transparency compliance
   - Color contrast

2. **Audit checklist**:
   - [ ] All interactive elements have accessibilityLabel
   - [ ] Touch targets are 44pt minimum
   - [ ] Text uses Dynamic Type text styles
   - [ ] Layout adapts to large text
   - [ ] Animations respect Reduce Motion
   - [ ] Materials respect Reduce Transparency
   - [ ] Contrast meets WCAG AA (4.5:1)
   - [ ] Custom views expose correct traits
   - [ ] Focus order is logical

3. **Generate report**:
   - Violations found
   - Impact on users
   - Required fixes with code
   - Testing instructions

## Output

Return accessibility audit report with:
- Pass/fail for each criterion
- Code fixes for violations
- Manual testing steps
