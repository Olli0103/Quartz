# Quartz ADA Polish – Cursor Implementation Plan

## Purpose
This document is a **grounded implementation handover** for Cursor.
It is intentionally constrained to the code that was actually audited in the Quartz repository.
The goal is to implement the missing last 10% of polish required to move Quartz closer to the standard of apps like Things 3 or Bear **without speculative refactors or hallucinated APIs**.

This plan focuses on the approved scope:

1. Implement missing haptic feedback for primary actions.
2. Refactor the sidebar toward a more native `NavigationSplitView` / sidebar-list experience.
3. Enhance the Liquid Glass system with reusable mesh-backed depth and phase-driven motion.

---

## Ground Rules for Cursor

Cursor must follow these rules strictly:

1. **Do not invent files, types, services, or scene architecture.**
   Only modify files that exist in the repo unless a new file is explicitly called for in this plan.

2. **Search before changing.**
   Before editing a symbol, search the repository for all references to it.

3. **One workstream per commit.**
   Do not mix haptics, sidebar refactor, and Liquid Glass changes in a single large patch.

4. **Compile after every milestone.**
   If a change introduces build errors, fix them before moving on.

5. **Do not silently broaden scope.**
   No “while I’m here” refactors outside the files listed below unless required by compilation.

6. **Prefer additive design-system helpers over repeated inline logic.**

7. **Preserve current behavior unless this plan explicitly changes it.**
   Especially for drag & drop, selection, security-scoped access, and autosave.

8. **If an API or behavior is uncertain, verify it from existing repository usage first.**
   Do not guess.

---

## Audited Files That Define Current Behavior

These files were directly inspected and are the primary implementation targets:

- `Quartz/QuartzApp.swift`
- `Quartz/ContentView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AdaptiveLayoutView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AppState.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/ServiceContainer.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarViewModel.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/FileNodeRow.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorViewModel.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/MacEditorToolbar.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/FrontmatterEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/LiquidGlass.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/QuartzAnimation.swift`
- `QuartzKit/Sources/QuartzKit/Data/FileSystem/FileSystemVaultProvider.swift`
- `QuartzKit/Tests/QuartzKitTests/ViewModelTests.swift`

---

## What Was Observed

### 1. Sidebar structure is custom, not fully native
`SidebarView.swift` uses a `ScrollView` + `VStack` tree with custom row handling and drag/drop.
Quartz already uses `NavigationSplitView` in `AdaptiveLayoutView.swift`, but the sidebar container is not a native sidebar-style `List`.

### 2. Haptic feedback exists only in isolated places
There is some `sensoryFeedback` usage in `SidebarView.swift`, `NoteEditorView.swift`, and `DashboardView.swift`, but there is no central feedback policy and most primary actions do not have consistent tactile response.

### 3. Liquid Glass is decent but not systemic
`LiquidGlass.swift` already provides material-based chrome and some visionOS handling, but the mesh/depth story is mostly limited to onboarding. The shared design system does not yet provide a reusable ambient depth layer for the main app shell.

### 4. Motion is defined, but not orchestrated
`QuartzAnimation.swift` centralizes animations, but it is mostly a constants file. There is no phase-driven pattern for shell transitions, expansion states, or toolbar/chrome polish.

### 5. Architecture should not be widened during this pass
There are deeper scene/windowing issues, but this implementation plan intentionally does **not** attempt a full scene-architecture redesign.

---

# IMPLEMENTATION ORDER

Implement in this exact order:

1. Shared feedback layer
2. Wire feedback into primary actions
3. Sidebar shell refactor
4. Mesh-backed glass depth layer
5. Phase-based motion polish
6. Tests / validation pass

Do not skip ahead.

---

# WORKSTREAM 1 — Shared Feedback Layer

