#!/usr/bin/env python3
"""Enrich source inventories with data-driven institution type metadata.

Existing source values are preserved. Records without a type use the same
name/category classifier as NIRF discovery, keeping taxonomy out of the app
and the database importer.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from discover_nirf_state_inventory import institution_type


def enrich_payload(payload: Any) -> Any:
    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict) and isinstance(payload.get("institutions"), list):
        records = payload["institutions"]
    else:
        raise ValueError("Input JSON must be a list or contain institutions")

    for index, record in enumerate(records, start=1):
        if not isinstance(record, dict):
            raise ValueError(f"institution {index} must be an object")
        existing = record.get("institution_type")
        if isinstance(existing, str) and existing.strip():
            continue
        name = record.get("nirf_name", record.get("name"))
        categories = record.get(
            "participating_categories", record.get("categories", [])
        )
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"institution {index} is missing a name")
        if not isinstance(categories, list):
            raise ValueError(f"institution {index} categories must be a list")
        record["institution_type"] = institution_type(
            name,
            [category for category in categories if isinstance(category, str)],
        )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    input_path = args.input.resolve()
    output_path = args.output.resolve()
    payload = json.loads(input_path.read_text(encoding="utf-8"))
    enriched = enrich_payload(payload)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    temporary_path.write_text(
        json.dumps(enriched, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(output_path)
    records = enriched if isinstance(enriched, list) else enriched["institutions"]
    print(f"Enriched {len(records)} institution records in {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
