#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from lib.notes_migration import (
    DEFAULT_REPORT_ROOT,
    DEFAULT_SOURCE_ROOT,
    configure_logging,
    default_people_config_path,
    inventory_notes,
    load_people_config,
    write_json_output,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Inventory exported Apple Notes Markdown files.")
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE_ROOT,
        help="Source Apple Notes export root.",
    )
    parser.add_argument(
        "--people-config",
        type=Path,
        default=default_people_config_path(),
        help="People configuration YAML file.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_REPORT_ROOT / "NOTES_INVENTORY.json",
        help="Inventory JSON output path.",
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
    people_config = load_people_config(args.people_config)
    payload = inventory_notes(args.source, people_config)
    write_json_output(args.output, payload)
    print(f"Wrote inventory to {args.output}")
    print(f"Scanned {payload['summary']['total_notes']} markdown note(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
