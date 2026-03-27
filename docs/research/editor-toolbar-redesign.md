# Editor Toolbar Redesign Research

**Date**: March 24, 2026
**Purpose**: Research best practices for markdown editor toolbar design on Apple platforms

---

## 1. Apple Human Interface Guidelines (HIG)

### 1.1 Toolbar Design Principles

**Platform-Specific Toolbar Placement**:
- **macOS**: Toolbars appear in the window title bar area (unified toolbar). Use `.toolbar` with `.principal` placement for centered content, `.navigation` for back buttons, and `.primaryAction` for primary actions on the trailing edge.
- **iOS/iPadOS**: Navigation bars at top, toolbars at bottom. `.toolbar` with `.bottomBar` for persistent actions.
- **visionOS**: Use ornaments for contextual controls; minimize chrome.

**Button Sizing Requirements**:
| Platform | Minimum Touch Target | Recommended |
|----------|---------------------|-------------|
| iOS | 44x44 pt | 44x44 pt or larger |
| iPadOS | 44x44 pt | Can be slightly smaller with hover states |
| macOS | 20x20 pt | 24-28 pt for icon buttons |

**Key HIG Principles**:
1. **Content first, chrome second** - Minimize toolbar presence when not actively formatting
2. **Native controls preferred** - Use system buttons, menus, and controls
3. **Progressive disclosure** - Show primary actions, hide secondary in menus
4. **Platform consistency** - Match platform conventions (bottom bars on iOS, top toolbars on macOS)

### 1.2 Navigation Bar vs Toolbar Separation

**Navigation Bar** (Top):
- Title/document name
- Back navigation
- Primary action buttons (Share, Save)
- Search (on macOS, often in toolbar area)

**Toolbar** (Bottom on iOS, Title bar on macOS):
- Formatting controls
- Context-specific actions
- Edit mode toggles

**Best Practice**: Keep navigation and formatting separate. Don't overload the navigation bar with formatting controls.

---

## 2. Markdown Editor Paradigms

### 2.1 WYSIWYG vs Live Preview vs Split View

| Approach | Examples | Pros | Cons |
|----------|----------|------|------|
| **Pure Markdown** | iA Writer, Obsidian (source mode) | Fast, predictable, portable | Steep learning curve, syntax visible |
| **Live Preview / Inline Rendering** | Bear, Obsidian (live preview), Typora | Best of both worlds, WYSIWYG-like | More complex to implement, can feel inconsistent |
| **Split View** | Obsidian (traditional), many web editors | Clear separation, good for learning | Wastes screen space, context switching |
| **Mode Toggle** | Apple Notes (sort of), many apps | Simple to implement | Jarring transition, loses position |

**Recommendation for Quartz**: **Live Preview / Inline Rendering** (like Bear)
- This is the most Apple-like approach - elegant, modern, reduces cognitive load
- Bear won an Apple Design Award with this approach
- Obsidian moved to live preview as default due to user preference

### 2.2 Inline Rendering Best Practices

**What to render inline**:
- Headings (show styled, hide `#` marks when not editing that line)
- Bold/italic (show styled, hide `**`/`*` marks)
- Links (show clickable link, hide URL unless editing)
- Checkboxes (show interactive checkbox)
- Images (show inline preview)
- Horizontal rules
- Blockquotes (show styled block)

**What to keep as syntax**:
- Code blocks (syntax highlighting, but show fence markers)
- Tables (too complex to render inline elegantly)
- Frontmatter (show as collapsible header)

**Key Implementation Detail**: When cursor is on or near a markdown element, reveal the syntax. When cursor moves away, render it.

---

## 3. Competitor Analysis

### 3.1 Bear App (Apple Design Award Winner)

**Toolbar Design**:
- **macOS**: Minimal unified toolbar with just search, tags, and settings
- **iOS**: Bottom formatting bar appears when editing
- No visible toolbar buttons for formatting on macOS - uses keyboard shortcuts
- Format menu accessed via right-click or keyboard

**Editor Design**:
- Inline rendering of markdown (hides syntax when not editing)
- Single editor view, no split preview
- Focus on content, minimal chrome
- Uses custom markdown flavor ("Polar Bear")

**Key Takeaway**: Bear proves you don't need visible formatting buttons. Power users prefer keyboard shortcuts.

### 3.2 Ulysses

