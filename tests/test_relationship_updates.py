from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from lib.notes_migration import DEFAULT_VAULT_ROOT, is_within, load_people_config  # noqa: E402
from lib.relationship_updates import (  # noqa: E402
    apply_relationship_plan,
    current_related_block,
    default_people_config_path,
    replace_or_append_generated_block,
    relationship_inventory,
    relationship_plan,
    render_related_block,
    write_relationship_reports,
)


PEOPLE_CONFIG = load_people_config(default_people_config_path())


def write_note(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


class RelationshipUpdateTests(unittest.TestCase):
    def test_person_relationship_detection_for_dedicated_note(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            write_note(
                vault_root / "people" / "directs" / "Alexandra.md",
                "---\ntype: person\n---\n\n# Alexandra\n",
            )
            write_note(
                vault_root / "meetings" / "2026" / "02" / "2026-02-24 24.02.2026 (Alexandra).md",
                "# 24.02.2026 (Alexandra)\n\n## Current priorities\n- ServiceNow AI implementation timing remains open.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            note = next(item for item in inventory["notes"] if item["note_type"] == "meeting")
            alexandra = next(item for item in note["people_relationships"] if item["name"] == "Alexandra")

            self.assertEqual(alexandra["confidence"], 0.95)
            self.assertTrue(alexandra["auto_link"])

    def test_project_relationship_detection_and_creation_threshold(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            write_note(vault_root / "people" / "directs" / "Tom.md", "# Tom\n")
            write_note(
                vault_root / "meetings" / "2026" / "03" / "2026-03-01 AppOps Steering.md",
                "# AppOps Steering\n\n- AppOps dashboard rollout is blocked by missing ownership.\n",
            )
            write_note(
                vault_root / "meetings" / "2026" / "03" / "2026-03-02 AppOps Dashboard Review.md",
                "# AppOps Dashboard Review\n\n- Tom is aligning the AppOps dashboard rollout with operations.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            plan = relationship_plan(inventory, vault_root)

            self.assertTrue(any(item["project"] == "AppOps" for item in plan["project_creates"]))

    def test_taxonomy_reference_project_is_not_recreated(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            taxonomy_path = Path(tmpdir) / "project_taxonomy.yml"
            taxonomy_path.write_text("active:\nreference:\n  - AppOps\narchive:\nmanual_review:\n", encoding="utf-8")
            write_note(
                vault_root / "meetings" / "2026" / "03" / "2026-03-01 AppOps Steering.md",
                "# AppOps Steering\n\n- AppOps dashboard rollout is blocked by missing ownership.\n",
            )
            write_note(
                vault_root / "meetings" / "2026" / "03" / "2026-03-02 AppOps Dashboard Review.md",
                "# AppOps Dashboard Review\n\n- AppOps dashboard rollout remains active.\n",
            )

            with patch("lib.relationship_updates.default_project_taxonomy_path", return_value=taxonomy_path):
                inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
                plan = relationship_plan(inventory, vault_root)

            self.assertFalse(any(item["project"] == "AppOps" for item in plan["project_creates"]))
            self.assertEqual(plan["summary"]["basename_collisions"], 0)

    def test_tom_vs_thomas_and_alex_vs_alexandra_are_distinct(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            for name in ("Tom", "Thomas", "Alex", "Alexandra"):
                write_note(vault_root / "people" / "directs" / f"{name}.md", f"# {name}\n")
            write_note(
                vault_root / "meetings" / "2026" / "03" / "2026-03-09 Status.md",
                "# Status\n\n- Tom reviewed rollout details with Thomas.\n- Alex synced with Alexandra on dataset ownership.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            note = next(item for item in inventory["notes"] if item["note_type"] == "meeting")
            names = {item["name"] for item in note["people_relationships"]}

            self.assertEqual(names, {"Alex", "Alexandra", "Thomas", "Tom"})

    def test_person_enrichment_uses_source_links(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            write_note(
                vault_root / "people" / "directs" / "Alexandra.md",
                "---\ntype: person\n---\n\n# Alexandra\n",
            )
            write_note(
                vault_root / "meetings" / "2026" / "02" / "2026-02-24 24.02.2026 (Alexandra).md",
                "# 24.02.2026 (Alexandra)\n\n- Main challenge: no fixed go-live date for ServiceNow AI implementation.\n- Need alignment on accepted demands and rollout timing.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            plan = relationship_plan(inventory, vault_root)
            alexandra = next(item for item in plan["person_updates"] if item["person"] == "Alexandra")

            self.assertIn("Source: [[2026-02-24 24.02.2026 (Alexandra)]]", alexandra["generated_block"])
            self.assertIn("## Synthesized from source notes", alexandra["generated_block"])

    def test_existing_wiki_links_are_not_duplicated_in_related_block(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            write_note(vault_root / "projects" / "AI.md", "# AI\n")
            write_note(
                vault_root / "meetings" / "2026" / "03" / "2026-03-02 Monthly AI.md",
                "# Monthly AI\n\nThis note already links [[AI]] in the body.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            note = next(item for item in inventory["notes"] if item["note_type"] == "meeting")

            self.assertEqual(note["missing_links_to_inject"], [])
            self.assertEqual(note["proposed_related_block"], "")

    def test_related_section_injection_is_grouped_and_has_no_backlinks_section(self) -> None:
        block = render_related_block(["Alexandra", "Tom"], ["AppOps Dashboard", "AI"])
        self.assertEqual(
            block,
            "## Related\n- People: [[Alexandra]], [[Tom]]\n- Projects: [[AppOps Dashboard]], [[AI]]\n\n",
        )
        self.assertNotIn("Backlinks", block)

    def test_reports_are_written_outside_vault(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            report_root = Path(tmpdir) / "reports"
            write_note(vault_root / "people" / "directs" / "Tom.md", "# Tom\n")
            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            plan = relationship_plan(inventory, vault_root)
            report_paths = write_relationship_reports(plan, report_root, vault_root)

            self.assertTrue(all(path.exists() for path in report_paths.values()))
            self.assertTrue(all(not is_within(path, vault_root) for path in report_paths.values()))
            self.assertFalse(is_within(report_root, DEFAULT_VAULT_ROOT))

    def test_no_manual_backlinks_section_is_created_anywhere(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            write_note(vault_root / "people" / "directs" / "Tom.md", "# Tom\n")
            write_note(
                vault_root / "meetings" / "2026" / "02" / "2026-02-05 Delivery Tool Alignment.md",
                "# Delivery Tool Alignment\n\n- Tom is aligning ESP rollout.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            plan = relationship_plan(inventory, vault_root)

            rendered = "\n".join(
                [
                    *(item["generated_block"] for item in plan["person_updates"]),
                    *(item["generated_block"] for item in plan["project_updates"]),
                    *(item["generated_block"] for item in plan["project_creates"]),
                    *(item["proposed_related_block"] for item in plan["link_updates"]),
                ]
            )
            self.assertNotIn("Backlinks", rendered)

    def test_granola_style_related_section_normalizes_without_eating_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            report_root = Path(tmpdir) / "reports"
            write_note(vault_root / "people" / "directs" / "Steffen.md", "# Steffen\n")
            write_note(vault_root / "people" / "directs" / "Thomas.md", "# Thomas\n")
            meeting_path = vault_root / "meetings" / "2025" / "08" / "2025-08-07 1 1 Steffen Olli.md"
            write_note(
                meeting_path,
                "# 1:1 Steffen <> Olli\n\n"
                "## Related\n\n"
                "- [[Steffen]]\n"
                "- [[Thomas]]\n\n"
                "- Note ID: abc123\n"
                "- Calendar Event: 1:1 Steffen <> Olli\n\n"
                "### Top of mind\n"
                "- Delivery remains blocked.\n",
            )

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            plan = relationship_plan(inventory, vault_root)
            self.assertEqual(len(plan["link_updates"]), 1)
            self.assertEqual(
                current_related_block(meeting_path.read_text(encoding="utf-8")),
                "## Related\n\n- [[Steffen]]\n- [[Thomas]]\n\n",
            )

            result = apply_relationship_plan(plan, vault_root=vault_root, report_root=report_root)
            self.assertIn(str(meeting_path), result["touched_files"])

            updated = meeting_path.read_text(encoding="utf-8")
            self.assertIn("## Related\n- People: [[Steffen]], [[Thomas]]\n\n", updated)
            self.assertIn("- Note ID: abc123\n- Calendar Event: 1:1 Steffen <> Olli\n", updated)
            self.assertIn("### Top of mind", updated)

    def test_curated_reference_notes_do_not_receive_related_updates(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            write_note(vault_root / "reference" / "topics" / "AI Weekly.md", "# AI Weekly\n\n## Notes\n\nContext only.\n")

            inventory = relationship_inventory(vault_root, PEOPLE_CONFIG)
            plan = relationship_plan(inventory, vault_root)

            self.assertEqual(plan["summary"]["source_notes_proposed_for_link_injection"], 0)

    def test_generated_block_replacement_treats_backslashes_literally(self) -> None:
        original = (
            "# Project\n\n"
            "<!-- GENERATED:project-synthesis:start -->\n"
            "old\n"
            "<!-- GENERATED:project-synthesis:end -->\n"
        )
        replacement = (
            "<!-- GENERATED:project-synthesis:start -->\n"
            "Revenue target: \\500M\n"
            "<!-- GENERATED:project-synthesis:end -->\n"
        )
        updated = replace_or_append_generated_block(
            original,
            replacement,
            "<!-- GENERATED:project-synthesis:start -->",
            "<!-- GENERATED:project-synthesis:end -->",
        )
        self.assertIn("Revenue target: \\500M", updated)


if __name__ == "__main__":
    unittest.main()
