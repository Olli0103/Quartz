from __future__ import annotations

import json
import logging
import os
import re
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional



LOGGER = logging.getLogger("todoist_reorg")
REST_API_BASE = "https://api.todoist.com/rest/v1"
SYNC_API_BASE = "https://api.todoist.com/sync/v9"


class MissingTodoistTokenError(RuntimeError):
    """Raised when TODOIST_API_TOKEN is unavailable."""


class TodoistApiError(RuntimeError):
    """Raised when a Todoist API request fails."""


@dataclass
class TaskAction:
    task_id: str
    current_title: str
    current_project: str
    current_section: str
    target_project: str
    target_section: str
    new_title: str
    labels_to_add: list[str] = field(default_factory=list)
    labels_to_remove: list[str] = field(default_factory=list)
    reason: str = ""

    @property
    def action_kinds(self) -> list[str]:
        kinds: list[str] = []
        if self.current_title != self.new_title:
            kinds.append("rename")
        if self.current_project != self.target_project or self.current_section != self.target_section:
            kinds.append("move")
        if self.labels_to_add or self.labels_to_remove:
            kinds.append("labels")
        return kinds or ["noop"]


@dataclass
class ManualReviewItem:
    task_id: str
    title: str
    project: str
    section: str
    reason: str


@dataclass
class IgnoredItem:
    task_id: str
    title: str
    project: str
    reason: str


@dataclass
class DryRunPlan:
    summary: dict[str, Any]
    projects_to_create: list[dict[str, str]]
    sections_to_create: list[dict[str, str]]
    labels_to_create: list[str]
    task_actions: list[TaskAction]
    manual_review: list[ManualReviewItem]
    ignored_items: list[IgnoredItem]
    projects_to_archive: list[dict[str, str]]
    warnings: list[str]


def configure_logging(verbose: bool = False) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def instruction_for_missing_token(script_name: str) -> str:
    return (
        "TODOIST_API_TOKEN is not set.\n"
        "Supply access before live export or apply:\n"
        "  export TODOIST_API_TOKEN='your_todoist_personal_token'\n"
        f"Then rerun:\n  python3 {script_name}"
    )


def require_token(script_name: str) -> str:
    token = os.environ.get("TODOIST_API_TOKEN", "").strip()
    if not token:
        raise MissingTodoistTokenError(instruction_for_missing_token(script_name))
    return token


