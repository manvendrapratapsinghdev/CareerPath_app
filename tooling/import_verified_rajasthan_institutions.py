#!/usr/bin/env python3
"""Import verified Rajasthan institutions into the bundled app database.

The import is deliberately strict: an institution is eligible only when its
website, district, description, and course catalogue were verified from its
official website. Removal candidates and manual-review inventory records are
never written to the app database.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"
DEFAULT_VERIFICATIONS = (
    REPO_ROOT / "research/rajasthan_institution_verifications.json"
)
DEFAULT_INVENTORY = REPO_ROOT / "research/rajasthan_nirf_master_inventory.json"

VERIFIED_COURSE_STATUSES = {"verified", "verified_programme_family"}
REQUIRED_INSTITUTION_STATUSES = {
    "record_status": "verified",
    "website_verification_status": "verified",
    "district_verification_status": "verified_official_website",
    "description_verification_status": "verified_official_website",
    "course_catalogue_status": "verified_official_website",
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return payload


def verified_records(payload: dict[str, Any]) -> list[dict[str, Any]]:
    records = payload.get("institutions")
    if not isinstance(records, list):
        raise ValueError("Verification payload must contain an institutions list")

    verified: list[dict[str, Any]] = []
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("Every verification record must be an object")
        if all(record.get(key) == value for key, value in REQUIRED_INSTITUTION_STATUSES.items()):
            verified.append(record)
    return verified


def ensure_columns(connection: sqlite3.Connection) -> None:
    columns = {
        row["name"]
        for row in connection.execute("PRAGMA table_info(institutes)")
    }
    additions = {
        "source_id": "TEXT",
        "district": "TEXT",
        "state": "TEXT",
    }
    for name, data_type in additions.items():
        if name not in columns:
            connection.execute(
                f"ALTER TABLE institutes ADD COLUMN {name} {data_type}"
            )


def ensure_course_columns(connection: sqlite3.Connection) -> None:
    columns = {
        row["name"]
        for row in connection.execute("PRAGMA table_info(institute_courses)")
    }
    if "mapping_gap" not in columns:
        connection.execute(
            "ALTER TABLE institute_courses ADD COLUMN mapping_gap TEXT"
        )


def ensure_schema(connection: sqlite3.Connection) -> None:
    ensure_columns(connection)
    connection.executescript(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_institutes_source_id
            ON institutes(source_id)
            WHERE source_id IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_institutes_location
            ON institutes(state, district, city);

        CREATE TABLE IF NOT EXISTS institute_courses (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id           TEXT UNIQUE NOT NULL,
            institute_id        INTEGER NOT NULL
                                    REFERENCES institutes(id)
                                    ON DELETE CASCADE,
            name                TEXT NOT NULL,
            level               TEXT NOT NULL,
            credential          TEXT,
            specialization      TEXT,
            duration            TEXT,
            mode                TEXT,
            eligibility         TEXT,
            official_course_url TEXT NOT NULL,
            verification_status TEXT NOT NULL,
            mapping_gap         TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_institute_courses_institute
            ON institute_courses(institute_id);

        CREATE TABLE IF NOT EXISTS course_career_nodes (
            course_id      INTEGER NOT NULL
                               REFERENCES institute_courses(id)
                               ON DELETE CASCADE,
            node_id        INTEGER NOT NULL
                               REFERENCES career_nodes(id)
                               ON DELETE CASCADE,
            relation       TEXT NOT NULL,
            confidence     TEXT NOT NULL,
            mapping_status TEXT NOT NULL,
            PRIMARY KEY (course_id, node_id)
        );
        CREATE INDEX IF NOT EXISTS idx_course_career_nodes_node
            ON course_career_nodes(node_id);

        CREATE TABLE IF NOT EXISTS institute_categories (
            institute_id INTEGER NOT NULL
                             REFERENCES institutes(id)
                             ON DELETE CASCADE,
            category     TEXT NOT NULL,
            PRIMARY KEY (institute_id, category)
        );

        CREATE TABLE IF NOT EXISTS institute_rankings (
            institute_id      INTEGER NOT NULL
                                  REFERENCES institutes(id)
                                  ON DELETE CASCADE,
            system            TEXT NOT NULL,
            year              INTEGER NOT NULL,
            category          TEXT NOT NULL,
            nirf_institute_id TEXT,
            rank              INTEGER,
            rank_band         TEXT,
            score             REAL,
            source_url        TEXT NOT NULL,
            PRIMARY KEY (institute_id, system, year, category)
        );
        CREATE INDEX IF NOT EXISTS idx_institute_rankings_order
            ON institute_rankings(year, category, rank, rank_band);
        """
    )
    ensure_course_columns(connection)


