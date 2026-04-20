from __future__ import annotations

import json
import logging
import re
import unicodedata
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable


LOGGER = logging.getLogger("notes_migration")

DEFAULT_SOURCE_ROOT = Path("/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/iCloud")
DEFAULT_VAULT_ROOT = Path("/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/notes")
DEFAULT_REPORT_ROOT = Path("/Users/I533181/Library/Mobile Documents/com~apple~CloudDocs/Notes/Mig/reports")

WIKILINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
MARKDOWN_LINK_RE = re.compile(r"(?<!!)\[([^\]]+)\]\(([^)]+)\)")
IMAGE_LINK_RE = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)")
FENCED_CODE_RE = re.compile(r"```[\s\S]*?```", re.MULTILINE)
INLINE_CODE_RE = re.compile(r"`[^`\n]+`")
H1_RE = re.compile(r"(?m)^#\s+(.+?)\s*$")
WORD_RE = re.compile(r"\b[\w'-]+\b", re.UNICODE)
DATE_PATTERNS = (
    re.compile(r"(?P<day>\d{2})-(?P<month>\d{2})-(?P<year>\d{4})"),
    re.compile(r"(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})"),
    re.compile(r"(?<!\d)(?P<year>\d{4})(?P<month>\d{2})(?P<day>\d{2})(?!\d)"),
)
SHORT_LIST_LINE_RE = re.compile(r"^(?:[-*+]\s|\d+\.\s|-\s\[[ xX]\]\s)")
REPORT_WIKILINK_RE = re.compile(r"(?<!`)(\[\[[^\]]+\]\])(?!`)")
CAMEL_OR_ACRONYM_RE = re.compile(
    r"\b(?:[A-Z]{2,}(?:[A-Z0-9]+)?|[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+)(?: [A-Z][a-z0-9]+)*\b"
)
GRANOLA_NOTE_DATE_RE = re.compile(r"(?mi)^-\s*Note Date:\s*(?P<date>\d{4}-\d{2}-\d{2})\s*$")
GRANOLA_SCHEDULED_RE = re.compile(r"(?mi)^-\s*Scheduled:\s*(?P<date>\d{4}-\d{2}-\d{2})T")
GRANOLA_METADATA_RE = re.compile(r"(?mi)^-\s*(Note ID|Calendar Event|Scheduled|Owner|Folders):\s+")

MEETING_KEYWORDS = (
    "1:1",
    "meeting",
    "leadership",
    "council",
    "management",
    "abstimmung",
    "sync",
    "review",
)
WEEKLY_KEYWORDS = ("weekly", "week ", "week-", "woche", "review")
REFERENCE_KEYWORDS = (
    "playbook",
    "process",
    "guide",
    "profile",
    "request",
    "architecture",
    "reference",
    "how to",
    "runbook",
    "roadmap",
)
ROSTER_KEYWORDS = (
    "acr",
    "roster",
    "team list",
    "org",
    "organization",
    "people",
    "headcount",
    "comp review",
)
NARRATIVE_KEYWORDS = (
    "agenda",
    "decision",
    "next step",
    "discussion",
    "action item",
    "follow up",
    "owner",
)
GENERIC_TITLES = {"new note", "neue notiz", "untitled"}
INVALID_FILENAME_CHARS_RE = re.compile(r'[\\/:*?"<>|]+')
MULTISPACE_RE = re.compile(r"\s+")
GENERIC_TOPIC_KEYS = {
    "sap",
    "notes",
    "private",
    "meeting",
    "management",
    "leadership",
    "services",
    "projects",
    "team",
    "goals",
    "general",
    "tool",
    "council",
}

PERSON_NOTE_TEMPLATE = """---
type: person
tags:
  - people
  - direct
---

# {name}

Role:
Team:
1:1 cadence:
Manager:

## Current priorities

## Current risks / blockers

## Development focus

## Support needed from me

## Evidence log

### Wins

### Concerns / coaching

### Growth / stretch

## 1:1 log
"""

PROJECT_NOTE_TEMPLATE = """---
type: project
tags:
  - project
---

# {name}

## Context

Created from recurring migration evidence.

## Related notes
"""


@dataclass
class PeopleConfig:
    canonical_people: list[str]
    routing_aliases: dict[str, list[str]]
    ambiguous_short_names: list[str]
    _canonical_lookup: dict[str, str] = field(init=False, repr=False)
    _routing_lookup: dict[str, str] = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self._canonical_lookup = {normalize_name_key(name): name for name in self.canonical_people}
        routing: dict[str, str] = {}
        for canonical, aliases in self.routing_aliases.items():
            routing[normalize_name_key(canonical)] = canonical
            for alias in aliases:
                routing[normalize_name_key(alias)] = canonical
        self._routing_lookup = routing

    def canonical_for_alias(self, value: str) -> str | None:
        return self._routing_lookup.get(normalize_name_key(value))

    def canonical_name(self, value: str) -> str | None:
        return self._canonical_lookup.get(normalize_name_key(value))


@dataclass
class DateGuess:
    iso: str
    source: str
    confidence: str

    def to_dict(self) -> dict[str, str]:
        return {"iso": self.iso, "source": self.source, "confidence": self.confidence}


