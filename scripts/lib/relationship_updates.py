from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from lib.notes_migration import (
    DEFAULT_REPORT_ROOT,
    DEFAULT_VAULT_ROOT,
    GENERIC_TOPIC_KEYS,
    PeopleConfig,
    assert_report_outside_vault,
    exact_people_matches,
    extract_project_topic_hints,
    extract_wiki_links,
    guess_date,
    guess_h1,
    is_within,
    load_json_file,
    mask_code_segments,
    normalize_topic_display,
    normalize_topic_key,
    read_file_text,
    repo_root,
    resolve_report_path,
    roster_signals_for_note,
    sanitize_filename_component,
    split_frontmatter,
    timestamp_utc,
    wiki_target,
    write_json_output,
    write_text_output,
    path_project_topic_hints,
)


GENERATED_PERSON_START = "<!-- GENERATED:notes-synthesis:start -->"
GENERATED_PERSON_END = "<!-- GENERATED:notes-synthesis:end -->"
GENERATED_PROJECT_START = "<!-- GENERATED:project-synthesis:start -->"
GENERATED_PROJECT_END = "<!-- GENERATED:project-synthesis:end -->"
GENERATED_BLOCK_RE = re.compile(
    r"<!-- GENERATED:[^>]+:start -->[\s\S]*?<!-- GENERATED:[^>]+:end -->",
    re.MULTILINE,
)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
LIST_PREFIX_RE = re.compile(r"^(?:[-*+]\s+|\d+\.\s+|-\s\[[ xX]\]\s+)")
WORD_BOUNDARY_TEMPLATE = r"(?<![\w]){value}(?![\w])"
RELATED_HEADING_RE = re.compile(r"^## Related\s*$")
RELATED_ITEM_LINE_RE = re.compile(
    r"^-\s+(?:People:\s+.+|Projects:\s+.+|\[\[[^\]]+\]\](?:\s*,\s*\[\[[^\]]+\]\])*)\s*$"
)
MARKDOWN_IMAGE_ONLY_RE = re.compile(r"^!\[[^\]]*\]\([^)]+\)\s*$")
HTML_TAG_ONLY_RE = re.compile(r"^<[^>]+>$")
WHITESPACE_RE = re.compile(r"\s+")
MARKDOWN_DECORATION_RE = re.compile(r"[*_`~#>]+")
PERSON_PRIORITY_KEYWORDS = (
    "priority",
    "focus",
    "target",
    "roadmap",
    "plan",
    "working on",
    "implementation",
    "rollout",
    "delivery",
    "current status",
)
PERSON_RISK_KEYWORDS = (
    "risk",
    "blocker",
    "issue",
    "problem",
    "delay",
    "challenge",
    "unclear",
    "pending",
    "waiting",
    "stuck",
    "concern",
)
PERSON_GROWTH_KEYWORDS = (
    "grow",
    "growth",
    "stretch",
    "lead",
    "ownership",
    "learning",
    "develop",
    "development",
    "mentor",
    "goal",
)
PERSON_SUPPORT_KEYWORDS = (
    "need support",
    "need help",
    "help",
    "support",
    "alignment",
    "decision",
    "approval",
    "feedback",
    "escalate",
)
WIN_KEYWORDS = (
    "improved",
    "approved",
    "ready",
    "completed",
    "launched",
    "success",
    "strong",
    "good progress",
    "on track",
    "performing well",
)
CONCERN_KEYWORDS = (
    "struggle",
    "poor",
    "negative",
    "demotivated",
    "concern",
    "risk",
    "blocker",
    "issue",
    "delay",
    "challenge",
)
PROJECT_STATUS_KEYWORDS = (
    "status",
    "progress",
    "launch",
    "rollout",
    "implementation",
    "current",
    "ready",
    "deployment",
)
PROJECT_DECISION_KEYWORDS = (
    "decision",
    "decided",
    "agreed",
    "approved",
    "will",
    "selected",
)
PROJECT_RISK_KEYWORDS = (
    "risk",
    "blocker",
    "issue",
    "problem",
    "delay",
    "challenge",
    "unclear",
    "pending",
)
PROJECT_OPEN_QUESTION_KEYWORDS = (
    "question",
    "unclear",
    "pending",
    "awaiting",
    "tbd",
    "need to decide",
)
CONTEXT_SECTION_KEYWORDS = (
    "decision",
    "risk",
    "blocker",
    "action",
    "next step",
    "status",
    "focus",
)
SHORT_ACRONYM_PROJECT_RE = re.compile(r"^[A-Z]{2,4}$")


@dataclass
class ContentUnit:
    text: str
    heading: str | None
    kind: str

    def to_dict(self) -> dict[str, Any]:
        return {"text": self.text, "heading": self.heading, "kind": self.kind}

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "ContentUnit":
        return cls(
            text=str(payload["text"]),
            heading=payload.get("heading"),
            kind=str(payload.get("kind", "paragraph")),
        )


@dataclass
class VaultNote:
    path: str
    relative_path: str
    stem: str
    title: str
    note_type: str
    date_iso: str | None
    frontmatter_present: bool
    existing_wiki_links: list[str]
    existing_wiki_targets: list[str]
    existing_related_targets: list[str]
    analysis_units: list[ContentUnit]
    roster_reference: bool
    title_path_people: list[str]
    title_path_people_alias: list[str]
    title_path_project_hints: list[str]

    def to_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "relative_path": self.relative_path,
            "stem": self.stem,
            "title": self.title,
            "note_type": self.note_type,
            "date_iso": self.date_iso,
            "frontmatter_present": self.frontmatter_present,
            "existing_wiki_links": list(self.existing_wiki_links),
            "existing_wiki_targets": list(self.existing_wiki_targets),
            "existing_related_targets": list(self.existing_related_targets),
            "analysis_units": [unit.to_dict() for unit in self.analysis_units],
            "roster_reference": self.roster_reference,
            "title_path_people": list(self.title_path_people),
            "title_path_people_alias": list(self.title_path_people_alias),
            "title_path_project_hints": list(self.title_path_project_hints),
        }

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "VaultNote":
        return cls(
            path=str(payload["path"]),
            relative_path=str(payload["relative_path"]),
            stem=str(payload["stem"]),
            title=str(payload["title"]),
            note_type=str(payload["note_type"]),
            date_iso=payload.get("date_iso"),
            frontmatter_present=bool(payload.get("frontmatter_present", False)),
            existing_wiki_links=list(payload.get("existing_wiki_links", [])),
            existing_wiki_targets=list(payload.get("existing_wiki_targets", [])),
            existing_related_targets=list(payload.get("existing_related_targets", [])),
            analysis_units=[ContentUnit.from_dict(item) for item in payload.get("analysis_units", [])],
            roster_reference=bool(payload.get("roster_reference", False)),
            title_path_people=list(payload.get("title_path_people", [])),
            title_path_people_alias=list(payload.get("title_path_people_alias", [])),
            title_path_project_hints=list(payload.get("title_path_project_hints", [])),
        )


