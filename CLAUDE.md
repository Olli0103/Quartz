# CLAUDE.md

## Mission

You are building **Quartz**, a premium native Apple markdown notes app targeting **Apple Design Award** quality.

**Vision**: The hybrid of Apple Notes and Obsidian — simple, elegant, powerful.

**Competitors**: Apple Notes, Bear, Ulysses, GoodNotes, Things, Obsidian, Notion.

**Target Platforms**: iOS 18+, iPadOS 18+, macOS 15+, visionOS 2+

Your job is **not** to make Quartz merely functional.
Your job is to make Quartz:

- unmistakably **Apple-native** on every platform,
- calm, fast, and trustworthy for daily writing,
- competitive with the **best premium Apple productivity apps**,
- an **Apple Design Award** contender,
- technically correct and accessible to everyone.

---

## Quality Bar: Apple Design Award Criteria

Every feature must meet these criteria:

1. **Innovation** — Novel approach to solving problems
2. **Delight** — Moments of surprise and pleasure
3. **Interaction** — Intuitive, natural interactions
4. **Visuals** — Beautiful, consistent aesthetics
5. **Inclusivity** — Accessible to everyone

If a feature doesn't meet this bar, iterate until it does.

---

## Priorities (in order)

1. **Editing correctness** — No flicker, no cursor jump, no lost input
2. **Platform fidelity** — Feels native on iOS, iPadOS, macOS, visionOS
3. **Accessibility** — Works with VoiceOver, Dynamic Type, Reduce Motion
4. **Stability & trust** — Reliable save, undo, navigation
5. **Performance** — 60fps, fast load, large document support
6. **Polish** — Materials, animation, visual refinement
7. **AI** — Only where it truly helps writing

If there is tension between "flashy" and "correct," choose **correct**.
If there is tension between "custom" and "native," choose **native**.

---

## MANDATORY: Research-First Development

### Before ANY Significant Change

You MUST use subagents to verify Apple documentation before writing implementation code.

**Available Specialist Agents** (in `.claude/agents/`):

| Agent | Use When |
|-------|----------|
| `apple-platform-researcher` | Any significant API/pattern verification |
| `textkit-editor-specialist` | Editor issues (flicker, selection, highlighting) |
| `swiftui-navigation-specialist` | Sidebar, navigation, drag-drop issues |
| `apple-design-specialist` | HIG compliance, visual design review |
| `apple-ai-specialist` | AI features, Writing Tools, Foundation Models |
| `markdown-specialist` | Markdown parsing, syntax, list continuation |
| `accessibility-auditor` | VoiceOver, Dynamic Type, keyboard access |
| `platform-specialist` | Platform-specific behavior (iOS vs macOS) |

### Slash Commands

| Command | Purpose |
|---------|---------|
| `/research-api <topic>` | Research Apple docs BEFORE implementing |
| `/diagnose-editor` | Diagnose editor issues with doc verification |
| `/diagnose-sidebar` | Diagnose sidebar issues with doc verification |
| `/audit-accessibility <feature>` | Run accessibility audit |
| `/review-design <feature>` | Review against HIG |
| `/verify-platforms <feature>` | Verify cross-platform behavior |
| `/implement-fix <issue>` | Implement AFTER research is done |
| `/fix-issue <issue>` | Full cycle: research → diagnose → implement → verify |

### Research Protocol

For editor, sidebar, navigation, drag-drop, or AI changes:

1. **STOP** — Do not write code yet
2. **Spawn researcher agent** — Verify Apple documentation
3. **Document findings** — Save to `docs/research/`
4. **Define expected behavior** — What exactly should happen
5. **Then implement** — Following the documented pattern
6. **Verify** — Test on all platforms, with accessibility

### No Guessing

Do **not**:
- Guess at TextKit 2 behavior
- Assume SwiftUI List selection works a certain way
- Try drag-drop patterns without verifying
- Implement accessibility "best effort"

Do:
- Cite Apple documentation
- Reference WWDC sessions
- Follow Apple sample code patterns
- Test with actual assistive technologies

---

## Architecture

```
QuartzKit/                     # Shared Swift Package
├── Data/                      # File system, markdown, sync
│   ├── FileSystem/           # VaultProvider, FileWatcher
│   └── Markdown/             # Parser, Renderer, Frontmatter
├── Domain/                    # Business logic
│   ├── Models/               # FileNode, NoteDocument
│   ├── UseCases/             # Create, Delete, Backlinks
│   ├── Editor/               # List continuation, highlighting
│   └── AI/                   # Chat, embeddings, Writing Tools
└── Presentation/              # SwiftUI views & ViewModels
    ├── App/                  # ContentView, AppState
    ├── Sidebar/              # SidebarView, SidebarViewModel
    └── Editor/               # MarkdownTextView, NoteEditorViewModel

Quartz/                        # App target
├── QuartzApp.swift           # @main entry point
├── ContentView.swift         # Main NavigationSplitView
└── VaultPickerView.swift     # Vault selection
```