@dataclass
class InventoryNote:
    source_path: str
    relative_path: str
    top_level_scope: str
    filename: str
    stem: str
    read_status: str
    read_error: str | None = None
    frontmatter_present: bool = False
    title_guess: str = ""
    h1_guess: str | None = None
    date_guess: DateGuess | None = None
    word_count: int = 0
    wiki_links: list[str] = field(default_factory=list)
    markdown_links: list[dict[str, str]] = field(default_factory=list)
    detected_people: list[str] = field(default_factory=list)
    path_people: list[str] = field(default_factory=list)
    project_topic_hints: list[str] = field(default_factory=list)
    local_asset_refs: list[dict[str, Any]] = field(default_factory=list)
    note_type_candidates: list[dict[str, Any]] = field(default_factory=list)
    roster_signals: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        payload = {
            "source_path": self.source_path,
            "relative_path": self.relative_path,
            "top_level_scope": self.top_level_scope,
            "filename": self.filename,
            "stem": self.stem,
            "read_status": self.read_status,
            "read_error": self.read_error,
            "frontmatter_present": self.frontmatter_present,
            "title_guess": self.title_guess,
            "h1_guess": self.h1_guess,
            "date_guess": self.date_guess.to_dict() if self.date_guess else None,
            "word_count": self.word_count,
            "wiki_links": list(self.wiki_links),
            "markdown_links": list(self.markdown_links),
            "detected_people": list(self.detected_people),
            "path_people": list(self.path_people),
            "project_topic_hints": list(self.project_topic_hints),
            "local_asset_refs": list(self.local_asset_refs),
            "note_type_candidates": list(self.note_type_candidates),
            "roster_signals": dict(self.roster_signals),
        }
        return payload

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "InventoryNote":
        date_guess = payload.get("date_guess")
        return cls(
            source_path=payload["source_path"],
            relative_path=payload["relative_path"],
            top_level_scope=payload["top_level_scope"],
            filename=payload["filename"],
            stem=payload["stem"],
            read_status=payload["read_status"],
            read_error=payload.get("read_error"),
            frontmatter_present=bool(payload.get("frontmatter_present", False)),
            title_guess=payload.get("title_guess", ""),
            h1_guess=payload.get("h1_guess"),
            date_guess=DateGuess(**date_guess) if isinstance(date_guess, dict) else None,
            word_count=int(payload.get("word_count", 0)),
            wiki_links=list(payload.get("wiki_links", [])),
            markdown_links=list(payload.get("markdown_links", [])),
            detected_people=list(payload.get("detected_people", [])),
            path_people=list(payload.get("path_people", [])),
            project_topic_hints=list(payload.get("project_topic_hints", [])),
            local_asset_refs=list(payload.get("local_asset_refs", [])),
            note_type_candidates=list(payload.get("note_type_candidates", [])),
            roster_signals=dict(payload.get("roster_signals", {})),
        )


@dataclass
class PlanNote:
    source_path: str
    relative_path: str
    classification: str
    target_path: str | None
    title: str
    reasons: list[str] = field(default_factory=list)
    related_links: list[str] = field(default_factory=list)
    intentional_reference_people_links: bool = False
    manual_review_reasons: list[str] = field(default_factory=list)
    missing_assets: list[str] = field(default_factory=list)
    existing_target_conflict: bool = False
    basename_stem: str | None = None
    already_migrated: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_path": self.source_path,
            "relative_path": self.relative_path,
            "classification": self.classification,
            "target_path": self.target_path,
            "title": self.title,
            "reasons": list(self.reasons),
            "related_links": list(self.related_links),
            "intentional_reference_people_links": self.intentional_reference_people_links,
            "manual_review_reasons": list(self.manual_review_reasons),
            "missing_assets": list(self.missing_assets),
            "existing_target_conflict": self.existing_target_conflict,
            "basename_stem": self.basename_stem,
            "already_migrated": self.already_migrated,
        }


def configure_logging(verbose: bool = False) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )


def timestamp_utc() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def default_people_config_path() -> Path:
    return repo_root() / "config" / "people.yml"


def ensure_parent_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def is_within(child: Path, parent: Path) -> bool:
    child_resolved = child.expanduser().resolve()
    parent_resolved = parent.expanduser().resolve()
    try:
        child_resolved.relative_to(parent_resolved)
        return True
    except ValueError:
        return False


def resolve_report_path(report_root: Path, filename: str) -> Path:
    return report_root.expanduser().resolve() / filename


def assert_report_outside_vault(report_path: Path, vault_root: Path) -> None:
    if is_within(report_path, vault_root):
        raise ValueError(
            f"Report path {report_path} resolves inside indexed vault {vault_root}. "
            "Move reports outside the vault or sanitize wiki links before writing."
        )


def sanitize_report_wikilinks(text: str) -> str:
    return REPORT_WIKILINK_RE.sub(lambda match: f"`{match.group(1)}`", text)


def write_text_output(path: Path, content: str, vault_root: Path | None = None) -> None:
    ensure_parent_dir(path)
    final_content = content
    if vault_root is not None and is_within(path, vault_root):
        final_content = sanitize_report_wikilinks(content)
    path.write_text(final_content, encoding="utf-8")


def write_json_output(path: Path, payload: dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False, sort_keys=False)
        handle.write("\n")


def load_json_file(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_people_config(path: Path) -> PeopleConfig:
    canonical_people: list[str] = []
    routing_aliases: dict[str, list[str]] = {}
    ambiguous_short_names: list[str] = []
    current_top: str | None = None
    current_nested: str | None = None

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
                raise ValueError(f"Unsupported people config line: {raw_line}")
            current_top = stripped[:-1]
            current_nested = None
            continue

        if indent == 2 and stripped.endswith(":"):
            if current_top != "routing_aliases":
                raise ValueError(f"Unexpected nested key outside routing_aliases: {raw_line}")
            current_nested = stripped[:-1]
            routing_aliases.setdefault(current_nested, [])
            continue

        if indent == 2 and stripped.startswith("- "):
            value = stripped[2:].strip()
            if current_top == "canonical_people":
                canonical_people.append(value)
            elif current_top == "ambiguous_short_names":
                ambiguous_short_names.append(value)
            else:
                raise ValueError(f"Unexpected list item: {raw_line}")
            continue

        if indent == 4 and stripped.startswith("- "):
            value = stripped[2:].strip()
            if current_top != "routing_aliases" or current_nested is None:
                raise ValueError(f"Unexpected alias item: {raw_line}")
            routing_aliases.setdefault(current_nested, []).append(value)
            continue

        raise ValueError(f"Unsupported people config structure: {raw_line}")

    return PeopleConfig(
        canonical_people=canonical_people,
        routing_aliases=routing_aliases,
        ambiguous_short_names=ambiguous_short_names,
    )


def normalize_name_key(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).strip()
    normalized = MULTISPACE_RE.sub(" ", normalized)
    return normalized.casefold()


def normalize_topic_display(value: str) -> str:
    cleaned = value.replace("_", " ").replace("-", " ").strip()
    cleaned = MULTISPACE_RE.sub(" ", cleaned)
    return cleaned


def normalize_topic_key(value: str) -> str:
    cleaned = normalize_topic_display(value)
    cleaned = re.sub(r"[^A-Za-z0-9 ]+", "", cleaned)
    cleaned = MULTISPACE_RE.sub(" ", cleaned).strip().casefold()
    return cleaned


def split_frontmatter(text: str) -> tuple[str, str]:
    if not text.startswith("---\n"):
        return "", text
    lines = text.splitlines(keepends=True)
    if not lines:
        return "", text
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            frontmatter = "".join(lines[: index + 1])
            body = "".join(lines[index + 1 :])
            return frontmatter, body
    return "", text


def mask_code_segments(text: str) -> str:
    chars = list(text)

    def mask_match(match: re.Match[str]) -> None:
        for index in range(match.start(), match.end()):
            if chars[index] != "\n":
                chars[index] = " "

    for match in FENCED_CODE_RE.finditer(text):
        mask_match(match)
    masked_after_fences = "".join(chars)
    chars = list(masked_after_fences)
    for match in INLINE_CODE_RE.finditer(masked_after_fences):
        mask_match(match)
    return "".join(chars)


def extract_wiki_links(text: str) -> list[str]:
    masked = mask_code_segments(text)
    links: list[str] = []
    for match in WIKILINK_RE.finditer(masked):
        raw = match.group(1).strip()
        if raw:
            links.append(raw)
    return links


def wiki_target(raw: str) -> str:
    target = raw.split("|", 1)[0].split("#", 1)[0].strip()
    return target


def extract_markdown_links(text: str) -> list[dict[str, str]]:
    masked = mask_code_segments(text)
    links: list[dict[str, str]] = []
    for match in MARKDOWN_LINK_RE.finditer(masked):
        links.append({"label": match.group(1).strip(), "target": match.group(2).strip()})
    return links


def extract_image_links(text: str) -> list[dict[str, str]]:
    masked = mask_code_segments(text)
    links: list[dict[str, str]] = []
    for match in IMAGE_LINK_RE.finditer(masked):
        links.append({"alt": match.group(1).strip(), "target": match.group(2).strip()})
    return links


def extract_local_asset_refs(text: str, note_path: Path) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    raw_targets: list[str] = []
    for link in extract_markdown_links(text):
        raw_targets.append(link["target"])
    for link in extract_image_links(text):
        raw_targets.append(link["target"])

    seen_targets: set[str] = set()
    for target in raw_targets:
        if target in seen_targets:
            continue
        seen_targets.add(target)
        if is_external_target(target) or target.startswith("#"):
            continue
        resolved = (note_path.parent / target).resolve()
        refs.append(
            {
                "path": target,
                "resolved_path": str(resolved),
                "exists": resolved.exists(),
            }
        )
    return refs


def is_external_target(target: str) -> bool:
    return re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target) is not None


