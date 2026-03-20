# Quartz ADA Final Mile – Updated Cursor Implementation Plan

## Purpose
This is the **updated, repo-grounded implementation plan** for Quartz after the first ADA polish pass has already landed on `main`.

The following improvements are **already implemented** and should **not** be reworked unless required by a build fix:

- shared tactile feedback layer (`QuartzFeedback`)
- native-feeling sidebar shell via `List` + `.sidebar`
- ambient mesh-backed shell/editor chrome depth
- focused motion polish for folder expansion, preview/edit toggle, and focus chrome

This plan addresses the **remaining gaps** between Quartz and the standard of apps like Things 3 or Bear.

---

## Current State Summary

### Already improved
- Sidebar feels significantly more native
- Primary actions have consistent tactile feedback
- Shell and editor header have better depth and hierarchy
- Motion feels more deliberate and less stiff

### Still missing or incomplete
1. Real macOS multiwindow note opening
2. Spotlight indexing for notes
3. Handoff / NSUserActivity
4. Quick Look support for assets and exported files
5. Accessibility custom actions beyond basic labels
6. Final macOS toolbar refinement
7. Dynamic type hardening for chips / compact chrome

---

## Ground Rules for Cursor

Cursor must follow these rules strictly:

1. **Do not reopen finished workstreams unless a bug is found.**
2. **Do not broaden scope into a full document-based or scene-based rewrite.**
3. **Search before changing.**
4. **One workstream per commit.**
5. **Build after every workstream.**
6. **If scene architecture blocks a feature, implement the safest narrow step and document the blocker.**
7. **No invented Apple APIs, no pseudo-code patches, no speculative infrastructure.**
8. **Prefer small additions over structural rewrites.**

---

## Primary Files Likely In Scope

- `Quartz/QuartzApp.swift`
- `Quartz/ContentView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AdaptiveLayoutView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AppState.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/ServiceContainer.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/FileNodeRow.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/MacEditorToolbar.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/LiquidGlass.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/QuartzAnimation.swift`

### New files that are acceptable if needed
- `QuartzKit/Sources/QuartzKit/Presentation/App/QuartzUserActivity.swift`
- `QuartzKit/Sources/QuartzKit/Data/FileSystem/QuartzSpotlightIndexer.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/QuickLook/QuartzQuickLookPreview.swift`

Do not add more new files unless necessary.

---

# IMPLEMENTATION ORDER

Implement in this exact order:

1. Real macOS multiwindow groundwork
2. Spotlight indexing
3. Handoff / NSUserActivity
4. Quick Look support
5. Accessibility custom actions
6. Dynamic type hardening
7. macOS toolbar final refinement
8. Validation pass

---

# WORKSTREAM 5 — Real macOS Multiwindow Groundwork

## Goal
Replace the current disabled “Open in New Window” affordance with a **real, minimal, safe implementation**, or narrow the UI to avoid advertising unsupported behavior.

## Why this matters
Quartz currently exposes the intent but not the behavior. That feels unfinished on macOS.

## Files to inspect first
- `Quartz/QuartzApp.swift`
- `Quartz/ContentView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AppState.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift`

## Required implementation
Cursor must do one of these two grounded paths:

### Preferred path
Implement actual per-note window opening on macOS using the smallest safe scene-based approach supported by the current app structure.

Requirements:
- opening a note in a new window must open that note directly
- the original window must remain intact
- no global-state corruption
- no fake or placeholder menu item

### Fallback path if architecture blocks safe implementation
- remove the disabled “Open in New Window” item
- replace it with no affordance at all
- add a TODO comment only in code, not in UI
- document what architectural change is still needed

## Acceptance criteria
- No disabled dead-end menu item remains
- Either new-window behavior is real, or the stub is removed
- No regressions in note selection or deep linking

## Non-goals
- Full document-based app rewrite
- Full scene isolation refactor

---

# WORKSTREAM 6 — Spotlight Indexing

