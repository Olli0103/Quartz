#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from todoist_reorg_lib import (
    MissingTodoistTokenError,
    TodoistClient,
    build_inventory,
    configure_logging,
    require_token,
    save_inventory_snapshot,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export Todoist projects, sections, labels, and tasks.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("reports/current_inventory.json"),
        help="Path to write the current inventory JSON.",
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=Path("reports/backups"),
        help="Directory for timestamped JSON snapshots and optional official backup downloads.",
    )
    parser.add_argument(
        "--download-latest-backup",
        action="store_true",
        help="Also download the latest official Todoist backup ZIP when the account permits it.",
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

    try:
        token = require_token("scripts/export_todoist.py --output reports/current_inventory.json --backup-dir reports/backups")
    except MissingTodoistTokenError as error:
        print(str(error), file=sys.stderr)
        return 2

    client = TodoistClient(token)
    inventory = build_inventory(
        client,
        generated_by="scripts/export_todoist.py",
        download_latest_backup=args.download_latest_backup,
        backup_dir=args.backup_dir,
    )
    snapshot_path = save_inventory_snapshot(
        inventory,
        output_path=args.output,
        backup_dir=args.backup_dir,
    )
    print(f"Wrote inventory to {args.output}")
    print(f"Wrote timestamped snapshot to {snapshot_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
