#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import time
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error, parse, request

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore[assignment]


API_BASE_URL = "https://public-api.granola.ai/v1"
DEFAULT_OUTPUT_DIR = Path("reports/granola_notes_md")
DEFAULT_TIMEZONE = "Europe/Berlin"
DEFAULT_PAGE_SIZE = 30
DEFAULT_SLEEP_SECONDS = 0.25
MAX_RETRIES = 5


class GranolaExportError(RuntimeError):
    pass


@dataclass(frozen=True)
class ExportedNote:
    note_id: str
    filename: str
    title: str | None
    created_at: str
    updated_at: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export Granola notes to Markdown files with YYYYMMDD-prefixed filenames."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Directory for exported Markdown files. Default: {DEFAULT_OUTPUT_DIR}",
    )
    parser.add_argument(
        "--timezone",
        default=DEFAULT_TIMEZONE,
        help=f"IANA timezone used for the YYYYMMDD filename prefix. Default: {DEFAULT_TIMEZONE}",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=DEFAULT_PAGE_SIZE,
        help=f"Granola API page size (1-30). Default: {DEFAULT_PAGE_SIZE}",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=DEFAULT_SLEEP_SECONDS,
        help=f"Delay between note detail requests. Default: {DEFAULT_SLEEP_SECONDS}",
    )
    parser.add_argument(
        "--no-transcript",
        action="store_true",
        help="Do not include transcripts in the exported Markdown files.",
    )
    parser.add_argument(
        "--api-key-env",
        default="GRANOLA_API_KEY",
        help="Environment variable containing the Granola Personal API key.",
    )
    return parser.parse_args()


def require_api_key(env_var: str) -> str:
    api_key = os.getenv(env_var, "").strip()
    if api_key:
        return api_key

    raise GranolaExportError(
        "Missing Granola API key.\n"
        f"Set {env_var} and rerun, for example:\n"
        f"  export {env_var}=grn_your_personal_api_key\n"
        "Create the key in Granola via Settings -> API -> Create new key -> Personal API key."
    )


def require_timezone(timezone_name: str):
    if ZoneInfo is None:
        raise GranolaExportError("Python zoneinfo support is unavailable in this environment.")
    try:
        return ZoneInfo(timezone_name)
    except Exception as exc:  # pragma: no cover - invalid timezone only
        raise GranolaExportError(f"Invalid timezone: {timezone_name}") from exc


def parse_timestamp(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    normalized = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", normalized)
    dt = datetime.fromisoformat(normalized)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def api_request(api_key: str, path: str, query: dict[str, Any] | None = None) -> dict[str, Any]:
    url = f"{API_BASE_URL}{path}"
    if query:
        encoded = parse.urlencode({key: value for key, value in query.items() if value is not None})
        if encoded:
            url = f"{url}?{encoded}"

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "User-Agent": "Quartz-Granola-Export/1.0",
    }

    for attempt in range(1, MAX_RETRIES + 1):
        req = request.Request(url, headers=headers, method="GET")
        try:
            with request.urlopen(req, timeout=60) as response:
                return json.load(response)
        except error.HTTPError as exc:
            retry_after_header = exc.headers.get("Retry-After")
            retry_after = float(retry_after_header) if retry_after_header else min(attempt, 5)
            body = exc.read().decode("utf-8", errors="replace")

            if exc.code in {429, 500, 502, 503, 504} and attempt < MAX_RETRIES:
                time.sleep(retry_after)
                continue

            raise GranolaExportError(
                f"Granola API request failed with HTTP {exc.code} for {url}\n{body}"
            ) from exc
        except (error.URLError, socket.timeout, TimeoutError) as exc:
            if attempt < MAX_RETRIES:
                time.sleep(min(attempt, 5))
                continue
            raise GranolaExportError(f"Granola API request failed for {url}: {exc}") from exc

    raise GranolaExportError(f"Granola API request failed after {MAX_RETRIES} attempts: {url}")


def list_all_notes(api_key: str, page_size: int) -> list[dict[str, Any]]:
    if not 1 <= page_size <= 30:
        raise GranolaExportError("--page-size must be between 1 and 30.")

    all_notes: list[dict[str, Any]] = []
    cursor: str | None = None

    while True:
        payload = api_request(api_key, "/notes", {"page_size": page_size, "cursor": cursor})
        notes = payload.get("notes", [])
        if not isinstance(notes, list):
            raise GranolaExportError("Unexpected Granola API response: 'notes' is not a list.")

        all_notes.extend(notes)
        has_more = bool(payload.get("hasMore"))
        cursor = payload.get("cursor")
        if not has_more:
            break

    return all_notes