def validate_record(
    record: dict[str, Any],
    inventory_record: dict[str, Any],
    career_nodes: dict[int, str],
) -> None:
    institution_id = record.get("id")
    for field in ("district", "official_website", "description"):
        if not isinstance(record.get(field), str) or not record[field].strip():
            raise ValueError(f"{institution_id}: verified record has no {field}")

    courses = record.get("courses")
    if not isinstance(courses, list) or not courses:
        raise ValueError(f"{institution_id}: verified record has no courses")

    seen_course_ids: set[str] = set()
    for course in courses:
        if not isinstance(course, dict):
            raise ValueError(f"{institution_id}: course must be an object")
        course_id = course.get("course_id")
        if not isinstance(course_id, str) or not course_id:
            raise ValueError(f"{institution_id}: course has no stable course_id")
        if course_id in seen_course_ids:
            raise ValueError(f"{institution_id}: duplicate course {course_id}")
        seen_course_ids.add(course_id)
        if course.get("verification_status") not in VERIFIED_COURSE_STATUSES:
            raise ValueError(
                f"{institution_id}/{course_id}: unverified course status "
                f"{course.get('verification_status')!r}"
            )
        for field in ("name", "level", "official_course_url"):
            if not isinstance(course.get(field), str) or not course[field].strip():
                raise ValueError(
                    f"{institution_id}/{course_id}: missing {field}"
                )
        mappings = course.get("career_path_mappings")
        if not isinstance(mappings, list):
            raise ValueError(
                f"{institution_id}/{course_id}: mappings must be a list"
            )
        for mapping in mappings:
            node_id = mapping.get("career_node_id")
            if node_id not in career_nodes:
                raise ValueError(
                    f"{institution_id}/{course_id}: unknown career node {node_id}"
                )
            if mapping.get("career_node_slug") != career_nodes[node_id]:
                raise ValueError(
                    f"{institution_id}/{course_id}: career node slug mismatch"
                )

    if inventory_record.get("id") != institution_id:
        raise ValueError(f"{institution_id}: inventory identity mismatch")


def exact_existing_institute_id(inventory_record: dict[str, Any]) -> int | None:
    matches = [
        match["id"]
        for match in inventory_record.get("existing_database_records", [])
        if match.get("match_method") == "identity_key"
        and isinstance(match.get("id"), int)
    ]
    if len(matches) > 1:
        raise ValueError(
            f"{inventory_record['id']}: multiple exact existing institutes"
        )
    return matches[0] if matches else None


def normalized_name(value: str) -> str:
    return " ".join(value.replace(",", ", ").replace(" -", " - ").split())