def ensure_parent_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def load_yaml_file(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a YAML object at the top level.")
    return data


def load_json_file(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object at the top level.")
    return data


def write_json_file(path: Path, payload: dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False, sort_keys=False)
        handle.write("\n")


def write_text_file(path: Path, content: str) -> None:
    ensure_parent_dir(path)
    with path.open("w", encoding="utf-8") as handle:
        handle.write(content)


def normalize_task(task: dict[str, Any]) -> dict[str, Any]:
    due = task.get("due")
    if isinstance(due, dict):
        due_value = {
            "date": due.get("date"),
            "datetime": due.get("datetime"),
            "string": due.get("string"),
            "timezone": due.get("timezone"),
            "recurring": due.get("recurring"),
        }
    else:
        due_value = None

    return {
        "id": str(task["id"]),
        "content": task.get("content", ""),
        "description": task.get("description", ""),
        "project_id": str(task.get("project_id", "")),
        "section_id": str(task.get("section_id", "")) if task.get("section_id") else "",
        "parent_id": str(task.get("parent_id", "")) if task.get("parent_id") else "",
        "labels": list(task.get("labels", [])),
        "priority": task.get("priority"),
        "responsible_uid": str(task.get("responsible_uid", "")) if task.get("responsible_uid") else "",
        "assigned_by_uid": str(task.get("assigned_by_uid", "")) if task.get("assigned_by_uid") else "",
        "url": task.get("url", ""),
        "due": due_value,
        "deadline": task.get("deadline"),
    }


def normalize_project(project: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(project["id"]),
        "name": project.get("name", ""),
        "parent_id": str(project.get("parent_id", "")) if project.get("parent_id") else "",
        "color": project.get("color", ""),
        "child_order": project.get("child_order", project.get("order")),
        "is_shared": bool(project.get("shared", project.get("is_shared", False))),
        "is_favorite": bool(project.get("favorite", project.get("is_favorite", False))),
        "inbox_project": bool(project.get("inbox_project", False)),
        "view_style": project.get("view_style", ""),
        "url": project.get("url", ""),
    }


def normalize_section(section: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(section["id"]),
        "project_id": str(section["project_id"]),
        "name": section.get("name", ""),
        "order": section.get("order", section.get("section_order")),
        "url": section.get("url", ""),
    }


def normalize_label(label: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(label["id"]),
        "name": label.get("name", ""),
        "color": label.get("color", ""),
        "order": label.get("order"),
        "favorite": bool(label.get("favorite", label.get("is_favorite", False))),
    }


class TodoistClient:
    def __init__(self, token: str) -> None:
        import requests

        self.token = token
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {token}"})

    def _request(
        self,
        method: str,
        url: str,
        *,
        params: Optional[dict[str, Any]] = None,
        json_body: Optional[dict[str, Any]] = None,
        data: Optional[dict[str, Any]] = None,
        expected_statuses: Iterable[int] = (200,),
        stream: bool = False,
    ) -> Any:
        headers: dict[str, str] = {}
        if json_body is not None:
            headers["Content-Type"] = "application/json"
            headers["X-Request-Id"] = str(uuid.uuid4())

        response = self.session.request(
            method=method,
            url=url,
            params=params,
            json=json_body,
            data=data,
            headers=headers,
            timeout=60,
            stream=stream,
        )
        if response.status_code not in set(expected_statuses):
            snippet = response.text[:500].strip()
            raise TodoistApiError(
                f"{method} {url} failed with HTTP {response.status_code}: {snippet}"
            )

        if stream:
            return response
        if response.status_code == 204 or not response.content:
            return None
        return response.json()

    def get_projects(self) -> list[dict[str, Any]]:
        return self._request("GET", f"{REST_API_BASE}/projects")

    def get_sections(self) -> list[dict[str, Any]]:
        return self._request("GET", f"{REST_API_BASE}/sections")

    def get_labels(self) -> list[dict[str, Any]]:
        return self._request("GET", f"{REST_API_BASE}/labels")

    def get_tasks(self) -> list[dict[str, Any]]:
        return self._request("GET", f"{REST_API_BASE}/tasks")

    def get_archived_projects(self) -> list[dict[str, Any]]:
        return self._request("GET", f"{SYNC_API_BASE}/projects/get_archived")

    def get_backups(self) -> list[dict[str, Any]]:
        return self._request("GET", f"{SYNC_API_BASE}/backups/get")

    def download_backup(self, url: str, destination: Path) -> None:
        LOGGER.info("Downloading official Todoist backup to %s", destination)
        ensure_parent_dir(destination)
        response = self._request("GET", url, expected_statuses=(200,), stream=True)
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=64 * 1024):
                if chunk:
                    handle.write(chunk)

    def create_project(self, *, name: str, parent_id: Optional[str], color: str = "blue") -> dict[str, Any]:
        payload: dict[str, Any] = {"name": name, "color": color}
        if parent_id:
            payload["parent_id"] = parent_id
        return self._request("POST", f"{REST_API_BASE}/projects", json_body=payload)

    def create_section(self, *, project_id: str, name: str) -> dict[str, Any]:
        payload = {"project_id": project_id, "name": name}
        return self._request("POST", f"{REST_API_BASE}/sections", json_body=payload)

    def create_label(self, *, name: str, color: str = "charcoal") -> dict[str, Any]:
        payload = {"name": name, "color": color}
        return self._request("POST", f"{REST_API_BASE}/labels", json_body=payload)

    def update_task(self, task_id: str, payload: dict[str, Any]) -> None:
        self._request(
            "POST",
            f"{REST_API_BASE}/tasks/{task_id}",
            json_body=payload,
            expected_statuses=(200, 204),
        )

    def sync_commands(self, commands: list[dict[str, Any]]) -> dict[str, Any]:
        return self._request(
            "POST",
            f"{SYNC_API_BASE}/sync",
            data={"commands": json.dumps(commands)},
        )

    def archive_project(self, project_id: str) -> None:
        command = {
            "type": "project_archive",
            "uuid": str(uuid.uuid4()),
            "args": {"id": project_id},
        }
        self.sync_commands([command])


def enrich_inventory(inventory: dict[str, Any]) -> dict[str, Any]:
    projects = inventory.get("projects", [])
    sections = inventory.get("sections", [])
    tasks = inventory.get("tasks", [])

    project_by_id = {project["id"]: project for project in projects}
    task_counts: dict[str, int] = {}
    section_counts: dict[str, int] = {}
    for task in tasks:
        task_counts[task["project_id"]] = task_counts.get(task["project_id"], 0) + 1
    for section in sections:
        section_counts[section["project_id"]] = section_counts.get(section["project_id"], 0) + 1

    summaries: list[dict[str, Any]] = []
    for project in projects:
        path_names = [project["name"]]
        parent_id = project.get("parent_id", "")
        while parent_id:
            parent = project_by_id.get(parent_id)
            if not parent:
                break
            path_names.append(parent["name"])
            parent_id = parent.get("parent_id", "")
        path_names.reverse()
        summaries.append(
            {
                "project_id": project["id"],
                "name": project["name"],
                "path": " / ".join(path_names),
                "task_count": task_counts.get(project["id"], 0),
                "section_count": section_counts.get(project["id"], 0),
                "parent_id": project.get("parent_id", ""),
                "inbox_project": project.get("inbox_project", False),
            }
        )

    inventory["project_summaries"] = summaries
    inventory.setdefault("metadata", {})
    inventory["metadata"]["project_count"] = len(projects)
    inventory["metadata"]["section_count"] = len(sections)
    inventory["metadata"]["task_count"] = len(tasks)
    inventory["metadata"]["archived_project_count"] = len(inventory.get("archived_projects", []))
    return inventory


def build_inventory(
    client: TodoistClient,
    *,
    generated_by: str,
    download_latest_backup: bool,
    backup_dir: Optional[Path],
) -> dict[str, Any]:
    warnings: list[str] = []
    backups: list[dict[str, Any]] = []
    archived_projects: list[dict[str, Any]] = []

    projects = [normalize_project(item) for item in client.get_projects()]
    sections = [normalize_section(item) for item in client.get_sections()]
    labels = [normalize_label(item) for item in client.get_labels()]
    tasks = [normalize_task(item) for item in client.get_tasks()]

    try:
        archived_projects = [normalize_project(item) for item in client.get_archived_projects()]
    except TodoistApiError as error:
        warnings.append(f"Could not list archived projects: {error}")

    try:
        backups = client.get_backups()
    except TodoistApiError as error:
        warnings.append(f"Could not list official backups: {error}")

    inventory = enrich_inventory(
        {
            "metadata": {
                "generated_at": utc_timestamp(),
                "generated_by": generated_by,
                "warnings": warnings,
            },
            "projects": projects,
            "sections": sections,
            "labels": labels,
            "tasks": tasks,
            "archived_projects": archived_projects,
            "backups": backups,
        }
    )

    if download_latest_backup and backups and backup_dir:
        latest = backups[0]
        backup_url = latest.get("url", "")
        if backup_url:
            version = re.sub(r"[^A-Za-z0-9._-]+", "-", latest.get("version", "latest"))
            backup_name = f"todoist-official-backup-{version}.zip"
            client.download_backup(backup_url, backup_dir / backup_name)

    return inventory


def save_inventory_snapshot(
    inventory: dict[str, Any],
    *,
    output_path: Path,
    backup_dir: Optional[Path],
) -> Path:
    write_json_file(output_path, inventory)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    snapshot_dir = backup_dir if backup_dir else output_path.parent
    snapshot_path = snapshot_dir / f"todoist-inventory-{timestamp}.json"
    write_json_file(snapshot_path, inventory)
    return snapshot_path


def build_indexes(inventory: dict[str, Any]) -> dict[str, Any]:
    projects = inventory.get("projects", [])
    sections = inventory.get("sections", [])
    tasks = inventory.get("tasks", [])
    labels = inventory.get("labels", [])

    projects_by_id = {item["id"]: item for item in projects}
    sections_by_id = {item["id"]: item for item in sections}
    labels_by_name = {item["name"]: item for item in labels}
    sections_by_project: dict[str, dict[str, dict[str, Any]]] = {}
    tasks_by_project: dict[str, list[dict[str, Any]]] = {}
    children_by_parent: dict[str, list[dict[str, Any]]] = {}

    for section in sections:
        sections_by_project.setdefault(section["project_id"], {})[section["name"]] = section
    for task in tasks:
        tasks_by_project.setdefault(task["project_id"], []).append(task)
    for project in projects:
        children_by_parent.setdefault(project.get("parent_id", ""), []).append(project)

    return {
        "projects_by_id": projects_by_id,
        "sections_by_id": sections_by_id,
        "labels_by_name": labels_by_name,
        "sections_by_project": sections_by_project,
        "tasks_by_project": tasks_by_project,
        "children_by_parent": children_by_parent,
    }


def find_project_by_name(
    projects: list[dict[str, Any]],
    name: str,
    *,
    parent_id: Optional[str] = None,
) -> Optional[dict[str, Any]]:
    for project in projects:
        if project["name"] != name:
            continue
        if parent_id is None or project.get("parent_id", "") == parent_id:
            return project
    return None


def lower_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def starts_with_allowed_verb(title: str, allowed_verbs: set[str]) -> bool:
    cleaned = title.strip()
    if cleaned.startswith("[") and "]" in cleaned:
        cleaned = cleaned.split("]", 1)[1].strip()
    words = cleaned.split()
    if not words:
        return False
    return words[0].lower().strip("[]():-") in allowed_verbs


def matches_regex_patterns(title: str, patterns: list[str]) -> bool:
    return any(re.search(pattern, title) for pattern in patterns)


def pick_route_from_keywords(title: str, keyword_routes: list[dict[str, Any]]) -> tuple[Optional[dict[str, Any]], Optional[str]]:
    title_lower = lower_text(title)
    matches: list[dict[str, Any]] = []
    for route in keyword_routes:
        for keyword in route.get("keywords", []):
            if lower_text(keyword) in title_lower:
                matches.append(route)
                break

    if not matches:
        return None, None

    distinct_targets = {
        (route["target_project"], route.get("target_section", ""))
        for route in matches
    }
    if len(distinct_targets) > 1:
        return None, "Multiple keyword routes matched with different targets."
    return matches[0], None


def classify_task(
    task: dict[str, Any],
    *,
    inventory: dict[str, Any],
    target_cfg: dict[str, Any],
    migration_cfg: dict[str, Any],
    indexes: dict[str, Any],
) -> tuple[Optional[TaskAction], Optional[ManualReviewItem], Optional[IgnoredItem]]:
    projects_by_id = indexes["projects_by_id"]
    sections_by_id = indexes["sections_by_id"]
    project = projects_by_id.get(task["project_id"])
    if project is None:
        return None, ManualReviewItem(task["id"], task["content"], "<missing>", "", "Current project not found in inventory."), None

    section_name = sections_by_id.get(task["section_id"], {}).get("name", "") if task.get("section_id") else ""
    current_project_name = project["name"]
    title = task["content"]

    scope_cfg = migration_cfg["scope"]
    root_name = migration_cfg["settings"]["root_project_name"]
    excluded_projects = set(scope_cfg.get("excluded_projects", []))
    included_projects = set(scope_cfg.get("included_projects", []))
    private_labels = set(scope_cfg.get("private_labels", []))
    allowed_verbs = set(migration_cfg.get("allowed_verbs", []))

    if current_project_name in excluded_projects:
        return None, None, IgnoredItem(task["id"], title, current_project_name, "Project is out of scope.")
    if private_labels.intersection(task.get("labels", [])):
        return None, None, IgnoredItem(task["id"], title, current_project_name, "Task has private or wellbeing labels.")

    project_routes = migration_cfg.get("project_routes", [])
    exact_overrides = {item["match"]: item for item in migration_cfg.get("title_overrides", [])}
    manual_exact = set(migration_cfg.get("manual_review", {}).get("exact_titles", []))
    manual_patterns = migration_cfg.get("manual_review", {}).get("regex_patterns", [])

    in_sap_children = project.get("parent_id", "") == find_project_by_name(inventory["projects"], root_name)["id"] if find_project_by_name(inventory["projects"], root_name) else False
    routed_scope = current_project_name in included_projects or in_sap_children
    project_route: Optional[dict[str, Any]] = None
    for route in project_routes:
        if current_project_name in route.get("source_project_names", []):
            project_route = route
            routed_scope = True
            break

    if not routed_scope:
        return None, None, IgnoredItem(task["id"], title, current_project_name, "Task is outside the SAP migration scope.")

    if title in manual_exact:
        return None, ManualReviewItem(task["id"], title, current_project_name, section_name, "Marked for manual review in config."), None

    override = exact_overrides.get(title)
    keyword_route, keyword_error = pick_route_from_keywords(title, migration_cfg.get("keyword_routes", []))
    if keyword_error and override is None and project_route is None:
        return None, ManualReviewItem(task["id"], title, current_project_name, section_name, keyword_error), None

    target_project_name = ""
    target_section_name = ""
    new_title = title
    target_labels = list(task.get("labels", []))

    if override:
        target_project_name = override["target_project"]
        target_section_name = override.get("target_section", "")
        new_title = override.get("rename_to", title)
        target_labels = list(override.get("target_labels", task.get("labels", [])))
    else:
        route = project_route or keyword_route
        if route is None:
            return None, ManualReviewItem(task["id"], title, current_project_name, section_name, "No confident route found."), None
        target_project_name = route["target_project"]
        target_section_name = route.get("target_section", "")
        extra_labels = route.get("target_labels", [])
        if extra_labels:
            target_labels = list(extra_labels)

    if not starts_with_allowed_verb(new_title, allowed_verbs):
        if matches_regex_patterns(title, manual_patterns):
            reason = "Title looks ambiguous or note-like and does not start with an allowed verb."
        else:
            reason = "Task title does not start with an allowed verb and no safe rewrite is configured."
        return None, ManualReviewItem(task["id"], title, current_project_name, section_name, reason), None

    root_project = find_project_by_name(inventory["projects"], root_name)
    if root_project is None:
        return None, ManualReviewItem(task["id"], title, current_project_name, section_name, "Root SAP project is missing from inventory."), None

    target_project = find_project_by_name(
        inventory["projects"],
        target_project_name,
        parent_id=root_project["id"],
    )
    if target_project is None:
        return None, ManualReviewItem(task["id"], title, current_project_name, section_name, f"Target project '{target_project_name}' is missing."), None

    if target_project_name == "Waiting" and "@waiting" not in target_labels:
        target_labels = target_labels + ["@waiting"]

    legacy_labels = set(migration_cfg.get("legacy_labels_to_replace", []))
    target_labels = [label for label in target_labels if label not in legacy_labels]
    target_labels = sorted(dict.fromkeys(target_labels))
    current_labels = list(task.get("labels", []))
    labels_to_add = [label for label in target_labels if label not in current_labels]
    labels_to_remove = [label for label in current_labels if label in legacy_labels or label not in target_labels]

    action = TaskAction(
        task_id=task["id"],
        current_title=title,
        current_project=current_project_name,
        current_section=section_name,
        target_project=target_project_name,
        target_section=target_section_name,
        new_title=new_title,
        labels_to_add=labels_to_add,
        labels_to_remove=labels_to_remove,
        reason="Configured exact override." if override else "Matched configured route.",
    )

    if (
        action.current_title == action.new_title
        and action.current_project == action.target_project
        and action.current_section == action.target_section
        and not action.labels_to_add
        and not action.labels_to_remove
    ):
        return None, None, None
    return action, None, None


def compute_dry_run_plan(
    inventory: dict[str, Any],
    target_cfg: dict[str, Any],
    migration_cfg: dict[str, Any],
) -> DryRunPlan:
    inventory = enrich_inventory(inventory)
    indexes = build_indexes(inventory)
    projects = inventory.get("projects", [])
    root_cfg = target_cfg["root_project"]
    root_name = root_cfg["name"]
    warnings = list(inventory.get("metadata", {}).get("warnings", []))

    root_project = find_project_by_name(projects, root_name)
    if root_project is None:
        warnings.append(f"Root project '{root_name}' does not exist in the current inventory.")

    projects_to_create: list[dict[str, str]] = []
    sections_to_create: list[dict[str, str]] = []
    labels_to_create: list[str] = []

    for label_name in target_cfg.get("allowed_labels", []):
        if label_name not in indexes["labels_by_name"]:
            labels_to_create.append(label_name)

    for child_name, child_cfg in root_cfg.get("children", {}).items():
        existing_child = find_project_by_name(projects, child_name, parent_id=root_project["id"] if root_project else None)
        if existing_child is None:
            projects_to_create.append({"name": child_name, "parent": root_name})
            continue
        existing_sections = indexes["sections_by_project"].get(existing_child["id"], {})
        for section_name in child_cfg.get("sections", []):
            if section_name not in existing_sections:
                sections_to_create.append({"project": child_name, "section": section_name})

    task_actions: list[TaskAction] = []
    manual_review: list[ManualReviewItem] = []
    ignored_items: list[IgnoredItem] = []

    for task in inventory.get("tasks", []):
        action, review, ignored = classify_task(
            task,
            inventory=inventory,
            target_cfg=target_cfg,
            migration_cfg=migration_cfg,
            indexes=indexes,
        )
        if action:
            task_actions.append(action)
        if review:
            manual_review.append(review)
        if ignored:
            ignored_items.append(ignored)

    archive_candidates = set(migration_cfg.get("archive_candidates", []))
    projects_to_archive: list[dict[str, str]] = []
    task_ids_needing_manual = {item.task_id for item in manual_review}
    task_ids_moving = {item.task_id for item in task_actions}
    tasks_by_project = indexes["tasks_by_project"]

    for project in projects:
        if project["name"] not in archive_candidates:
            continue
        current_tasks = tasks_by_project.get(project["id"], [])
        unresolved = [
            task for task in current_tasks if task["id"] not in task_ids_moving and task["id"] not in task_ids_needing_manual
        ]
        if unresolved or any(task["id"] in task_ids_needing_manual for task in current_tasks):
            continue
        projects_to_archive.append({"project": project["name"], "reason": "No actionable open tasks remain after planned moves."})

    sap_root_summary = next((item for item in inventory.get("project_summaries", []) if item["name"] == root_name), None)
    inbox_summary = next((item for item in inventory.get("project_summaries", []) if item["name"] == "Inbox"), None)

    summary = {
        "root_project": root_name,
        "sap_root_task_count": sap_root_summary.get("task_count", 0) if sap_root_summary else 0,
        "inbox_task_count": inbox_summary.get("task_count", 0) if inbox_summary else 0,
        "projects_to_create": len(projects_to_create),
        "sections_to_create": len(sections_to_create),
        "labels_to_create": len(labels_to_create),
        "task_actions": len(task_actions),
        "manual_review": len(manual_review),
        "ignored_items": len(ignored_items),
        "projects_to_archive": len(projects_to_archive),
    }

    return DryRunPlan(
        summary=summary,
        projects_to_create=projects_to_create,
        sections_to_create=sections_to_create,
        labels_to_create=labels_to_create,
        task_actions=sorted(task_actions, key=lambda item: (item.target_project, item.target_section, item.current_title.lower())),
        manual_review=sorted(manual_review, key=lambda item: (item.project, item.title.lower())),
        ignored_items=sorted(ignored_items, key=lambda item: (item.project, item.title.lower())),
        projects_to_archive=projects_to_archive,
        warnings=warnings,
    )


def render_dry_run_markdown(
    plan: DryRunPlan,
    *,
    inventory: dict[str, Any],
    target_cfg: dict[str, Any],
    migration_cfg: dict[str, Any],
) -> str:
    lines: list[str] = []
    generated_at = inventory.get("metadata", {}).get("generated_at", "unknown")
    lines.append("# Todoist SAP Reorg Dry Run")
    lines.append("")
    lines.append(f"- Snapshot: `{generated_at}`")
    lines.append(f"- Root project: `{plan.summary['root_project']}`")
    lines.append(f"- Current `{plan.summary['root_project']}` root tasks: `{plan.summary['sap_root_task_count']}`")
    lines.append(f"- Current `Inbox` tasks: `{plan.summary['inbox_task_count']}`")
    lines.append("")

    lines.append("## Projects to Create")
    if plan.projects_to_create:
        for item in plan.projects_to_create:
            lines.append(f"- Create project `{item['name']}` under `{item['parent']}`")
    else:
        lines.append("- None. The SAP root project and target child projects already exist.")
    lines.append("")

    lines.append("## Sections to Create")
    if plan.sections_to_create:
        for item in plan.sections_to_create:
            lines.append(f"- `{item['project']}`: create section `{item['section']}`")
    else:
        lines.append("- None.")
    lines.append("")

    lines.append("## Labels to Create")
    if plan.labels_to_create:
        for label in plan.labels_to_create:
            lines.append(f"- Create label `{label}`")
    else:
        lines.append("- None.")
    lines.append("")

    lines.append("## Task Renames and Moves")
    if plan.task_actions:
        for action in plan.task_actions:
            change_bits: list[str] = []
            if action.current_title != action.new_title:
                change_bits.append(f"rename to `{action.new_title}`")
            if action.current_project != action.target_project or action.current_section != action.target_section:
                destination = action.target_project
                if action.target_section:
                    destination = f"{destination} / {action.target_section}"
                change_bits.append(f"move to `{destination}`")
            if action.labels_to_add:
                change_bits.append(f"add labels {', '.join(f'`{label}`' for label in action.labels_to_add)}")
            if action.labels_to_remove:
                change_bits.append(f"remove labels {', '.join(f'`{label}`' for label in action.labels_to_remove)}")
            changes = "; ".join(change_bits) if change_bits else "no change"
            current_location = action.current_project if not action.current_section else f"{action.current_project} / {action.current_section}"
            lines.append(f"- `{action.current_title}` from `{current_location}`: {changes}")
    else:
        lines.append("- None.")
    lines.append("")

    lines.append("## Projects to Archive")
    if plan.projects_to_archive:
        for item in plan.projects_to_archive:
            lines.append(f"- Archive `{item['project']}`: {item['reason']}")
    else:
        lines.append("- None. No archive candidates are currently safe to archive automatically.")
    lines.append("")

    lines.append("## Manual Review")
    if plan.manual_review:
        for item in plan.manual_review:
            location = item.project if not item.section else f"{item.project} / {item.section}"
            lines.append(f"- `{item.title}` in `{location}`: {item.reason}")
    else:
        lines.append("- None.")
    lines.append("")

    lines.append("## Ignored Out-of-Scope Items")
    if plan.ignored_items:
        grouped: dict[str, int] = {}
        for item in plan.ignored_items:
            grouped[item.project] = grouped.get(item.project, 0) + 1
        for project_name, count in sorted(grouped.items()):
            lines.append(f"- `{project_name}`: `{count}` ignored task(s)")
    else:
        lines.append("- None.")
    lines.append("")

    lines.append("## Review Before Apply")
    lines.append("- Confirm the section layout in `todoist_target.yaml`.")
    lines.append("- Confirm the exact title overrides and keyword routes in `todoist_migration_plan.yaml`.")
    lines.append("- Review every manual-review item before any apply run.")
    lines.append("- Confirm the label replacement policy, because migrated SAP tasks will drop configured legacy SAP labels.")
    lines.append("- Confirm that no task listed under manual review should be moved automatically before running apply.")
    lines.append("")

    if plan.warnings:
        lines.append("## Warnings")
        for warning in plan.warnings:
            lines.append(f"- {warning}")
        lines.append("")

    return "\n".join(lines)


def build_task_payload(
    action: TaskAction,
    *,
    inventory: dict[str, Any],
    indexes: dict[str, Any],
) -> dict[str, Any]:
    root_name = "📤 SAP"
    root_project = find_project_by_name(inventory["projects"], root_name)
    target_project = find_project_by_name(
        inventory["projects"],
        action.target_project,
        parent_id=root_project["id"] if root_project else None,
    )
    if target_project is None:
        raise ValueError(f"Target project '{action.target_project}' is missing from the inventory.")

    payload: dict[str, Any] = {}
    if action.current_title != action.new_title:
        payload["content"] = action.new_title
    if action.current_project != action.target_project:
        payload["project_id"] = target_project["id"]

    target_section_id = ""
    if action.target_section:
        target_section = indexes["sections_by_project"].get(target_project["id"], {}).get(action.target_section)
        if target_section is None:
            raise ValueError(
                f"Target section '{action.target_section}' in project '{action.target_project}' is missing from the inventory."
            )
        target_section_id = target_section["id"]

    current_section = action.current_section
    if current_section != action.target_section:
        payload["section_id"] = target_section_id

    current_task = next(task for task in inventory["tasks"] if task["id"] == action.task_id)
    next_labels = [label for label in current_task.get("labels", []) if label not in action.labels_to_remove]
    next_labels.extend(action.labels_to_add)
    next_labels = sorted(dict.fromkeys(next_labels))
    if next_labels != current_task.get("labels", []):
        payload["labels"] = next_labels
    return payload
