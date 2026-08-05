#!/usr/bin/env python3
"""Serially validate and collect isolated college-agent results."""

from __future__ import annotations

import argparse
from datetime import date
from pathlib import Path
from typing import Any

from college_agents.common import (
    REPO_ROOT,
    load_json,
    validate_agent_result,
    write_json_atomic,
)
from validate_rajasthan_verifications import validate


DEFAULT_VERIFICATIONS = (
    REPO_ROOT / "research/rajasthan_institution_verifications.json"
)
DEFAULT_INVENTORY = REPO_ROOT / "research/rajasthan_nirf_master_inventory.json"
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"


def curated_record(result: dict[str, Any]) -> dict[str, Any]:
    outcome = result["verification_outcome"]
    record_status = "remove" if outcome == "remove_candidate" else outcome
    fields = (
        "district",
        "district_verification_status",
        "official_website",
        "website_verification_status",
        "description",
        "description_verification_status",
        "allowed_official_domains",
        "verification_sources",
        "website_search_evidence",
        "course_catalogue_status",
        "courses",
        "agent_notes",
    )
    return {
        "id": result["institution_id"],
        **{field: result[field] for field in fields if field in result},
        "record_status": record_status,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument(
        "--verifications",
        type=Path,
        default=DEFAULT_VERIFICATIONS,
    )
    parser.add_argument(
        "--output",
        type=Path,
        help=(
            "Write the merged verification file here. Defaults to a preview "
            "inside the run directory."
        ),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Atomically replace the curated verification file.",
    )
    parser.add_argument(
        "--include-removal-candidates",
        action="store_true",
        help="Convert evidenced remove_candidate outcomes to remove records.",
    )
    parser.add_argument(
        "--replace-existing",
        action="store_true",
        help="Replace an existing curated record with the same institution id.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_dir = args.run_dir.resolve()
    results_dir = run_dir / "results"
    result_paths = sorted(
        path
        for path in results_dir.glob("*.json")
        if not path.name.endswith(".invalid.json")
    )
    if not result_paths:
        raise SystemExit(f"No valid result files found in {results_dir}")

    source_path = args.verifications.resolve()
    payload = load_json(source_path)
    existing = {
        record["id"]: record for record in payload.get("institutions", [])
    }
    collected: list[str] = []
    skipped: dict[str, str] = {}

    for result_path in result_paths:
        result = load_json(result_path)
        institution_id = result.get("institution_id")
        if not isinstance(institution_id, str):
            raise SystemExit(f"{result_path}: missing institution_id")
        errors = validate_agent_result(result, institution_id)
        if errors:
            raise SystemExit(
                f"{result_path} failed validation:\n- " + "\n- ".join(errors)
            )
        outcome = result["verification_outcome"]
        if outcome == "manual_review":
            skipped[institution_id] = "manual_review"
            continue
        if outcome == "remove_candidate" and not args.include_removal_candidates:
            skipped[institution_id] = "remove_candidate_not_applied"
            continue
        if institution_id in existing and not args.replace_existing:
            skipped[institution_id] = "existing_record_not_replaced"
            continue
        existing[institution_id] = curated_record(result)
        collected.append(institution_id)

    payload["metadata"]["updated_on"] = date.today().isoformat()
    payload["institutions"] = sorted(
        existing.values(),
        key=lambda record: record["id"],
    )
    output_path = (
        args.output.resolve()
        if args.output
        else run_dir / "verification_merge_preview.json"
    )
    if output_path == source_path:
        raise SystemExit(
            "--output must not be the curated verification path; use --apply "
            "for an atomic replacement"
        )
    write_json_atomic(output_path, payload)
    errors = validate(output_path, DEFAULT_INVENTORY, DEFAULT_DATABASE)
    if errors:
        output_path.unlink(missing_ok=True)
        raise SystemExit(
            "Merged verification file failed validation:\n- "
            + "\n- ".join(errors)
        )
    if args.apply:
        write_json_atomic(source_path, payload)
        if output_path != source_path:
            output_path.unlink(missing_ok=True)
        output_path = source_path

    summary = {
        "source_verifications": str(source_path),
        "output": str(output_path),
        "applied": args.apply,
        "collected_count": len(collected),
        "collected_institution_ids": collected,
        "skipped": skipped,
    }
    write_json_atomic(run_dir / "collection_summary.json", summary)
    print(
        f"Collected {len(collected)} result(s); skipped {len(skipped)}. "
        f"Wrote {output_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
