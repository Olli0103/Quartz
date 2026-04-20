#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from todoist_reorg_lib import (
    MissingTodoistTokenError,
    TodoistClient,
    build_indexes,
    build_inventory,
    build_task_payload,
    compute_dry_run_plan,
    configure_logging,
    load_yaml_file,
    require_token,
    save_inventory_snapshot,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply the approved Todoist SAP reorg.")
    parser.add_argument(
        "--inventory",
        type=Path,
        default=Path("reports/current_inventory.json"),
        help="Where to write the fresh pre-apply inventory snapshot.",
    )
    parser.add_argument(
        "--target",
        type=Path,
        default=Path("todoist_target.yaml"),
        help="Target Todoist structure YAML.",
    )
    parser.add_argument(
        "--plan",
        type=Path,
        default=Path("todoist_migration_plan.yaml"),
        help="Migration routing YAML.",
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=Path("reports/backups"),
        help="Directory for timestamped JSON snapshots and optional official backup downloads.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Export the current inventory and print the apply summary without mutating Todoist.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually perform the planned changes after confirmation.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the interactive confirmation prompt after the summary is printed.",
    )
    parser.add_argument(
        "--download-latest-backup",
        action="store_true",
        help="Download the latest official Todoist backup before apply when the account permits it.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug logging.",
    )
    return parser.parse_args()


def print_summary(plan) -> None:
    print("Planned Todoist SAP reorg summary")
    print(f"- Projects to create: {plan.summary['projects_to_create']}")
    print(f"- Sections to create: {plan.summary['sections_to_create']}")
    print(f"- Labels to create: {plan.summary['labels_to_create']}")
    print(f"- Task actions: {plan.summary['task_actions']}")
    print(f"- Manual-review items left untouched: {plan.summary['manual_review']}")
    print(f"- Projects to archive: {plan.summary['projects_to_archive']}")


def main() -> int:
    args = parse_args()
    configure_logging(args.verbose)

    try:
        token = require_token("scripts/apply_todoist_reorg.py --inventory reports/current_inventory.json --target todoist_target.yaml --plan todoist_migration_plan.yaml --apply")
    except MissingTodoistTokenError as error:
        print(str(error), file=sys.stderr)
        return 2

    target_cfg = load_yaml_file(args.target)
    migration_cfg = load_yaml_file(args.plan)
    client = TodoistClient(token)

    inventory = build_inventory(
        client,
        generated_by="scripts/apply_todoist_reorg.py",
        download_latest_backup=args.download_latest_backup,
        backup_dir=args.backup_dir,
    )
    snapshot_path = save_inventory_snapshot(
        inventory,
        output_path=args.inventory,
        backup_dir=args.backup_dir,
    )
    print(f"Saved pre-apply inventory to {args.inventory}")
    print(f"Saved timestamped rollback snapshot to {snapshot_path}")

    plan = compute_dry_run_plan(inventory, target_cfg, migration_cfg)
    print_summary(plan)

    if not args.apply:
        print("No Todoist changes were applied. Re-run with --apply after reviewing the summary.")
        return 0

    if not args.yes:
        response = input("Type APPLY to continue: ").strip()
        if response != "APPLY":
            print("Cancelled. No Todoist changes were applied.")
            return 1

    root_name = target_cfg["root_project"]["name"]
    root_project = next(
        (project for project in inventory["projects"] if project["name"] == root_name and not project.get("parent_id")),
        None,
    )
    if root_project is None:
        raise RuntimeError(f"Root project '{root_name}' is missing.")

    for label_name in plan.labels_to_create:
        client.create_label(name=label_name)

    refreshed_inventory = build_inventory(
        client,
        generated_by="scripts/apply_todoist_reorg.py",
        download_latest_backup=False,
        backup_dir=args.backup_dir,
    )
    for project_item in plan.projects_to_create:
        client.create_project(name=project_item["name"], parent_id=root_project["id"])

    refreshed_inventory = build_inventory(
        client,
        generated_by="scripts/apply_todoist_reorg.py",
        download_latest_backup=False,
        backup_dir=args.backup_dir,
    )
    for section_item in plan.sections_to_create:
        child = next(
            (
                project
                for project in refreshed_inventory["projects"]
                if project["name"] == section_item["project"] and project.get("parent_id") == root_project["id"]
            ),
            None,
        )
        if child is None:
            raise RuntimeError(f"Target project '{section_item['project']}' is missing before section creation.")
        client.create_section(project_id=child["id"], name=section_item["section"])

    refreshed_inventory = build_inventory(
        client,
        generated_by="scripts/apply_todoist_reorg.py",
        download_latest_backup=False,
        backup_dir=args.backup_dir,
    )
    refreshed_indexes = build_indexes(refreshed_inventory)
    refreshed_plan = compute_dry_run_plan(refreshed_inventory, target_cfg, migration_cfg)

    for action in refreshed_plan.task_actions:
        payload = build_task_payload(action, inventory=refreshed_inventory, indexes=refreshed_indexes)
        if payload:
            client.update_task(action.task_id, payload)

    refreshed_inventory = build_inventory(
        client,
        generated_by="scripts/apply_todoist_reorg.py",
        download_latest_backup=False,
        backup_dir=args.backup_dir,
    )
    refreshed_plan = compute_dry_run_plan(refreshed_inventory, target_cfg, migration_cfg)
    for item in refreshed_plan.projects_to_archive:
        project = next((project for project in refreshed_inventory["projects"] if project["name"] == item["project"]), None)
        if project is not None:
            client.archive_project(project["id"])

    save_inventory_snapshot(
        build_inventory(
            client,
            generated_by="scripts/apply_todoist_reorg.py",
            download_latest_backup=False,
            backup_dir=args.backup_dir,
        ),
        output_path=args.inventory,
        backup_dir=args.backup_dir,
    )
    print("Todoist changes applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
