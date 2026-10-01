"""Tests for the institution taxonomy tables and their seed data."""

from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from institution_taxonomy import FAMILIES, GROUPS, STATES, apply  # noqa: E402


def _database() -> sqlite3.Connection:
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("CREATE TABLE institutes (id INTEGER PRIMARY KEY, name TEXT)")
    return connection


class InstitutionTaxonomyTest(unittest.TestCase):
    def test_seeds_groups_families_and_all_states(self) -> None:
        connection = _database()
        apply(connection)
        count = lambda table: connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        self.assertEqual(count("institution_groups"), 13)
        self.assertEqual(count("families"), len(FAMILIES))
        self.assertEqual(count("states"), 36)
        self.assertEqual(
            connection.execute("SELECT COUNT(*) FROM states WHERE kind = 'ut'").fetchone()[0], 8
        )
        self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_every_family_belongs_to_a_known_group(self) -> None:
        codes = {code for code, _, _ in GROUPS}
        self.assertEqual({group for _, _, group, _ in FAMILIES} - codes, set())
        slugs = [slug for slug, _, _, _ in FAMILIES]
        self.assertEqual(len(slugs), len(set(slugs)))
        # Every group has at least one family.
        self.assertTrue(all(any(g == code for _, _, g, _ in FAMILIES) for code in codes))

    def test_state_codes_are_unique(self) -> None:
        self.assertEqual(len({s[0] for s in STATES}), 36)
        self.assertEqual(len({s[1] for s in STATES}), 36)
        self.assertEqual(len({s[2] for s in STATES}), 36)

    def test_rerun_keeps_counts_set_by_batches(self) -> None:
        connection = _database()
        apply(connection)
        connection.execute(
            "UPDATE families SET national_count = 23, national_count_as_of = '2025', "
            "official_list_url = 'https://www.iitsystem.ac.in/' WHERE slug = 'iit'"
        )
        apply(connection)
        self.assertEqual(
            connection.execute(
                "SELECT national_count, national_count_as_of, official_list_url "
                "FROM families WHERE slug = 'iit'"
            ).fetchone(),
            (23, "2025", "https://www.iitsystem.ac.in/"),
        )
        self.assertEqual(
            connection.execute("SELECT COUNT(*) FROM families").fetchone()[0], len(FAMILIES)
        )

    def test_classification_rejects_unknown_values(self) -> None:
        connection = _database()
        apply(connection)
        connection.execute("INSERT INTO institutes (id, name) VALUES (1, 'IIT Bombay')")
        with self.assertRaises(sqlite3.IntegrityError):
            connection.execute(
                "INSERT INTO institute_classification (institute_id, group_code, confidence) "
                "VALUES (1, 'G99', 'high')"
            )
        with self.assertRaises(sqlite3.IntegrityError):
            connection.execute(
                "INSERT INTO institute_classification "
                "(institute_id, group_code, confidence, ugc_verified) VALUES (1, 'G1', 'high', 2)"
            )


    def test_ugc_check_is_private_only_and_required_for_private(self) -> None:
        connection = _database()
        apply(connection)
        connection.execute("INSERT INTO institutes (id, name) VALUES (1, 'A'), (2, 'B')")
        insert = (
            "INSERT INTO institute_classification "
            "(institute_id, group_code, ownership, ugc_verified, confidence) "
            "VALUES (?, ?, ?, ?, 'high')"
        )
        with self.assertRaises(sqlite3.IntegrityError):
            connection.execute(insert, (1, "G1", "central_govt", 1))
        with self.assertRaises(sqlite3.IntegrityError):
            connection.execute(insert, (1, "G7", "private", None))
        connection.execute(insert, (1, "G1", "central_govt", None))
        connection.execute(insert, (2, "G8", "private", 0))

    def test_only_phase_two_or_non_admitting_rows_can_be_unlisted(self) -> None:
        connection = _database()
        apply(connection)
        connection.execute("INSERT INTO institutes (id, name) VALUES (1, 'A'), (2, 'B'), (3, 'C')")
        insert = (
            "INSERT INTO institute_classification "
            "(institute_id, group_code, listed, admits_students, is_family_record, confidence) "
            "VALUES (?, ?, 0, ?, ?, 'high')"
        )
        with self.assertRaises(sqlite3.IntegrityError):
            connection.execute(insert, (1, "G1", 1, 0))
        connection.execute(insert, (1, "G10b", 1, 0))
        connection.execute(insert, (2, "G3", 0, 0))
        connection.execute(insert, (3, "G2", 1, 1))


if __name__ == "__main__":
    unittest.main()
