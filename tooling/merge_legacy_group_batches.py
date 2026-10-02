#!/usr/bin/env python3
"""Validate and merge worker classification JSON without touching SQLite.

Workers may call the result list ``records`` or ``results`` and may use scalar
or list notes. This command normalizes both forms, verifies IDs/names against
the current database and writes one reviewable wave JSON. Database application
is intentionally a separate, approval-gated operation.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = ROOT / "assets/data/career_path.db"
DEFAULT_RESULTS = ROOT / "research/legacy_group_batches/results"
DEFAULT_OUTPUT = ROOT / "research/legacy_group_batches/legacy-group-wave-01.json"
GROUPS = {
    "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9",
    "G10a", "G10b", "G11", "X",
}
OWNERSHIPS = {None, "central_govt", "state_govt", "govt_aided", "private", "trust", "ppp"}


def load_records(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    records = payload.get("records", payload.get("results"))
    if not isinstance(records, list):
        raise ValueError(f"{path}: expected records or results list")
    return records


def merge(database: Path, result_paths: list[Path], output: Path) -> dict:
    connection = sqlite3.connect(f"file:{database.resolve()}?mode=ro", uri=True)
    try:
        expected = {
            row[0]: row[1]
            for row in connection.execute(
                """
                SELECT i.id, i.name
                FROM institutes i
                LEFT JOIN institute_classification c ON c.institute_id = i.id
                WHERE c.institute_id IS NULL
                """
            )
        }
        groups = {row[0] for row in connection.execute("SELECT code FROM institution_groups")}
        families = {row[0] for row in connection.execute("SELECT slug FROM families")}
    finally:
        connection.close()

    merged: list[dict] = []
    seen: set[int] = set()
    errors: list[str] = []
    for path in result_paths:
        input_path = path.parent.parent / path.name
        if not input_path.exists():
            errors.append(f"{path}: matching input batch is missing: {input_path}")
            continue
        input_records = load_records(input_path)
        expected_batch = {record["database_id"]: record["name"] for record in input_records}
        batch_seen: set[int] = set()
        for record in load_records(path):
            database_id = record.get("database_id")
            if not isinstance(database_id, int):
                errors.append(f"{path}: invalid database_id {database_id!r}")
                continue
            if database_id in seen:
                errors.append(f"duplicate database_id {database_id} from {path}: {database_id}")
                continue
            seen.add(database_id)
            batch_seen.add(database_id)
            if database_id not in expected_batch:
                errors.append(f"{path}: database_id {database_id} is not in its input batch")
            elif record.get("name") != expected_batch[database_id]:
                errors.append(f"{path}: database_id {database_id}: name does not match input batch")
            if database_id not in expected:
                errors.append(f"database_id {database_id} is not currently unclassified")
            elif record.get("name") != expected[database_id]:
                errors.append(f"database_id {database_id}: name does not match current DB")
            outcome = record.get("outcome")
            if outcome not in {"classified", "manual_review"}:
                errors.append(f"database_id {database_id}: invalid outcome {outcome!r}")
            if outcome == "classified":
                if record.get("group_code") not in GROUPS or record.get("group_code") not in groups:
                    errors.append(f"database_id {database_id}: invalid group_code")
                family = record.get("family_slug")
                if family is not None and family not in families:
                    errors.append(f"database_id {database_id}: unknown family_slug {family!r}")
                if record.get("ownership") not in OWNERSHIPS:
                    errors.append(f"database_id {database_id}: invalid ownership")
                if record.get("confidence") not in {"high", "medium", "low"}:
                    errors.append(f"database_id {database_id}: invalid confidence")
                if not isinstance(record.get("source_url"), str) or not record["source_url"].startswith(("http://", "https://")):
                    errors.append(f"database_id {database_id}: classified result needs HTTP source_url")
                if not isinstance(record.get("evidence"), str) or not record["evidence"].strip():
                    errors.append(f"database_id {database_id}: classified result needs evidence")
            else:
                for key in ("group_code", "family_slug", "ownership"):
                    if record.get(key) not in (None, "", []):
                        errors.append(f"database_id {database_id}: manual_review must not set {key}")
            notes = record.get("notes", [])
            if isinstance(notes, str):
                notes = [notes] if notes else []
            if not isinstance(notes, list) or not all(isinstance(note, str) and note for note in notes):
                errors.append(f"database_id {database_id}: notes must be a string list")
                notes = []
            normalized = dict(record)
            normalized["notes"] = notes
            normalized.setdefault("family_slug", None)
            merged.append(normalized)
        if batch_seen != set(expected_batch):
            missing = sorted(set(expected_batch) - batch_seen)
            extra = sorted(batch_seen - set(expected_batch))
            errors.append(f"{path}: input/result ID mismatch; missing={missing}, extra={extra}")

    if errors:
        raise ValueError("\n".join(errors))

    payload = {
        "wave_id": "legacy-group-wave-01",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "database": str(database),
        "selection": "Institutes without institute_classification at merge time",
        "record_count": len(merged),
        "classified_count": sum(record["outcome"] == "classified" for record in merged),
        "manual_review_count": sum(record["outcome"] == "manual_review" for record in merged),
        "source_batches": [str(path) for path in result_paths],
        "records": merged,
        "database_apply_status": "not_applied",
        "database_apply_note": "Private/trust rows still need structured UGC Yes/No evidence before import.",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--results-dir", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--batch", action="append", required=True, help="Batch number, e.g. 001")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    paths = [args.results_dir / f"legacy-group-{batch}.json" for batch in args.batch]
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        parser.error("missing result files: " + ", ".join(missing))
    payload = merge(args.database, paths, args.output)
    print(json.dumps({key: payload[key] for key in ("record_count", "classified_count", "manual_review_count")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
