#!/usr/bin/env python3
"""Import the LGD state/district master and safely link legacy institute locations.

The LGD source CSVs are comma-delimited snapshots from the Ministry of
Panchayati Raj Local Government Directory. Institute locations are linked only
when the existing institute row names a state, district, and specific city that
match the official district master. Missing or conflicting locations are
written to a review CSV instead of being inferred.

Usage:
  python3 tooling/import_locations.py \
    --states-csv /path/to/states.31May2026.csv \
    --districts-csv /path/to/districts.31May2026.csv
"""

from __future__ import annotations

import argparse
import csv
import re
import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"
DEFAULT_REVIEW = REPO_ROOT / "research/location_review.csv"

PLACE_ALIASES = {
    "bangalore": "Bengaluru",
    "bombay": "Mumbai",
    "gurgaon": "Gurugram",
    "allahabad": "Prayagraj",
    "calcutta": "Kolkata",
    "madras": "Chennai",
    "trivandrum": "Thiruvananthapuram",
    "baroda": "Vadodara",
    "poona": "Pune",
    "cochin": "Kochi",
    "mysore": "Mysuru",
    "benares": "Varanasi",
    "benaras": "Varanasi",
}

STATE_ALIASES = {
    "andaman nicobar islands": "andaman and nicobar islands",
    "dadra nagar haveli daman diu": "dadra and nagar haveli and daman and diu",
    "jammu kashmir": "jammu and kashmir",
    "nct delhi": "delhi",
    "orissa": "odisha",
    "pondicherry": "puducherry",
    "uttaranchal": "uttarakhand",
    "the dadra and nagar haveli and daman and diu": "dadra and nagar haveli and daman and diu",
}

GENERIC_CITIES = {
    "all india",
    "all campuses",
    "india",
    "multiple locations",
    "nationwide",
    "online",
    "various",
}


@dataclass(frozen=True)
class LgdState:
    lgd_code: int
    name: str
    kind: str


@dataclass(frozen=True)
class LgdDistrict:
    lgd_code: int
    state_lgd_code: int
    name: str


def normalize_name(value: str | None) -> str:
    """Case/punctuation-insensitive key used only for exact name matching."""
    if not value:
        return ""
    decomposed = unicodedata.normalize("NFKD", value)
    ascii_text = "".join(char for char in decomposed if not unicodedata.combining(char))
    return " ".join(re.sub(r"[^a-z0-9]+", " ", ascii_text.casefold()).split())


def display_name(value: str) -> str:
    """Make the all-caps LGD export readable while preserving numeric prefixes."""
    return " ".join(part[:1].upper() + part[1:].lower() for part in value.strip().split())


def _field(row: dict[str, str], *names: str) -> str:
    for name in names:
        value = row.get(name)
        if value is not None:
            return value.strip()
    raise ValueError(f"LGD CSV is missing expected column; tried {names!r}")


def _state_kind(row: dict[str, str]) -> str:
    value = _field(row, "State or UT", "State/UT", "State or UT Name").strip().casefold()
    if value in {"u", "ut", "union territory"}:
        return "ut"
    if value in {"s", "state"}:
        return "state"
    raise ValueError(f"Unexpected LGD state/UT type: {value!r}")


def read_states(path: Path) -> list[LgdState]:
    with path.open(encoding="utf-8-sig", newline="") as source:
        rows = csv.DictReader(source)
        result = [
            LgdState(
                lgd_code=int(_field(row, "State Code", "State LGD Code")),
                name=_field(row, "State Name (In English)", "State Name(In English)"),
                kind=_state_kind(row),
            )
            for row in rows
        ]
    codes = [row.lgd_code for row in result]
    if not result or len(codes) != len(set(codes)):
        raise ValueError("LGD state CSV is empty or contains duplicate state codes")
    return result


