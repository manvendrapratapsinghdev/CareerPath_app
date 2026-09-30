#!/usr/bin/env python3
"""Correct misspellings the source websites put into the app database.

Search matches words exactly, so a course named "B.Sc Psycology" never shows
up for "psychology". The typos come from the colleges' own pages (and so from
research/*.json), which means every import writes them back; the importer
runs this fix before committing, and it is safe to re-run at any time.

Only clear misspellings are listed. Real names that look like typos (Kannur,
Bhupal Nobles', Lovely Professional, Narsee Monjee, Sanskriti), accepted
spelling variants (counseling, homoeo, karmakand) and abbreviations are left
alone. The spelling each college already uses elsewhere wins ("Honors",
"Paediatric", "Gynaecology").

Usage: python3 tooling/fix_data_spellings.py [--database path] [--dry-run]
"""

from __future__ import annotations

import argparse
import re
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"

# Whole words, matched case-insensitively; the replacement keeps the case.
WORD_FIXES = {
    "admistration": "administration",
    "anaesthsia": "anaesthesia",
    "analyatics": "analytics",
    "architechture": "architecture",
    "artifical": "artificial",
    "artificlal": "artificial",
    "assitant": "assistant",
    "autonmous": "autonomous",
    "bararbanki": "barabanki",
    "biochemestry": "biochemistry",
    "biotechnoloy": "biotechnology",
    "cetificate": "certificate",
    "chemsitry": "chemistry",
    "collboration": "collaboration",
    "commerece": "commerce",
    "councelling": "counselling",
    "criminalogy": "criminology",
    "drawnig": "drawing",
    "enginerring": "engineering",
    "enginneering": "engineering",
    "entamology": "entomology",
    "enterpreneurship": "entrepreneurship",
    "gasteroenterology": "gastroenterology",
    "gastroentereology": "gastroenterology",
    "graudate": "graduate",
    "gynechology": "gynaecology",
    "haemotology": "haematology",
    "homors": "honors",
    "husbandary": "husbandry",
    "intellegence": "intelligence",
    "mahavidylaya": "mahavidyalaya",
    "maraketing": "marketing",
    "mechenical": "mechanical",
    "mechnical": "mechanical",
    "mechtronics": "mechatronics",
    "mircobiology": "microbiology",
    "nagour": "nagaur",
    "nutritions": "nutrition",
    "obstestrics": "obstetrics",
    "pathalogy": "pathology",
    "pedaitric": "paediatric",
    "pharmacetical": "pharmaceutical",
    "pharmacetuics": "pharmaceutics",
    "pharmacitical": "pharmaceutical",
    "philosphy": "philosophy",
    "psycology": "psychology",
    "rehabilitaion": "rehabilitation",
    "sculture": "sculpture",
    "serivces": "services",
    "specilisation": "specialisation",
    "specilizaion": "specialization",
    "specilization": "specialization",
    "taxtile": "textile",
    "techology": "technology",
    "transfustion": "transfusion",
    "venerology": "venereology",
}

# Exact text: a Cyrillic "\u0443" that looks like "y", and words glued together
# so that "economics" or "college" can't match on its own.
TEXT_FIXES = {
    "Therap\u0443": "Therapy",
    "M.A.Economics": "M.A. Economics",
    "M.A.English": "M.A. English",
    "M.A.Geography": "M.A. Geography",
    "M.A.Political": "M.A. Political",
    "M.A.Sociology": "M.A. Sociology",
    "P.G.College": "P.G. College",
    "inThoracic": "in Thoracic",
}

# Text people read or search. Ids, slugs and source_id stay untouched: the
# importer matches existing rows on source_id.
COLUMNS = {
    "institutes": ("name", "city", "district", "description"),
    "institute_courses": ("name", "specialization"),
    "institute_categories": ("category",),
    "career_nodes": ("name", "intro"),
}

_WORD = re.compile(
    r"(?<![A-Za-z])(" + "|".join(WORD_FIXES) + r")(?![A-Za-z])",
    re.IGNORECASE,
)


def _keep_case(original: str, fixed: str) -> str:
    if original.isupper():
        return fixed.upper()
    if original[0].isupper():
        return fixed[0].upper() + fixed[1:]
    return fixed


def fix_text(value: str) -> str:
    for wrong, right in TEXT_FIXES.items():
        value = value.replace(wrong, right)
    return _WORD.sub(
        lambda match: _keep_case(
            match.group(0), WORD_FIXES[match.group(0).lower()]
        ),
        value,
    )


def fix_spellings(connection: sqlite3.Connection) -> dict[str, int]:
    """Rows changed per "table.column"; the caller commits."""
    changed: dict[str, int] = {}
    for table, columns in COLUMNS.items():
        for column in columns:
            rows = connection.execute(
                f"SELECT rowid, {column} FROM {table} "
                f"WHERE {column} IS NOT NULL"
            ).fetchall()
            updates = [
                (fixed, rowid)
                for rowid, value in rows
                if (fixed := fix_text(value)) != value
            ]
            connection.executemany(
                f"UPDATE {table} SET {column} = ? WHERE rowid = ?", updates
            )
            if updates:
                changed[f"{table}.{column}"] = len(updates)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    connection = sqlite3.connect(args.database)
    try:
        changed = fix_spellings(connection)
        if args.dry_run:
            connection.rollback()
        else:
            connection.commit()
    finally:
        connection.close()

    total = sum(changed.values())
    for key, count in sorted(changed.items()):
        print(f"{key}: {count}")
    verb = "Would fix" if args.dry_run else "Fixed"
    print(f"{verb} spellings in {total} values.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