## Goal
Create a small design-system feedback helper so Quartz stops sprinkling feedback ad hoc across views.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/LiquidGlass.swift` **(do not modify here unless needed for namespace consistency)**
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/QuartzAnimation.swift`
- **New file:** `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/QuartzFeedback.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `Quartz/ContentView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/FrontmatterEditorView.swift`

## Required implementation
Create a reusable feedback abstraction with a minimal API like:

- `selection()`
- `primaryAction()`
- `success()`
- `warning()`
- `destructive()`
- `toggle()`

### Requirements
- On iOS, back the helper with `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`, or equivalent safe UIKit implementation.
- On macOS, make the implementation no-op unless there is already a native pattern in the repo.
- Do **not** break existing `sensoryFeedback` triggers that already work well. Replace them only when the new helper clearly improves consistency.
- Keep the helper extremely small and deterministic.

## Primary actions that must use the helper

### In `SidebarView.swift`
Add feedback for:
- Quick Access row selection
- Tag filter selection / clear
- New note creation trigger
- New folder creation trigger
- Move-to-folder action
- Successful drop/move action
- Delete confirmation action

### In `NoteEditorView.swift`
Add feedback for:
- Manual save button
- Favorite toggle
- Focus mode toggle
- Preview mode toggle
- AI & Tools menu entry taps that trigger sheets
- Export-as-PDF action
- Tag add/remove actions
- Link suggestion apply action

### In `FrontmatterEditorView.swift`
Add feedback for:
- Expand/collapse
- Add tag
- Remove tag
- Add custom field

### In `ContentView.swift`
Add feedback for:
- Open vault
- Search open
- Chat with vault open
- New note trigger
- Refresh trigger
- Dismiss error banner

## Acceptance criteria
- There is a single reusable feedback helper in the design system.
- Primary actions feel consistent instead of random.
- No duplicated haptic boilerplate is spread across views.
- The app still builds on macOS, iOS, and visionOS targets.

## Non-goals
- Do not attempt advanced CoreHaptics choreography.
- Do not add feedback to every single tap in the app.

---

# WORKSTREAM 2 — Sidebar Refactor Toward Native Sidebar Behavior

## Goal
Retain Quartz’s existing tree logic and drag/drop behavior, but move the sidebar shell closer to native Apple sidebar conventions.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/FileNodeRow.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AdaptiveLayoutView.swift`
- `Quartz/ContentView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarViewModel.swift`

## Required implementation

### 2.1 Replace the outer custom shell with a native sidebar list where feasible
Refactor the sidebar’s top-level structure so the main content is hosted in a `List` or a sidebar-styled native list container instead of a pure `ScrollView` + `VStack` shell.

### 2.2 Preserve current sections
Retain these sections:
- New Note CTA
- Quick Access
- Tags
- Folders
- macOS Map View / Trash section if still present

### 2.3 Preserve current behaviors
Do not regress:
- Drag & drop move behavior
- Spring-open folder behavior
- Context menus
- Swipe actions on iOS
- Selection binding via `selectedNoteURL`
- Search behavior
- Empty state behavior

### 2.4 Improve macOS-native affordances
Add at least one of the following in a grounded way, based on existing architecture:
- macOS-specific `Open in New Window` context action for notes, or
- explicit double-click handling for notes on macOS

Important:
- Only implement new-window behavior if it can be done safely with the current scene setup.
- If safe new-window support cannot be completed without architectural broadening, implement **context-level affordance only** and leave a TODO comment referencing scene isolation work.
- Do not fake multiwindow support.

### 2.5 Apply native sidebar styling
Use the most native available sidebar list style for the platform. Avoid introducing a custom style that only imitates sidebar appearance.

## Acceptance criteria
- Sidebar still functions correctly.
- The container feels more like a native Apple sidebar.
- Keyboard / selection behavior is not worse than before.
- Drag/drop still works.
- The implementation is smaller or cleaner at the container level, even if row logic stays custom.

## Non-goals
- Do not redesign the full tree model.
- Do not rewrite drag/drop logic from scratch.
- Do not perform a full multiwindow scene architecture refactor.

---

# WORKSTREAM 3 — Liquid Glass Depth System