def read_file_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def guess_h1(body: str) -> str | None:
    match = H1_RE.search(mask_code_segments(body))
    if not match:
        return None
    value = match.group(1).strip()
    return value or None


def guess_date(*candidates: tuple[str, str | None]) -> DateGuess | None:
    for source, value in candidates:
        if not value:
            continue
        for pattern in DATE_PATTERNS:
            match = pattern.search(value)
            if not match:
                continue
            try:
                year = int(match.group("year"))
                month = int(match.group("month"))
                day = int(match.group("day"))
                iso = datetime(year, month, day).strftime("%Y-%m-%d")
            except ValueError:
                continue
            confidence = "high" if source == "filename" else "medium"
            return DateGuess(iso=iso, source=source, confidence=confidence)
    return None


def granola_date_guess(body: str) -> DateGuess | None:
    for pattern, source in (
        (GRANOLA_NOTE_DATE_RE, "granola_note_date"),
        (GRANOLA_SCHEDULED_RE, "granola_scheduled"),
    ):
        match = pattern.search(body)
        if not match:
            continue
        value = match.group("date")
        try:
            iso = datetime.strptime(value, "%Y-%m-%d").strftime("%Y-%m-%d")
        except ValueError:
            continue
        return DateGuess(iso=iso, source=source, confidence="high")
    return None


def clean_title_from_stem(stem: str) -> str:
    value = stem
    for _ in range(2):
        value = re.sub(r"^(?:\d{2}-\d{2}-\d{4}|\d{4}-\d{2}-\d{2}|\d{8})[-_ ]*", "", value)
    value = value.strip(" -_")
    value = MULTISPACE_RE.sub(" ", value)
    return value.strip()


def guess_title(stem: str, h1_guess: str | None) -> str:
    if h1_guess and h1_guess.strip("# ").strip():
        return h1_guess.strip()
    cleaned = clean_title_from_stem(stem)
    if cleaned:
        return cleaned
    return stem.strip()


def word_count_for_text(text: str) -> int:
    return len(WORD_RE.findall(mask_code_segments(text)))


def exact_people_matches(text: str, people: list[str]) -> list[str]:
    masked = mask_code_segments(text)
    found: list[str] = []
    for name in sorted(people, key=len, reverse=True):
        pattern = re.compile(rf"(?<![\w]){re.escape(name)}(?![\w])")
        if pattern.search(masked):
            found.append(name)
    return sorted(set(found), key=lambda value: value.casefold())


def detect_path_people(relative_path: str, people_config: PeopleConfig) -> list[str]:
    parts = Path(relative_path).parts
    matches: list[str] = []
    if "1:1" in parts:
        index = parts.index("1:1")
        if index + 1 < len(parts):
            candidate = parts[index + 1].strip()
            canonical = people_config.canonical_for_alias(candidate)
            if canonical:
                matches.append(canonical)
    return sorted(set(matches), key=lambda value: value.casefold())


def extract_project_topic_hints(relative_path: str, title_guess: str, text: str, people_config: PeopleConfig) -> list[str]:
    hints: list[str] = []
    hints.extend(path_project_topic_hints(relative_path))

    sample_text = "\n".join(mask_code_segments(text).splitlines()[:20])
    for source in (title_guess, sample_text):
        for match in CAMEL_OR_ACRONYM_RE.findall(source):
            hint = normalize_topic_display(match)
            if not hint:
                continue
            topic_key = normalize_topic_key(hint)
            if topic_key in GENERIC_TOPIC_KEYS:
                continue
            if people_config.canonical_name(hint) is not None:
                continue
            hints.append(hint)

    ordered: list[str] = []
    seen: set[str] = set()
    for hint in hints:
        key = normalize_topic_key(hint)
        if not key or key in seen:
            continue
        seen.add(key)
        ordered.append(hint)
    return ordered


def path_project_topic_hints(relative_path: str) -> list[str]:
    hints: list[str] = []
    path_segments = list(Path(relative_path).parts[:-1])
    for marker in ("Projects", "Services"):
        if marker in path_segments:
            index = path_segments.index(marker)
            if index + 1 < len(path_segments):
                hint = normalize_topic_display(path_segments[index + 1])
                if hint:
                    hints.append(hint)
    return hints


