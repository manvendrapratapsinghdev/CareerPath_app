#!/usr/bin/env python3
"""Fill in the state of institutes that only have a city.

The older, hand-curated institutes (New Delhi, Mumbai, Chennai, ...) were
added without a state, so a question about "colleges in Maharashtra" or
"colleges in Delhi" skipped all of them. Every one of them has a city, and a
city names its state, so the state is taken from the city. Placeholders such
as "Various" or "Online" name no place and stay empty; districts are never
guessed. Existing states are never changed.

The importer runs this before committing, and it is safe to re-run.

Usage: python3 tooling/fill_institute_states.py [--database path] [--dry-run]
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"

# Lowercase city → state, spelled as the app's state aliases expect.
CITY_STATES = {
    "ahmedabad": "Gujarat",
    "amritsar": "Punjab",
    "bangalore": "Karnataka",
    "bareilly": "Uttar Pradesh",
    "bengaluru": "Karnataka",
    "berhampur": "Odisha",
    "bhopal": "Madhya Pradesh",
    "bhubaneswar": "Odisha",
    "chandigarh": "Chandigarh",
    "chennai": "Tamil Nadu",
    "coimbatore": "Tamil Nadu",
    "dehradun": "Uttarakhand",
    "dhanbad": "Jharkhand",
    "dharwad": "Karnataka",
    "faridabad": "Haryana",
    "gandhinagar": "Gujarat",
    "ghaziabad": "Uttar Pradesh",
    "goa": "Goa",
    "gondia": "Maharashtra",
    "greater noida": "Uttar Pradesh",
    "gurgaon": "Haryana",
    "gurugram": "Haryana",
    "guwahati": "Assam",
    "gwalior": "Madhya Pradesh",
    "hyderabad": "Telangana",
    "imphal": "Manipur",
    "jaipur": "Rajasthan",
    "jamnagar": "Gujarat",
    "jamshedpur": "Jharkhand",
    "kannur": "Kerala",
    "kanpur": "Uttar Pradesh",
    "kharagpur": "West Bengal",
    "kochi": "Kerala",
    "kolkata": "West Bengal",
    "kozhikode": "Kerala",
    "kurukshetra": "Haryana",
    "lucknow": "Uttar Pradesh",
    "ludhiana": "Punjab",
    "manesar": "Haryana",
    "mangalore": "Karnataka",
    "manipal": "Karnataka",
    "mohali": "Punjab",
    "mumbai": "Maharashtra",
    "mussoorie": "Uttarakhand",
    "mysuru": "Karnataka",
    "nagpur": "Maharashtra",
    "navi mumbai": "Maharashtra",
    "new delhi": "Delhi",
    "noida": "Uttar Pradesh",
    "pantnagar": "Uttarakhand",
    "patiala": "Punjab",
    "phagwara": "Punjab",
    "pilani": "Rajasthan",
    "puducherry": "Puducherry",
    "pune": "Maharashtra",
    "rae bareli": "Uttar Pradesh",
    "ranchi": "Jharkhand",
    "ropar": "Punjab",
    "roorkee": "Uttarakhand",
    "santiniketan": "West Bengal",
    "sehore": "Madhya Pradesh",
    "sonipat": "Haryana",
    "thiruvananthapuram": "Kerala",
    "tiruchirappalli": "Tamil Nadu",
    "vadodara": "Gujarat",
    "varanasi": "Uttar Pradesh",
    "vellore": "Tamil Nadu",
    "vijayawada": "Andhra Pradesh",
    "visakhapatnam": "Andhra Pradesh",
    "wardha": "Maharashtra",
    "warangal": "Telangana",
}


def fill_states(connection: sqlite3.Connection) -> dict[str, int]:
    """Rows filled per state; the caller commits."""
    rows = connection.execute(
        "SELECT id, city FROM institutes "
        "WHERE (state IS NULL OR trim(state) = '') AND city IS NOT NULL"
    ).fetchall()
    filled: dict[str, int] = {}
    updates = []
    for institute_id, city in rows:
        state = CITY_STATES.get(" ".join(city.lower().split()))
        if state is None:
            continue
        updates.append((state, institute_id))
        filled[state] = filled.get(state, 0) + 1
    connection.executemany(
        "UPDATE institutes SET state = ? WHERE id = ?", updates
    )
    return filled


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    connection = sqlite3.connect(args.database)
    try:
        filled = fill_states(connection)
        missing = connection.execute(
            "SELECT city, count(*) FROM institutes "
            "WHERE state IS NULL OR trim(state) = '' GROUP BY city"
        ).fetchall()
        if args.dry_run:
            connection.rollback()
        else:
            connection.commit()
    finally:
        connection.close()

    for state, count in sorted(filled.items()):
        print(f"{state}: {count}")
    verb = "Would fill" if args.dry_run else "Filled"
    print(f"{verb} the state of {sum(filled.values())} institutes.")
    if missing:
        print("Still without a state: " + ", ".join(f"{c} ({n})" for c, n in missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