## Goal
Promote MeshGradient depth from a one-off onboarding flourish into a reusable ambient design-system layer for the main app shell and floating chrome.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/LiquidGlass.swift`
- `Quartz/ContentView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Onboarding/OnboardingView.swift` **(only if deduplication is needed)**

## Required implementation

### 3.1 Add a reusable ambient depth background
Create a reusable design-system view or modifier for subtle mesh-backed depth, for example:
- `QuartzAmbientMeshBackground`
- `quartzAmbientGlassBackground(...)`

### 3.2 Use it only where it improves shell depth
Candidate placements:
- Main app shell background in `ContentView.swift`
- Editor chrome / header surfaces if subtle and not distracting
- Floating toolbars or overlays where current material feels flat

### 3.3 Respect accessibility and platform boundaries
- Reduce motion path must remain calm.
- Do not create a noisy animated background behind text-heavy editing surfaces.
- Keep the effect subtle.
- Preserve visionOS-specific `glassBackgroundEffect()` behavior already present.

### 3.4 Avoid duplicating onboarding mesh logic
If onboarding and app shell need the same mesh system, extract shared code instead of cloning it.

## Acceptance criteria
- The design system now has a reusable ambient depth layer.
- The main shell feels less flat.
- No readability regressions.
- No visual over-design.

## Non-goals
- Do not animate backgrounds aggressively.
- Do not make the editor canvas itself visually busy.

---

# WORKSTREAM 4 — Phase-Based Motion Polish

## Goal
Add more intentional state transitions using modern SwiftUI motion patterns instead of plain animation constants everywhere.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/QuartzAnimation.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/MacEditorToolbar.swift`

## Required implementation

### 4.1 Extend the motion language
Add one or two focused phase-driven patterns for:
- folder expansion / spring-open state
- preview/edit toggle
- focus mode toggle
- maybe toolbar state transitions if it remains simple

### 4.2 Use the new patterns in real interaction points
Do not just add more constants to `QuartzAnimation.swift`.
Actually apply them to:
- folder expansion in the sidebar
- preview mode toggle in the editor
- focus mode hint/chrome transitions if beneficial

### 4.3 Keep motion interruptible and understated
Quartz is a notes app, not a demo reel.
Motion should communicate state, not perform.

## Acceptance criteria
- The app feels more responsive and polished.
- Expand/collapse transitions feel intentional.
- Motion still respects `reduceMotion`.

## Non-goals
- Do not add animation to every property change.
- Do not introduce fragile chained animations.

---

# TEST AND VALIDATION PASS

## Files to inspect / update
- `QuartzKit/Tests/QuartzKitTests/ViewModelTests.swift`
- Any existing snapshot or UI tests if present

## Required validation

### Build validation
Cursor must confirm:
- Quartz app target builds
- QuartzKit package builds
- No platform guard regressions on iOS/macOS/visionOS

### Manual validation checklist

#### Sidebar
- Can still select notes
- Can still filter by tag
- Can still create note/folder
- Can still drag note into folder
- Can still delete note/folder
- Search still works

#### Editor
- Manual save still works
- Favorite toggle still works
- Preview/edit toggle still works
- Focus mode still works
- Tag add/remove still works
- Link suggestion apply still works
- Export still works

#### Shell
- Open vault still works
- Search sheet still opens
- Chat with vault still opens
- Settings still accessible

#### Accessibility / comfort
- Reduce Motion path still compiles and behaves correctly
- No new clipping in tag badges or toolbar chrome
- No unreadable mesh backgrounds behind editor text

---

# ANTI-HALLUCINATION EXECUTION TEMPLATE FOR CURSOR

Use this exact working pattern for each workstream:

## Step 1
Search for all references to the target symbols and files.

## Step 2
Make the smallest possible grounded patch.

## Step 3
Build.

## Step 4
List exactly what changed and why.

## Step 5
Only then proceed to the next workstream.

If something cannot be implemented safely because the current architecture is not ready, Cursor must:
- stop broadening scope,
- leave a concise TODO,
- and report the blocker explicitly.

---

# DELIVERABLES EXPECTED FROM CURSOR

Cursor should produce:

1. A series of small commits or checkpoints:
   - `feat: add shared feedback layer`
   - `refactor: move sidebar shell toward native list behavior`
   - `feat: add ambient mesh-backed glass depth`
   - `feat: polish interaction motion with phased transitions`

2. A final implementation note summarizing:
   - files changed
   - behaviors improved
   - any deliberate deferrals
   - any architecture blockers discovered

---

# WHAT NOT TO DO

- Do not rewrite the app around documents/scenes in this pass.
- Do not invent Spotlight, Handoff, or Quick Look implementation in this pass.
- Do not change `FileSystemVaultProvider` behavior unless required by compilation.
- Do not replace working drag/drop with a new model just because the container changes.
- Do not turn the UI into a visual experiment.

---

# FINAL SUCCESS DEFINITION

This plan succeeds if Quartz feels:
- more native,
- more tactile,
- more spatially layered,
- and more intentional in motion,

**without** widening the architecture beyond what the current audited code can support safely.
