# Accessibility Features

Quartz Notes is designed to be fully accessible. Accessibility is a core requirement, not an afterthought.

## VoiceOver

All interactive elements in Quartz Notes have proper accessibility labels:

- **Toolbar buttons** — Each button announces its function ("Bold", "New Note", "Toggle Focus Mode")
- **Dashboard stats** — Read as combined phrases ("329 Notes", "137 Folders")
- **Action items** — Checkboxes announce "Complete task" with button trait
- **Note list rows** — Announce title, date, snippet, and tags as a combined element
- **Sidebar items** — Folder and note names with type context

### VoiceOver navigation

- Use **VO+Right/Left Arrow** to navigate between elements
- The three-column layout follows a logical left-to-right focus order
- The command palette (Cmd+K) is fully navigable with VoiceOver

## Dynamic Type

All text in Quartz Notes respects macOS accessibility text size settings:

- Dashboard greeting, stats, and section headers use semantic font styles (`.largeTitle`, `.title`, `.body`, `.subheadline`)
- The editor font size is independently adjustable in Settings (12-24pt)
- UI elements scale proportionally with text size changes

**Note:** Some icon sizes (sidebar icons, heatmap cells) use fixed dimensions for layout consistency, following Apple's practice in system apps.

## Reduce Motion

When **Reduce Motion** is enabled in System Settings > Accessibility > Display:

- Spring animations are replaced with simple crossfades
- The ambient mesh background uses a static gradient instead of animated colors
- Focus Mode transitions use instant cuts
- Symbol effects (breathe, bounce) are disabled

## Reduce Transparency

When **Reduce Transparency** is enabled:

- All frosted glass materials (`.regularMaterial`, `.thinMaterial`) fall back to solid opaque backgrounds
- Borders become stronger (1px instead of 0.5px) for clear visual separation
- Drop shadows are removed (unnecessary with opaque backgrounds)
- The sidebar and note list use solid system background colors

This ensures WCAG AA contrast compliance even when the vibrancy layer is disabled.

## Increase Contrast

When **Increase Contrast** is enabled:

- Container borders become more visible
- The Liquid Glass pane modifier uses stronger stroke opacity
- Text maintains its standard color hierarchy (`.primary`, `.secondary`)

## Full Keyboard Access

All major functions are accessible via keyboard:

- **Cmd+K** — Command palette for searching notes and running commands
- **Cmd+1 through Cmd+6** — Heading levels
- **Cmd+B/I** — Bold/Italic
- **Cmd+N** — New note
- **Tab/Shift+Tab** — List indentation
- **Arrow keys** — Navigate command palette and lists
- See [All Keyboard Shortcuts](../keyboard-shortcuts/all-shortcuts.md) for the complete list

## Color and contrast

- Primary content text uses `.primary` (automatically adapts to light/dark mode)
- Secondary metadata uses `.secondary` (sufficient contrast in both modes)
- The accent color is user-configurable (7 options) and used consistently for selection, focus, and interactive elements
- Pure Dark Mode provides maximum contrast with true black backgrounds

## Platform-specific notes

> **macOS:** This documentation covers macOS accessibility. iOS, iPadOS, and visionOS sections will be added as those platforms ship. The same accessibility principles (VoiceOver labels, Dynamic Type, Reduce Motion) apply across all platforms.