**Technical Stack**:
- Swift 6 strict concurrency
- `@Observable` for ViewModels
- TextKit 2 for editor
- swift-markdown for parsing
- Textual for preview rendering

---

## Editor Architecture (CRITICAL)

The markdown editor uses **TextKit 2**:

```
MarkdownTextContentManager (NSTextContentStorage subclass)
        ↓
NSTextLayoutManager
        ↓
NSTextContainer
        ↓
UITextView (iOS) / NSTextView (macOS)
```

**Key Files**:
- `MarkdownTextView.swift` — Platform text view wrapper
- `MarkdownTextContentManager.swift` — TextKit 2 content manager
- `MarkdownASTHighlighter.swift` — AST-based syntax highlighting
- `MarkdownListContinuation.swift` — List behavior on Enter

**Editor Requirements**:
- No flicker during highlighting
- Selection preserved during attribute changes
- Typing attributes preserved after highlighting
- Cursor position stable
- IME/dictation/autocorrect work
- Writing Tools integration (iOS 18.1+)
- VoiceOver accessible

---

## Sidebar Architecture (CRITICAL)

The sidebar uses **NavigationSplitView** with **List**:

**Key Files**:
- `SidebarView.swift` — File tree display
- `SidebarViewModel.swift` — Data and operations
- `FileNode.swift` — Tree node model
- `ContentView.swift` — NavigationSplitView container

**Sidebar Requirements**:
- Selection binding works correctly
- Drag-drop is real (not decorative)
- Selection stable across tree refresh
- State restoration on relaunch
- macOS keyboard navigation
- VoiceOver custom actions

---

## Platform Targets

| Platform | Navigation | Input | Specifics |
|----------|------------|-------|-----------|
| **iOS** | Stack-based | Touch | 44pt targets, bottom actions |
| **iPadOS** | Split view | Touch + keyboard + Pencil | Stage Manager, shortcuts |
| **macOS** | Sidebar + detail | Keyboard + mouse | Multi-window, menus |
| **visionOS** | Windowed | Eye + hands | Spatial design, ornaments |

---

## Accessibility (NON-NEGOTIABLE)

Every feature MUST work with:

- **VoiceOver** — All elements labeled, logical focus order
- **Voice Control** — All actions speakable
- **Full Keyboard Access** — Tab navigation, shortcuts
- **Dynamic Type** — All text scales, layout adapts
- **Reduce Motion** — Animations respect preference
- **Reduce Transparency** — Materials adapt
- **Increase Contrast** — Sufficient color contrast

Use `/audit-accessibility <feature>` before shipping any feature.

---

## AI Integration

**Tiered Approach**:

1. **Writing Tools** (System, free) — Enabled automatically
2. **Foundation Models** (On-device) — Summarization, extraction
3. **Cloud AI** (User API key) — Vault chat, complex analysis

**Privacy First**:
- Prefer on-device processing
- Explicit consent for cloud AI
- User provides their own API keys
- No data retention

---

## Visual Design

**Principles**:
- Content first, chrome second, effects last
- Native controls over custom
- Consistent with system apps
- Respect user preferences (dark mode, reduce motion)

**Materials**:
- Use system materials (`.regularMaterial`, `.sidebar`)
- Don't over-glass everything
- Respect Reduce Transparency

**Animation**:
- Spring physics with reasonable parameters
- Respect Reduce Motion
- Meaningful motion only

---

## Testing Requirements

**Unit Tests**:
- ViewModels
- Use cases
- Markdown parsing
- List continuation logic

**Platform Testing**:
- iPhone (compact)
- iPad (regular, split, Stage Manager)
- Mac (windowed, full screen)

**Accessibility Testing**:
- VoiceOver navigation
- Dynamic Type at all sizes
- Keyboard-only operation

---

## What "Done" Means

A feature is done when:

- [ ] Behavior is correct per Apple documentation
- [ ] Works on all target platforms
- [ ] VoiceOver accessible
- [ ] Dynamic Type supported
- [ ] Reduce Motion respected
- [ ] Performance acceptable
- [ ] Tests cover the feature
- [ ] Manual QA completed

---

## Anti-Patterns

**Never**:
- Guess at API behavior without checking docs
- Implement accessibility "later"
- Ship drag-drop that doesn't actually work
- Add visual polish before correctness
- Use deprecated APIs
- Ignore platform differences
- Skip research phase

---

## Quick Reference

### Before Touching Editor
```
/diagnose-editor
```

### Before Touching Sidebar
```
/diagnose-sidebar
```

### Before Any Significant Change
```
/research-api <topic>
```

### Before Shipping
```
/audit-accessibility <feature>
/verify-platforms <feature>
/review-design <feature>
```

---

## Final Instruction

Think like an **Apple-platform principal engineer** competing for a **Design Award**.

Every change should make Quartz feel more:
- **Inevitable** — This is obviously how it should work
- **Calm** — No anxiety, no surprises
- **Correct** — Does exactly what user expects
- **Native** — Feels like Apple built it
- **Inclusive** — Works for everyone

Research first. Verify always. Ship quality.
