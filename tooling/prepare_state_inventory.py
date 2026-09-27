#!/usr/bin/env python3
"""Create a state inventory from a government-published college list.

The source list is intentionally supplied as structured JSON because state
portal formats differ. This command normalizes the discovery layer into the
inventory contract consumed by the batched verification agents. It never marks
an institution or course as verified.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_source(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict) and isinstance(payload.get("institutions"), list):
        records = payload["institutions"]
    else:
        raise ValueError("Source JSON must be a list or contain institutions")
    if not all(isinstance(record, dict) for record in records):
        raise ValueError("Every source institution must be an object")
    return records


def identity_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.casefold()).strip("-")


def build_inventory(
    state: str,
    source_path: Path,
    source_url: str,
) -> dict[str, Any]:
    if not state.strip():
        raise ValueError("state must not be empty")
    records = load_source(source_path)
    institutions: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for index, source in enumerate(records, start=1):
        name = source.get("name", source.get("nirf_name"))
        city = source.get("city", source.get("nirf_city"))
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"source record {index} is missing name")
        if not isinstance(city, str) or not city.strip():
            raise ValueError(f"source record {index} is missing city")
        source_state = source.get("state")
        if source_state is not None and source_state != state:
            raise ValueError(
                f"source record {index} belongs to {source_state!r}, "
                f"not {state!r}"
            )
        normalized_name = re.sub(r"\s+", " ", name).strip()
        normalized_city = re.sub(r"\s+", " ", city).strip()
        institution_id = source.get("id", identity_key(normalized_name))
        if not isinstance(institution_id, str) or not institution_id.strip():
            raise ValueError(f"source record {index} has an invalid id")
        if institution_id in seen_ids:
            raise ValueError(f"duplicate institution id: {institution_id}")
        seen_ids.add(institution_id)
        categories = source.get("participating_categories", source.get("categories", []))
        institution_type = source.get("institution_type", "other")
        if not isinstance(institution_type, str) or not institution_type.strip():
            raise ValueError(f"source record {index} has an invalid institution_type")
        government_sources = source.get(
            "government_listing_sources",
            source.get("discovery_sources", [source_url]),
        )
        if not isinstance(government_sources, list) or not government_sources:
            raise ValueError(
                f"source record {index} has no government listing source"
            )
        if any(
            not isinstance(value, str)
            or urlparse(value).scheme not in {"http", "https"}
            or not urlparse(value).netloc
            for value in government_sources
        ):
            raise ValueError(
                f"source record {index} has an invalid government listing URL"
            )
        if not isinstance(categories, list) or not all(
            isinstance(category, str) and category.strip() for category in categories
        ):
            raise ValueError(
                f"source record {index} categories must be a list of strings"
            )
        institutions.append(
            {
                "id": institution_id,
                "nirf_name": normalized_name,
                "nirf_city": normalized_city,
                "state": state,
                "institution_type": institution_type.strip().casefold(),
                "government_listing_sources": sorted(set(government_sources)),
                "district": None,
                "district_verification_status": "pending_official_source",
                "participating_categories": sorted(set(categories)),
                "rankings": source.get("rankings", []),
                "official_website": None,
                "website_verification_status": "pending",
                "description": None,
                "description_verification_status": "pending",
                "courses": [],
                "course_catalogue_status": "pending_official_website",
                "verification_sources": [],
                "record_status": "candidate",
                "existing_database_records": source.get(
                    "existing_database_records", []
                ),
            }
        )
    institutions.sort(key=lambda item: (item["nirf_city"].casefold(), item["nirf_name"].casefold()))
    return {
        "metadata": {
            "title": f"{state} college discovery inventory",
            "generated_on": __import__("datetime").date.today().isoformat(),
            "state": state,
            "source_authority": "Official government discovery source supplied by operator",
            "source_home": source_url,
            "scope": "Institutions discovered from the supplied official state list; all official-site facts remain pending until agent verification.",
            "unique_institution_count": len(institutions),
            "verified_official_website_count": 0,
            "verified_course_catalogue_count": 0,
            "verification_policy": {
                "discovery_source": source_url,
                "government_listing_required": True,
                "official_site_required_before_import": True,
                "complete_course_catalogue_required_before_import": True,
            },
        },
        "institutions": institutions,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True, help="State name, e.g. Gujarat")
    parser.add_argument(
        "--source-list",
        type=Path,
        required=True,
        help="JSON list exported or transcribed from the official state portal.",
    )
    parser.add_argument("--source-url", required=True, help="Official list URL")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    inventory = build_inventory(
        args.state,
        args.source_list.resolve(),
        args.source_url,
    )
    args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.output.resolve().write_text(
        json.dumps(inventory, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {len(inventory['institutions'])} pending {args.state} institutions "
        f"to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