def roster_signals_for_note(
    title_guess: str,
    relative_path: str,
    body: str,
    detected_people: list[str],
) -> dict[str, Any]:
    masked = mask_code_segments(body)
    lines = [line.strip() for line in masked.splitlines()]
    non_empty_lines = [line for line in lines if line]
    short_list_lines = 0
    for line in non_empty_lines:
        if SHORT_LIST_LINE_RE.match(line):
            short_list_lines += 1
        elif len(line) <= 48 and any(name in line for name in detected_people):
            short_list_lines += 1

    combined = f"{title_guess}\n{relative_path}".casefold()
    roster_keyword_hits = sum(1 for keyword in ROSTER_KEYWORDS if keyword in combined)
    narrative_text = masked.casefold()
    narrative_score = sum(narrative_text.count(keyword) for keyword in NARRATIVE_KEYWORDS)
    short_ratio = 0.0
    if non_empty_lines:
        short_ratio = short_list_lines / len(non_empty_lines)

    is_roster_reference = (
        len(set(detected_people)) >= 6
        and short_list_lines >= 8
        and short_ratio >= 0.6
        and narrative_score < 3
    )

    return {
        "unique_people_count": len(set(detected_people)),
        "short_list_lines": short_list_lines,
        "non_empty_lines": len(non_empty_lines),
        "short_list_ratio": round(short_ratio, 3),
        "roster_keyword_hits": roster_keyword_hits,
        "narrative_score": narrative_score,
        "is_roster_reference": is_roster_reference,
    }


def note_type_candidates_for(
    note: InventoryNote,
    title_guess: str,
    body: str,
    people_config: PeopleConfig,
) -> list[dict[str, Any]]:
    scores: dict[str, int] = {
        "person": 0,
        "meeting": 0,
        "project": 0,
        "weekly": 0,
        "reference": 0,
        "manual review": 0,
    }
    reasons: dict[str, list[str]] = {key: [] for key in scores}
    path_folded = note.relative_path.casefold()
    title_folded = title_guess.casefold()
    body_folded = body.casefold()

    if note.read_status != "ok":
        scores["manual review"] += 10
        reasons["manual review"].append("source unreadable")
        return rank_candidates(scores, reasons)

    if note.top_level_scope in {"Private", "Recently Deleted"}:
        scores["manual review"] += 6
        reasons["manual review"].append(f"{note.top_level_scope} defaults to manual review")

    if note.roster_signals.get("is_roster_reference"):
        scores["reference"] += 8
        reasons["reference"].append("roster/list note detected")

    if GRANOLA_METADATA_RE.search(body):
        scores["meeting"] += 5
        reasons["meeting"].append("granola meeting metadata detected")

    if any(keyword in title_folded or keyword in path_folded for keyword in WEEKLY_KEYWORDS):
        scores["weekly"] += 5
        reasons["weekly"].append("weekly keyword in title or path")

    if any(keyword in path_folded for keyword in MEETING_KEYWORDS):
        scores["meeting"] += 3
        reasons["meeting"].append("meeting keyword in path")
    if any(keyword in title_folded for keyword in MEETING_KEYWORDS):
        scores["meeting"] += 2
        reasons["meeting"].append("meeting keyword in title")
    if "calendar event:" in body_folded or "attendees:" in body_folded:
        scores["meeting"] += 2
        reasons["meeting"].append("calendar metadata present in body")
    if note.date_guess is not None:
        scores["meeting"] += 1
        reasons["meeting"].append("dated note")
    if note.roster_signals.get("narrative_score", 0) >= 3:
        scores["meeting"] += 1
        reasons["meeting"].append("narrative meeting language present")
    if "/projects/" in f"/{path_folded}/" or "/services/" in f"/{path_folded}/":
        scores["meeting"] += 1
        reasons["meeting"].append("project/service path likely holds meeting notes")

    if "/projects/" in f"/{path_folded}/":
        scores["project"] += 2
        reasons["project"].append("project path")
    if "/services/" in f"/{path_folded}/":
        scores["project"] += 1
        reasons["project"].append("service path")
    if note.project_topic_hints:
        scores["project"] += 1
        reasons["project"].append("project/topic hints detected")
    if note.date_guess is None and "/projects/" in f"/{path_folded}/":
        scores["project"] += 1
        reasons["project"].append("undated project note")

    if any(keyword in title_folded or keyword in path_folded for keyword in REFERENCE_KEYWORDS):
        scores["reference"] += 2
        reasons["reference"].append("reference/process keyword present")
    if note.top_level_scope == "Notes":
        scores["reference"] += 1
        reasons["reference"].append("general notes scope")

    if people_config.canonical_name(title_guess) is not None and note.date_guess is None:
        scores["person"] += 2
        reasons["person"].append("title matches canonical person")

    if not any(score > 0 for score in scores.values()):
        scores["manual review"] += 1
        reasons["manual review"].append("no confident classification signal")

    return rank_candidates(scores, reasons)


def rank_candidates(scores: dict[str, int], reasons: dict[str, list[str]]) -> list[dict[str, Any]]:
    ordered = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    return [
        {"type": note_type, "score": score, "reasons": reasons[note_type]}
        for note_type, score in ordered
        if score > 0
    ]


def build_inventory_note(
    source_root: Path,
    path: Path,
    people_config: PeopleConfig,
    *,
    reader: Callable[[Path], str] = read_file_text,
) -> InventoryNote:
    relative_path = str(path.relative_to(source_root))
    relative_parts = Path(relative_path).parts
    if len(relative_parts) > 1:
        top_level_scope = relative_parts[0]
    else:
        top_level_scope = source_root.name
    base = InventoryNote(
        source_path=str(path),
        relative_path=relative_path,
        top_level_scope=top_level_scope,
        filename=path.name,
        stem=path.stem,
        read_status="ok",
    )
    try:
        text = reader(path)
    except (OSError, UnicodeError, ValueError) as exc:
        base.read_status = "unreadable"
        base.read_error = f"{type(exc).__name__}: {exc}"
        base.title_guess = guess_title(path.stem, None)
        base.note_type_candidates = note_type_candidates_for(base, base.title_guess, "", people_config)
        return base

    frontmatter, body = split_frontmatter(text)
    h1_guess = guess_h1(body)
    title_guess = guess_title(path.stem, h1_guess)
    date_guess = guess_date(("filename", path.stem), ("h1", h1_guess), ("title", title_guess)) or granola_date_guess(body)
    detected_people = exact_people_matches("\n".join([title_guess, body]), people_config.canonical_people)
    path_people = detect_path_people(relative_path, people_config)
    project_hints = extract_project_topic_hints(relative_path, title_guess, body, people_config)
    roster_signals = roster_signals_for_note(title_guess, relative_path, body, detected_people)

    base.frontmatter_present = bool(frontmatter)
    base.title_guess = title_guess
    base.h1_guess = h1_guess
    base.date_guess = date_guess
    base.word_count = word_count_for_text(body)
    base.wiki_links = extract_wiki_links(body)
    base.markdown_links = extract_markdown_links(body)
    base.detected_people = detected_people
    base.path_people = path_people
    base.project_topic_hints = project_hints
    base.local_asset_refs = extract_local_asset_refs(body, path)
    base.roster_signals = roster_signals
    base.note_type_candidates = note_type_candidates_for(base, title_guess, body, people_config)
    return base


