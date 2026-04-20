# Apple Notes Migration

This repository includes a Python migration toolchain for exported Apple Notes Markdown files.

## Fixed Paths

- Source root: `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/iCloud`
- Indexed vault root: `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/notes`
- Runtime report root: `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports`

Runtime reports are intentionally written outside the indexed vault so Quartz does not index them as notes or backlinks.

## Scripts

- `scripts/inventory_notes.py`
  - scans source exports
  - records metadata, candidate types, people matches, project hints, and local asset refs
  - writes `NOTES_INVENTORY.json`
- `scripts/plan_notes_migration.py`
  - reads the inventory
  - computes proposed destinations
  - identifies canonical people notes to create
  - detects basename collisions
  - proposes body wiki links
  - writes dry-run reports
- `scripts/apply_notes_migration.py`
  - creates target directories
  - creates canonical person notes if missing
  - copies or transforms notes into the target vault
  - injects deterministic `## Related` wiki-link sections
  - refuses unresolved basename collisions by default

## Dry-Run First

Run only these commands during the review phase:

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

Expected outputs:

- `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports/NOTES_INVENTORY.json`
- `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports/NOTES_DRY_RUN.md`
- `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports/MANUAL_REVIEW.md`
- `/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports/BASENAME_COLLISIONS.md`

Stop there. Do not run apply until the dry run has been reviewed.