def default_people_config_path() -> Path:
    return repo_root() / "config" / "people.yml"


def relationship_scripts_root() -> Path:
    return repo_root() / "scripts"


def default_project_taxonomy_path() -> Path:
    return repo_root() / "config" / "project_taxonomy.yml"


def load_project_taxonomy(path: Path) -> dict[str, set[str]]:
    taxonomy: dict[str, set[str]] = {
        "active": set(),
        "reference": set(),
        "archive": set(),
        "manual_review": set(),
    }
    if not path.exists():
        return taxonomy

    current_top: str | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        if line.lstrip().startswith("#"):
            continue

        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if indent == 0:
            if not stripped.endswith(":"):
                raise ValueError(f"Unsupported project taxonomy line: {raw_line}")
            current_top = stripped[:-1]
            if current_top not in taxonomy:
                raise ValueError(f"Unsupported project taxonomy key: {current_top}")
            continue
        if indent == 2 and stripped.startswith("- "):
            if current_top is None:
                raise ValueError(f"Unexpected project taxonomy value without section: {raw_line}")
            taxonomy[current_top].add(stripped[2:].strip())
            continue
        raise ValueError(f"Unsupported project taxonomy structure: {raw_line}")
    return taxonomy


def note_type_from_relative_path(relative_path: str) -> str:
    parts = Path(relative_path).parts
    if len(parts) < 2:
        return "other"
    top = parts[0]
    if top == "people":
        return "person"
    if top == "projects":
        return "project"
    if top == "meetings":
        return "meeting"
    if top == "weekly":
        return "weekly"
    if top == "reference":
        return "reference"
    if top == "inbox-import":
        return "inbox-import"
    return "other"


def curated_reference_relative_path(relative_path: str) -> bool:
    return relative_path.startswith("reference/topics/") or relative_path.startswith("reference/archive/") or relative_path.startswith("reference/people/")


def business_note_scope(relative_path: str, note_type: str) -> bool:
    if note_type in {"meeting", "weekly", "reference", "project"}:
        return True
    return relative_path.startswith("inbox-import/SAP/")


def exact_phrase_occurrences(text: str, value: str) -> int:
    pattern = re.compile(WORD_BOUNDARY_TEMPLATE.format(value=re.escape(value)))
    return len(pattern.findall(text))


def clean_display_text(value: str) -> str:
    text = MARKDOWN_DECORATION_RE.sub("", value)
    text = text.replace("&nbsp;", " ")
    text = WHITESPACE_RE.sub(" ", text).strip()
    return text


def strip_generated_blocks(body: str) -> str:
    return GENERATED_BLOCK_RE.sub("", body)


def current_related_span(body: str) -> tuple[int, int] | None:
    lines = body.splitlines(keepends=True)
    offset = 0
    for index, line in enumerate(lines):
        if not RELATED_HEADING_RE.match(line.strip()):
            offset += len(line)
            continue
        start = offset
        cursor = index + 1
        end = start + len(line)
        saw_related_item = False
        while cursor < len(lines):
            candidate = lines[cursor]
            stripped = candidate.strip()
            if not stripped:
                end += len(candidate)
                cursor += 1
                continue
            if RELATED_ITEM_LINE_RE.match(stripped):
                saw_related_item = True
                end += len(candidate)
                cursor += 1
                continue
            break
        if saw_related_item:
            return start, end
        return None
    return None


def split_related_section(body: str) -> tuple[str, str | None]:
    span = current_related_span(body)
    if not span:
        return body, None
    start, end = span
    before = body[:start]
    after = body[end:]
    cleaned = before.rstrip() + "\n\n" + after.lstrip()
    return cleaned.strip("\n") + ("\n" if body.endswith("\n") else ""), body[start:end]


def extract_related_targets(related_section: str | None) -> list[str]:
    if not related_section:
        return []
    return [wiki_target(item) for item in extract_wiki_links(related_section)]


def build_content_units(body: str) -> list[ContentUnit]:
    masked = mask_code_segments(body)
    units: list[ContentUnit] = []
    current_heading: str | None = None
    for raw_line in masked.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        heading_match = HEADING_RE.match(stripped)
        if heading_match:
            current_heading = clean_display_text(heading_match.group(2))
            continue
        if stripped.startswith("|"):
            continue
        if MARKDOWN_IMAGE_ONLY_RE.match(stripped):
            continue
        if HTML_TAG_ONLY_RE.match(stripped):
            continue
        line_kind = "paragraph"
        if LIST_PREFIX_RE.match(stripped):
            stripped = LIST_PREFIX_RE.sub("", stripped)
            line_kind = "bullet"
        cleaned = clean_display_text(stripped)
        if not cleaned:
            continue
        if len(cleaned) > 240:
            cleaned = cleaned[:237].rstrip() + "..."
        units.append(ContentUnit(text=cleaned, heading=current_heading, kind=line_kind))
    return units


def title_path_people(
    relative_path: str,
    stem: str,
    title: str,
    people_config: PeopleConfig,
) -> tuple[list[str], list[str]]:
    canonical_hits: set[str] = set()
    alias_hits: set[str] = set()
    combined = "\n".join([relative_path, stem, title])
    for person in people_config.canonical_people:
        if exact_phrase_occurrences(combined, person):
            canonical_hits.add(person)
    for canonical, aliases in people_config.routing_aliases.items():
        for alias in aliases:
            if exact_phrase_occurrences(combined, alias):
                alias_hits.add(canonical)
    return sorted(canonical_hits, key=str.casefold), sorted(alias_hits, key=str.casefold)


def guess_note_title(path: Path, body: str) -> str:
    h1 = guess_h1(body)
    if h1:
        return clean_display_text(h1)
    stem = path.stem
    stem = re.sub(r"^(?:\d{4}-\d{2}-\d{2}|\d{2}\.\d{2}\.\d{4}|\d{2}-\d{2}-\d{4})\s*", "", stem)
    stem = stem.strip(" -_")
    return clean_display_text(stem or path.stem)


def guess_note_date(path: Path, title: str) -> str | None:
    guess = guess_date(("filename", path.stem), ("title", title))
    if guess:
        return guess.iso
    return None


def title_path_project_hints(
    note_type: str,
    relative_path: str,
    title: str,
    analysis_text: str,
    people_config: PeopleConfig,
) -> list[str]:
    hints = extract_project_topic_hints(relative_path, title, analysis_text, people_config)
    if note_type == "project":
        hints.append(title)
    normalized: list[str] = []
    seen: set[str] = set()
    for hint in hints:
        key = normalize_topic_key(hint)
        if not key or key in GENERIC_TOPIC_KEYS:
            continue
        if people_config.canonical_name(hint) is not None:
            continue
        if key in seen:
            continue
        seen.add(key)
        normalized.append(normalize_topic_display(hint))
    return normalized