## Goal
Make notes discoverable through Spotlight.

## Why this matters
This is one of the clearest “real Apple app” differentiators still missing.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift`
- `QuartzKit/Sources/QuartzKit/Data/FileSystem/VaultSearchIndex.swift`
- `QuartzKit/Sources/QuartzKit/Domain/Models/NoteDocument.swift` if needed
- new file if needed: `QuartzKit/Sources/QuartzKit/Data/FileSystem/QuartzSpotlightIndexer.swift`

## Required implementation
Add Core Spotlight indexing for notes using stable identifiers.

Index at least:
- note title
- note file URL / stable ID
- tags if available
- short body excerpt
- modified date

Trigger indexing at sensible times:
- after vault load
- after note save
- after vault reindex if that path already exists

## Requirements
- keep indexing async and non-blocking
- do not duplicate existing in-app search responsibilities
- keep stable identifiers aligned with file URLs or existing stable note ID logic

## Acceptance criteria
- Notes are submitted to Core Spotlight
- Reindexing path exists
- Delete / rename handling is accounted for, even if minimal
- No UI jank during indexing

## Non-goals
- Full semantic Spotlight metadata model
- Search UI redesign

---

# WORKSTREAM 7 — Handoff / NSUserActivity

## Goal
Allow Quartz to continue a note session across devices in a system-native way.

## Why this matters
Handoff is still absent and is an Apple Design Awards-level integration gap.

## Files to modify
- `Quartz/ContentView.swift`
- `Quartz/QuartzApp.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/App/AdaptiveLayoutView.swift`
- new file if needed: `QuartzKit/Sources/QuartzKit/Presentation/App/QuartzUserActivity.swift`

## Required implementation
Create a small, reusable NSUserActivity helper for:
- currently open note
- optionally active search session, if simple

The activity must contain enough information to reopen the note safely:
- vault-relative path or validated deep-link equivalent
- human-readable title
- eligibility flags for Handoff

Use current deep-linking patterns where possible instead of inventing a parallel routing model.

## Acceptance criteria
- Opening a note updates user activity
- Activity encodes enough info to resume that note safely
- Implementation reuses current deep-link / note-opening model where possible

## Non-goals
- Cloud sync redesign
- cross-account collaboration

---

# WORKSTREAM 8 — Quick Look Support

## Goal
Provide system-native preview behavior for assets where it meaningfully improves the workflow.

## Why this matters
Quick Look is a high-signal Apple affordance and currently absent.

## Files to inspect
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- asset-related editor/image import/export files
- new file if needed: `QuartzKit/Sources/QuartzKit/Presentation/QuickLook/QuartzQuickLookPreview.swift`

## Required implementation
Add Quick Look preview support for at least one grounded flow:
- imported images
- PDFs
- exported files
- attachments/assets if already represented in the UI

Pick the narrowest flow that already exists in the product rather than inventing a full asset browser.

## Acceptance criteria
- At least one real asset/file flow can be previewed with Quick Look
- No duplicate custom preview UI is introduced where Quick Look is enough
- macOS and iOS behavior remain platform-correct

## Non-goals
- Custom gallery system
- asset management redesign

---

# WORKSTREAM 9 — Accessibility Custom Actions

## Goal
Move accessibility beyond labels into alternative interaction paths.

## Why this matters
Quartz still feels behind in accessibility depth compared with the rest of the polish work.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/FileNodeRow.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`

## Required implementation
Add `AccessibilityCustomActions` or equivalent SwiftUI accessibility actions for note rows and primary entities.

Target actions:
- add/remove favorite
- move to folder
- delete
- maybe open / preview depending on the row

Requirements:
- actions must map to real existing behaviors
- do not invent parallel state logic
- do not expose actions that are unavailable on that row type

## Acceptance criteria
- Note rows expose more than static labels
- VoiceOver users can trigger common actions without relying only on context menus or swipe gestures
- No action duplication causes ambiguity