def get_note_detail(api_key: str, note_id: str, include_transcript: bool) -> dict[str, Any]:
    query: dict[str, Any] = {}
    if include_transcript:
        query["include"] = "transcript"
    return api_request(api_key, f"/notes/{note_id}", query)


def strip_leading_date_prefix(title: str) -> str:
    patterns = (
        r"^\d{2}\.\d{2}\.\d{4}\s*[-_:]\s*",
        r"^\d{4}-\d{2}-\d{2}\s*[-_:]\s*",
        r"^\d{2}\.\d{2}\.\d{4}\s+",
        r"^\d{4}-\d{2}-\d{2}\s+",
    )
    result = title.strip()
    for pattern in patterns:
        result = re.sub(pattern, "", result)
    return result.strip() or title.strip()


def sanitize_title_for_filename(title: str | None, fallback: str) -> str:
    candidate = strip_leading_date_prefix(title or "").strip()
    if not candidate:
        candidate = fallback

    normalized = unicodedata.normalize("NFKD", candidate)
    ascii_text = normalized.encode("ascii", "ignore").decode("ascii")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", ascii_text)
    safe = re.sub(r"_+", "_", safe).strip("._")
    return safe or fallback


def pick_note_datetime(note: dict[str, Any]) -> datetime:
    calendar_event = note.get("calendar_event") or {}
    scheduled_start = calendar_event.get("scheduled_start_time")
    if isinstance(scheduled_start, str) and scheduled_start:
        return parse_timestamp(scheduled_start)
    created_at = note.get("created_at")
    if not isinstance(created_at, str) or not created_at:
        raise GranolaExportError(f"Note {note.get('id')} is missing created_at.")
    return parse_timestamp(created_at)


def build_markdown(note: dict[str, Any], include_transcript: bool, tz) -> str:
    title = note.get("title") or "Untitled"
    owner = note.get("owner") or {}
    attendees = note.get("attendees") or []
    folders = note.get("folder_membership") or []
    calendar_event = note.get("calendar_event") or {}

    note_dt = pick_note_datetime(note).astimezone(tz)
    created_at = parse_timestamp(note["created_at"]).astimezone(tz)
    updated_at = parse_timestamp(note["updated_at"]).astimezone(tz)

    lines: list[str] = [
        f"# {title}",
        "",
        f"- Note ID: {note['id']}",
        f"- Created: {created_at.isoformat()}",
        f"- Updated: {updated_at.isoformat()}",
        f"- Note Date: {note_dt.date().isoformat()}",
    ]

    owner_name = owner.get("name") or ""
    owner_email = owner.get("email") or ""
    if owner_name or owner_email:
        owner_display = owner_name
        if owner_email:
            owner_display = f"{owner_name} <{owner_email}>" if owner_name else owner_email
        lines.append(f"- Owner: {owner_display}")

    if calendar_event:
        event_title = calendar_event.get("event_title")
        if event_title:
            lines.append(f"- Calendar Event: {event_title}")
        scheduled_start = calendar_event.get("scheduled_start_time")
        scheduled_end = calendar_event.get("scheduled_end_time")
        if scheduled_start:
            start_display = parse_timestamp(scheduled_start).astimezone(tz).isoformat()
            if scheduled_end:
                end_display = parse_timestamp(scheduled_end).astimezone(tz).isoformat()
                lines.append(f"- Scheduled: {start_display} -> {end_display}")
            else:
                lines.append(f"- Scheduled: {start_display}")

    if attendees:
        attendee_values = []
        for attendee in attendees:
            attendee_name = attendee.get("name") or ""
            attendee_email = attendee.get("email") or ""
            if attendee_name and attendee_email:
                attendee_values.append(f"{attendee_name} <{attendee_email}>")
            elif attendee_name:
                attendee_values.append(attendee_name)
            elif attendee_email:
                attendee_values.append(attendee_email)
        if attendee_values:
            lines.append(f"- Attendees: {', '.join(attendee_values)}")

    if folders:
        folder_names = [folder.get("name") for folder in folders if folder.get("name")]
        if folder_names:
            lines.append(f"- Folders: {', '.join(folder_names)}")

    lines.append("")

    summary_markdown = note.get("summary_markdown")
    summary_text = note.get("summary_text")
    if isinstance(summary_markdown, str) and summary_markdown.strip():
        lines.extend([summary_markdown.strip(), ""])
    elif isinstance(summary_text, str) and summary_text.strip():
        lines.extend(["## Summary", "", summary_text.strip(), ""])
    else:
        lines.extend(["## Summary", "", "_No summary returned by Granola._", ""])

    if include_transcript:
        transcript = note.get("transcript") or []
        lines.extend(["## Transcript", ""])
        if transcript:
            for entry in transcript:
                speaker = entry.get("speaker") or {}
                source = speaker.get("source") or "unknown"
                diarization_label = speaker.get("diarization_label")
                speaker_label = str(diarization_label or source)

                start_time = entry.get("start_time")
                end_time = entry.get("end_time")
                time_bits = []
                if start_time:
                    time_bits.append(parse_timestamp(start_time).astimezone(tz).isoformat())
                if end_time:
                    time_bits.append(parse_timestamp(end_time).astimezone(tz).isoformat())
                when = f" ({' -> '.join(time_bits)})" if time_bits else ""

                lines.append(f"### {speaker_label}{when}")
                lines.append("")
                lines.append((entry.get("text") or "").strip())
                lines.append("")
        else:
            lines.append("_No transcript returned by Granola._")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def choose_filename(note: dict[str, Any], tz, used_names: set[str]) -> str:
    note_dt = pick_note_datetime(note).astimezone(tz)
    date_prefix = note_dt.strftime("%Y%m%d")
    base_title = sanitize_title_for_filename(note.get("title"), note["id"])
    filename = f"{date_prefix}_{base_title}.md"

    if filename not in used_names:
        used_names.add(filename)
        return filename

    counter = 2
    while True:
        candidate = f"{date_prefix}_{base_title}_{counter}.md"
        if candidate not in used_names:
            used_names.add(candidate)
            return candidate
        counter += 1