def read_vault_note(path: Path, vault_root: Path, people_config: PeopleConfig) -> VaultNote:
    relative_path = str(path.relative_to(vault_root))
    note_type = note_type_from_relative_path(relative_path)
    text = read_file_text(path)
    frontmatter, body = split_frontmatter(text)
    body_without_generated = strip_generated_blocks(body)
    body_for_analysis, existing_related = split_related_section(body_without_generated)
    title = guess_note_title(path, body_without_generated)
    date_iso = guess_note_date(path, title)
    units = build_content_units(body_for_analysis)
    analysis_text = "\n".join(unit.text for unit in units)
    title_people, alias_people = title_path_people(relative_path, path.stem, title, people_config)
    roster = roster_signals_for_note(title, relative_path, body_for_analysis, exact_people_matches(analysis_text, people_config.canonical_people))
    return VaultNote(
        path=str(path),
        relative_path=relative_path,
        stem=path.stem,
        title=title,
        note_type=note_type,
        date_iso=date_iso,
        frontmatter_present=bool(frontmatter),
        existing_wiki_links=extract_wiki_links(body_without_generated),
        existing_wiki_targets=sorted({wiki_target(item) for item in extract_wiki_links(body_without_generated)}, key=str.casefold),
        existing_related_targets=sorted(set(extract_related_targets(existing_related)), key=str.casefold),
        analysis_units=units,
        roster_reference=bool(roster.get("is_roster_reference", False)) or "/reference/teams/" in f"/{relative_path}/",
        title_path_people=title_people,
        title_path_people_alias=alias_people,
        title_path_project_hints=title_path_project_hints(note_type, relative_path, title, analysis_text, people_config),
    )


def load_vault_notes(vault_root: Path, people_config: PeopleConfig) -> list[VaultNote]:
    notes: list[VaultNote] = []
    for path in sorted(vault_root.rglob("*.md")):
        if not path.is_file():
            continue
        notes.append(read_vault_note(path, vault_root, people_config))
    return notes


def candidate_project_names(notes: list[VaultNote], people_config: PeopleConfig) -> dict[str, dict[str, Any]]:
    existing_projects = {
        normalize_topic_key(note.title): {
            "name": note.title,
            "existing": True,
            "notes": set(),
            "title_path_hits": 0,
            "body_hits": 0,
            "folder_hits": 0,
        }
        for note in notes
        if note.note_type == "project"
    }
    candidates: dict[str, dict[str, Any]] = {key: dict(value) for key, value in existing_projects.items()}

    for note in notes:
        if note.note_type == "person" or not business_note_scope(note.relative_path, note.note_type):
            continue
        analysis_text = "\n".join(unit.text for unit in note.analysis_units)
        combined_title_path = "\n".join([note.relative_path, note.stem, note.title])
        folder_hints = path_project_topic_hints(note.relative_path)
        for hint in folder_hints:
            key = normalize_topic_key(hint)
            if not key or key in GENERIC_TOPIC_KEYS:
                continue
            if people_config.canonical_name(hint) is not None:
                continue
            entry = candidates.setdefault(
                key,
                {
                    "name": normalize_topic_display(hint),
                    "existing": False,
                    "notes": set(),
                    "title_path_hits": 0,
                    "body_hits": 0,
                    "folder_hits": 0,
                },
            )
            entry["folder_hits"] += 1
            title_path_hits = exact_phrase_occurrences(combined_title_path, hint)
            body_hits = exact_phrase_occurrences(analysis_text, hint)
            if title_path_hits:
                entry["title_path_hits"] += 1
            if body_hits:
                entry["body_hits"] += 1
            entry["notes"].add(note.path)

        for hint in note.title_path_project_hints:
            key = normalize_topic_key(hint)
            if not key or key in GENERIC_TOPIC_KEYS:
                continue
            if people_config.canonical_name(hint) is not None:
                continue
            title_path_hits = exact_phrase_occurrences(combined_title_path, hint)
            if title_path_hits == 0:
                continue
            entry = candidates.setdefault(
                key,
                {
                    "name": normalize_topic_display(hint),
                    "existing": False,
                    "notes": set(),
                    "title_path_hits": 0,
                    "body_hits": 0,
                    "folder_hits": 0,
                },
            )
            entry["title_path_hits"] += 1
            entry["notes"].add(note.path)

        for existing_name in existing_projects.values():
            hint = existing_name["name"]
            key = normalize_topic_key(hint)
            entry = candidates[key]
            title_path_hits = exact_phrase_occurrences(combined_title_path, hint)
            body_hits = exact_phrase_occurrences(analysis_text, hint)
            if title_path_hits:
                entry["title_path_hits"] += 1
            if body_hits:
                entry["body_hits"] += 1
            if title_path_hits or body_hits:
                entry["notes"].add(note.path)

    canonical: dict[str, dict[str, Any]] = {}
    for key, entry in candidates.items():
        name = entry["name"]
        support_count = len(entry["notes"])
        title_path_hits = int(entry["title_path_hits"])
        folder_hits = int(entry["folder_hits"])
        existing = bool(entry["existing"])
        if existing:
            canonical[key] = {
                "name": name,
                "existing": True,
                "support_count": max(1, support_count),
                "title_path_hits": title_path_hits,
                "folder_hits": folder_hits,
            }
            continue
        if folder_hits == 0 and title_path_hits < 2:
            continue
        if SHORT_ACRONYM_PROJECT_RE.match(name) and folder_hits == 0:
            continue
        if (folder_hits >= 1 and support_count >= 2) or title_path_hits >= 2:
            canonical[key] = {
                "name": name,
                "existing": False,
                "support_count": support_count,
                "title_path_hits": title_path_hits,
                "folder_hits": folder_hits,
            }
    return canonical


def project_name_set(project_registry: dict[str, dict[str, Any]]) -> list[str]:
    return sorted({item["name"] for item in project_registry.values()}, key=str.casefold)


def person_relationships_for_note(note: VaultNote, people_config: PeopleConfig) -> list[dict[str, Any]]:
    analysis_text = "\n".join(unit.text for unit in note.analysis_units)
    relationships: list[dict[str, Any]] = []
    title_path_candidates = set(note.title_path_people) | set(note.title_path_people_alias)
    for person in people_config.canonical_people:
        reasons: list[str] = []
        confidence = 0.0
        dedicated = False
        if person in title_path_candidates:
            confidence = 0.95
            dedicated = True
            if person in note.title_path_people:
                reasons.append("person appears in filename, path, or title")
            else:
                reasons.append("routing alias in filename or path maps to canonical person")
        else:
            body_count = exact_phrase_occurrences(analysis_text, person)
            body_units = [unit for unit in note.analysis_units if exact_phrase_occurrences(unit.text, person)]
            if body_count >= 2:
                confidence = 0.90
                reasons.append("exact canonical name appears multiple times in body context")
            elif body_count == 1 and any(len(unit.text) >= 24 for unit in body_units):
                confidence = 0.80
                reasons.append("exact canonical name appears once in meaningful body context")
            elif body_count == 1:
                confidence = 0.60
                reasons.append("single weak exact-name mention")
        if confidence <= 0:
            continue
        relationships.append(
            {
                "name": person,
                "confidence": round(confidence, 2),
                "reasons": reasons,
                "auto_link": confidence >= 0.85,
                "dedicated_context": dedicated,
            }
        )
    return relationships