## Non-goals
- Full accessibility audit across every screen in the repo

---

# WORKSTREAM 10 — Dynamic Type Hardening

## Goal
Strengthen compact UI components against clipping, crowding, or fragile layout under larger text sizes.

## Why this matters
`QuartzTagBadge` and compact chrome still look like likely weak points under aggressive text scaling.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/LiquidGlass.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/FrontmatterEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarView.swift`

## Required implementation
At minimum:
- harden `QuartzTagBadge`
- review compact chips/badges/tokens in editor and sidebar
- use `@ScaledMetric` where needed
- ensure adequate vertical padding and line behavior

Requirements:
- prefer resilient layouts over forcing a one-line aesthetic
- no clipping at larger accessibility text sizes
- avoid exploding row heights unless necessary

## Acceptance criteria
- Tag badges do not clip or look cramped at larger text sizes
- compact controls stay tappable and legible
- no major layout breakage in sidebar/editor chrome

## Non-goals
- complete redesign of chip visuals

---

# WORKSTREAM 11 — macOS Toolbar Final Refinement

## Goal
Make the Mac toolbar feel less like a custom formatting bar mounted in `.principal`, and more like true macOS chrome.

## Why this matters
This is one of the last aesthetic/systemic gaps after the first polish pass.

## Files to modify
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/MacEditorToolbar.swift`
- `QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteEditorView.swift`
- `Quartz/ContentView.swift`

## Required implementation
Refine toolbar hierarchy without reopening broad editor architecture.

Potential improvements:
- reduce density in `.principal`
- move some controls into more appropriate toolbar placements if safe
- reduce duplication between editor header identity and toolbar identity
- keep the toolbar visually calmer on macOS

## Requirements
- do not remove core actions users now rely on
- do not break keyboard shortcuts
- do not create platform divergence where iOS and macOS logic become impossible to maintain

## Acceptance criteria
- macOS toolbar looks more like native window chrome
- principal area is less overloaded
- no regression in discoverability of core actions

## Non-goals
- complete editor-header redesign

---

# VALIDATION PASS

## Build validation
Cursor must confirm:
- app target builds
- package target builds
- no macOS-only API leaks into iOS or visionOS
- no regressions in existing workstreams 1–4

## Manual validation checklist

### Multiwindow
- context menu does not contain a dead stub
- if implemented, new window opens real note context

### Spotlight
- notes appear in Spotlight after indexing
- renamed/deleted notes do not accumulate obvious stale garbage

### Handoff
- current note session emits valid user activity
- resuming the note path still respects vault path safety

### Quick Look
- at least one real asset flow previews correctly

### Accessibility
- VoiceOver actions exist on note rows where appropriate
- no ambiguity or double announcements

### Dynamic Type
- tags and compact chrome remain legible at larger sizes
- no clipping in badges and pills

### Toolbar
- Mac toolbar still exposes needed actions
- toolbar feels calmer and more native

---

# ANTI-HALLUCINATION EXECUTION TEMPLATE

Use this exact pattern for each remaining workstream:

## Step 1
Search all references to the target files and symbols.

## Step 2
Describe the smallest safe implementation path.

## Step 3
Patch only that path.

## Step 4
Build.

## Step 5
Report:
- files changed
- what now works
- what remains blocked

Stop after each workstream unless explicitly told to continue.

---

# WHAT NOT TO DO

- Do not rewrite Quartz into a full document-based app
- Do not invent unsupported scene routing abstractions
- Do not add a second search system unrelated to Spotlight
- Do not implement fake UI affordances for features that still do nothing
- Do not regress the already completed haptics/sidebar/liquid glass/motion work

---

# Success Definition

This updated plan succeeds if Quartz reaches the point where:

- it feels fully intentional on macOS,
- participates in core Apple system workflows,
- avoids unfinished affordances,
- and closes the remaining “great app” vs “award-level app” gap.

That means Quartz should feel not only polished **inside** the app, but also genuinely integrated **with the platform**.
