#!/usr/bin/env python3
"""Import verified, non-private legacy taxonomy classifications.

The review JSON is deliberately broader than the database import set.  This
command imports only ``classified`` rows with non-private ownership; private
and trust rows require an explicit UGC Yes/No value and are reported but not
written.  Manual-review rows are never imported.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = ROOT / "assets/data/career_path.db"
DEFAULT_SOURCE = ROOT / "research/legacy_group_batches/legacy-group-all-439.json"


def load_records(source: Path) -> list[dict]:
    payload = json.loads(source.read_text(encoding="utf-8"))
    records = payload.get("records")
    if not isinstance(records, list):
        raise ValueError(f"{source}: expected records list")
    return records


def import_records(database: Path, source: Path, apply: bool) -> dict[str, int]:
    records = load_records(source)
    eligible = [
        record
        for record in records
        if record.get("outcome") == "classified"
        and record.get("ownership") not in {"private", "trust"}
    ]
    blocked_private = sum(
        record.get("outcome") == "classified"
        and record.get("ownership") in {"private", "trust"}
        for record in records
    )
    manual_review = sum(record.get("outcome") == "manual_review" for record in records)

    connection = sqlite3.connect(database)
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        existing = {
            row[0]: row[1]
            for row in connection.execute(
                "SELECT i.id, c.institute_id FROM institutes i "
                "LEFT JOIN institute_classification c ON c.institute_id = i.id"
            )
        }
        groups = {row[0] for row in connection.execute("SELECT code FROM institution_groups")}
        families = {row[0] for row in connection.execute("SELECT slug FROM families")}
        errors: list[str] = []
        for record in eligible:
            institute_id = record.get("database_id")
            if institute_id not in existing:
                errors.append(f"{institute_id}: institute does not exist")
            elif existing[institute_id] is not None:
                errors.append(f"{institute_id}: classification already exists")
            if record.get("group_code") not in groups:
                errors.append(f"{institute_id}: invalid group_code {record.get('group_code')!r}")
            family = record.get("family_slug")
            if family is not None and family not in families:
                errors.append(f"{institute_id}: invalid family_slug {family!r}")
            if not record.get("source_url", "").startswith(("http://", "https://")):
                errors.append(f"{institute_id}: missing source_url")
            if not record.get("evidence"):
                errors.append(f"{institute_id}: missing evidence")
        if errors:
            raise ValueError("\n".join(errors))

        summary = {
            "eligible": len(eligible),
            "imported": 0,
            "blocked_private_or_trust": blocked_private,
            "manual_review": manual_review,
        }
        if not apply:
            return summary

        verified_at = datetime.now(timezone.utc).date().isoformat()
        connection.execute("BEGIN")
        for record in eligible:
            notes = [f"Evidence: {record['evidence']}"]
            notes.extend(record.get("notes") or [])
            listed = 0 if record.get("group_code") in {"G10b", "X"} or not record.get("admits_students", 1) else 1
            connection.execute(
                """
                INSERT INTO institute_classification
                  (institute_id, group_code, family_slug, ownership, statutory_basis,
                   admits_students, is_family_record, regulators, listed, confidence,
                   source_url, verified_at, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    record["database_id"], record["group_code"], record.get("family_slug"),
                    record.get("ownership"), record.get("statutory_basis"),
                    int(bool(record.get("admits_students", 1))), int(bool(record.get("is_family_record", 0))),
                    json.dumps(record.get("regulators") or [], ensure_ascii=False), listed,
                    record["confidence"], record["source_url"], verified_at, "\n".join(notes),
                ),
            )
            summary["imported"] += 1
        connection.commit()
        return summary
    except Exception:
        if apply:
            connection.rollback()
        raise
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--apply", action="store_true", help="write eligible rows; default is a dry run")
    args = parser.parse_args()
    print(json.dumps(import_records(args.database, args.source, args.apply), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
