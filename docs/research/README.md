# Research Documentation

This directory contains verified Apple documentation research that informs Quartz implementation decisions.

## Purpose

Before implementing or fixing features in critical areas (editor, sidebar, navigation, AI), we document:
- Official Apple documentation findings
- WWDC session references
- Sample code patterns
- Platform-specific behavior
- Accessibility requirements

## Structure

```
docs/research/
├── README.md                    # This file
├── textkit2-patterns.md         # TextKit 2 editor patterns
├── list-selection-patterns.md   # NavigationSplitView + List
├── drag-drop-patterns.md        # Transferable, dropDestination
├── writing-tools-integration.md # iOS 18.1+ Writing Tools
├── foundation-models.md         # On-device AI
├── accessibility-patterns.md    # VoiceOver, Dynamic Type
└── platform-specifics.md        # iOS vs iPadOS vs macOS
```

## Usage

1. **Before implementing**: Run `/research-api <topic>` to populate this directory
2. **Before fixing bugs**: Run `/diagnose-editor` or `/diagnose-sidebar` to verify against docs
3. **Reference during implementation**: Cite these docs in code comments if behavior is non-obvious

## Why This Exists

We've experienced circular debugging when:
- Guessing at TextKit 2 behavior
- Assuming SwiftUI List selection works a certain way
- Trial-and-error drag-drop implementations

By documenting verified patterns FIRST, we implement correctly ONCE.

## Contributing

When adding research:
1. Include source URLs (developer.apple.com)
2. Reference WWDC session numbers
3. Include code patterns from Apple
4. Note platform/version requirements
5. Document accessibility implications