def write_manifest(output_dir: Path, exported: list[ExportedNote], include_transcript: bool) -> Path:
    manifest_path = output_dir / "export_manifest.json"
    manifest_payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "note_count": len(exported),
        "includes_transcript": include_transcript,
        "notes": [export.__dict__ for export in exported],
    }
    manifest_path.write_text(json.dumps(manifest_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest_path


def write_export(
    note: dict[str, Any],
    output_dir: Path,
    include_transcript: bool,
    tz,
    used_names: set[str],
) -> ExportedNote:
    filename = choose_filename(note, tz, used_names)
    markdown = build_markdown(note, include_transcript=include_transcript, tz=tz)
    target_path = output_dir / filename
    target_path.write_text(markdown, encoding="utf-8")
    return ExportedNote(
        note_id=note["id"],
        filename=filename,
        title=note.get("title"),
        created_at=note["created_at"],
        updated_at=note["updated_at"],
    )


def main() -> int:
    args = parse_args()

    try:
        api_key = require_api_key(args.api_key_env)
        tz = require_timezone(args.timezone)
        note_summaries = list_all_notes(api_key, args.page_size)
        include_transcript = not args.no_transcript
        used_names: set[str] = set()
        exported: list[ExportedNote] = []

        args.output_dir.mkdir(parents=True, exist_ok=True)
        print(f"Found {len(note_summaries)} notes via Granola API.", flush=True)

        for index, summary in enumerate(note_summaries, start=1):
            note_id = summary.get("id")
            if not isinstance(note_id, str) or not note_id:
                raise GranolaExportError(f"Unexpected note summary without an id: {summary}")
            note = get_note_detail(api_key, note_id, include_transcript)
            exported.append(
                write_export(
                    note,
                    output_dir=args.output_dir,
                    include_transcript=include_transcript,
                    tz=tz,
                    used_names=used_names,
                )
            )
            if index % 25 == 0 or index == len(note_summaries):
                print(f"Fetched and wrote {index}/{len(note_summaries)} notes.", flush=True)
            if args.sleep_seconds > 0:
                time.sleep(args.sleep_seconds)

        manifest_path = write_manifest(args.output_dir, exported, include_transcript)
        print(f"Wrote {len(exported)} Markdown files to {args.output_dir}", flush=True)
        print(f"Wrote manifest to {manifest_path}", flush=True)
        return 0
    except GranolaExportError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
