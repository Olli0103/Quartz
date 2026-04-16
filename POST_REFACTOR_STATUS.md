# Post-Refactor Status

## Completed Milestones

### M1: Routing Unification

- Toolbar, hardware-keyboard, and command/menu formatting now converge through one shared resolver before mutation
- Formatting-path parity was preserved across macOS, iPad, and iPhone

### M2: Selection, Focus, and Lifecycle Stabilization

- Runtime selection ownership was clarified around the live native editor
- Mirrored selection state was reduced to a derived snapshot role
- Restoration and startup readiness became explicit instead of inferred

### M3: Semantic Markdown / Render Cleanup

- One authoritative semantic span pipeline now drives in-scope render semantics
- Duplicated AST/regex semantic authority was reduced for links, emphasis, code, math, images, and related spans
- Long-document parsing/highlighting headroom improved without changing storage format

### M4: Identity, Sync-Safety, and External-Change Hardening

- Canonical note identity now aligns routing, editor binding, persistence, and window flows
- Clean external changes preserve user context where safely possible
- Dirty-local vs external-change behavior is explicit and non-destructive

### M5: Product Truthfulness, Parity, and Polish

- Misleading affordances were either wired honestly or de-scoped
- Search Notes remained vault-wide and truthful
- Backlinks became surfaced in the inspector instead of remaining implicit-only infrastructure
- Typewriter mode, preview exposure, and shallow footnote affordances were de-scoped honestly

### Shipped Feature: Real In-Note Find / Replace

- `Find in Note` is now a real editor-scoped feature
- `Search Notes` remains separate and vault-wide
- Current-note-only find supports:
  - query input
  - current match and total count
  - next / previous navigation
  - reveal and select current match
  - replace current
  - replace all in the active note only

## Technical Changes

- Shared formatting routing replaced divergent mutation entry paths
- Selection/focus authority moved closer to the native editor rather than heuristics
- Semantic rendering now relies on a single render-authoritative span model for the stabilized constructs
- Canonical file-URL identity now anchors note routing and external-change handling
- Product-surface cleanup removed misleading settings and labels without destabilizing the editor core
- In-note find/replace was implemented editor-locally and routed through established mutation semantics

## User-Visible Product Changes

- Formatting behaves consistently across toolbar, keyboard shortcuts, and command/menu entry points
- Cursor and selection stability improved during formatting, note switching, and restoration
- External clean reloads preserve context more safely
- Search Notes and Find in Note are now separate and honest concepts
- Backlinks are visible in the inspector
- Typewriter mode is no longer exposed as if it were shipped
- Preview is no longer treated as a shipped product capability

## Intentionally De-Scoped

- True live typewriter mode
- Live preview mode
- Rich backlinks workflow beyond inspector surfacing
- Regex search mode
- Whole-word search mode
- Sync-provider redesign
- External structural merge for conflicting content
- New semantic markdown constructs beyond the stabilized in-scope pipeline

## Remaining Benchmark Gaps

### Bear

- Folding remains missing
- Callouts remain missing
- Link previews remain missing
- Backlinks are surfaced but still not a richer interlinking workflow

### iA Writer

- No true live typewriter mode
- Current-note find/replace is solid, but not yet a more polished writing-environment search workflow

### Ulysses

- No live preview mode
- Long-form writing workflow polish remains incomplete

### Antinote

- Interaction immediacy is stronger than before, but lightweight delight and utility still have headroom

## Overall Status

The editor refactor and product-hardening cycle is complete for the work that was explicitly in scope. The subsystem is materially stronger, more honest, and more deterministic than the pre-refactor state.

What remains is mostly future product work, performance/test reliability follow-up, and benchmark-closing polish rather than unfinished milestone architecture.
