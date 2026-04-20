# Notes Migration Plan

This repository contains a dry-run-first migration toolchain for exported Apple Notes Markdown files.

## Defaults

- Source root: `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/iCloud`
- Indexed vault root: `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/notes`
- Report root: `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports`

Reports live outside the indexed Quartz vault on purpose so they do not create backlink noise.

## Workflow

1. Run inventory to scan source exports and produce `NOTES_INVENTORY.json`.
2. Run planning to classify notes, compute proposed targets, detect collisions, and generate dry-run reports.
3. Review:
   - `NOTES_DRY_RUN.md`
   - `MANUAL_REVIEW.md`
   - `BASENAME_COLLISIONS.md`
4. Do not run apply until the dry run has been reviewed and approved.

## Safety Rules

- Never mutate source exports in place.
- Never write runtime reports inside the indexed vault by default.
- Prefer manual review over guessed links or guessed routing.
- Treat `Private/` and `Recently Deleted/` conservatively and route them to manual review unless a later policy says otherwise.
- Treat duplicate case-insensitive basenames as blockers.

## Commands

```bash
python3 /Users/I533181/Developments/Quartz/scripts/inventory_notes.py \
  --source '/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/iCloud' \
  --output '/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports/NOTES_INVENTORY.json'

python3 /Users/I533181/Developments/Quartz/scripts/plan_notes_migration.py \
  --inventory '/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports/NOTES_INVENTORY.json' \
  --target-root '/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/notes' \
  --report-root '/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports' \
  --dry-run
```

`apply_notes_migration.py` exists for the later approved phase, but this workflow stops after the dry run.