def upsert_institute(
    connection: sqlite3.Connection,
    record: dict[str, Any],
    inventory_record: dict[str, Any],
) -> int:
    existing = connection.execute(
        "SELECT id FROM institutes WHERE source_id = ?",
        (record["id"],),
    ).fetchone()
    institute_id = (
        existing["id"]
        if existing is not None
        else exact_existing_institute_id(inventory_record)
    )
    values = (
        normalized_name(inventory_record["nirf_name"]),
        inventory_record["nirf_city"],
        record["official_website"],
        record["description"],
        record["id"],
        record["district"],
        inventory_record["state"],
    )
    if institute_id is None:
        cursor = connection.execute(
            """
            INSERT INTO institutes(
                name, city, website, description, source_id, district, state
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            values,
        )
        return int(cursor.lastrowid)

    connection.execute(
        """
        UPDATE institutes
        SET name = ?, city = ?, website = ?, description = ?,
            source_id = ?, district = ?, state = ?
        WHERE id = ?
        """,
        (*values, institute_id),
    )
    return int(institute_id)


def replace_institute_details(
    connection: sqlite3.Connection,
    institute_id: int,
    record: dict[str, Any],
    inventory_record: dict[str, Any],
) -> tuple[int, int]:
    connection.execute(
        "DELETE FROM institute_courses WHERE institute_id = ?",
        (institute_id,),
    )
    connection.execute(
        "DELETE FROM institute_categories WHERE institute_id = ?",
        (institute_id,),
    )
    connection.execute(
        "DELETE FROM institute_rankings WHERE institute_id = ?",
        (institute_id,),
    )

    for category in inventory_record.get("participating_categories", []):
        connection.execute(
            """
            INSERT INTO institute_categories(institute_id, category)
            VALUES (?, ?)
            """,
            (institute_id, category),
        )

    for ranking in inventory_record.get("rankings", []):
        connection.execute(
            """
            INSERT INTO institute_rankings(
                institute_id, system, year, category, nirf_institute_id,
                rank, rank_band, score, source_url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                institute_id,
                ranking["system"],
                ranking["year"],
                ranking["category"],
                ranking.get("nirf_institute_id"),
                ranking.get("rank"),
                ranking.get("rank_band"),
                ranking.get("score"),
                ranking["source"],
            ),
        )

    course_count = 0
    mapping_count = 0
    for course in record["courses"]:
        cursor = connection.execute(
            """
            INSERT INTO institute_courses(
                source_id, institute_id, name, level, credential,
                specialization, duration, mode, eligibility,
                official_course_url, verification_status, mapping_gap
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                course["course_id"],
                institute_id,
                course["name"],
                course["level"],
                course.get("credential"),
                course.get("specialization"),
                course.get("duration"),
                course.get("mode"),
                course.get("eligibility"),
                course["official_course_url"],
                course["verification_status"],
                course.get("mapping_gap"),
            ),
        )
        course_row_id = int(cursor.lastrowid)
        course_count += 1
        for mapping in course["career_path_mappings"]:
            connection.execute(
                """
                INSERT INTO course_career_nodes(
                    course_id, node_id, relation, confidence, mapping_status
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    course_row_id,
                    mapping["career_node_id"],
                    mapping["relation"],
                    mapping["confidence"],
                    mapping["mapping_status"],
                ),
            )
            connection.execute(
                """
                INSERT OR IGNORE INTO node_institutes(node_id, institute_id)
                VALUES (?, ?)
                """,
                (mapping["career_node_id"], institute_id),
            )
            mapping_count += 1
    return course_count, mapping_count


def import_verified(
    database_path: Path,
    verification_path: Path,
    inventory_path: Path,
) -> dict[str, int]:
    verification_payload = load_json(verification_path)
    inventory_payload = load_json(inventory_path)
    records = verified_records(verification_payload)
    inventory = {
        item["id"]: item for item in inventory_payload.get("institutions", [])
    }

    connection = sqlite3.connect(database_path)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        baseline_foreign_key_errors = {
            tuple(row) for row in connection.execute("PRAGMA foreign_key_check")
        }
        connection.execute("BEGIN IMMEDIATE")
        ensure_schema(connection)
        career_nodes = {
            row["id"]: row["slug"]
            for row in connection.execute("SELECT id, slug FROM career_nodes")
        }

        institution_count = 0
        course_count = 0
        mapping_count = 0
        for record in sorted(records, key=lambda item: item["id"]):
            inventory_record = inventory.get(record["id"])
            if inventory_record is None:
                raise ValueError(f"{record['id']}: missing inventory record")
            validate_record(record, inventory_record, career_nodes)
            institute_id = upsert_institute(
                connection, record, inventory_record
            )
            courses, mappings = replace_institute_details(
                connection, institute_id, record, inventory_record
            )
            institution_count += 1
            course_count += courses
            mapping_count += mappings

        foreign_key_errors = {
            tuple(row) for row in connection.execute("PRAGMA foreign_key_check")
        }
        new_foreign_key_errors = (
            foreign_key_errors - baseline_foreign_key_errors
        )
        if new_foreign_key_errors:
            raise ValueError(
                "Import introduced foreign-key errors: "
                f"{sorted(new_foreign_key_errors)[:5]}"
            )
        connection.execute("PRAGMA user_version = 1")
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    return {
        "institutions": institution_count,
        "courses": course_count,
        "career_mappings": mapping_count,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument(
        "--verifications", type=Path, default=DEFAULT_VERIFICATIONS
    )
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = import_verified(
        args.database.resolve(),
        args.verifications.resolve(),
        args.inventory.resolve(),
    )
    print(
        "Imported "
        f"{summary['institutions']} verified institutions, "
        f"{summary['courses']} verified courses, and "
        f"{summary['career_mappings']} career mappings."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