def inventory_notes(
    source_root: Path,
    people_config: PeopleConfig,
    *,
    reader: Callable[[Path], str] = read_file_text,
) -> dict[str, Any]:
    notes: list[InventoryNote] = []
    for path in sorted(source_root.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".md", ".markdown"}:
            continue
        notes.append(build_inventory_note(source_root, path, people_config, reader=reader))

    summary: dict[str, Any] = {
        "total_notes": len(notes),
        "scopes": {},
        "read_status": {},
        "files_with_local_asset_refs": 0,
    }
    for note in notes:
        summary["scopes"][note.top_level_scope] = summary["scopes"].get(note.top_level_scope, 0) + 1
        summary["read_status"][note.read_status] = summary["read_status"].get(note.read_status, 0) + 1
        if note.local_asset_refs:
            summary["files_with_local_asset_refs"] += 1

    return {
        "generated_at": timestamp_utc(),
        "source_root": str(source_root),
        "summary": summary,
        "notes": [note.to_dict() for note in notes],
    }


def load_inventory(path: Path) -> tuple[Path, list[InventoryNote], dict[str, Any]]:
    payload = load_json_file(path)
    source_root = Path(payload["source_root"])
    notes = [InventoryNote.from_dict(item) for item in payload.get("notes", [])]
    return source_root, notes, payload


def strong_project_topics(
    notes: list[InventoryNote],
    people_config: PeopleConfig,
    target_root: Path | None = None,
) -> dict[str, dict[str, Any]]:
    topic_counts: dict[str, dict[str, Any]] = {}
    for note in notes:
        if note.read_status != "ok":
            continue
        for hint in path_project_topic_hints(note.relative_path):
            key = normalize_topic_key(hint)
            if not key or key in GENERIC_TOPIC_KEYS:
                continue
            if people_config.canonical_name(hint) is not None:
                continue
            entry = topic_counts.setdefault(key, {"name": hint, "count": 0, "sources": []})
            entry["count"] += 1
            entry["sources"].append(note.relative_path)
            if len(hint) > len(entry["name"]):
                entry["name"] = hint

    if target_root is not None:
        projects_dir = target_root / "projects"
        if projects_dir.exists():
            for path in sorted(projects_dir.glob("*.md")):
                hint = path.stem
                key = normalize_topic_key(hint)
                if not key or key in GENERIC_TOPIC_KEYS:
                    continue
                entry = topic_counts.setdefault(key, {"name": hint, "count": 0, "sources": []})
                entry["count"] = max(2, int(entry["count"]))
                if not entry["name"]:
                    entry["name"] = hint

    return {key: value for key, value in topic_counts.items() if value["count"] >= 2}


def choose_classification(note: InventoryNote, strong_projects: dict[str, dict[str, Any]]) -> tuple[str, list[str]]:
    reasons: list[str] = []

    if note.read_status != "ok":
        return "manual review", ["source unreadable"]

    if note.top_level_scope == "granola_notes_md" and note.date_guess is not None:
        return "meeting", ["granola export note routed to meetings"]

    if note.top_level_scope in {"Private", "Recently Deleted"}:
        return "inbox-import", [f"{note.top_level_scope} routed to inbox-import"]

    if note.roster_signals.get("is_roster_reference"):
        reasons.append("roster/list note classified as reference")
        return "reference", reasons

    scores = {candidate["type"]: int(candidate["score"]) for candidate in note.note_type_candidates}
    if scores.get("weekly", 0) >= 5:
        return "weekly", ["weekly cadence signals"]
    if scores.get("meeting", 0) >= 3:
        return "meeting", ["meeting/date/path signals"]
    if scores.get("project", 0) >= 4 and note.date_guess is None:
        has_strong_project = any(normalize_topic_key(hint) in strong_projects for hint in note.project_topic_hints)
        if has_strong_project:
            return "project", ["project topic is strongly evidenced"]
    if scores.get("reference", 0) >= 2:
        return "reference", ["reference/process/static note signals"]
    if scores.get("person", 0) >= 2:
        return "person", ["title matches canonical person note pattern"]

    return "inbox-import", ["classification confidence too low; routed to inbox-import"]


def sanitize_filename_component(value: str) -> str:
    value = unicodedata.normalize("NFC", value)
    value = INVALID_FILENAME_CHARS_RE.sub(" ", value)
    value = MULTISPACE_RE.sub(" ", value).strip().rstrip(".")
    return value or "Untitled"


def build_note_filename(note: InventoryNote) -> str:
    title = sanitize_filename_component(note.title_guess or note.stem)
    if note.date_guess is not None and not title.casefold().startswith(note.date_guess.iso.casefold()):
        return f"{note.date_guess.iso} {title}.md"
    if title.casefold().endswith(".md"):
        return title
    return f"{title}.md"


def proposed_target_path(note: InventoryNote, classification: str, target_root: Path) -> Path | None:
    filename = build_note_filename(note)
    if classification == "meeting":
        if note.date_guess is None:
            return None
        return target_root / "meetings" / note.date_guess.iso[:4] / note.date_guess.iso[5:7] / filename
    if classification == "weekly":
        return target_root / "weekly" / filename
    if classification == "reference":
        roster = bool(note.roster_signals.get("is_roster_reference"))
        subdir = target_root / "reference" / "teams" if roster else target_root / "reference"
        return subdir / filename
    if classification == "project":
        return target_root / "projects" / filename
    if classification == "person":
        title = sanitize_filename_component(note.title_guess or note.stem)
        return target_root / "people" / "directs" / f"{title}.md"
    if classification == "inbox-import":
        relative = Path(note.relative_path)
        scope_dir = sanitize_filename_component(note.top_level_scope or "Imported")
        extra_dirs = [sanitize_filename_component(part) for part in relative.parts[1:-1]]
        return target_root / "inbox-import" / scope_dir / Path(*extra_dirs) / filename
    return None


def target_existing_markdown_files(target_root: Path) -> list[Path]:
    if not target_root.exists():
        return []
    return sorted(
        path
        for path in target_root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".md", ".markdown"}
    )


