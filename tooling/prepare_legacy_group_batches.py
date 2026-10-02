#!/usr/bin/env python3
"""Prepare deterministic review batches for institutes without taxonomy rows.

The generated JSON is a review manifest only. It never writes the database or
guesses a group. Workers return classifications with official evidence, and a
separate merge step can validate/apply only approved results.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = ROOT / "assets/data/career_path.db"
DEFAULT_OUTPUT = ROOT / "research/legacy_group_batches"


def _json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def build(database: Path, output: Path, batch_size: int, limit: int) -> int:
    connection = sqlite3.connect(f"file:{database.resolve()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            """
            SELECT i.id, i.name, i.city, i.district, i.state, i.website,
                   i.description, i.institution_type,
                   GROUP_CONCAT(DISTINCT ic.category) AS categories,
                   GROUP_CONCAT(DISTINCT cn.name) AS career_nodes
            FROM institutes AS i
            LEFT JOIN institute_classification AS c ON c.institute_id = i.id
            LEFT JOIN institute_categories AS ic ON ic.institute_id = i.id
            LEFT JOIN node_institutes AS ni ON ni.institute_id = i.id
            LEFT JOIN career_nodes AS cn ON cn.id = ni.node_id
            WHERE c.institute_id IS NULL
            GROUP BY i.id
            ORDER BY i.id
            """
        ).fetchall()
    finally:
        connection.close()

    if limit > 0:
        rows = rows[:limit]
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for row in rows:
        records.append(
            {
                "database_id": row["id"],
                "name": row["name"],
                "city": row["city"],
                "district": row["district"],
                "state": row["state"],
                "website": row["website"],
                "description": row["description"],
                "existing_institution_type": row["institution_type"],
                "existing_categories": sorted(filter(None, (row["categories"] or "").split(","))),
                "career_nodes": sorted(filter(None, (row["career_nodes"] or "").split(","))),
                "review_status": "pending_official_review",
            }
        )

    batches = []
    for offset in range(0, len(records), batch_size):
        batch_number = offset // batch_size + 1
        batch_records = records[offset : offset + batch_size]
        batch_id = f"legacy-group-{batch_number:03d}"
        payload = {
            "batch_id": batch_id,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "database": str(database),
            "selection": "Institutes without institute_classification",
            "classification_policy": "Do not infer silently; require official evidence or manual_review.",
            "records": batch_records,
        }
        (output / f"{batch_id}.json").write_text(_json(payload), encoding="utf-8")
        batches.append(
            {
                "batch_id": batch_id,
                "file": f"{batch_id}.json",
                "record_count": len(batch_records),
                "database_ids": [record["database_id"] for record in batch_records],
            }
        )

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "database": str(database),
        "selection": "Institutes without institute_classification",
        "total_records": len(records),
        "batch_size": batch_size,
        "batch_count": len(batches),
        "batches": batches,
    }
    (output / "manifest.json").write_text(_json(manifest), encoding="utf-8")
    print(f"prepared {len(records)} records in {len(batches)} batches at {output}")
    return len(records)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    if args.batch_size <= 0:
        parser.error("--batch-size must be positive")
    build(args.database, args.output, args.batch_size, args.limit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