**Toolbar Design**:
- **macOS**: Three-pane design (library, sheets, editor)
- Minimal toolbar - just navigation and view toggles
- Formatting accessed through markup menu or keyboard
- "Markup bar" can be shown/hidden at bottom

**Editor Design**:
- Markup-based (similar to markdown but custom)
- Inline preview of formatting
- Focus mode dims non-active paragraphs
- Live style preview in sidebar

**Key Takeaway**: Ulysses emphasizes keyboard-first writing. Formatting controls are secondary.

### 3.3 iA Writer

**Philosophy**: "No buttons, no popups, no title bar"

**Toolbar Design**:
- Intentionally minimal - almost no toolbar
- Focus Mode, Syntax Highlight as the main features
- No formatting toolbar at all on macOS
- iOS keyboard accessory bar with minimal formatting

**Editor Design**:
- Pure markdown (no inline rendering)
- Focus Mode highlights current sentence/paragraph
- Syntax highlighting for parts of speech
- Custom monospace font

**Key Takeaway**: iA Writer proves that extreme minimalism can be a selling point.

### 3.4 Apple Notes

**Toolbar Design**:
- **macOS**: Standard toolbar with formatting controls in a segment
- Formatting bar shows: Checklist, Table, Highlight, Font, List
- Uses native NSToolbar with standard appearance
- Inspector panel for detailed formatting

**Editor Design**:
- Rich text (not markdown)
- WYSIWYG editing
- Inline attachments
- Format menu for additional options

**Key Takeaway**: Apple Notes shows the "native" approach - uses standard toolbar patterns.

### 3.5 Obsidian

**Toolbar Design**:
- Customizable toolbar with formatting buttons
- Can be configured to show/hide specific controls
- Mobile has floating formatting bar
- Heavy reliance on command palette (Cmd+P)

**Editor Design**:
- Three modes: Source, Live Preview, Reading
- Live Preview is now default (added in 2022)
- When cursor on syntax, shows markdown; when away, renders

**Key Takeaway**: Obsidian's move to Live Preview as default validates this approach.

### 3.6 Craft (Apple Design Award Winner 2021)

**Toolbar Design**:
- Block-based editor with inline formatting menu
- "/" command for inserting blocks
- Minimal persistent toolbar
- Context menus for block actions

**Editor Design**:
- Block-based (not pure markdown)
- Rich inline formatting
- Native Apple feel with custom implementation
- Sub-second sync, native performance

**Key Takeaway**: Craft shows that contextual menus (appearing when needed) can replace persistent toolbars.

---

## 4. SwiftUI Toolbar Best Practices

### 4.1 Toolbar Placement Options

```swift
.toolbar {
    // macOS: Left of title, iOS: Leading edge
    ToolbarItem(placement: .navigation) { ... }

    // macOS: Center of toolbar, iOS: Center of nav bar
    ToolbarItem(placement: .principal) { ... }

    // macOS: Right side, iOS: Trailing edge - PRIMARY ACTIONS GO HERE
    ToolbarItem(placement: .primaryAction) { ... }

    // iOS only: Bottom toolbar
    ToolbarItem(placement: .bottomBar) { ... }

    // macOS: Trailing edge, distinct from primaryAction
    ToolbarItem(placement: .confirmationAction) { ... }

    // Cancellation actions (Back, Cancel)
    ToolbarItem(placement: .cancellationAction) { ... }
}
```

### 4.2 Unified Toolbar on macOS

For a modern macOS app like Quartz:
- Use `.toolbar` modifier, not custom views overlaid on content
- Place formatting controls in `.principal` for center alignment
- Keep primary actions (Save, Share) in `.primaryAction`
- Use `ToolbarItemGroup` for grouping related items

**Avoiding Duplicate Toolbars**:
- Don't create custom overlay toolbars AND use `.toolbar`
- If using `.toolbar`, don't add additional header views
- The current Quartz implementation has potential conflicts between `MacEditorToolbar` in `.principal` and the custom `editorHeader` view

### 4.3 macOS-Specific Considerations

```swift
// Hide title to make room for toolbar content
.navigationTitle("")

// Or use inline display mode
.navigationBarTitleDisplayMode(.inline)

// For toolbar-only title bar
.windowStyle(.hiddenTitleBar) // At window level
```

---

## 5. Liquid Glass / Modern macOS Design (2025-2026)

