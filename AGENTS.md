# Todoist SAP Reorg Agents Guide

## Scope

This repository contains a local Todoist migration toolkit for restructuring SAP management work inside Todoist.

The toolkit must:

- keep Todoist focused on commitments and follow-ups
- avoid using Todoist for meeting notes or performance journals
- never delete tasks
- archive old projects only after actionable tasks are moved
- stop before any live Todoist mutation unless the operator explicitly confirms the apply step

## Credentials

- Read Todoist access from `TODOIST_API_TOKEN`
- Prefer the official Todoist REST API for active resources
- Use the Todoist Sync API only where the REST API does not cover the needed capability, such as project archive commands or official backup downloads

If `TODOIST_API_TOKEN` is missing, export and apply commands must fail fast and print exact setup instructions.

## Safety Rules

- Dry-run mode must not mutate Todoist
- Apply mode must print a summary before changing anything
- Ambiguous tasks go to manual review instead of guessed routing
- Person context belongs in the task title, not in labels or person-specific projects
- Legacy SAP labels on migrated SAP tasks should be replaced with the minimal label set when rules require it
- Private and wellbeing tasks stay outside SAP

## Default Workflow

1. Export the current Todoist state to JSON
2. Review the machine-readable config files
3. Generate the dry-run report
4. Review manual-review items
5. Run the apply script only after approval

## Commands

```bash
python3 scripts/export_todoist.py --output reports/current_inventory.json --backup-dir reports/backups
python3 scripts/dry_run_todoist_reorg.py --inventory reports/current_inventory.json --target todoist_target.yaml --plan todoist_migration_plan.yaml --report reports/DRY_RUN.md --dry-run
python3 scripts/apply_todoist_reorg.py --inventory reports/current_inventory.json --target todoist_target.yaml --plan todoist_migration_plan.yaml --apply
```
