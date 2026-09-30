"""Tests for filling institute states from their city."""

from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from fill_institute_states import DEFAULT_DATABASE, fill_states  # noqa: E402


def _database(rows: list[tuple[str, str | None]]) -> sqlite3.Connection:
    connection = sqlite3.connect(":memory:")
    connection.execute(
        "CREATE TABLE institutes (id INTEGER PRIMARY KEY, name TEXT, "
        "city TEXT, district TEXT, state TEXT)"
    )
    connection.executemany(
        "INSERT INTO institutes (name, city, state) VALUES (?, ?, ?)",
        [(f"Institute {i}", city, state) for i, (city, state) in enumerate(rows)],
    )
    return connection


class FillInstituteStatesTest(unittest.TestCase):
    def test_fills_missing_states_from_the_city(self) -> None:
        connection = _database(
            [("New Delhi", None), ("  Navi  Mumbai ", None), ("Bangalore", "")]
        )
        filled = fill_states(connection)
        self.assertEqual(filled, {"Delhi": 1, "Maharashtra": 1, "Karnataka": 1})
        self.assertEqual(
            [row[0] for row in connection.execute("SELECT state FROM institutes")],
            ["Delhi", "Maharashtra", "Karnataka"],
        )

    def test_keeps_existing_states_placeholders_and_districts(self) -> None:
        connection = _database(
            [("Jaipur", "Rajasthan"), ("Various", None), ("Atlantis", None)]
        )
        self.assertEqual(fill_states(connection), {})
        rows = connection.execute("SELECT state, district FROM institutes").fetchall()
        self.assertEqual(rows, [("Rajasthan", None), (None, None), (None, None)])

    def test_is_safe_to_rerun(self) -> None:
        connection = _database([("Mumbai", None)])
        fill_states(connection)
        self.assertEqual(fill_states(connection), {})

    def test_bundled_database_has_a_state_for_every_real_place(self) -> None:
        connection = sqlite3.connect(f"file:{DEFAULT_DATABASE}?mode=ro", uri=True)
        try:
            missing = {
                city
                for (city,) in connection.execute(
                    "SELECT DISTINCT city FROM institutes "
                    "WHERE state IS NULL OR trim(state) = ''"
                )
            }
        finally:
            connection.close()
        self.assertEqual(missing, {"Various", "Online"})


if __name__ == "__main__":
    unittest.main()
