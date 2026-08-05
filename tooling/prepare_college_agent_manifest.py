#!/usr/bin/env python3
"""Create deterministic 10-by-10 agent assignments from the master inventory."""

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
) -> dict[str, Any]:
    inventory = load_json(INVENTORY_PATH)
    excluded_ids = excluded_ids or set()
    candidates = [
        institution
        for institution in inventory["institutions"]
        if institution.get("website_verification_status") != "verified"
        and institution.get("record_status") != "remove"
        and institution["id"] not in excluded_ids
    ]
    candidates.sort(key=ranking_priority)
    limit = batch_count * batch_size
    selected = candidates[:limit]
    assignments = [
        {
            "batch": (index // batch_size) + 1,
            "slot": (index % batch_size) + 1,
            "institution_id": institution["id"],
            "nirf_name": institution["nirf_name"],
            "nirf_city": institution["nirf_city"],
            "ranked_or_banded": bool(institution["rankings"]),
        }
        for index, institution in enumerate(selected)
    ]
    return {
        "metadata": {
            "created_at": utc_now(),
            "inventory_path": str(INVENTORY_PATH.relative_to(INVENTORY_PATH.parent.parent)),
            "inventory_sha256": sha256_file(INVENTORY_PATH),
            "batch_count": batch_count,
            "batch_size": batch_size,
            "assignment_count": len(assignments),
            "selection": (
                "Pending institutions, ranked/banded first by best visible "
                "NIRF rank or band, then by city and institution name, "
                "excluding caller-supplied previously attempted ids."
            ),
        },
        "assignments": assignments,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-count", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_MANIFEST_PATH,
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
    if args.output.exists() and not args.force:
        raise SystemExit(
            f"{args.output} already exists; use --force to replace it"
        )
    manifest = build_manifest(args.batch_count, args.batch_size)
    write_json_atomic(args.output, manifest)
    print(
        f"Wrote {len(manifest['assignments'])} assignments to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