def read_districts(path: Path) -> list[LgdDistrict]:
    with path.open(encoding="utf-8-sig", newline="") as source:
        rows = csv.DictReader(source)
        result = [
            LgdDistrict(
                lgd_code=int(_field(row, "District Code", "District LGD Code")),
                state_lgd_code=int(_field(row, "State Code", "State LGD Code")),
                name=_field(row, "District Name(In English)", "District Name (In English)"),
            )
            for row in rows
        ]
    codes = [row.lgd_code for row in result]
    if not result or 0 in codes or len(codes) != len(set(codes)):
        raise ValueError("LGD district CSV is empty or has invalid/duplicate district codes")
    return result


def import_lgd_master(
    connection: sqlite3.Connection,
    states: Iterable[LgdState],
    districts: Iterable[LgdDistrict],
    *,
    require_complete_states: bool = True,
) -> tuple[int, int]:
    """Validate source codes against seeded states and idempotently upsert LGD districts."""
    states = list(states)
    districts = list(districts)
    app_states = {
        int(lgd_code): (code, name, kind)
        for code, lgd_code, name, kind in connection.execute(
            "SELECT code, lgd_code, name, kind FROM states"
        )
    }
    source_codes = {row.lgd_code for row in states}
    if require_complete_states and (len(states) != 36 or source_codes != set(app_states)):
        raise ValueError(
            f"Expected all 36 seeded LGD state/UT codes; source has {len(states)} rows"
        )
    if not source_codes.issubset(app_states):
        missing = sorted(source_codes - set(app_states))
        raise ValueError(f"LGD state codes are not seeded in the app database: {missing}")

    for row in states:
        _, app_name, app_kind = app_states[row.lgd_code]
        source_name = normalize_name(row.name)
        source_name = STATE_ALIASES.get(source_name, source_name)
        if source_name != normalize_name(app_name):
            raise ValueError(
                f"State name/code mismatch for LGD {row.lgd_code}: "
                f"source={row.name!r}, app={app_name!r}"
            )
        if row.kind != app_kind:
            raise ValueError(
                f"State type/code mismatch for LGD {row.lgd_code}: "
                f"source={row.kind!r}, app={app_kind!r}"
            )

    unknown_state_codes = sorted(
        {row.state_lgd_code for row in districts} - source_codes
    )
    if unknown_state_codes:
        raise ValueError(f"District rows refer to unknown LGD state codes: {unknown_state_codes}")

    for district in districts:
        if not district.name.strip():
            raise ValueError(f"District {district.lgd_code} has an empty name")

    state_map = {code: app_states[code][0] for code in source_codes}
    connection.executemany(
        "INSERT INTO districts (lgd_code, state_code, name) VALUES (?, ?, ?) "
        "ON CONFLICT(lgd_code) DO UPDATE SET state_code = excluded.state_code, "
        "name = excluded.name",
        [
            (row.lgd_code, state_map[row.state_lgd_code], display_name(row.name))
            for row in districts
        ],
    )
    return len(states), len(districts)


def _state_index(connection: sqlite3.Connection) -> dict[str, str]:
    result = {}
    for code, name in connection.execute("SELECT code, name FROM states"):
        key = normalize_name(name)
        result[key] = code
        result[normalize_name(code.replace("IN-", ""))] = code
    for alias, canonical in STATE_ALIASES.items():
        match = result.get(canonical)
        if match:
            result[alias] = match
    return result


def _resolve_state(index: dict[str, str], name: str | None) -> str | None:
    return index.get(normalize_name(name))


def _canonical_city(value: str) -> str:
    alias_target = PLACE_ALIASES.get(normalize_name(value))
    return alias_target or display_name(value)


def _insert_place(connection: sqlite3.Connection, district_lgd: int, name: str) -> int:
    connection.execute(
        "INSERT INTO places (district_lgd, name, kind, is_district_hq) "
        "VALUES (?, ?, 'city', 0) ON CONFLICT(district_lgd, name) DO NOTHING",
        (district_lgd, name),
    )
    row = connection.execute(
        "SELECT id FROM places WHERE district_lgd = ? AND name = ?",
        (district_lgd, name),
    ).fetchone()
    if row is None:
        raise RuntimeError(f"Could not retrieve place row for {name!r} in district {district_lgd}")
    return int(row[0])


