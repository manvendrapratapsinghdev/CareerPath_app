#!/usr/bin/env python3
"""Validate curated Rajasthan institution and course verification records."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


ALLOWED_STATUSES = {
    "candidate",
    "keep",
    "remove",
    "verified",
}
ALLOWED_CONFIDENCE = {"high", "medium", "low"}
ALLOWED_MAPPING_STATUS = {
    "pending",
    "reviewed_against_local_tree",
    "reviewed_with_career_tree_label_issue",
    "verified",
}
ALLOWED_COURSE_VERIFICATION_STATUSES = {
    "verified",
    "verified_programme_family",
}


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def load_career_nodes(database_path: Path) -> dict[int, dict[str, Any]]:
    connection = sqlite3.connect(database_path)
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
                raise ValueError(
                    f"Cycle detected in career_nodes at node {current_id}"
                )
            seen.add(current_id)
            current = nodes.get(current_id)
            if current is None:
                raise ValueError(
                    f"Missing career_nodes parent referenced by {current_id}"
                )
            names.append(current["name"])
            current_id = current["parent_id"]
        node["breadcrumb"] = " > ".join(reversed(names))
    return nodes


def is_http_url(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def normalized_hostname(value: str) -> str:
    hostname = urlparse(value).hostname or ""
    return hostname.casefold().removeprefix("www.")


def is_allowed_official_url(
    value: Any,
    official_website: Any,
    additional_domains: Any,
) -> bool:
    if not is_http_url(value) or not is_http_url(official_website):
        return False
    allowed = {normalized_hostname(official_website)}
    if isinstance(additional_domains, list):
        allowed.update(
            domain.casefold().removeprefix("www.")
            for domain in additional_domains
            if isinstance(domain, str) and domain
        )
    hostname = normalized_hostname(value)
    return any(
        hostname == domain or hostname.endswith(f".{domain}")
        for domain in allowed
    )


def validate(
    verification_path: Path,
    inventory_path: Path,
    database_path: Path,
) -> list[str]:
    errors: list[str] = []
    payload = load_json(verification_path)
    inventory = load_json(inventory_path)
    career_nodes = load_career_nodes(database_path)

    institutions = payload.get("institutions")
    if not isinstance(institutions, list):
        return ["The verification file requires an institutions array"]

    inventory_ids = {
        item.get("id")
        for item in inventory.get("institutions", [])
        if isinstance(item, dict)
    }
    institution_ids: set[str] = set()
    course_ids: set[str] = set()

    for institution_index, institution in enumerate(institutions):
        prefix = f"institutions[{institution_index}]"
        if not isinstance(institution, dict):
            errors.append(f"{prefix} must be an object")
            continue

        institution_id = institution.get("id")
        if not isinstance(institution_id, str) or not institution_id:
            errors.append(f"{prefix}.id must be a non-empty string")
            continue
        prefix = institution_id
        if institution_id in institution_ids:
            errors.append(f"{prefix}: duplicate institution id")
        institution_ids.add(institution_id)
        if institution_id not in inventory_ids:
            errors.append(f"{prefix}: not present in the NIRF master inventory")

        record_status = institution.get("record_status")
        if record_status not in ALLOWED_STATUSES:
            errors.append(
                f"{prefix}: record_status must be one of "
                f"{sorted(ALLOWED_STATUSES)}"
            )

        website_status = institution.get("website_verification_status")
        website = institution.get("official_website")
        if website_status == "verified" and not is_http_url(website):
            errors.append(
                f"{prefix}: verified official_website must be an HTTP(S) URL"
            )
        if (
            record_status in {"keep", "verified"}
            and website_status != "verified"
        ):
            errors.append(
                f"{prefix}: a kept or verified record must have a verified "
                "official website"
            )
        additional_domains = institution.get("allowed_official_domains")

        sources = institution.get("verification_sources")
        if not isinstance(sources, list):
            errors.append(f"{prefix}: verification_sources must be an array")
        elif not sources and record_status != "remove":
            errors.append(f"{prefix}: verification_sources must not be empty")
        else:
            for source_index, source in enumerate(sources):
                source_prefix = (
                    f"{prefix}.verification_sources[{source_index}]"
                )
                if not isinstance(source, dict):
                    errors.append(f"{source_prefix} must be an object")
                    continue
                if not is_http_url(source.get("url")):
                    errors.append(f"{source_prefix}.url must be an HTTP(S) URL")
                elif website_status == "verified" and not is_allowed_official_url(
                    source.get("url"),
                    website,
                    additional_domains,
                ):
                    errors.append(
                        f"{source_prefix}.url is outside the official domain"
                    )
                if not source.get("supports"):
                    errors.append(f"{source_prefix}.supports must not be empty")

        if record_status == "remove":
            if website is not None or website_status != "not_found":
                errors.append(
                    f"{prefix}: removed record requires a null website and "
                    "not_found website status"
                )
            search_evidence = institution.get("website_search_evidence")
            if not isinstance(search_evidence, list) or len(search_evidence) < 2:
                errors.append(
                    f"{prefix}: removed record requires at least two "
                    "website_search_evidence entries"
                )

        courses = institution.get("courses")
        if not isinstance(courses, list):
            errors.append(f"{prefix}: courses must be an array")
            continue
        if (
            institution.get("course_catalogue_status")
            == "verified_official_website"
            and not courses
        ):
            errors.append(
                f"{prefix}: verified course catalogue must contain courses"
            )

        for course_index, course in enumerate(courses):
            course_prefix = f"{prefix}.courses[{course_index}]"
            if not isinstance(course, dict):
                errors.append(f"{course_prefix} must be an object")
                continue
            course_id = course.get("course_id")
            if not isinstance(course_id, str) or not course_id:
                errors.append(f"{course_prefix}.course_id is required")
            elif course_id in course_ids:
                errors.append(f"{course_prefix}: duplicate course_id {course_id}")
            else:
                course_ids.add(course_id)

            for field in ("name", "level", "credential"):
                if not isinstance(course.get(field), str) or not course[field]:
                    errors.append(f"{course_prefix}.{field} is required")
            if not is_http_url(course.get("official_course_url")):
                errors.append(
                    f"{course_prefix}.official_course_url must be an HTTP(S) URL"
                )
            elif website_status == "verified" and not is_allowed_official_url(
                course.get("official_course_url"),
                website,
                additional_domains,
            ):
                errors.append(
                    f"{course_prefix}.official_course_url is outside the "
                    "official domain"
                )
            if (
                course.get("verification_status")
                not in ALLOWED_COURSE_VERIFICATION_STATUSES
            ):
                errors.append(
                    f"{course_prefix}.verification_status must be one of "
                    f"{sorted(ALLOWED_COURSE_VERIFICATION_STATUSES)}"
                )

            mappings = course.get("career_path_mappings")
            if not isinstance(mappings, list):
                errors.append(
                    f"{course_prefix}.career_path_mappings must be an array"
                )
                continue
            if not mappings and not course.get("mapping_gap"):
                errors.append(
                    f"{course_prefix}: unmapped course requires mapping_gap"
                )

            mapped_ids: set[int] = set()
            for mapping_index, mapping in enumerate(mappings):
                mapping_prefix = (
                    f"{course_prefix}.career_path_mappings[{mapping_index}]"
                )
                if not isinstance(mapping, dict):
                    errors.append(f"{mapping_prefix} must be an object")
                    continue
                node_id = mapping.get("career_node_id")
                if node_id in mapped_ids:
                    errors.append(
                        f"{mapping_prefix}: duplicate career node {node_id}"
                    )
                mapped_ids.add(node_id)
                node = career_nodes.get(node_id)
                if node is None:
                    errors.append(
                        f"{mapping_prefix}: unknown career node {node_id}"
                    )
                    continue
                expected = {
                    "career_node_slug": node["slug"],
                    "career_breadcrumb": node["breadcrumb"],
                }
                for field, expected_value in expected.items():
                    if mapping.get(field) != expected_value:
                        errors.append(
                            f"{mapping_prefix}.{field} is "
                            f"{mapping.get(field)!r}; expected {expected_value!r}"
                        )
                if mapping.get("confidence") not in ALLOWED_CONFIDENCE:
                    errors.append(
                        f"{mapping_prefix}.confidence must be one of "
                        f"{sorted(ALLOWED_CONFIDENCE)}"
                    )
                if (
                    mapping.get("mapping_status")
                    not in ALLOWED_MAPPING_STATUS
                ):
                    errors.append(
                        f"{mapping_prefix}.mapping_status must be one of "
                        f"{sorted(ALLOWED_MAPPING_STATUS)}"
                    )
                if not mapping.get("relation"):
                    errors.append(f"{mapping_prefix}.relation is required")

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--verifications",
        type=Path,
        default=Path("research/rajasthan_institution_verifications.json"),
    )
    parser.add_argument(
        "--inventory",
        type=Path,
        default=Path("research/rajasthan_nirf_master_inventory.json"),
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=Path("assets/data/career_path.db"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    errors = validate(args.verifications, args.inventory, args.database)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(
            f"Validation failed with {len(errors)} error(s).",
            file=sys.stderr,
        )
        return 1
    payload = load_json(args.verifications)
    institutions = payload["institutions"]
    course_count = sum(len(item["courses"]) for item in institutions)
    print(
        f"Validated {len(institutions)} institution(s) "
        f"and {course_count} course(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
