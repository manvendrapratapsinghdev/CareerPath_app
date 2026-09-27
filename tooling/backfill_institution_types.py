#!/usr/bin/env python3
"""Backfill database institution types from source inventory metadata."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any


def load_types(path: Path) -> dict[str, str]:
    payload: Any = json.loads(path.read_text(encoding="utf-8"))
    records = payload if isinstance(payload, list) else payload.get("institutions")
    if not isinstance(records, list):
        raise ValueError(f"{path}: expected an institutions list")
    types: dict[str, str] = {}
    for index, record in enumerate(records, start=1):
        if not isinstance(record, dict):
            raise ValueError(f"{path}: institution {index} is not an object")
        source_id = record.get("id")
        institution_type = record.get("institution_type")
        if not isinstance(source_id, str) or not source_id.strip():
            raise ValueError(f"{path}: institution {index} has no id")
        if not isinstance(institution_type, str) or not institution_type.strip():
            raise ValueError(f"{path}: {source_id} has no institution_type")
        existing = types.get(source_id)
        if existing is not None and existing != institution_type.strip():
            raise ValueError(f"{source_id}: conflicting institution_type values")
        types[source_id] = institution_type.strip()
    return types


def backfill(database: Path, inventories: list[Path]) -> tuple[int, int]:
    types: dict[str, str] = {}
    for inventory in inventories:
        types.update(load_types(inventory))

    connection = sqlite3.connect(database)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        columns = {
            row[1] for row in connection.execute("PRAGMA table_info(institutes)")
        }
        connection.execute("BEGIN IMMEDIATE")
        if "institution_type" not in columns:
            connection.execute("ALTER TABLE institutes ADD COLUMN institution_type TEXT")
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_institutes_type "
            "ON institutes(institution_type)"
        )
        updated = 0
        for source_id, institution_type in sorted(types.items()):
            updated += connection.execute(
                "UPDATE institutes SET institution_type = ? WHERE source_id = ?",
                (institution_type, source_id),
            ).rowcount
        connection.commit()
        return updated, len(types)
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, action="append", required=True)
    args = parser.parse_args()
    updated, source_count = backfill(
        args.database.resolve(), [path.resolve() for path in args.inventory]
    )
    print(f"Backfilled {updated} database rows from {source_count} source records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
