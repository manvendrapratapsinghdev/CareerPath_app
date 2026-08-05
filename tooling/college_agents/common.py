"""Shared helpers for isolated college-verification agents."""

from __future__ import annotations

import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from jsonschema import Draft202012Validator, FormatChecker


REPO_ROOT = Path(__file__).resolve().parents[2]
INVENTORY_PATH = REPO_ROOT / "research/rajasthan_nirf_master_inventory.json"
DATABASE_PATH = REPO_ROOT / "assets/data/career_path.db"
SCHEMA_PATH = Path(__file__).with_name("agent_result.schema.json")
PROMPT_PATH = Path(__file__).with_name("worker_prompt.md")
DEFAULT_MANIFEST_PATH = (
    REPO_ROOT / "research/rajasthan_agent_assignments.json"
)
RUNS_ROOT = REPO_ROOT / "research/agent_runs"


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def write_json_atomic(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(path)


def normalize_agent_result(
    result: dict[str, Any],
    institution_id: str,
) -> dict[str, Any]:
    """Apply deterministic identifier normalization before validation."""
    prefix = f"{institution_id}-"
    career_nodes = load_career_nodes()
    for course in result.get("courses", []):
        course_id = course.get("course_id")
        if isinstance(course_id, str) and not course_id.startswith(prefix):
            course["course_id"] = f"{prefix}{course_id}"
        for mapping in course.get("career_path_mappings", []):
            node = career_nodes.get(mapping.get("career_node_id"))
            if node is not None:
                mapping["career_node_slug"] = node["slug"]
                mapping["career_breadcrumb"] = node["breadcrumb"]
        if course.get("career_path_mappings"):
            course["mapping_gap"] = None
    if result.get("verification_outcome") == "verified":
        verified_prerequisites = (
            result.get("website_verification_status") == "verified"
            and bool(result.get("district"))
            and result.get("district_verification_status")
            == "verified_official_website"
            and bool(result.get("description"))
            and result.get("description_verification_status")
            == "verified_official_website"
            and result.get("course_catalogue_status")
            == "verified_official_website"
            and bool(result.get("courses"))
            and len(result.get("verification_sources", [])) >= 2
        )
        if not verified_prerequisites:
            result["verification_outcome"] = "manual_review"
            result["record_status"] = "manual_review"
            note = (
                "Automatically downgraded from verified because one or more "
                "required official-source verification prerequisites were "
                "not satisfied."
            )
            notes = result.setdefault("agent_notes", [])
            if note not in notes:
                notes.append(note)
    website = result.get("official_website")
    if isinstance(website, str):
        website_host = normalized_hostname(website)
        allowed_domains = set(result.get("allowed_official_domains", []))
        for source in result.get("verification_sources", []):
            source_url = source.get("url")
            if not isinstance(source_url, str):
                continue
            source_host = normalized_hostname(source_url)
            if website_host.endswith(f".{source_host}"):
                allowed_domains.add(source_host)
        result["allowed_official_domains"] = sorted(allowed_domains)
    return result


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_inventory_institution(institution_id: str) -> dict[str, Any]:
    inventory = load_json(INVENTORY_PATH)
    matches = [
        item
        for item in inventory.get("institutions", [])
        if isinstance(item, dict) and item.get("id") == institution_id
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Expected one inventory record for {institution_id!r}; "
            f"found {len(matches)}"
        )
    return matches[0]


def build_prompt(institution: dict[str, Any]) -> str:
    context = {
        "id": institution["id"],
        "nirf_name": institution["nirf_name"],
        "nirf_city": institution["nirf_city"],
        "state": institution["state"],
        "participating_categories": institution["participating_categories"],
        "rankings": institution["rankings"],
    }
    template = PROMPT_PATH.read_text(encoding="utf-8")
    return template.replace(
        "{{INSTITUTION_CONTEXT}}",
        json.dumps(context, ensure_ascii=False, indent=2),
    )


def normalized_hostname(value: str) -> str:
    hostname = urlparse(value).hostname or ""
    return hostname.casefold().removeprefix("www.")


def official_domains(result: dict[str, Any]) -> set[str]:
    website = result.get("official_website")
    domains: set[str] = set()
    if isinstance(website, str):
        domains.add(normalized_hostname(website))
    for domain in result.get("allowed_official_domains", []):
        if isinstance(domain, str):
            domains.add(domain.casefold().removeprefix("www."))
    return {domain for domain in domains if domain}


def is_official_url(url: str, domains: set[str]) -> bool:
    hostname = normalized_hostname(url)
    return any(
        hostname == domain or hostname.endswith(f".{domain}")
        for domain in domains
    )


def load_career_nodes() -> dict[int, dict[str, Any]]:
    connection = sqlite3.connect(f"file:{DATABASE_PATH}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        nodes = {
            row["id"]: {
                "id": row["id"],
                "slug": row["slug"],
                "name": row["name"],
                "parent_id": row["parent_id"],
            }
            for row in connection.execute(
                "SELECT id, slug, name, parent_id FROM career_nodes"
            )
        }
    finally:
        connection.close()

    for node in nodes.values():
        names: list[str] = []
        seen: set[int] = set()
        current_id: int | None = node["id"]
        while current_id is not None:
            if current_id in seen:
                raise ValueError(f"Career-node cycle at {current_id}")
            seen.add(current_id)
            current = nodes.get(current_id)
            if current is None:
                raise ValueError(f"Missing career node {current_id}")
            names.append(current["name"])
            current_id = current["parent_id"]
        node["breadcrumb"] = " > ".join(reversed(names))
    return nodes


def validate_agent_result(
    result: dict[str, Any],
    expected_institution_id: str,
) -> list[str]:
    schema = load_json(SCHEMA_PATH)
    validator = Draft202012Validator(
        schema,
        format_checker=FormatChecker(),
    )
    errors = [
        f"{'/'.join(str(part) for part in error.path) or '<root>'}: "
        f"{error.message}"
        for error in sorted(validator.iter_errors(result), key=str)
    ]
    if errors:
        return errors

    if result["institution_id"] != expected_institution_id:
        errors.append(
            "institution_id does not match the assigned institution: "
            f"{result['institution_id']!r} != {expected_institution_id!r}"
        )
    expected_institution = load_inventory_institution(expected_institution_id)
    if result["nirf_name"] != expected_institution["nirf_name"]:
        errors.append(
            "nirf_name does not match the assigned inventory record: "
            f"{result['nirf_name']!r} != "
            f"{expected_institution['nirf_name']!r}"
        )

    outcome = result["verification_outcome"]
    if result["record_status"] != outcome:
        errors.append("record_status must equal verification_outcome")

    if outcome == "verified":
        if result["website_verification_status"] != "verified":
            errors.append("verified outcome requires a verified website")
        if (
            not result["district"]
            or result["district_verification_status"]
            != "verified_official_website"
        ):
            errors.append(
                "verified outcome requires an officially verified district"
            )
        if (
            not result["description"]
            or result["description_verification_status"]
            != "verified_official_website"
        ):
            errors.append(
                "verified outcome requires an officially verified description"
            )
        if (
            result["course_catalogue_status"]
            != "verified_official_website"
        ):
            errors.append(
                "verified outcome requires a complete official course catalogue"
            )
        if not result["courses"]:
            errors.append("verified outcome requires at least one course")
        if len(result["verification_sources"]) < 2:
            errors.append(
                "verified outcome requires at least two official sources"
            )
        support_text = " ".join(
            support.casefold()
            for source in result["verification_sources"]
            for support in source["supports"]
        )
        if not any(
            keyword in support_text
            for keyword in ("course", "programme", "program", "catalogue")
        ):
            errors.append(
                "verified outcome requires a source supporting the course "
                "catalogue"
            )
        if not any(
            keyword in support_text
            for keyword in ("district", "campus", "location", "address")
        ):
            errors.append(
                "verified outcome requires a source supporting district or "
                "campus location"
            )
    elif outcome == "remove_candidate":
        if result["official_website"] is not None:
            errors.append("remove_candidate must not set official_website")
        if len(result["website_search_evidence"]) < 2:
            errors.append(
                "remove_candidate requires at least two search-evidence entries"
            )

    domains = official_domains(result)
    additional_domains = result["allowed_official_domains"]
    if len(additional_domains) != len(set(additional_domains)):
        errors.append("allowed_official_domains contains duplicates")
    if result["website_verification_status"] == "verified" and not domains:
        errors.append("verified website did not produce an official domain")
    for source in result["verification_sources"]:
        if domains and not is_official_url(source["url"], domains):
            errors.append(
                f"verification source is outside official domains: "
                f"{source['url']}"
            )
    for course in result["courses"]:
        if domains and not is_official_url(
            course["official_course_url"],
            domains,
        ):
            errors.append(
                f"course URL is outside official domains: "
                f"{course['official_course_url']}"
            )
        mappings = course["career_path_mappings"]
        if not mappings and not course.get("mapping_gap"):
            errors.append(
                f"{course['course_id']}: unmapped course requires mapping_gap"
            )
        if mappings and course.get("mapping_gap") is not None:
            errors.append(
                f"{course['course_id']}: mapped course requires null mapping_gap"
            )

    nodes = load_career_nodes()
    course_ids: set[str] = set()
    for course in result["courses"]:
        course_id = course["course_id"]
        if not course_id.startswith(f"{expected_institution_id}-"):
            errors.append(
                f"{course_id}: course_id must start with "
                f"{expected_institution_id}-"
            )
        if course_id in course_ids:
            errors.append(f"duplicate course_id: {course_id}")
        course_ids.add(course_id)
        mapping_ids: set[int] = set()
        for mapping in course["career_path_mappings"]:
            node_id = mapping["career_node_id"]
            if node_id in mapping_ids:
                errors.append(
                    f"{course_id}: duplicate career node {node_id}"
                )
            mapping_ids.add(node_id)
            node = nodes.get(node_id)
            if node is None:
                errors.append(f"{course_id}: unknown career node {node_id}")
                continue
            if mapping["career_node_slug"] != node["slug"]:
                errors.append(
                    f"{course_id}: slug mismatch for career node {node_id}"
                )
            if mapping["career_breadcrumb"] != node["breadcrumb"]:
                errors.append(
                    f"{course_id}: breadcrumb mismatch for career node {node_id}"
                )
    return errors
