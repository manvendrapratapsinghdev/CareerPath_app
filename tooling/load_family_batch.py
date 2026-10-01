#!/usr/bin/env python3
"""Load one institution batch (e.g. "A1: IITs and IISc") into the database.

A batch spec (research/batches/<batch>.json) lists the institutes of one or
more families taken from an official government list. For every institute
the loader:

1. finds its existing rows by name and merges duplicates into one row,
   moving every link (career nodes, courses, categories, rankings ...);
2. inserts it if it is new, and sets its official name, city, state and
   website (city and state come from NIRF unless the spec gives them);
3. records its group, family and ownership (institute_classification) and
   the official list it was verified against (institute_verifications);
4. replaces its NIRF rankings for the snapshot year with every category it
   appears in;
5. links it to the batch's career nodes;
6. attaches department/centre rows to it as children, merging duplicates;
7. marks national summary rows ("IITs") as family records.

Nothing is written when any institute fails a check (no NIRF match, a
department that does not exist, ...). Run with --dry-run to see the report.

Usage: python3 tooling/load_family_batch.py research/batches/A1_iit_iisc.json \
           [--database path] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"

GOVERNMENT_OWNERSHIP = {"central_govt", "state_govt", "govt_aided", "ppp"}


class BatchError(Exception):
    """The batch cannot be loaded as written."""


class Claims:
    """Institute rows and names already taken by this batch."""

    def __init__(self) -> None:
        self.ids: set[int] = set()
        self.names: set[str] = set()


def normalize(name: str) -> str:
    folded = name.casefold().replace("&", " and ")
    return " ".join(re.sub(r"[^a-z0-9]+", " ", folded).split())


def institute_references(connection: sqlite3.Connection) -> list[tuple[str, str]]:
    """Every (table, column) whose foreign key points at institutes(id)."""
    tables = [
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        )
    ]
    references = []
    for table in tables:
        for key in connection.execute(f"PRAGMA foreign_key_list({table})"):
            if key[2] == "institutes":
                references.append((table, key[3]))
    return references


def merge_into(connection: sqlite3.Connection, keep: int, drop: int) -> None:
    """Move every link of institute [drop] to [keep], then delete [drop].

    The kept row also takes [drop]'s source id, website and description when
    it has none, so a later re-import still finds it by source id."""
    if keep == drop:
        raise BatchError(f"cannot merge institute {keep} into itself")
    source_id, website, description = connection.execute(
        "SELECT source_id, website, description FROM institutes WHERE id = ?", (drop,)
    ).fetchone()
    for table, column in institute_references(connection):
        connection.execute(
            f"UPDATE OR IGNORE {table} SET {column} = ? WHERE {column} = ?", (keep, drop)
        )
        connection.execute(f"DELETE FROM {table} WHERE {column} = ?", (drop,))
    connection.execute("DELETE FROM institutes WHERE id = ?", (drop,))
    connection.execute(
        "UPDATE institutes SET source_id = COALESCE(source_id, ?), "
        "website = COALESCE(website, ?), description = COALESCE(description, ?) WHERE id = ?",
        (source_id, website, description, keep),
    )


def link_count(connection: sqlite3.Connection, institute_id: int) -> int:
    return sum(
        connection.execute(
            f"SELECT COUNT(*) FROM {table} WHERE institute_id = ?", (institute_id,)
        ).fetchone()[0]
        for table in ("node_institutes", "institute_courses", "institute_categories",
                      "institute_rankings")
    )


def find_rows(connection: sqlite3.Connection, names: list[str]) -> list[int]:
    wanted = {normalize(name) for name in names}
    return [
        row_id
        for row_id, name in connection.execute("SELECT id, name FROM institutes ORDER BY id")
        if normalize(name) in wanted
    ]


def consolidate(
    connection: sqlite3.Connection,
    name: str,
    existing: list[str],
    report: dict[str, Any],
    claimed: Claims,
) -> int | None:
    """Merge the rows named [existing] (and [name]) into one; return its id.

    A row or name already claimed by another institute or department of this
    batch is never merged away: overlapping names are an error in the spec."""
    names = {normalize(n) for n in [name, *existing]}
    ids = find_rows(connection, [name, *existing])
    taken = sorted(names & claimed.names) or [
        _name_of(connection, i) for i in ids if i in claimed.ids
    ]
    if taken:
        raise BatchError(f"{name}: '{taken[0]}' already belongs to another institute in this batch")
    claimed.names |= names
    if not ids:
        return None
    exact = [i for i in ids if normalize(_name_of(connection, i)) == normalize(name)]
    keep = exact[0] if exact else max(ids, key=lambda i: (link_count(connection, i), -i))
    for drop in ids:
        if drop != keep:
            report["merged"].append(f"{_name_of(connection, drop)} -> {name}")
            merge_into(connection, keep, drop)
    return keep


def _name_of(connection: sqlite3.Connection, institute_id: int) -> str:
    return connection.execute(
        "SELECT name FROM institutes WHERE id = ?", (institute_id,)
    ).fetchone()[0]


def nirf_entries(
    snapshot: dict[str, Any], names: list[str], city: str | None = None
) -> list[dict[str, Any]]:
    """NIRF entries for one institute. Several campuses can share a name
    (Amity University), so a name found in more than one city needs [city]."""
    wanted = {normalize(name) for name in names}
    entries = [entry for entry in snapshot["entries"] if normalize(entry["name"]) in wanted]
    if city is not None:
        entries = [entry for entry in entries if normalize(entry["city"]) == normalize(city)]
    else:
        cities = {normalize(entry["city"]) for entry in entries}
        if len(cities) > 1:
            raise BatchError(f"{names[0]}: NIRF lists it in {len(cities)} cities; set nirf_city")
    categories = [entry["category"] for entry in entries]
    if len(categories) != len(set(categories)):
        raise BatchError(f"{names[0]}: more than one NIRF entry in the same category")
    return entries


def node_ids(connection: sqlite3.Connection, slugs: list[str]) -> list[int]:
    ids = []
    for slug in slugs:
        row = connection.execute("SELECT id FROM career_nodes WHERE slug = ?", (slug,)).fetchone()
        if row is None:
            raise BatchError(f"unknown career node slug: {slug}")
        ids.append(row[0])
    return ids


def describe(item: dict[str, Any], family_name: str, entries: list[dict[str, Any]],
             year: int, list_name: str, group_name: str, single: bool) -> str:
    """A short description built only from verified fields. A family with
    one member (NISER) is not "one of" itself, so it names the group."""
    if single:
        text = f"{item['name']} — {group_name}. Verified against {list_name}."
    else:
        text = f"{item['name']} is one of the {family_name}, listed in {list_name}."
    ranked = sorted(
        (e for e in entries if e["rank"] is not None), key=lambda e: e["rank"]
    )
    if ranked:
        best = ranked[0]
        text += f" NIRF {year}: rank {best['rank']} in {best['category']}."
    elif entries:
        text += f" NIRF {year}: band {entries[0]['rank_band']} in {entries[0]['category']}."
    return text


def relocate(connection: sqlite3.Connection, institute_id: int, city: str, state: str) -> None:
    """Set the official city and state. A district is never guessed, so one
    recorded for a different city or state is cleared."""
    old_city, old_state = connection.execute(
        "SELECT city, state FROM institutes WHERE id = ?", (institute_id,)
    ).fetchone()
    unchanged = (normalize(old_city or ""), normalize(old_state or "")) == (
        normalize(city), normalize(state))
    connection.execute(
        "UPDATE institutes SET city = ?, state = ?, "
        "district = CASE WHEN ? THEN district ELSE NULL END WHERE id = ?",
        (city, state, unchanged, institute_id),
    )


def classify(
    connection: sqlite3.Connection,
    institute_id: int,
    spec: dict[str, Any],
    *,
    parent_id: int | None = None,
    family_record: bool = False,
    confidence: str = "high",
) -> None:
    ownership = spec["ownership"]
    ugc = spec.get("ugc")
    if ownership in GOVERNMENT_OWNERSHIP and ugc is not None:
        raise BatchError(f"{spec['name']}: UGC check is for private institutions only")
    if ownership not in GOVERNMENT_OWNERSHIP and ugc is None:
        raise BatchError(f"{spec['name']}: private institutions need a UGC Yes/No check")
    connection.execute(
        "INSERT OR REPLACE INTO institute_classification (institute_id, group_code, "
        "family_slug, ownership, statutory_basis, admits_students, parent_institute_id, "
        "is_family_record, regulators, listed, ugc_verified, ugc_list_name, "
        "ugc_reference_id, ugc_source_url, ugc_checked_at, confidence, source_url, "
        "verified_at, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            institute_id, spec["group"], spec["family"], ownership,
            spec.get("statutory_basis"),
            # An institute still being built is listed but marked as not admitting.
            int(spec.get("admits_students", True)),
            parent_id, int(family_record),
            spec.get("regulators"),
            None if ugc is None else int(ugc["verified"]),
            None if ugc is None else ugc.get("list_name"),
            None if ugc is None else ugc.get("reference_id"),
            None if ugc is None else ugc.get("source_url"),
            None if ugc is None else spec["verified_at"],
            confidence, spec["verification"]["list_url"], spec["verified_at"],
            spec.get("notes"),
        ),
    )


def load(connection: sqlite3.Connection, batch: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    year = snapshot["metadata"]["year"]
    report: dict[str, Any] = {
        "batch": batch["batch"], "inserted": [], "updated": [], "renamed": [], "merged": [],
        "departments": [], "summary_rows": [], "rankings": 0, "node_links": 0,
    }
    family_names = dict(connection.execute("SELECT slug, name FROM families"))
    group_names = dict(connection.execute("SELECT code, name FROM institution_groups"))
    defaults = batch.get("defaults", {})
    claimed = Claims()

    for raw in batch["institutes"]:
        item = {**defaults, **raw, "verified_at": batch["verified_at"]}
        item["verification"] = {**batch["verification"], **raw.get("verification", {})}
        if item["family"] not in family_names:
            raise BatchError(f"{item['name']}: unknown family {item['family']}")
        entries = nirf_entries(
            snapshot, item.get("nirf_names", [item["name"]]), item.get("nirf_city")
        )
        if not entries and item.get("nirf", True):
            raise BatchError(f"{item['name']}: no NIRF {year} entry matches")
        located = next((e for e in entries if e["nirf_institute_id"]), entries[0] if entries else None)
        city = item.get("city") or (located or {}).get("city")
        state = item.get("state") or (located or {}).get("state")
        if not city or not state:
            raise BatchError(f"{item['name']}: no city/state")

        institute_id = consolidate(
            connection, item["name"], item.get("existing", []), report, claimed
        )
        if institute_id is None:
            connection.execute(
                # source_id stays NULL: it marks rows from the state research
                # imports; a batch row is traced by its verification record.
                "INSERT INTO institutes (name, city, state, website, description, "
                "institution_type) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    item["name"], city, state, item.get("website"),
                    describe(item, family_names[item["family"]], entries, year,
                             item["verification"]["list_name"], group_names[item["group"]],
                             batch.get("families", {}).get(item["family"], {})
                             .get("national_count") == 1),
                    item.get("legacy_type"),
                ),
            )
            institute_id = connection.execute("SELECT last_insert_rowid()").fetchone()[0]
            report["inserted"].append(item["name"])
        else:
            old_name = _name_of(connection, institute_id)
            if old_name != item["name"]:
                # Short names disappear from the data; add search aliases for them.
                report["renamed"].append(f"{old_name} -> {item['name']}")
            relocate(connection, institute_id, city, state)
            connection.execute(
                "UPDATE institutes SET name = ?, website = COALESCE(?, website), "
                "institution_type = COALESCE(?, institution_type) WHERE id = ?",
                # An unknown website is never guessed; a known one is kept.
                (item["name"], item.get("website"), item.get("legacy_type"), institute_id),
            )
            report["updated"].append(item["name"])
        connection.execute(
            "UPDATE institutes SET institution_type_source_url = ?, "
            "institution_type_confidence = 'high', institution_type_verified_at = ?, "
            "institution_type_notes = ? WHERE id = ?",
            (item["verification"]["list_url"], batch["verified_at"],
             f"Verified against {item['verification']['list_name']} (batch {batch['batch']}).",
             institute_id),
        )
        claimed.ids.add(institute_id)

        # A status that rests on an old or partial source is not "high".
        classify(connection, institute_id, item, confidence=item.get("confidence", "high"))
        verification = item["verification"]
        connection.execute(
            "INSERT OR REPLACE INTO institute_verifications (institute_id, authority, "
            "list_name, list_url, list_as_of, reference_id, verified_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (institute_id, verification["authority"], verification["list_name"],
             verification["list_url"], verification.get("list_as_of"),
             item.get("reference_id"), batch["verified_at"]),
        )

        connection.execute(
            "DELETE FROM institute_rankings WHERE institute_id = ? AND system = 'NIRF' AND year = ?",
            (institute_id, year),
        )
        for entry in entries:
            connection.execute(
                "INSERT INTO institute_rankings (institute_id, system, year, category, "
                "nirf_institute_id, rank, rank_band, score, source_url) "
                "VALUES (?, 'NIRF', ?, ?, ?, ?, ?, ?, ?)",
                (institute_id, year, entry["category"], entry["nirf_institute_id"],
                 entry["rank"], entry["rank_band"], entry["score"], entry["source_url"]),
            )
            report["rankings"] += 1

        for node_id in node_ids(connection, item.get("nodes", [])):
            cursor = connection.execute(
                "INSERT OR IGNORE INTO node_institutes (node_id, institute_id) VALUES (?, ?)",
                (node_id, institute_id),
            )
            report["node_links"] += cursor.rowcount

        for department in item.get("departments", []):
            if isinstance(department, str):
                department = {"name": department}
            department_id = consolidate(
                connection, department["name"], department.get("existing", []), report, claimed
            )
            if department_id is None:
                raise BatchError(f"{item['name']}: department not found: {department['name']}")
            # A department at another campus (IIM Lucknow's Noida campus) keeps its place.
            relocate(connection, department_id, department.get("city", city),
                     department.get("state", state))
            # Departments come from earlier curated research, not the official list.
            classify(connection, department_id, {**item, "name": department["name"]},
                     parent_id=institute_id, confidence="medium")
            claimed.ids.add(department_id)
            report["departments"].append(f"{department['name']} -> {item['name']}")

    for summary in batch.get("summary_rows", []):
        ids = find_rows(connection, [summary["name"]])
        if not ids:
            raise BatchError(f"summary row not found: {summary['name']}")
        if ids[0] in claimed.ids or normalize(summary["name"]) in claimed.names:
            raise BatchError(f"summary row {summary['name']} is also a listed institute")
        spec = {**defaults, **summary, "verified_at": batch["verified_at"],
                "verification": batch["verification"]}
        classify(connection, ids[0], spec, family_record=True)
        report["summary_rows"].append(summary["name"])

    for slug, family in batch.get("families", {}).items():
        connection.execute(
            "UPDATE families SET national_count = ?, national_count_as_of = ?, "
            "official_list_url = ? WHERE slug = ?",
            (family["national_count"], family["as_of"], family["official_list_url"], slug),
        )
        listed = connection.execute(
            "SELECT COUNT(*) FROM institute_classification WHERE family_slug = ? "
            "AND parent_institute_id IS NULL AND is_family_record = 0",
            (slug,),
        ).fetchone()[0]
        if listed != family["national_count"]:
            raise BatchError(
                f"family {slug}: {listed} institutes loaded, official count is "
                f"{family['national_count']}"
            )
    problems = connection.execute("PRAGMA foreign_key_check").fetchall()
    if problems:
        raise BatchError(f"foreign key problems: {problems[:5]}")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("batch", type=Path)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    batch = json.loads(args.batch.read_text(encoding="utf-8"))
    snapshot = json.loads((REPO_ROOT / batch["nirf_snapshot"]).read_text(encoding="utf-8"))
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        connection.execute("BEGIN")
        report = load(connection, batch, snapshot)
        if args.dry_run:
            connection.rollback()
        else:
            connection.commit()
    except (BatchError, sqlite3.Error) as error:
        connection.rollback()
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    finally:
        connection.close()
    print(json.dumps(report, ensure_ascii=False, indent=1))
    print("(dry run: nothing written)" if args.dry_run else "written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
