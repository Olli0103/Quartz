from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from lib.notes_migration import (  # noqa: E402
    DEFAULT_REPORT_ROOT,
    DEFAULT_VAULT_ROOT,
    build_inventory_note,
    compute_migration_plan,
    exact_people_matches,
    extract_image_links,
    extract_markdown_links,
    extract_wiki_links,
    is_within,
    load_people_config,
    resolve_report_path,
    sanitize_report_wikilinks,
    write_text_output,
)


FIXTURES = REPO_ROOT / "tests" / "fixtures" / "notes_migration"
PEOPLE_CONFIG = load_people_config(REPO_ROOT / "config" / "people.yml")


def fixture_text(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


class NotesMigrationTests(unittest.TestCase):
    def test_granola_filename_and_metadata_route_to_meetings(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "granola_notes_md"
            note_path = source_root / "20250807_1_1_Steffen_Olli.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(
                "# 1:1 Steffen <> Olli\n\n"
                "- Note ID: not_demo\n"
                "- Created: 2025-08-07T14:00:40.599000+02:00\n"
                "- Updated: 2025-08-07T14:22:20.314000+02:00\n"
                "- Note Date: 2025-08-07\n"
                "- Calendar Event: 1:1 Steffen <> Olli\n"
                "- Scheduled: 2025-08-07T14:00:00+02:00\n"
                "- Attendees: Oliver Posselt <oliver.posselt@gmail.com>\n"
                "- Folders: 1:1s\n\n"
                "### Top of mind\n\n"
                "- ESP rollout remains blocked.\n",
                encoding="utf-8",
            )
            vault_root = Path(tmpdir) / "vault"
            (vault_root / "projects").mkdir(parents=True, exist_ok=True)
            (vault_root / "projects" / "ESP.md").write_text("# ESP\n", encoding="utf-8")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, vault_root)
            planned = plan["plan_notes"][0]

            self.assertIsNotNone(note.date_guess)
            self.assertEqual(note.date_guess.iso, "2025-08-07")
            self.assertEqual(planned["classification"], "meeting")
            self.assertIn("/meetings/2025/08/", planned["target_path"])
            self.assertIn("[[Steffen]]", planned["related_links"])
            self.assertIn("[[ESP]]", planned["related_links"])

    def test_granola_weekly_titled_note_still_routes_to_meetings(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "granola_notes_md"
            note_path = source_root / "20250812_Weekly_CAS_for_Cloud_ERP_Portfolio_Steering_Call.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(
                "# Weekly CAS for Cloud ERP Portfolio Steering Call\n\n"
                "- Note Date: 2025-08-12\n"
                "- Calendar Event: Weekly CAS for Cloud ERP Portfolio Steering Call\n"
                "- Scheduled: 2025-08-12T09:00:00+02:00\n\n"
                "### Information\n\n"
                "- ESP and AI roadmap alignment for the portfolio.\n",
                encoding="utf-8",
            )
            vault_root = Path(tmpdir) / "vault"
            (vault_root / "projects").mkdir(parents=True, exist_ok=True)
            (vault_root / "projects" / "AI.md").write_text("# AI\n", encoding="utf-8")
            (vault_root / "projects" / "ESP.md").write_text("# ESP\n", encoding="utf-8")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, vault_root)
            planned = plan["plan_notes"][0]

            self.assertEqual(planned["classification"], "meeting")
            self.assertIn("/meetings/2025/08/", planned["target_path"])
            self.assertNotIn("/weekly/", planned["target_path"])

    def test_pure_acr_roster_classifies_to_reference_teams(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "SAP" / "Management" / "1:1" / "13-03-2026-ACR.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(fixture_text("acr_roster.md"), encoding="utf-8")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, Path(tmpdir) / "vault")
            planned = plan["plan_notes"][0]

            self.assertTrue(note.roster_signals["is_roster_reference"])
            self.assertEqual(planned["classification"], "reference")
            self.assertIn("/reference/teams/", planned["target_path"])
            self.assertEqual(planned["related_links"], [])
            self.assertEqual(plan["canonical_projects"], [])
            self.assertTrue(plan["manual_review_sections"]["roster_reference_withheld_from_auto_linking"])

    def test_narrative_acr_remains_meeting(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "SAP" / "Management" / "1:1" / "MY" / "06-02-2026-ACR with Vinay.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(fixture_text("acr_narrative.md"), encoding="utf-8")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, Path(tmpdir) / "vault")
            planned = plan["plan_notes"][0]

            self.assertFalse(note.roster_signals["is_roster_reference"])
            self.assertEqual(planned["classification"], "meeting")
            self.assertIn("/meetings/2026/02/", planned["target_path"])

    def test_project_meeting_mentions_appops_and_tom_without_promoting_project(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "SAP" / "Projects" / "AI" / "07-03-2026-AppOps sync.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(fixture_text("project_meeting.md"), encoding="utf-8")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, Path(tmpdir) / "vault")
            planned = plan["plan_notes"][0]

            self.assertIn("AppOps", note.project_topic_hints)
            self.assertEqual(planned["classification"], "meeting")
            self.assertIn("[[Tom]]", planned["related_links"])
            self.assertNotIn("[[Thomas]]", planned["related_links"])
            self.assertEqual(plan["canonical_projects"], [])

    def test_exact_name_matching_distinguishes_short_names(self) -> None:
        alexandra_only = exact_people_matches("Alexandra owns the topic.", PEOPLE_CONFIG.canonical_people)
        mixed = exact_people_matches(
            "Tom worked with Thomas while Alex synced with Alexandra.",
            PEOPLE_CONFIG.canonical_people,
        )

        self.assertEqual(alexandra_only, ["Alexandra"])
        self.assertEqual(mixed, ["Alex", "Alexandra", "Thomas", "Tom"])

    def test_duplicate_basename_collision_is_a_blocker(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            first = source_root / "SAP" / "Management" / "Team Meeting" / "02-02-2026-02-02-2026.md"
            second = source_root / "SAP" / "Projects" / "Reporting" / "02-02-2026-02-02-2026.md"
            for path in (first, second):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("# Sync\n\nAgenda\n\nNext step\n", encoding="utf-8")

            notes = [
                build_inventory_note(source_root, first, PEOPLE_CONFIG),
                build_inventory_note(source_root, second, PEOPLE_CONFIG),
            ]
            plan = compute_migration_plan(notes, PEOPLE_CONFIG, Path(tmpdir) / "vault")

            self.assertFalse(plan["basename_collisions"])
            self.assertTrue(plan["manual_review_sections"]["hard_basename_collisions"])
            targets = [item["target_path"] for item in plan["plan_notes"]]
            self.assertEqual(len(targets), len(set(targets)))
            self.assertTrue(any("(Reporting)" in target or "(Team Meeting)" in target for target in targets))

    def test_report_path_safety_defaults_outside_vault(self) -> None:
        report_path = resolve_report_path(DEFAULT_REPORT_ROOT, "NOTES_DRY_RUN.md")
        self.assertFalse(is_within(report_path, DEFAULT_VAULT_ROOT))

    def test_fallback_report_sanitization_escapes_wikilinks_inside_vault(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_root = Path(tmpdir) / "notes"
            report_path = vault_root / "reports" / "NOTES_DRY_RUN.md"
            content = "[[Alexandra]] and [[Tom]]"
            write_text_output(report_path, content, vault_root=vault_root)
            written = report_path.read_text(encoding="utf-8")
            self.assertEqual(written, "`[[Alexandra]]` and `[[Tom]]`")
            self.assertEqual(sanitize_report_wikilinks(content), written)

    def test_unreadable_file_is_marked_and_routed_to_manual_review(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "SAP" / "Unreadable.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text("placeholder", encoding="utf-8")

            def broken_reader(_: Path) -> str:
                raise OSError("iCloud placeholder not downloaded")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG, reader=broken_reader)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, Path(tmpdir) / "vault")

            self.assertEqual(note.read_status, "unreadable")
            self.assertTrue(plan["manual_review_sections"]["unreadable_or_dataless"])
            self.assertIn("source unreadable", plan["plan_notes"][0]["manual_review_reasons"])

    def test_links_inside_code_fences_do_not_count(self) -> None:
        text = fixture_text("code_fence_links.md")
        self.assertEqual(extract_wiki_links(text), ["Thomas"])
        markdown_targets = [item["target"] for item in extract_markdown_links(text)]
        self.assertEqual(markdown_targets, ["https://example.com/real"])

    def test_missing_local_assets_appear_in_manual_review(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "SAP" / "15-04-2024-Priorities.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text(
                "# Priorities\n\nAgenda\n\nSee [Attachment](attachments/missing.pdf)\n",
                encoding="utf-8",
            )

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            plan = compute_migration_plan([note], PEOPLE_CONFIG, Path(tmpdir) / "vault")

            self.assertEqual(note.local_asset_refs[0]["exists"], False)
            self.assertTrue(plan["manual_review_sections"]["missing_local_assets"])

    def test_image_links_are_tracked_as_local_assets(self) -> None:
        text = "![diagram](images/example.png)\n"
        self.assertEqual(extract_image_links(text), [{"alt": "diagram", "target": "images/example.png"}])

        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "SAP" / "Image Note.md"
            image_path = note_path.parent / "images" / "example.png"
            image_path.parent.mkdir(parents=True, exist_ok=True)
            image_path.write_bytes(b"png")
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text("# Image\n\n![diagram](images/example.png)\n", encoding="utf-8")

            note = build_inventory_note(source_root, note_path, PEOPLE_CONFIG)
            self.assertEqual(len(note.local_asset_refs), 1)
            self.assertTrue(note.local_asset_refs[0]["exists"])

    def test_low_confidence_and_private_notes_route_to_inbox_import(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            source_root = Path(tmpdir) / "source"
            note_path = source_root / "Notes" / "04-12-2025-New Note.md"
            note_path.parent.mkdir(parents=True, exist_ok=True)
            note_path.write_text("# New Note\n\nRandom thought.\n", encoding="utf-8")
            private_path = source_root / "Private" / "Schule" / "11-04-2024-Elternabend.md"
            private_path.parent.mkdir(parents=True, exist_ok=True)
            private_path.write_text("# Elternabend\n\nPlanung.\n", encoding="utf-8")

            notes = [
                build_inventory_note(source_root, note_path, PEOPLE_CONFIG),
                build_inventory_note(source_root, private_path, PEOPLE_CONFIG),
            ]
            plan = compute_migration_plan(notes, PEOPLE_CONFIG, Path(tmpdir) / "vault")

            planned_by_source = {item["source_path"]: item for item in plan["plan_notes"]}
            self.assertEqual(planned_by_source[str(note_path)]["classification"], "inbox-import")
            self.assertIn("/inbox-import/Notes/", planned_by_source[str(note_path)]["target_path"])
            self.assertEqual(planned_by_source[str(private_path)]["classification"], "inbox-import")
            self.assertIn("/inbox-import/Private/Schule/", planned_by_source[str(private_path)]["target_path"])


if __name__ == "__main__":
    unittest.main()
