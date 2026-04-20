#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from todoist_reorg_lib import (
    compute_dry_run_plan,
    configure_logging,
    load_json_file,
    load_yaml_file,
    render_dry_run_markdown,
    write_text_file,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a dry-run Todoist SAP reorg report.")
    parser.add_argument(
        "--inventory",
        type=Path,
        default=Path("reports/current_inventory.json"),
        help="Inventory JSON file produced by scripts/export_todoist.py.",
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
        "--report",
        type=Path,
        default=Path("reports/DRY_RUN.md"),
        help="Markdown report output path.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Explicit no-op flag for parity with the apply script.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug logging.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    configure_logging(args.verbose)

    inventory = load_json_file(args.inventory)
    target_cfg = load_yaml_file(args.target)
    migration_cfg = load_yaml_file(args.plan)

    plan = compute_dry_run_plan(inventory, target_cfg, migration_cfg)
    markdown = render_dry_run_markdown(
        plan,
        inventory=inventory,
        target_cfg=target_cfg,
        migration_cfg=migration_cfg,
    )
    write_text_file(args.report, markdown)

    print(f"Wrote dry-run report to {args.report}")
    print(
        "Summary:"
        f" {plan.summary['projects_to_create']} project(s) to create,"
        f" {plan.summary['sections_to_create']} section(s) to create,"
        f" {plan.summary['labels_to_create']} label(s) to create,"
        f" {plan.summary['task_actions']} task action(s),"
        f" {plan.summary['manual_review']} manual-review item(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