### 5.1 Materials and Vibrancy

**When to Use Glass Effects**:
- Sidebars and secondary surfaces
- Floating palettes and popovers
- NOT on primary content areas

**When to Use Solid Backgrounds**:
- Editor/content area (readability is critical)
- Modal dialogs
- Areas requiring focus

### 5.2 Toolbar Styling

**Do**:
- Use system toolbar appearance (automatic vibrancy)
- Let system handle material based on scroll position
- Respect user's Reduce Transparency setting

**Don't**:
- Over-glass everything
- Use glass on text editing surfaces
- Apply custom materials when system provides appropriate ones

### 5.3 Current Quartz Implementation Review

Looking at the current implementation:
- `editorHeader` uses `.quartzAmbientGlassBackground()` - potentially appropriate
- `IosEditorToolbar` uses `.quartzMaterialBackground()` - good for floating elements
- Consider whether the glass header competes with content

---

## 6. Specific Recommendations for Quartz

### 6.1 Should We Have Inline Markdown Rendering?

**Recommendation: YES**

**Rationale**:
1. Bear and Obsidian both moved to this approach
2. More Apple-like (WYSIWYG feel without leaving markdown)
3. Reduces visual clutter
4. Better for non-technical users
5. Apple Design Award precedent (Bear)

**Implementation Strategy**:
- When cursor is NOT on a markdown element: render it (hide syntax)
- When cursor IS on or selecting the element: show syntax
- Animate the transition subtly
- Preserve cursor position precisely

### 6.2 How Should Formatting Options Be Organized?

**Recommendation: Contextual + Keyboard First**

**macOS**:
1. **Primary**: Keyboard shortcuts (Cmd+B, Cmd+I, etc.)
2. **Secondary**: Right-click context menu
3. **Tertiary**: Format menu in menu bar
4. **Optional**: Slim toolbar in `.principal` position for discoverability

**iOS/iPadOS**:
1. **Primary**: Keyboard accessory bar (when keyboard is visible)
2. **Secondary**: Bottom floating pill (current implementation - good!)
3. **Tertiary**: Long-press context menu

**Specific Layout**:
```
Primary Actions (always visible):
[Bold] [Italic] [Link] [List] | [More...]

Secondary Actions (in "More" menu):
- Heading (with level submenu)
- Checkbox
- Code
- Quote
- Table
- Image
```

### 6.3 Ideal Toolbar Layout

**macOS Toolbar** (in window title bar area):
```
[← Back] [Breadcrumb / Folder Name]     [Preview Toggle] [B I Link •••]     [Search] [+] [Save] [Share]
         ↑ Navigation                    ↑ Principal (centered)               ↑ Primary Actions
```

**iOS Navigation Bar**:
```
[< Back]     [Note Title]     [AI ✨] [Preview] [•••]
```

**iOS Bottom Toolbar** (floating pill - current approach is good):
```
[Preview] | [B] [I] [List] [Link] | [Table] [Image] [Code] [•••] || [✓ Save]
```

### 6.4 Title/Filename: Inline or Separate?

**Recommendation: Inline Editable Title (Current approach is correct)**

**Rationale**:
1. Bear, Ulysses, Apple Notes all use inline titles
2. Reduces chrome
3. More natural writing flow
4. Title is content, not metadata

**Implementation Notes**:
- Current `editorHeader` with `TextField` for title is good
- Consider making it more prominent (larger font)
- Auto-derive filename from title (already implemented)

### 6.5 Breadcrumb + Title + Toolbar Integration

**Current Problem**:
- `editorHeader` (breadcrumb + title) is a custom overlay
- `MacEditorToolbar` is in `.toolbar(.principal)`
- Potential visual conflict and double-bar appearance

**Recommended Solution**:

**Option A: Unified Header (Recommended)**
Remove the separate `editorHeader` and integrate into system toolbar:
```
macOS Toolbar: [Back] [Folder > Subfolder >] [Note Title ★]     [Formatting Controls]     [Actions]
```
- Breadcrumb in `.navigation`
- Title as part of breadcrumb (editable on click)
- Formatting in `.principal`
- Actions in `.primaryAction`

**Option B: Content Header + Minimal Toolbar**
Keep `editorHeader` but simplify toolbar:
```
Toolbar: [Back]                               [Preview]                          [Save] [Share]
Header:  Folder > Subfolder
         [Title Field                                                           ★ Favorite]
```
- Only essential controls in toolbar
- Formatting appears contextually or in bottom bar