def project_relationships_for_note(
    note: VaultNote,
    canonical_projects: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    analysis_text = "\n".join(unit.text for unit in note.analysis_units)
    combined_title_path = "\n".join([note.relative_path, note.stem, note.title])
    relationships: list[dict[str, Any]] = []
    for key, candidate in canonical_projects.items():
        name = candidate["name"]
        title_path_count = exact_phrase_occurrences(combined_title_path, name)
        body_count = exact_phrase_occurrences(analysis_text, name)
        contextual_units = [
            unit
            for unit in note.analysis_units
            if exact_phrase_occurrences(unit.text, name)
            and unit.heading
            and any(keyword in unit.heading.casefold() for keyword in CONTEXT_SECTION_KEYWORDS)
        ]
        confidence = 0.0
        reasons: list[str] = []
        if title_path_count:
            confidence = 0.95
            reasons.append("project appears in title or path")
        elif body_count >= 1 and candidate["support_count"] >= 2:
            confidence = 0.90
            reasons.append("project is repeated across multiple notes and appears in this note")
        elif body_count >= 1 and contextual_units:
            confidence = 0.85
            reasons.append("project appears in decisions, risks, or status context")
        elif body_count >= 2:
            confidence = 0.90
            reasons.append("project appears repeatedly in body context")
        elif body_count == 1:
            confidence = 0.70
            reasons.append("single project mention with unclear context")
        if confidence <= 0:
            continue
        if SHORT_ACRONYM_PROJECT_RE.match(name) and body_count == 1 and not title_path_count and candidate["support_count"] < 2:
            confidence = min(confidence, 0.70)
            reasons = ["short acronym project mention is too weak without stronger context"]
        relationships.append(
            {
                "name": name,
                "confidence": round(confidence, 2),
                "reasons": reasons,
                "auto_link": confidence >= 0.85,
                "supporting_notes": candidate["support_count"],
            }
        )
    return sorted(relationships, key=lambda item: (-item["confidence"], item["name"].casefold()))


def existing_related_people_projects(
    note: VaultNote,
    canonical_people: set[str],
    canonical_projects: set[str],
) -> tuple[list[str], list[str], list[str]]:
    people: list[str] = []
    projects: list[str] = []
    other: list[str] = []
    for target in note.existing_related_targets:
        if target in canonical_people:
            people.append(target)
        elif target in canonical_projects:
            projects.append(target)
        else:
            other.append(target)
    return sorted(set(people), key=str.casefold), sorted(set(projects), key=str.casefold), sorted(set(other), key=str.casefold)


def render_related_block(people: list[str], projects: list[str]) -> str:
    if not people and not projects:
        return ""
    lines = ["## Related"]
    if people:
        lines.append("- People: " + ", ".join(f"[[{item}]]" for item in people))
    if projects:
        lines.append("- Projects: " + ", ".join(f"[[{item}]]" for item in projects))
    return "\n".join(lines) + "\n\n"


def current_related_block(body: str) -> str | None:
    span = current_related_span(body)
    if not span:
        return None
    start, end = span
    return body[start:end].strip() + "\n\n"


def note_supports_relationship_updates(note: VaultNote) -> bool:
    if curated_reference_relative_path(note.relative_path):
        return False
    return note.note_type in {"meeting", "weekly", "reference"} or (
        note.note_type == "inbox-import" and note.relative_path.startswith("inbox-import/SAP/")
    )


def plan_link_updates_for_note(
    note: VaultNote,
    body: str,
    people_relationships: list[dict[str, Any]],
    project_relationships: list[dict[str, Any]],
    canonical_people: set[str],
    canonical_projects: set[str],
) -> dict[str, Any]:
    existing_people, existing_projects, existing_other = existing_related_people_projects(note, canonical_people, canonical_projects)
    existing_targets = set(note.existing_wiki_targets)
    auto_people = [item["name"] for item in people_relationships if item["auto_link"]]
    auto_projects = [item["name"] for item in project_relationships if item["auto_link"]]
    manual_review_reasons: list[str] = []
    withheld_people: list[str] = []

    if note.roster_reference and auto_people:
        withheld_people = sorted(auto_people, key=str.casefold)
        auto_people = []
        manual_review_reasons.append("roster/reference note withheld from automatic people linking")

    proposed_people = sorted(set(existing_people) | {item for item in auto_people if item not in existing_targets or item in existing_people}, key=str.casefold)
    proposed_projects = sorted(set(existing_projects) | {item for item in auto_projects if item not in existing_targets or item in existing_projects}, key=str.casefold)
    proposed_block = render_related_block(proposed_people, proposed_projects)
    current_block = current_related_block(body)

    if existing_other:
        manual_review_reasons.append("existing Related section contains non-person/non-project links")

    needs_update = False
    if proposed_block:
        needs_update = proposed_block != (current_block or "")

    missing_links = sorted(
        [item for item in auto_people + auto_projects if item not in existing_targets],
        key=str.casefold,
    )
    return {
        "existing_related_people": existing_people,
        "existing_related_projects": existing_projects,
        "existing_related_other": existing_other,
        "missing_links_to_inject": [f"[[{item}]]" for item in missing_links],
        "proposed_related_block": proposed_block,
        "needs_related_update": needs_update,
        "withheld_people_links": withheld_people,
        "manual_review_reasons": manual_review_reasons,
    }


def relationship_inventory(vault_root: Path, people_config: PeopleConfig) -> dict[str, Any]:
    notes = load_vault_notes(vault_root, people_config)
    project_registry = candidate_project_names(notes, people_config)
    canonical_people = set(people_config.canonical_people)
    canonical_projects = set(project_name_set(project_registry))

    note_payloads: list[dict[str, Any]] = []
    manual_review_items: list[dict[str, Any]] = []
    for note in notes:
        body = read_file_text(Path(note.path))
        _, full_body = split_frontmatter(body)
        people_relationships = person_relationships_for_note(note, people_config)
        project_relationships = project_relationships_for_note(note, project_registry)
        link_plan = plan_link_updates_for_note(
            note,
            full_body,
            people_relationships,
            project_relationships,
            canonical_people,
            canonical_projects,
        ) if note_supports_relationship_updates(note) else {
            "existing_related_people": [],
            "existing_related_projects": [],
            "existing_related_other": [],
            "missing_links_to_inject": [],
            "proposed_related_block": "",
            "needs_related_update": False,
            "withheld_people_links": [],
            "manual_review_reasons": [],
        }

        low_conf_people = [
            item["name"]
            for item in people_relationships
            if item["confidence"] < 0.85 and item["confidence"] >= 0.60
        ]
        low_conf_projects = [
            item["name"]
            for item in project_relationships
            if item["confidence"] < 0.85 and item["confidence"] >= 0.70
        ]
        reasons = list(link_plan["manual_review_reasons"])
        if low_conf_people:
            reasons.append("low-confidence people relationship(s): " + ", ".join(low_conf_people))
        if low_conf_projects:
            reasons.append("low-confidence project relationship(s): " + ", ".join(low_conf_projects))
        if reasons:
            manual_review_items.append({"path": note.path, "reasons": reasons})

        note_payloads.append(
            {
                **note.to_dict(),
                "people_relationships": people_relationships,
                "project_relationships": project_relationships,
                "existing_related_people": link_plan["existing_related_people"],
                "existing_related_projects": link_plan["existing_related_projects"],
                "existing_related_other": link_plan["existing_related_other"],
                "missing_links_to_inject": link_plan["missing_links_to_inject"],
                "proposed_related_block": link_plan["proposed_related_block"],
                "needs_related_update": link_plan["needs_related_update"],
                "withheld_people_links": link_plan["withheld_people_links"],
                "manual_review_reasons": reasons,
            }
        )

    basename_collisions = detect_basename_collisions(vault_root, project_registry)
    return {
        "generated_at": timestamp_utc(),
        "vault_root": str(vault_root),
        "summary": {
            "notes_scanned": len(notes),
            "existing_project_notes": sum(1 for note in notes if note.note_type == "project"),
            "existing_person_notes": sum(1 for note in notes if note.note_type == "person"),
            "notes_with_related_updates": sum(1 for item in note_payloads if item["needs_related_update"]),
            "manual_review_items": len(manual_review_items),
            "basename_collisions": len(basename_collisions),
        },
        "project_registry": [
            {
                "name": value["name"],
                "existing": value["existing"],
                "support_count": value["support_count"],
                "title_path_hits": value["title_path_hits"],
                "folder_hits": value.get("folder_hits", 0),
            }
            for value in sorted(project_registry.values(), key=lambda item: item["name"].casefold())
        ],
        "basename_collisions": basename_collisions,
        "notes": note_payloads,
    }


def load_relationship_inventory(path: Path) -> tuple[Path, list[VaultNote], dict[str, Any]]:
    payload = load_json_file(path)
    vault_root = Path(payload["vault_root"])
    notes = [VaultNote.from_dict(item) for item in payload.get("notes", [])]
    return vault_root, notes, payload


def basename_buckets_for_paths(paths: list[Path]) -> dict[str, list[str]]:
    buckets: dict[str, list[str]] = defaultdict(list)
    for path in paths:
        buckets[path.stem.casefold()].append(str(path))
    return buckets


def detect_basename_collisions(vault_root: Path, project_registry: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    project_taxonomy = load_project_taxonomy(default_project_taxonomy_path())
    non_active_projects = (
        project_taxonomy["reference"] | project_taxonomy["archive"] | project_taxonomy["manual_review"]
    )
    existing_paths = sorted(vault_root.rglob("*.md"))
    buckets = basename_buckets_for_paths(existing_paths)
    for value in project_registry.values():
        if value["name"] in non_active_projects:
            continue
        path = vault_root / "projects" / f"{sanitize_filename_component(value['name'])}.md"
        buckets[path.stem.casefold()].append(str(path))
    collisions: list[dict[str, Any]] = []
    for stem, items in sorted(buckets.items()):
        unique_items = sorted(set(items))
        if len(unique_items) > 1:
            collisions.append({"stem": stem, "paths": unique_items})
    return collisions


def source_note_link(note: dict[str, Any]) -> str:
    return f"[[{note['stem']}]]"


def source_date(note: dict[str, Any]) -> str:
    return note.get("date_iso") or "undated"


def unit_mentions_person(unit: dict[str, Any], person: str) -> bool:
    return exact_phrase_occurrences(unit["text"], person) > 0


def unit_mentions_project(unit: dict[str, Any], project: str) -> bool:
    return exact_phrase_occurrences(unit["text"], project) > 0


def dedicated_person_note(note: dict[str, Any], person: str) -> bool:
    matches = {item["name"] for item in note.get("people_relationships", []) if item.get("confidence", 0) >= 0.85}
    dedicated_names = set(note.get("title_path_people", [])) | set(note.get("title_path_people_alias", []))
    return person in dedicated_names and (len(matches) <= 1 or person in matches)


def dedicated_project_note(note: dict[str, Any], project: str) -> bool:
    return exact_phrase_occurrences("\n".join([note["relative_path"], note["title"], note["stem"]]), project) > 0


def pick_units_for_person(note: dict[str, Any], person: str) -> list[dict[str, Any]]:
    units = note.get("analysis_units", [])
    if dedicated_person_note(note, person):
        return units
    return [unit for unit in units if unit_mentions_person(unit, person)]


def pick_units_for_project(note: dict[str, Any], project: str) -> list[dict[str, Any]]:
    units = note.get("analysis_units", [])
    if dedicated_project_note(note, project):
        return units
    return [unit for unit in units if unit_mentions_project(unit, project)]


def keyword_score(text: str, keywords: tuple[str, ...], heading: str | None = None) -> int:
    combined = f"{heading or ''}\n{text}".casefold()
    return sum(1 for keyword in keywords if keyword in combined)


def render_source_bullet(note: dict[str, Any], text: str, *, dated: bool = False) -> str:
    if dated and note.get("date_iso"):
        return f"- {note['date_iso']} — {text}. Source: {source_note_link(note)}"
    return f"- {text}. Source: {source_note_link(note)}"


def normalize_bullet_text(text: str) -> str:
    cleaned = clean_display_text(text).rstrip(".")
    return cleaned


def select_best_bullets(candidates: list[tuple[int, str]], limit: int = 3) -> list[str]:
    ordered = sorted(candidates, key=lambda item: (-item[0], item[1].casefold()))
    seen: set[str] = set()
    results: list[str] = []
    for _, text in ordered:
        key = text.casefold()
        if key in seen:
            continue
        seen.add(key)
        results.append(text)
        if len(results) >= limit:
            break
    return results


def person_generated_block(person: str, supporting_notes: list[dict[str, Any]]) -> str | None:
    priorities: list[tuple[int, str]] = []
    risks: list[tuple[int, str]] = []
    development: list[tuple[int, str]] = []
    support_needed: list[tuple[int, str]] = []
    wins: list[tuple[int, str]] = []
    concerns: list[tuple[int, str]] = []
    growth: list[tuple[int, str]] = []
    related_source_notes: list[str] = []

    for note in supporting_notes:
        related_source_notes.append(source_note_link(note))
        for unit in pick_units_for_person(note, person):
            text = normalize_bullet_text(unit["text"])
            if len(text) < 12:
                continue
            priority_score = keyword_score(text, PERSON_PRIORITY_KEYWORDS, unit.get("heading"))
            risk_score = keyword_score(text, PERSON_RISK_KEYWORDS, unit.get("heading"))
            growth_score = keyword_score(text, PERSON_GROWTH_KEYWORDS, unit.get("heading"))
            support_score = keyword_score(text, PERSON_SUPPORT_KEYWORDS, unit.get("heading"))
            win_score = keyword_score(text, WIN_KEYWORDS, unit.get("heading"))
            concern_score = keyword_score(text, CONCERN_KEYWORDS, unit.get("heading"))

            if priority_score:
                priorities.append((priority_score, render_source_bullet(note, text)))
            if risk_score:
                risks.append((risk_score, render_source_bullet(note, text)))
            if growth_score:
                development.append((growth_score, render_source_bullet(note, text)))
                growth.append((growth_score, render_source_bullet(note, text, dated=True)))
            if support_score:
                support_needed.append((support_score, render_source_bullet(note, text)))
            if win_score:
                wins.append((win_score, render_source_bullet(note, text, dated=True)))
            if concern_score or risk_score:
                concerns.append((max(concern_score, risk_score), render_source_bullet(note, text, dated=True)))

    if not any([priorities, risks, development, support_needed, wins, concerns, growth]):
        return None

    lines = [
        GENERATED_PERSON_START,
        "## Synthesized from source notes",
        "",
        "### Current priorities",
    ]
    lines.extend(select_best_bullets(priorities, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "### Current risks / blockers"])
    lines.extend(select_best_bullets(risks, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "### Development focus"])
    lines.extend(select_best_bullets(development, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "### Support needed from me"])
    lines.extend(select_best_bullets(support_needed, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "### Evidence log", "", "#### Wins"])
    lines.extend(select_best_bullets(wins, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "#### Concerns / coaching"])
    lines.extend(select_best_bullets(concerns, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "#### Growth / stretch"])
    lines.extend(select_best_bullets(growth, limit=3) or ["- None generated from high-confidence evidence."])
    lines.extend(["", "### Related source notes"])
    for link in sorted(set(related_source_notes), key=str.casefold):
        lines.append(f"- {link}")
    lines.append(GENERATED_PERSON_END)
    return "\n".join(lines) + "\n"


def project_generated_block(project: str, supporting_notes: list[dict[str, Any]]) -> str | None:
    purpose: list[tuple[int, str]] = []
    status: list[tuple[int, str]] = []
    decisions: list[tuple[int, str]] = []
    risks: list[tuple[int, str]] = []
    open_questions: list[tuple[int, str]] = []
    notes_misc: list[tuple[int, str]] = []
    key_people_sources: dict[str, list[str]] = defaultdict(list)
    key_source_notes: list[str] = []

    for note in supporting_notes:
        key_source_notes.append(source_note_link(note))
        for relationship in note.get("people_relationships", []):
            if relationship.get("confidence", 0) >= 0.85:
                key_people_sources[relationship["name"]].append(source_note_link(note))
        for unit in pick_units_for_project(note, project):
            text = normalize_bullet_text(unit["text"])
            if len(text) < 12:
                continue
            if dedicated_project_note(note, project):
                purpose_score = 1 if keyword_score(text, PROJECT_STATUS_KEYWORDS, unit.get("heading")) == 0 else 0
            else:
                purpose_score = 0
            status_score = keyword_score(text, PROJECT_STATUS_KEYWORDS, unit.get("heading"))
            decision_score = keyword_score(text, PROJECT_DECISION_KEYWORDS, unit.get("heading"))
            risk_score = keyword_score(text, PROJECT_RISK_KEYWORDS, unit.get("heading"))
            question_score = keyword_score(text, PROJECT_OPEN_QUESTION_KEYWORDS, unit.get("heading"))

            if purpose_score:
                purpose.append((purpose_score, render_source_bullet(note, text)))
            if status_score:
                status.append((status_score, render_source_bullet(note, text)))
            if decision_score:
                decisions.append((decision_score, render_source_bullet(note, text)))
            if risk_score:
                risks.append((risk_score, render_source_bullet(note, text)))
            if question_score:
                open_questions.append((question_score, render_source_bullet(note, text)))
            if not any([status_score, decision_score, risk_score, question_score]) and dedicated_project_note(note, project):
                notes_misc.append((1, render_source_bullet(note, text)))

    if not any([purpose, status, decisions, risks, open_questions, notes_misc, key_people_sources]):
        return None

    lines = [
        GENERATED_PROJECT_START,
        "## Synthesized from source notes",
        "",
        "### Purpose / outcome",
    ]
    lines.extend(select_best_bullets(purpose, limit=2) or ["- No high-confidence purpose statement generated from source notes."])
    lines.extend(["", "### Current status"])
    lines.extend(select_best_bullets(status, limit=4) or ["- No high-confidence current-status bullet generated from source notes."])
    lines.extend(["", "### Key people"])
    if key_people_sources:
        for person in sorted(key_people_sources, key=str.casefold):
            links = ", ".join(sorted(set(key_people_sources[person]), key=str.casefold)[:3])
            lines.append(f"- [[{person}]] appears in recurring project context. Sources: {links}")
    else:
        lines.append("- No high-confidence people relationship generated from source notes.")
    lines.extend(["", "### Decisions"])
    lines.extend(select_best_bullets(decisions, limit=3) or ["- No high-confidence decision bullet generated from source notes."])
    lines.extend(["", "### Risks / blockers"])
    lines.extend(select_best_bullets(risks, limit=4) or ["- No high-confidence risk bullet generated from source notes."])
    lines.extend(["", "### Open questions"])
    lines.extend(select_best_bullets(open_questions, limit=3) or ["- No high-confidence open-question bullet generated from source notes."])
    lines.extend(["", "### Key source notes"])
    for link in sorted(set(key_source_notes), key=str.casefold)[:8]:
        lines.append(f"- {link}")
    lines.extend(["", "### Notes"])
    lines.extend(select_best_bullets(notes_misc, limit=3) or ["- No additional synthesized note generated from source notes."])
    lines.append(GENERATED_PROJECT_END)
    return "\n".join(lines) + "\n"


def replace_or_append_generated_block(text: str, block: str, start_marker: str, end_marker: str) -> str:
    pattern = re.compile(re.escape(start_marker) + r"[\s\S]*?" + re.escape(end_marker), re.MULTILINE)
    if pattern.search(text):
        updated = pattern.sub(lambda _: block.strip(), text)
        if not updated.endswith("\n"):
            updated += "\n"
        return updated
    stripped = text.rstrip()
    if stripped:
        return stripped + "\n\n" + block
    return block


def person_note_updates(inventory_payload: dict[str, Any], vault_root: Path) -> list[dict[str, Any]]:
    notes = inventory_payload["notes"]
    people_files = {
        Path(item["path"]).stem: item
        for item in notes
        if item["note_type"] == "person"
    }
    updates: list[dict[str, Any]] = []
    for person, person_note in sorted(people_files.items(), key=lambda item: item[0].casefold()):
        supporting_notes = [
            item
            for item in notes
            if business_note_scope(item["relative_path"], item["note_type"])
            and not item.get("roster_reference", False)
            and any(
                rel["name"] == person and rel["confidence"] >= 0.85
                for rel in item.get("people_relationships", [])
            )
        ]
        block = person_generated_block(person, supporting_notes)
        if not block:
            continue
        path = Path(person_note["path"])
        current_text = read_file_text(path)
        updated_text = replace_or_append_generated_block(current_text, block, GENERATED_PERSON_START, GENERATED_PERSON_END)
        if updated_text == current_text:
            continue
        updates.append(
            {
                "person": person,
                "path": str(path),
                "supporting_note_count": len(supporting_notes),
                "generated_block": block,
                "updated_text": updated_text,
                "source_notes": [item["stem"] for item in supporting_notes],
            }
        )
    return updates


def project_note_updates(inventory_payload: dict[str, Any], vault_root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    notes = inventory_payload["notes"]
    project_registry = inventory_payload["project_registry"]
    project_taxonomy = load_project_taxonomy(default_project_taxonomy_path())
    non_active_projects = (
        project_taxonomy["reference"] | project_taxonomy["archive"] | project_taxonomy["manual_review"]
    )
    existing_project_files = {
        Path(item["path"]).stem: item
        for item in notes
        if item["note_type"] == "project"
    }
    existing_stems = {Path(item["path"]).stem.casefold() for item in notes}
    updates: list[dict[str, Any]] = []
    creates: list[dict[str, Any]] = []
    manual_review: list[dict[str, Any]] = []

    for project_entry in project_registry:
        project = project_entry["name"]
        if project in non_active_projects:
            continue
        supporting_notes = [
            item
            for item in notes
            if business_note_scope(item["relative_path"], item["note_type"])
            and not item.get("roster_reference", False)
            and any(
                rel["name"] == project and rel["confidence"] >= 0.85
                for rel in item.get("project_relationships", [])
            )
        ]
        if not supporting_notes:
            continue
        block = project_generated_block(project, supporting_notes)
        if not block:
            continue

        existing = existing_project_files.get(project)
        if existing:
            path = Path(existing["path"])
            current_text = read_file_text(path)
            updated_text = replace_or_append_generated_block(current_text, block, GENERATED_PROJECT_START, GENERATED_PROJECT_END)
            if updated_text != current_text:
                updates.append(
                    {
                        "project": project,
                        "path": str(path),
                        "supporting_note_count": len(supporting_notes),
                        "generated_block": block,
                        "updated_text": updated_text,
                        "source_notes": [item["stem"] for item in supporting_notes],
                    }
                )
            continue

        project_filename = sanitize_filename_component(project) + ".md"
        target_path = vault_root / "projects" / project_filename
        if target_path.stem.casefold() in existing_stems:
            manual_review.append(
                {
                    "project": project,
                    "reason": "proposed project filename collides with existing vault basename",
                    "target_path": str(target_path),
                }
            )
            continue
        if project_entry["support_count"] < 2 and project_entry["title_path_hits"] < 1:
            manual_review.append(
                {
                    "project": project,
                    "reason": "project creation threshold not met",
                    "target_path": str(target_path),
                }
            )
            continue
        full_text = (
            "---\n"
            "type: project\n"
            "tags:\n"
            "  - project\n"
            "---\n\n"
            f"# {project}\n\n"
            "Status:\n"
            "Owner:\n"
            "Key stakeholders:\n\n"
            "## Purpose / outcome\n\n"
            "## Current status\n\n"
            "## Key people\n\n"
            "## Decisions\n\n"
            "## Risks / blockers\n\n"
            "## Open questions\n\n"
            "## Key source notes\n\n"
            "## Notes\n\n"
            + block
        )
        creates.append(
            {
                "project": project,
                "path": str(target_path),
                "supporting_note_count": len(supporting_notes),
                "generated_block": block,
                "updated_text": full_text,
                "source_notes": [item["stem"] for item in supporting_notes],
            }
        )
    return updates, creates, manual_review


def link_injection_updates(inventory_payload: dict[str, Any]) -> list[dict[str, Any]]:
    updates: list[dict[str, Any]] = []
    for item in inventory_payload["notes"]:
        if item["needs_related_update"] and item["proposed_related_block"]:
            updates.append(
                {
                    "path": item["path"],
                    "relative_path": item["relative_path"],
                    "title": item["title"],
                    "proposed_related_block": item["proposed_related_block"],
                    "missing_links_to_inject": item["missing_links_to_inject"],
                }
            )
    return updates


def relationship_plan(inventory_payload: dict[str, Any], vault_root: Path) -> dict[str, Any]:
    people_updates = person_note_updates(inventory_payload, vault_root)
    project_updates, project_creates, project_manual_review = project_note_updates(inventory_payload, vault_root)
    link_updates = link_injection_updates(inventory_payload)
    basename_collisions = inventory_payload.get("basename_collisions", [])
    notes_manual_review = [
        {"path": item["path"], "reasons": item["manual_review_reasons"]}
        for item in inventory_payload["notes"]
        if item.get("manual_review_reasons")
    ]
    roster_withheld = [
        {
            "path": item["path"],
            "withheld_people_links": item["withheld_people_links"],
        }
        for item in inventory_payload["notes"]
        if item.get("withheld_people_links")
    ]
    manual_review = notes_manual_review + project_manual_review
    return {
        "generated_at": timestamp_utc(),
        "vault_root": str(vault_root),
        "summary": {
            "notes_scanned": inventory_payload["summary"]["notes_scanned"],
            "project_notes_proposed": len(project_updates) + len(project_creates),
            "project_note_updates": len(project_updates),
            "project_note_creates": len(project_creates),
            "person_files_proposed_for_enrichment": len(people_updates),
            "source_notes_proposed_for_link_injection": len(link_updates),
            "manual_review_items": len(manual_review),
            "basename_collisions": len(basename_collisions),
        },
        "project_updates": project_updates,
        "project_creates": project_creates,
        "person_updates": people_updates,
        "link_updates": link_updates,
        "manual_review": manual_review,
        "roster_reference_withheld": roster_withheld,
        "basename_collisions": basename_collisions,
    }


def render_relationship_dry_run(plan: dict[str, Any]) -> str:
    lines = ["# Relationship Dry Run", "", "## Summary", ""]
    for key, value in plan["summary"].items():
        lines.append(f"- {key}: {value}")

    lines.extend(["", "## Project Files Proposed For Creation", ""])
    if plan["project_creates"]:
        for item in plan["project_creates"]:
            lines.append(f"- {item['project']} -> {item['path']} ({item['supporting_note_count']} supporting notes)")
    else:
        lines.append("- none")

    lines.extend(["", "## Project Files Proposed For Update", ""])
    if plan["project_updates"]:
        for item in plan["project_updates"]:
            lines.append(f"- {item['project']} -> {item['path']} ({item['supporting_note_count']} supporting notes)")
    else:
        lines.append("- none")

    lines.extend(["", "## Person Files Proposed For Enrichment", ""])
    if plan["person_updates"]:
        for item in plan["person_updates"]:
            lines.append(f"- {item['person']} -> {item['path']} ({item['supporting_note_count']} supporting notes)")
    else:
        lines.append("- none")

    lines.extend(["", "## Source Notes Proposed For Link Injection", ""])
    if plan["link_updates"]:
        for item in plan["link_updates"]:
            lines.append(f"- {item['path']}: {', '.join(item['missing_links_to_inject']) or 'normalize existing Related section'}")
    else:
        lines.append("- none")

    lines.extend(["", "## Manual Review Items", ""])
    if plan["manual_review"]:
        for item in plan["manual_review"]:
            if "reasons" in item:
                lines.append(f"- {item['path']}: {'; '.join(item['reasons'])}")
            else:
                lines.append(f"- {item['project']}: {item['reason']} -> {item['target_path']}")
    else:
        lines.append("- none")

    lines.extend(["", "## Basename Collisions", ""])
    if plan["basename_collisions"]:
        for item in plan["basename_collisions"]:
            lines.append(f"- {item['stem']}: {', '.join(item['paths'])}")
    else:
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def render_project_notes_dry_run(plan: dict[str, Any]) -> str:
    lines = ["# Project Notes Dry Run", ""]
    items = plan["project_creates"] + plan["project_updates"]
    if not items:
        lines.extend(["- none", ""])
        return "\n".join(lines)
    for item in items:
        action = "create" if item in plan["project_creates"] else "update"
        lines.extend([f"## {item['project']} ({action})", "", f"- Path: {item['path']}", f"- Supporting notes: {item['supporting_note_count']}", "", "```md", item["updated_text"].rstrip(), "```", ""])
    return "\n".join(lines)


def render_people_notes_dry_run(plan: dict[str, Any]) -> str:
    lines = ["# People Notes Dry Run", ""]
    if not plan["person_updates"]:
        lines.extend(["- none", ""])
        return "\n".join(lines)
    for item in plan["person_updates"]:
        lines.extend([f"## {item['person']}", "", f"- Path: {item['path']}", f"- Supporting notes: {item['supporting_note_count']}", "", "```md", item["generated_block"].rstrip(), "```", ""])
    return "\n".join(lines)


def render_link_injection_dry_run(plan: dict[str, Any]) -> str:
    lines = ["# Link Injection Dry Run", ""]
    if not plan["link_updates"]:
        lines.extend(["- none", ""])
        return "\n".join(lines)
    for item in plan["link_updates"]:
        lines.extend([f"## {item['title']}", "", f"- Path: {item['path']}", "", "```md", item["proposed_related_block"].rstrip(), "```", ""])
    return "\n".join(lines)


def render_manual_review(plan: dict[str, Any]) -> str:
    lines = ["# Manual Review", "", "## Unreadable / Dataless Source Files", "", "- none", ""]
    lines.extend(["## Roster / Reference Notes Withheld From Auto-Linking", ""])
    if plan["roster_reference_withheld"]:
        for item in plan["roster_reference_withheld"]:
            lines.append(f"- {item['path']}: {', '.join(f'[[{name}]]' for name in item['withheld_people_links'])}")
    else:
        lines.append("- none")
    lines.extend(["", "## Existing Target Conflicts", "", "- none", "", "## Ambiguous Person / Topic Matches", ""])
    ambiguous = [item for item in plan["manual_review"] if "reasons" in item]
    if ambiguous:
        for item in ambiguous:
            lines.append(f"- {item['path']}: {'; '.join(item['reasons'])}")
    else:
        lines.append("- none")
    lines.extend(["", "## Missing Local Assets", "", "- none", "", "## Hard Basename Collisions", ""])
    if plan["basename_collisions"]:
        for item in plan["basename_collisions"]:
            lines.append(f"- {item['stem']}: {', '.join(item['paths'])}")
    else:
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def render_basename_collisions(plan: dict[str, Any]) -> str:
    lines = ["# Basename Collisions", ""]
    if not plan["basename_collisions"]:
        lines.extend(["- none", ""])
        return "\n".join(lines)
    for item in plan["basename_collisions"]:
        lines.append(f"## {item['stem']}")
        lines.append("")
        for path in item["paths"]:
            lines.append(f"- {path}")
        lines.append("")
    return "\n".join(lines)


def write_relationship_reports(plan: dict[str, Any], report_root: Path, vault_root: Path) -> dict[str, Path]:
    report_map = {
        "RELATIONSHIP_DRY_RUN.md": render_relationship_dry_run(plan),
        "PROJECT_NOTES_DRY_RUN.md": render_project_notes_dry_run(plan),
        "PEOPLE_NOTES_DRY_RUN.md": render_people_notes_dry_run(plan),
        "LINK_INJECTION_DRY_RUN.md": render_link_injection_dry_run(plan),
        "MANUAL_REVIEW.md": render_manual_review(plan),
        "BASENAME_COLLISIONS.md": render_basename_collisions(plan),
    }
    paths: dict[str, Path] = {}
    for filename, content in report_map.items():
        path = resolve_report_path(report_root, filename)
        try:
            assert_report_outside_vault(path, vault_root)
        except ValueError:
            pass
        write_text_output(path, content, vault_root=vault_root)
        paths[filename] = path
    return paths


def load_relationship_plan(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def timestamp_slug() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def write_relationship_inventory(path: Path, payload: dict[str, Any]) -> None:
    write_json_output(path, payload)


def apply_relationship_plan(
    plan: dict[str, Any],
    *,
    vault_root: Path,
    report_root: Path,
    allow_basename_collisions: bool = False,
) -> dict[str, Any]:
    collisions = plan.get("basename_collisions", [])
    if collisions and not allow_basename_collisions:
        raise RuntimeError("Hard basename collisions exist. Resolve them or pass explicit override.")

    backup_root = report_root / "backups" / f"relationship-updates-{timestamp_slug()}"
    touched: list[str] = []

    def backup_and_write(path: Path, content: str) -> None:
        if not is_within(path, vault_root):
            raise RuntimeError(f"Refusing to modify file outside vault: {path}")
        backup_path = backup_root / path.relative_to(vault_root)
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            backup_path.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        touched.append(str(path))

    for item in plan["person_updates"]:
        backup_and_write(Path(item["path"]), item["updated_text"])
    for item in plan["project_updates"]:
        backup_and_write(Path(item["path"]), item["updated_text"])
    for item in plan["project_creates"]:
        backup_and_write(Path(item["path"]), item["updated_text"])
    for item in plan["link_updates"]:
        path = Path(item["path"])
        current_text = read_file_text(path)
        _, body = split_frontmatter(current_text)
        proposed_block = item["proposed_related_block"]
        current_span = current_related_span(body)
        if current_span:
            start, end = current_span
            updated_body = body[:start] + proposed_block + body[end:]
        else:
            frontmatter, body_only = split_frontmatter(current_text)
            if body_only.startswith("# "):
                lines = body_only.splitlines(keepends=True)
                insert_at = 1
                while insert_at < len(lines) and not lines[insert_at].strip():
                    insert_at += 1
                lines.insert(insert_at, "\n" + proposed_block)
                updated_body = "".join(lines)
                backup_and_write(path, frontmatter + updated_body)
                continue
            updated_body = proposed_block + body
        frontmatter, _ = split_frontmatter(current_text)
        backup_and_write(path, frontmatter + updated_body)

    return {"backup_root": str(backup_root), "touched_files": touched}
