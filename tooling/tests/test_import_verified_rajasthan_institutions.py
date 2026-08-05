"""Tests for the verified Rajasthan institution database import."""

from __future__ import annotations

import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from import_verified_rajasthan_institutions import (  # noqa: E402
    DEFAULT_DATABASE,
    DEFAULT_INVENTORY,
    DEFAULT_VERIFICATIONS,
    import_verified,
)


class VerifiedInstitutionImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.database = Path(self.temp_dir.name) / "career_path.db"
        shutil.copy2(DEFAULT_DATABASE, self.database)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_imports_only_verified_records_and_is_idempotent(self) -> None:
        first = import_verified(
            self.database, DEFAULT_VERIFICATIONS, DEFAULT_INVENTORY
        )
        second = import_verified(
            self.database, DEFAULT_VERIFICATIONS, DEFAULT_INVENTORY
        )

        self.assertEqual(first, second)
        self.assertEqual(first["institutions"], 103)
        self.assertEqual(first["courses"], 2800)
        self.assertGreater(first["career_mappings"], 0)

        connection = sqlite3.connect(self.database)
        try:
            verified_institutes = connection.execute(
                """
                SELECT COUNT(*) FROM institutes
                WHERE source_id IS NOT NULL
                """
            ).fetchone()[0]
            courses = connection.execute(
                "SELECT COUNT(*) FROM institute_courses"
            ).fetchone()[0]
            missing_locations = connection.execute(
                """
                SELECT COUNT(*) FROM institutes
                WHERE source_id IS NOT NULL
                  AND (district IS NULL OR state IS NULL)
                """
            ).fetchone()[0]
            unverified_courses = connection.execute(
                """
                SELECT COUNT(*) FROM institute_courses
                WHERE verification_status NOT IN (
                    'verified', 'verified_programme_family'
                )
                """
            ).fetchone()[0]
            mapping_gaps = connection.execute(
                """
                SELECT COUNT(*) FROM institute_courses
                WHERE mapping_gap IS NOT NULL
                """
            ).fetchone()[0]
            imported_foreign_key_errors = []
            for table in (
                "institute_courses",
                "course_career_nodes",
                "institute_categories",
                "institute_rankings",
            ):
                imported_foreign_key_errors.extend(
                    connection.execute(
                        f"PRAGMA foreign_key_check({table})"
                    ).fetchall()
                )
        finally:
            connection.close()

        self.assertEqual(verified_institutes, 103)
        self.assertEqual(courses, 2800)
        self.assertEqual(missing_locations, 0)
        self.assertEqual(unverified_courses, 0)
        self.assertEqual(mapping_gaps, 110)
        self.assertEqual(imported_foreign_key_errors, [])

    def test_location_and_ranking_indexes_are_queryable(self) -> None:
        import_verified(
            self.database, DEFAULT_VERIFICATIONS, DEFAULT_INVENTORY
        )
        connection = sqlite3.connect(self.database)
        try:
            jaipur_count = connection.execute(
                """
                SELECT COUNT(*) FROM institutes
                WHERE source_id IS NOT NULL AND district = ?
                """,
                ("Jaipur",),
            ).fetchone()[0]
            ranking_count = connection.execute(
                "SELECT COUNT(*) FROM institute_rankings"
            ).fetchone()[0]
            location_index = connection.execute(
                """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type = 'index' AND name = 'idx_institutes_location'
                """
            ).fetchone()[0]
        finally:
            connection.close()

        self.assertEqual(jaipur_count, 43)
        self.assertGreater(ranking_count, 0)
        self.assertEqual(location_index, 1)


if __name__ == "__main__":
    unittest.main()