def _insert_campus(connection: sqlite3.Connection, institute_id: int, place_id: int) -> bool:
    existing = connection.execute(
        "SELECT id, place_id, name FROM campuses WHERE institute_id = ?",
        (institute_id,),
    ).fetchall()
    if existing:
        if any(row[1] == place_id and row[2] is None for row in existing):
            return False
        raise ValueError(f"Institute {institute_id} already has a different campus mapping")
    connection.execute(
        "INSERT INTO campuses (institute_id, name, place_id, is_main, source_url, verified_at) "
        "VALUES (?, NULL, ?, 1, NULL, NULL)",
        (institute_id, place_id),
    )
    return True


def populate_institute_campuses(
    connection: sqlite3.Connection,
    review_path: Path,
) -> tuple[int, int, int]:
    """Create places/campuses only for exact legacy state+district+city locations."""
    state_index = _state_index(connection)
    district_index = {
        (state_code, normalize_name(name)): int(lgd_code)
        for lgd_code, state_code, name in connection.execute(
            "SELECT lgd_code, state_code, name FROM districts"
        )
    }
    rows = connection.execute(
        "SELECT i.id, i.name, i.city, i.district, i.state, "
        "       c.is_family_record, c.listed, c.admits_students, c.parent_institute_id, i.website "
        "FROM institutes AS i "
        "LEFT JOIN institute_classification AS c ON c.institute_id = i.id "
        "ORDER BY i.id"
    ).fetchall()

    review: list[dict[str, str]] = []
    direct: dict[int, tuple[int, str, str | None]] = {}
    skipped_summary = 0

    for row in rows:
        institute_id, name, city, district, state = row[:5]
        is_family_record, listed, admits_students, _, website = row[5:]
        city = (city or "").strip()
        district = (district or "").strip()
        state = (state or "").strip()
        if normalize_name(city) in GENERIC_CITIES or is_family_record == 1:
            skipped_summary += 1
            continue
        if listed == 0 or admits_students == 0:
            skipped_summary += 1
            continue

        reason = ""
        state_code = _resolve_state(state_index, state)
        if not state_code:
            reason = "missing_or_unmatched_state"
        elif not city:
            reason = "missing_city"
        elif not district:
            reason = "missing_explicit_district"

        district_lgd = None
        if not reason:
            district_lgd = district_index.get((state_code, normalize_name(district)))
            if district_lgd is None:
                reason = "district_not_found_in_current_lgd"

        if reason:
            review.append(
                {
                    "institute_id": str(institute_id),
                    "institute_name": name or "",
                    "city": city,
                    "district": district,
                    "state": state,
                    "reason": reason,
                    "institute_website_for_review": website or "",
                }
            )
            continue

        city_name = _canonical_city(city)
        place_id = _insert_place(connection, district_lgd, city_name)
        try:
            _insert_campus(connection, institute_id, place_id)
        except ValueError as exc:
            review.append(
                {
                    "institute_id": str(institute_id),
                    "institute_name": name or "",
                    "city": city,
                    "district": district,
                    "state": state,
                    "reason": "conflicting_existing_campus_mapping",
                    "institute_website_for_review": website or "",
                }
            )
            continue
        direct[int(institute_id)] = (place_id, city_name, website or None)

    # A child institution may inherit a campus only through its explicit parent FK.
    # Conflicting child location data remains in the review sheet.
    child_rows = connection.execute(
        "SELECT i.id, i.name, i.city, i.district, i.state, c.parent_institute_id, i.website "
        "FROM institutes AS i JOIN institute_classification AS c ON c.institute_id = i.id "
        "WHERE c.parent_institute_id IS NOT NULL AND COALESCE(c.is_family_record, 0) = 0 "
        "AND COALESCE(c.listed, 1) = 1 AND COALESCE(c.admits_students, 1) = 1"
    ).fetchall()
    inherited_count = 0
    for institute_id, name, city, district, state, parent_id, website in child_rows:
        parent = direct.get(int(parent_id))
        if not parent:
            continue
        child_city = (city or "").strip()
        child_district = (district or "").strip()
        child_state = (state or "").strip()
        if child_city and normalize_name(child_city) not in GENERIC_CITIES:
            if _canonical_city(child_city) != parent[1]:
                continue
        if child_district and normalize_name(child_district) != normalize_name(
            connection.execute(
                "SELECT name FROM districts WHERE lgd_code = (SELECT district_lgd FROM places WHERE id = ?)",
                (parent[0],),
            ).fetchone()[0]
        ):
            continue
        parent_state = connection.execute(
            "SELECT state_code FROM districts WHERE lgd_code = (SELECT district_lgd FROM places WHERE id = ?)",
            (parent[0],),
        ).fetchone()[0]
        if child_state and _resolve_state(state_index, child_state) != parent_state:
            continue
        try:
            if _insert_campus(connection, int(institute_id), parent[0]):
                inherited_count += 1
        except ValueError:
            review.append(
                {
                    "institute_id": str(institute_id),
                    "institute_name": name or "",
                    "city": child_city,
                    "district": child_district,
                    "state": child_state,
                    "reason": "conflicting_existing_campus_mapping",
                    "institute_website_for_review": website or "",
                }
            )
        else:
            review = [entry for entry in review if entry["institute_id"] != str(institute_id)]

    # Add the plan's known former city names only when the canonical place is
    # present exactly once. Ambiguous cross-state matches are deliberately omitted.
    for alias, canonical in PLACE_ALIASES.items():
        targets = connection.execute(
            "SELECT id FROM places WHERE lower(name) = lower(?)",
            (canonical,),
        ).fetchall()
        if len(targets) != 1:
            continue
        alias_key = " ".join(alias.casefold().split())
        existing = connection.execute(
            "SELECT place_id, district_lgd, state_code FROM place_aliases WHERE alias = ?",
            (alias_key,),
        ).fetchone()
        if existing:
            if existing[0] == targets[0][0] and existing[1] is None and existing[2] is None:
                continue
            continue
        # Do not make a canonical place name resolve to a different place.
        canonical_name_exists = connection.execute(
            "SELECT 1 FROM places WHERE lower(name) = lower(?) LIMIT 1", (alias_key,)
        ).fetchone()
        if canonical_name_exists:
            continue
        connection.execute(
            "INSERT INTO place_aliases (alias, place_id, district_lgd, state_code) "
            "VALUES (?, ?, NULL, NULL)",
            (alias_key, targets[0][0]),
        )

    review_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "institute_id",
        "institute_name",
        "city",
        "district",
        "state",
        "reason",
        "institute_website_for_review",
    ]
    with review_path.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(review)

    place_count = connection.execute("SELECT COUNT(*) FROM places").fetchone()[0]
    alias_count = connection.execute("SELECT COUNT(*) FROM place_aliases").fetchone()[0]
    campus_count = connection.execute("SELECT COUNT(*) FROM campuses").fetchone()[0]
    return place_count, campus_count, alias_count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--states-csv", type=Path, required=True)
    parser.add_argument("--districts-csv", type=Path, required=True)
    parser.add_argument("--review-csv", type=Path, default=DEFAULT_REVIEW)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    states = read_states(args.states_csv)
    districts = read_districts(args.districts_csv)
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        with connection:
            state_count, district_count = import_lgd_master(connection, states, districts)
            place_count, campus_count, alias_count = populate_institute_campuses(
                connection, args.review_csv
            )
    finally:
        connection.close()
    print(
        f"Imported {state_count} states/UTs, {district_count} districts; "
        f"database now has {place_count} places, {campus_count} campuses, "
        f"{alias_count} place aliases."
    )
    print(f"Unresolved location records: {args.review_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