**Option C: Bear-Style Minimal**
Remove formatting toolbar entirely:
- Rely on keyboard shortcuts
- Format menu in menu bar
- Right-click context menu
- Bottom floating bar for iOS only

### 6.6 Mockup: Recommended macOS Design

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [←] Documents > Projects > Meeting Notes                    [🔍] [+] [💾] [↗]│
│─────────────────────────────────────────────────────────────────────────────│
│                                                                              │
│ Meeting Notes 2024-03-24                                               [★]  │
│ ─────────────────────────────────────────────────────────────────────────── │
│                                                                              │
│ ## Attendees                                                                 │
│                                                                              │
│ - Alice                                                                      │
│ - Bob                                                                        │
│ - Charlie                                                                    │
│                                                                              │
│ ## Action Items                                                              │
│                                                                              │
│ - [ ] Review proposal                                                        │
│ - [ ] Send follow-up email                                                  │
│ - [x] Book conference room                                                  │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ 📄 245 words  ⏱ 2 min read                              ✓ Saved             │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Key Features**:
1. **Toolbar**: Breadcrumb path, search, new, save, share
2. **Title**: Large, editable, with favorite star
3. **Content**: Clean, focused, inline rendered markdown
4. **Status**: Minimal status bar

### 6.7 Mockup: Recommended iOS Design

```
┌──────────────────────────────────────┐
│ < Back      Meeting Notes     ✨ 📖  │
├──────────────────────────────────────┤
│                                      │
│ Meeting Notes 2024-03-24         [★] │
│ ──────────────────────────────────── │
│                                      │
│ ## Attendees                         │
│                                      │
│ - Alice                              │
│ - Bob                                │
│ - Charlie                            │
│                                      │
│ ## Action Items                      │
│                                      │
│ - [ ] Review proposal                │
│ - [ ] Send follow-up                 │
│                                      │
│                                      │
│                                      │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ 📖 │ B I • 🔗 │ ⊞ 📷 </> ••• ││✓│ │
│ └──────────────────────────────────┘ │
├──────────────────────────────────────┤
│ #meeting #project         + Add tag  │
└──────────────────────────────────────┘
```

---

## 7. Implementation Priorities

### Phase 1: Clean Up Current Structure
1. Remove visual conflicts between `editorHeader` and toolbar
2. Consolidate toolbar placement
3. Ensure no duplicate controls

### Phase 2: Implement Inline Rendering
1. Research TextKit 2 approach for inline rendering
2. Implement cursor-aware syntax hiding
3. Handle all markdown elements progressively

### Phase 3: Contextual Formatting
1. Implement right-click formatting menu
2. Ensure all keyboard shortcuts work
3. Add Format menu to menu bar

### Phase 4: Polish
1. Refine animations
2. Test accessibility
3. Platform-specific optimizations

---

## 8. References

### Apple Documentation
- Human Interface Guidelines: Toolbars
- Human Interface Guidelines: Navigation Bars
- SwiftUI Toolbar documentation
- WWDC 2025: What's New in SwiftUI

### Competitor Apps
- Bear: https://bear.app
- Ulysses: https://ulysses.app
- iA Writer: https://ia.net/writer
- Obsidian: https://obsidian.md
- Craft: https://www.craft.do

### Design Resources
- Apple Design Resources: https://developer.apple.com/design/resources/
- SF Symbols: https://developer.apple.com/sf-symbols/

---

## 9. Summary of Key Decisions

| Decision | Recommendation | Rationale |
|----------|----------------|-----------|
| Inline rendering | YES | Bear/Obsidian precedent, Apple-like feel |
| Formatting toolbar location | Contextual + Keyboard | Follow iA Writer/Bear minimal approach |
| Title editing | Inline (current) | Natural, reduces chrome |
| Preview mode | Toggle + Live preview | Best of both worlds |
| macOS toolbar | Unified in title bar | Platform convention |
| iOS toolbar | Floating bottom pill | Current implementation good |
| Breadcrumbs | In navigation area | Keep separate from content |
| Status bar | Minimal footer | Current implementation good |

---

*Document created: March 24, 2026*
*For Quartz markdown notes app - targeting Apple Design Award quality*
