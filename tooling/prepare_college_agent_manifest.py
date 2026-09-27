#!/usr/bin/env python3
"""Create deterministic agent assignments for a state inventory.

The default plan processes up to 200 candidates in twenty batches of ten.
The inventory remains the discovery boundary; verification workers still handle
exactly one institution and only fully verified records can be imported.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from college_agents.common import (
    DEFAULT_MANIFEST_PATH,
    INVENTORY_PATH,
    load_json,
    sha256_file,
    utc_now,
    write_json_atomic,
)


# This is the requested discovery order. Private universities and colleges are
# intentionally one tier; specialized institutes follow agriculture.
INSTITUTION_TYPE_PRIORITY = {
    "iit": 0,
    "iim": 1,
    "nit": 2,
    "iiit": 2,
    "central_institute": 3,
    "central_university": 3,
    "state_university": 4,
    "private_university": 5,
    "private_college": 5,
    "government_college": 6,
    "government_aided_college": 6,
    "aided_college": 6,
    "government_polytechnic": 7,
    "polytechnic": 7,
    "medical": 8,
    "law": 9,
    "agriculture": 10,
    "specialized": 11,
    "other": 12,
}


def normalized_institution_type(institution: dict[str, Any]) -> str:
    raw = str(institution.get("institution_type", "other"))
    normalized = raw.strip().casefold().replace("-", "_").replace(" ", "_")
    aliases = {
        "government_aided": "government_aided_college",
        "aided_degree_college": "aided_college",
        "govt_college": "government_college",
        "govt_polytechnic": "government_polytechnic",
        "medical_college": "medical",
        "law_college": "law",
        "agricultural": "agriculture",
        "specialised": "specialized",
    }
    return aliases.get(normalized, normalized)


def ranking_priority(institution: dict[str, Any]) -> tuple[Any, ...]:
    rankings = institution.get("rankings", [])
    rank_values: list[int] = []
    for ranking in rankings:
        rank = ranking.get("rank")
        if isinstance(rank, int):
            rank_values.append(rank)
            continue
        rank_band = ranking.get("rank_band")
        if isinstance(rank_band, str):
            try:
                rank_values.append(int(rank_band.split("-", 1)[0]))
            except ValueError:
                pass
    return (
        INSTITUTION_TYPE_PRIORITY.get(
            normalized_institution_type(institution),
            INSTITUTION_TYPE_PRIORITY["other"],
        ),
        0 if rankings else 1,
        min(rank_values, default=1_000_000),
        institution["nirf_city"].casefold(),
        institution["nirf_name"].casefold(),
        institution["id"],
    )


def build_manifest(
    batch_count: int,
    batch_size: int,
    excluded_ids: set[str] | None = None,
    inventory_path: Path = INVENTORY_PATH,
    candidate_limit: int | None = None,
) -> dict[str, Any]:
    if batch_count < 1 or batch_size < 1:
        raise ValueError("batch_count and batch_size must be positive")
    if candidate_limit is not None and candidate_limit < 1:
        raise ValueError("candidate_limit must be positive or None")

    inventory = load_json(inventory_path)
    excluded_ids = excluded_ids or set()
    candidates = [
        institution
        for institution in inventory["institutions"]
        if institution.get("website_verification_status") != "verified"
        and institution.get("record_status") != "remove"
        and institution["id"] not in excluded_ids
    ]
    candidates.sort(key=ranking_priority)

    # The batch plan is the only capacity boundary. candidate_limit is an
    # optional discovery selection limit; None means use every eligible record
    # that fits the requested batch plan. The CLI defaults to 200, while 0 on
    # the CLI means no explicit candidate limit.
    if candidate_limit is not None:
        candidates = candidates[:candidate_limit]
    selected = candidates[: batch_count * batch_size]
    actual_batch_count = (
        (len(selected) + batch_size - 1) // batch_size
        if selected
        else 0
    )
    assignments = [
        {
            "batch": (index // batch_size) + 1,
            "slot": (index % batch_size) + 1,
            "institution_id": institution["id"],
            "nirf_name": institution["nirf_name"],
            "nirf_city": institution["nirf_city"],
            "institution_type": normalized_institution_type(institution),
            "ranked_or_banded": bool(institution["rankings"]),
        }
        for index, institution in enumerate(selected)
    ]
    return {
        "metadata": {
            "created_at": utc_now(),
            "inventory_path": str(inventory_path),
            "inventory_sha256": sha256_file(inventory_path),
            "batch_count": actual_batch_count,
            "requested_batch_count": batch_count,
            "batch_size": batch_size,
            "candidate_limit": candidate_limit,
            "eligible_candidate_count": len(candidates),
            "assignment_count": len(assignments),
            "selection": (
                "Priority order is IIT, IIM, NIT/IIIT, central university or "
                "institute, state university, private university/college, "
                "government/aided degree college, polytechnic, medical, law, "
                "agriculture, then specialized institutions. Within a tier, "
                "ranked/banded institutions are ordered by best visible rank "
                "or band, then city and name. Caller-supplied previously "
                "attempted ids are excluded. Only records that remain fully "
                "verified are eligible for collection and import.",
            ),
        },
        "assignments": assignments,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-count", type=int, default=40)
    parser.add_argument("--batch-size", type=int, default=5)
    parser.add_argument(
        "--candidate-limit",
        type=int,
        default=200,
        help="Maximum candidates to assign; 0 means no explicit limit.",
    )
    parser.add_argument(
        "--exclude-run-dir",
        type=Path,
        action="append",
        default=[],
        help="Exclude institution ids found in one or more prior run metrics directories.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_MANIFEST_PATH,
    )
    parser.add_argument(
        "--inventory",
        type=Path,
        default=INVENTORY_PATH,
        help="State inventory JSON to turn into assignments.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing manifest.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.batch_count < 1 or args.batch_size < 1:
        raise SystemExit("batch-count and batch-size must be positive")
    if args.candidate_limit < 0:
        raise SystemExit("candidate-limit must be zero or positive")
    if args.output.exists() and not args.force:
        raise SystemExit(
            f"{args.output} already exists; use --force to replace it"
        )
    excluded_ids: set[str] = set()
    for run_dir in args.exclude_run_dir:
        for metrics_path in run_dir.resolve().joinpath("metrics").glob("*.json"):
            try:
                metrics = load_json(metrics_path)
            except (OSError, ValueError):
                continue
            institution_id = metrics.get("institution_id")
            if isinstance(institution_id, str):
                excluded_ids.add(institution_id)
    manifest = build_manifest(
        args.batch_count,
        args.batch_size,
        excluded_ids=excluded_ids,
        inventory_path=args.inventory.resolve(),
        candidate_limit=(args.candidate_limit or None),
    )
    write_json_atomic(args.output, manifest)
    print(
        f"Wrote {len(manifest['assignments'])} assignments to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
