#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from lib.notes_migration import DEFAULT_REPORT_ROOT, DEFAULT_VAULT_ROOT, configure_logging, load_people_config
from lib.relationship_updates import (
    default_people_config_path,
    relationship_inventory,
    write_relationship_inventory,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze the migrated Quartz vault for people and project relationships.")
    parser.add_argument(
        "--vault-root",
        type=Path,
        default=DEFAULT_VAULT_ROOT,
        help="Indexed Quartz vault root.",
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
        default=DEFAULT_REPORT_ROOT / "RELATIONSHIP_INVENTORY.json",
        help="Relationship inventory JSON output path.",
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
    payload = relationship_inventory(args.vault_root, people_config)
    write_relationship_inventory(args.output, payload)
    print(f"Wrote relationship inventory to {args.output}")
    print(f"Scanned {payload['summary']['notes_scanned']} markdown note(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