def canonical_person_file_specs(target_root: Path, people_config: PeopleConfig) -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    for name in people_config.canonical_people:
        path = target_root / "people" / "directs" / f"{name}.md"
        specs.append({"name": name, "path": str(path), "exists": path.exists()})
    return specs


def canonical_project_file_specs(target_root: Path, strong_projects: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    for entry in sorted(strong_projects.values(), key=lambda item: item["name"].casefold()):
        path = target_root / "projects" / f"{sanitize_filename_component(entry['name'])}.md"
        specs.append({"name": entry["name"], "path": str(path), "count": entry["count"], "sources": entry["sources"]})
    return specs


def existing_wiki_targets(note: InventoryNote) -> set[str]:
    return {wiki_target(raw).casefold() for raw in note.wiki_links}


def project_link_targets(note: InventoryNote, strong_projects: dict[str, dict[str, Any]]) -> list[str]:
    results: list[str] = []
    for hint in note.project_topic_hints:
        key = normalize_topic_key(hint)
        entry = strong_projects.get(key)
        if not entry:
            continue
        results.append(entry["name"])
    ordered: list[str] = []
    seen: set[str] = set()
    for item in sorted(results, key=lambda value: value.casefold()):
        key = item.casefold()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(item)
    return ordered


def related_links_for_note(
    note: InventoryNote,
    classification: str,
    strong_projects: dict[str, dict[str, Any]],
) -> tuple[list[str], bool]:
    if classification not in {"meeting", "weekly"}:
        return [], False

    links: list[str] = []
    existing_targets = existing_wiki_targets(note)
    people_targets = sorted(set(note.detected_people + note.path_people), key=lambda value: value.casefold())
    for person in people_targets:
        if person.casefold() in existing_targets:
            continue
        links.append(f"[[{person}]]")

    for project in project_link_targets(note, strong_projects):
        if project.casefold() in existing_targets:
            continue
        links.append(f"[[{project}]]")

    return links, False


def manual_review_sections_template() -> dict[str, list[dict[str, Any]]]:
    return {
        "unreadable_or_dataless": [],
        "roster_reference_withheld_from_auto_linking": [],
        "existing_target_conflicts": [],
        "ambiguous_person_or_topic_matches": [],
        "missing_local_assets": [],
        "hard_basename_collisions": [],
    }


def expected_migrated_text(source_note: InventoryNote, related_links: list[str]) -> str | None:
    if source_note.read_status != "ok":
        return None
    source_path = Path(source_note.source_path)
    if not source_path.exists():
        return None
    text = read_file_text(source_path)
    frontmatter, body = split_frontmatter(text)
    updated_body = insert_related_section(body, related_links)
    return merge_frontmatter_and_body(frontmatter, updated_body)


def disambiguation_labels(note: InventoryNote) -> list[str]:
    relative = Path(note.relative_path)
    parent_parts = [sanitize_filename_component(part) for part in relative.parts[:-1] if part]
    preferred: list[str] = []
    for width in range(1, min(len(parent_parts), 4) + 1):
        label = " - ".join(parent_parts[-width:])
        if label and label not in preferred:
            preferred.append(label)
    fallback = sanitize_filename_component(relative.as_posix().replace("/", " - ").replace(".md", ""))
    if fallback and fallback not in preferred:
        preferred.append(fallback)
    return preferred


def disambiguate_target_path(
    target_path: Path,
    note: InventoryNote,
    occupied_stems: set[str],
) -> Path:
    base_dir = target_path.parent
    suffix = target_path.suffix or ".md"
    stem = target_path.stem
    for label in disambiguation_labels(note):
        candidate = base_dir / f"{stem} ({label}){suffix}"
        if candidate.stem.casefold() not in occupied_stems:
            return candidate
    counter = 2
    while True:
        candidate = base_dir / f"{stem} ({counter}){suffix}"
        if candidate.stem.casefold() not in occupied_stems:
            return candidate
        counter += 1


def resolve_target_paths(
    plan_notes: list[PlanNote],
    notes_by_source: dict[str, InventoryNote],
    target_root: Path,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    existing_files = target_existing_markdown_files(target_root)
    occupied_stems = {path.stem.casefold() for path in existing_files}
    existing_by_stem = {path.stem.casefold(): path for path in existing_files}
    resolved_collisions: list[dict[str, Any]] = []
    existing_conflicts: list[dict[str, Any]] = []

    for item in plan_notes:
        if not item.target_path:
            continue

        inventory_note = notes_by_source[item.source_path]
        candidate = Path(item.target_path)
        expected_text = expected_migrated_text(inventory_note, item.related_links)

        if candidate.exists() and expected_text is not None:
            try:
                current_text = candidate.read_text(encoding="utf-8")
            except OSError:
                current_text = None
            if current_text == expected_text:
                item.already_migrated = True
                item.manual_review_reasons = [
                    reason for reason in item.manual_review_reasons if reason != "target file already exists"
                ]
                item.existing_target_conflict = False
                item.basename_stem = candidate.stem
                occupied_stems.add(candidate.stem.casefold())
                continue

        stem_key = candidate.stem.casefold()
        occupied_by_existing = stem_key in existing_by_stem and not item.already_migrated
        occupied_by_plan = any(
            other is not item and other.target_path and Path(other.target_path).stem.casefold() == stem_key
            for other in plan_notes
            if other.source_path < item.source_path
        )

        if occupied_by_existing or occupied_by_plan:
            original = candidate
            candidate = disambiguate_target_path(candidate, inventory_note, occupied_stems)
            resolved_collisions.append(
                {
                    "source_path": item.source_path,
                    "original_target_path": str(original),
                    "resolved_target_path": str(candidate),
                }
            )

        if candidate.exists() and not item.already_migrated:
            item.existing_target_conflict = True
            if "target file already exists" not in item.manual_review_reasons:
                item.manual_review_reasons.append("target file already exists")
            existing_conflicts.append(
                {
                    "source_path": item.source_path,
                    "target_path": str(candidate),
                    "reason": "target file already exists",
                }
            )
        else:
            item.existing_target_conflict = False
            item.manual_review_reasons = [
                reason for reason in item.manual_review_reasons if reason != "target file already exists"
            ]

        item.target_path = str(candidate)
        item.basename_stem = candidate.stem
        occupied_stems.add(candidate.stem.casefold())

    return resolved_collisions, existing_conflicts


def compute_migration_plan(
    notes: list[InventoryNote],
    people_config: PeopleConfig,
    target_root: Path,
) -> dict[str, Any]:
    strong_projects = strong_project_topics(notes, people_config, target_root=target_root)
    plan_notes: list[PlanNote] = []
    manual_sections = manual_review_sections_template()
    notes_by_source = {note.source_path: note for note in notes}

    for note in notes:
        classification, reasons = choose_classification(note, strong_projects)
        target_path = proposed_target_path(note, classification, target_root)
        related_links, intentional_reference_people_links = related_links_for_note(
            note,
            classification,
            strong_projects,
        )
        missing_assets = [ref["path"] for ref in note.local_asset_refs if not ref.get("exists", False)]
        manual_review_reasons: list[str] = []

        if note.read_status != "ok":
            manual_sections["unreadable_or_dataless"].append(
                {"source_path": note.source_path, "reason": note.read_error or "unreadable"}
            )
            manual_review_reasons.append("source unreadable")

        if note.roster_signals.get("is_roster_reference"):
            manual_sections["roster_reference_withheld_from_auto_linking"].append(
                {"source_path": note.source_path, "reason": "reference roster notes do not auto-link people by default"}
            )

        if missing_assets:
            manual_sections["missing_local_assets"].append(
                {"source_path": note.source_path, "missing_assets": missing_assets}
            )
            manual_review_reasons.append("missing local assets")

        plan_notes.append(
            PlanNote(
                source_path=note.source_path,
                relative_path=note.relative_path,
                classification=classification,
                target_path=str(target_path) if target_path is not None else None,
                title=note.title_guess or note.stem,
                reasons=reasons,
                related_links=related_links,
                intentional_reference_people_links=intentional_reference_people_links,
                manual_review_reasons=list(dict.fromkeys(manual_review_reasons)),
                missing_assets=missing_assets,
                existing_target_conflict=False,
                basename_stem=target_path.stem if target_path is not None else None,
            )
        )

    canonical_people = canonical_person_file_specs(target_root, people_config)
    canonical_projects = canonical_project_file_specs(target_root, strong_projects)
    resolved_collisions, existing_conflicts = resolve_target_paths(plan_notes, notes_by_source, target_root)
    for conflict in existing_conflicts:
        manual_sections["existing_target_conflicts"].append(conflict)
    for resolved in resolved_collisions:
        manual_sections["hard_basename_collisions"].append(resolved)

    existing_stems = {path.stem.casefold(): str(path) for path in target_existing_markdown_files(target_root)}
    collisions = detect_basename_collisions(plan_notes, canonical_people, existing_stems)

    summary = {
        "notes_total": len(plan_notes),
        "manual_review_total": sum(1 for item in plan_notes if item.manual_review_reasons),
        "meeting_notes": sum(1 for item in plan_notes if item.classification == "meeting"),
        "weekly_notes": sum(1 for item in plan_notes if item.classification == "weekly"),
        "reference_notes": sum(1 for item in plan_notes if item.classification == "reference"),
        "project_notes": sum(1 for item in plan_notes if item.classification == "project"),
        "person_notes": sum(1 for item in plan_notes if item.classification == "person"),
        "inbox_import_notes": sum(1 for item in plan_notes if item.classification == "inbox-import"),
        "canonical_people_to_create": sum(1 for item in canonical_people if not item["exists"]),
        "canonical_projects_to_create": len(canonical_projects),
        "collision_groups": len(resolved_collisions),
    }

    return {
        "generated_at": timestamp_utc(),
        "target_root": str(target_root),
        "summary": summary,
        "canonical_people": canonical_people,
        "canonical_projects": canonical_projects,
        "plan_notes": [item.to_dict() for item in plan_notes],
        "manual_review_sections": manual_sections,
        "basename_collisions": collisions,
    }


def detect_basename_collisions(
    plan_notes: list[PlanNote],
    canonical_people: list[dict[str, Any]],
    existing_stems: dict[str, str],
) -> list[dict[str, Any]]:
    buckets: dict[str, list[dict[str, Any]]] = {}
    canonical_paths = {item["path"] for item in canonical_people}

    for item in plan_notes:
        if item.already_migrated or not item.target_path or not item.basename_stem:
            continue
        stem_key = item.basename_stem.casefold()
        buckets.setdefault(stem_key, []).append(
            {
                "kind": "planned_note",
                "source_path": item.source_path,
                "target_path": item.target_path,
                "classification": item.classification,
            }
        )

    for person in canonical_people:
        path = Path(person["path"])
        stem_key = path.stem.casefold()
        buckets.setdefault(stem_key, []).append(
            {
                "kind": "canonical_person",
                "source_path": None,
                "target_path": person["path"],
                "name": person["name"],
            }
        )

    for stem_key, existing_path in existing_stems.items():
        if existing_path in canonical_paths:
            continue
        buckets.setdefault(stem_key, []).append(
            {
                "kind": "existing_target",
                "source_path": None,
                "target_path": existing_path,
            }
        )

    collisions: list[dict[str, Any]] = []
    for stem_key, items in sorted(buckets.items()):
        if len(items) < 2:
            continue
        collisions.append({"stem": stem_key, "items": items})
    return collisions


def render_dry_run_markdown(plan: dict[str, Any]) -> str:
    lines = ["# Notes Migration Dry Run", "", "## Summary", ""]
    for key, value in plan["summary"].items():
        lines.append(f"- {key}: {value}")

    lines.extend(["", "## Canonical Person Files To Create", ""])
    people_to_create = [item for item in plan["canonical_people"] if not item["exists"]]
    if people_to_create:
        for item in people_to_create:
            lines.append(f"- {item['name']} -> {item['path']}")
    else:
        lines.append("- none")

    lines.extend(["", "## Canonical Project Notes Proposed", ""])
    if plan["canonical_projects"]:
        for item in plan["canonical_projects"]:
            lines.append(f"- {item['name']} -> {item['path']} ({item['count']} supporting notes)")
    else:
        lines.append("- none")

    lines.extend(["", "## Proposed Note Destinations", ""])
    for item in plan["plan_notes"]:
        target = item["target_path"] or "MANUAL REVIEW"
        lines.append(f"- {item['source_path']} -> {target} [{item['classification']}]")

    lines.extend(["", "## Proposed Wiki Link Injection", ""])
    injections = [item for item in plan["plan_notes"] if item["related_links"]]
    if injections:
        for item in injections:
            lines.append(f"- {item['source_path']}: {', '.join(item['related_links'])}")
    else:
        lines.append("- none")

    lines.extend(["", "## Roster/Reference Notes Intentionally Receiving People Links", ""])
    intentional = [
        item for item in plan["plan_notes"] if item["intentional_reference_people_links"] and item["related_links"]
    ]
    if intentional:
        for item in intentional:
            lines.append(f"- {item['source_path']}: {', '.join(item['related_links'])}")
    else:
        lines.append("- none")

    lines.extend(["", "## Manual Review Items", ""])
    manual_items = [item for item in plan["plan_notes"] if item["manual_review_reasons"]]
    if manual_items:
        for item in manual_items:
            lines.append(f"- {item['source_path']}: {'; '.join(item['manual_review_reasons'])}")
    else:
        lines.append("- none")

    lines.extend(["", "## Basename Collision Blockers", ""])
    if plan["manual_review_sections"]["hard_basename_collisions"]:
        for group in plan["manual_review_sections"]["hard_basename_collisions"]:
            lines.append(
                f"- {group['source_path']}: {group['original_target_path']} -> {group['resolved_target_path']}"
            )
    else:
        lines.append("- none")

    lines.append("")
    return "\n".join(lines)


def render_manual_review_markdown(plan: dict[str, Any]) -> str:
    sections = plan["manual_review_sections"]
    lines = ["# Manual Review", ""]
    section_titles = {
        "unreadable_or_dataless": "Unreadable / Dataless Source Files",
        "roster_reference_withheld_from_auto_linking": "Roster / Reference Notes Withheld From Auto-Linking",
        "existing_target_conflicts": "Existing Target Conflicts",
        "ambiguous_person_or_topic_matches": "Ambiguous Person / Topic Matches",
        "missing_local_assets": "Missing Local Assets",
        "hard_basename_collisions": "Hard Basename Collisions",
    }
    for key, title in section_titles.items():
        lines.extend([f"## {title}", ""])
        items = sections.get(key, [])
        if not items:
            lines.append("- none")
            lines.append("")
            continue
        if key == "hard_basename_collisions":
            for group in items:
                lines.append(
                    f"- {group['source_path']}: {group['original_target_path']} -> {group['resolved_target_path']}"
                )
            lines.append("")
            continue
        for item in items:
            if "missing_assets" in item:
                lines.append(f"- {item['source_path']}: {', '.join(item['missing_assets'])}")
            elif "target_path" in item:
                lines.append(f"- {item['source_path']}: {item['reason']} -> {item['target_path']}")
            else:
                lines.append(f"- {item['source_path']}: {item['reason']}")
        lines.append("")
    return "\n".join(lines)


def render_basename_collisions_markdown(plan: dict[str, Any]) -> str:
    lines = ["# Basename Collision Resolutions", ""]
    items = plan["manual_review_sections"]["hard_basename_collisions"]
    if not items:
        lines.extend(["- none", ""])
        return "\n".join(lines)

    for item in items:
        lines.append(f"- {item['source_path']}")
        lines.append(f"  original: {item['original_target_path']}")
        lines.append(f"  resolved: {item['resolved_target_path']}")
        lines.append("")
    return "\n".join(lines)


def create_person_note_content(name: str) -> str:
    return PERSON_NOTE_TEMPLATE.format(name=name)


def create_project_note_content(name: str) -> str:
    return PROJECT_NOTE_TEMPLATE.format(name=name)


def insert_related_section(body: str, related_links: list[str]) -> str:
    if not related_links:
        return body
    if "## Related" in body:
        return body

    related_block = "## Related\n\n" + "\n".join(f"- {link}" for link in related_links) + "\n\n"
    lines = body.splitlines(keepends=True)
    insert_index = 0
    if lines and lines[0].startswith("# "):
        insert_index = 1
        while insert_index < len(lines) and lines[insert_index].strip() == "":
            insert_index += 1
    return "".join(lines[:insert_index] + [related_block] + lines[insert_index:])


def merge_frontmatter_and_body(frontmatter: str, body: str) -> str:
    if frontmatter:
        if not frontmatter.endswith("\n"):
            frontmatter += "\n"
        return frontmatter + body.lstrip("\n")
    return body


def apply_migration_plan(
    plan: dict[str, Any],
    inventory_notes_by_source: dict[str, InventoryNote],
    target_root: Path,
    people_config: PeopleConfig,
    *,
    allow_basename_collisions: bool = False,
) -> dict[str, Any]:
    collisions = plan.get("basename_collisions", [])
    if collisions and not allow_basename_collisions:
        raise RuntimeError("Unresolved basename collisions exist. Re-run with explicit override only if reviewed.")

    created_people: list[str] = []
    created_projects: list[str] = []
    written_notes: list[str] = []
    skipped_notes: list[dict[str, Any]] = []

    for spec in plan["canonical_people"]:
        path = Path(spec["path"])
        if path.exists():
            continue
        ensure_parent_dir(path)
        path.write_text(create_person_note_content(spec["name"]), encoding="utf-8")
        created_people.append(str(path))

    for spec in plan.get("canonical_projects", []):
        path = Path(spec["path"])
        if path.exists():
            continue
        ensure_parent_dir(path)
        path.write_text(create_project_note_content(spec["name"]), encoding="utf-8")
        created_projects.append(str(path))

    for plan_note in plan["plan_notes"]:
        if plan_note.get("already_migrated"):
            continue
        if plan_note["manual_review_reasons"]:
            skipped_notes.append({"source_path": plan_note["source_path"], "reason": "; ".join(plan_note["manual_review_reasons"])})
            continue
        target_path = plan_note["target_path"]
        if not target_path:
            skipped_notes.append({"source_path": plan_note["source_path"], "reason": "no target path"})
            continue
        source_note = inventory_notes_by_source[plan_note["source_path"]]
        source_path = Path(source_note.source_path)
        text = read_file_text(source_path)
        frontmatter, body = split_frontmatter(text)
        updated_body = insert_related_section(body, list(plan_note["related_links"]))
        final_text = merge_frontmatter_and_body(frontmatter, updated_body)
        target = Path(target_path)
        ensure_parent_dir(target)
        target.write_text(final_text, encoding="utf-8")
        written_notes.append(str(target))

        for asset in source_note.local_asset_refs:
            if not asset.get("exists", False):
                continue
            relative_asset = Path(asset["path"])
            destination = target.parent / relative_asset
            ensure_parent_dir(destination)
            destination.write_bytes(Path(asset["resolved_path"]).read_bytes())

    return {
        "created_people": created_people,
        "created_projects": created_projects,
        "written_notes": written_notes,
        "skipped_notes": skipped_notes,
    }
