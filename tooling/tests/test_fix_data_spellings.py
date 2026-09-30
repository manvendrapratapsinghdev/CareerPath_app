"""Tests for correcting misspellings in the bundled app database."""

from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from fix_data_spellings import (  # noqa: E402
    DEFAULT_DATABASE,
    fix_spellings,
    fix_text,
)


class FixDataSpellingsTest(unittest.TestCase):
    def test_fixes_whole_words_and_keeps_case(self) -> None:
        self.assertEqual(fix_text("B.Sc Psycology"), "B.Sc Psychology")
        self.assertEqual(
            fix_text("MASTER OF BUSINESS ADMISTRATION (MBA)"),
            "MASTER OF BUSINESS ADMINISTRATION (MBA)",
        )
        self.assertEqual(fix_text("Bio-Techology"), "Bio-Technology")
        self.assertEqual(fix_text("mechnical"), "mechanical")
        # A Cyrillic "\u0443" that looks like a Latin "y".
        self.assertEqual(
            fix_text("Occupational Therap\u0443;"), "Occupational Therapy;"
        )
        self.assertEqual(fix_text("(M.A.Economics)"), "(M.A. Economics)")

    def test_leaves_real_names_and_variants_alone(self) -> None:
        for text in [
            "Kannur University",
            "Lovely Professional University",
            "BHUPAL NOBLES' UNIVERSITY",
            "Narsee Monjee College of Commerce and Economics",
            "Sanskriti University",
            "Wealth Manager / Private Banker",
            "Baking and Confectionery Vocational",
            "Guidance and Counseling",
            "Psychologyx",
        ]:
            self.assertEqual(fix_text(text), text)

    def test_updates_rows_and_is_idempotent(self) -> None:
        connection = sqlite3.connect(":memory:")
        connection.executescript(
            """
            CREATE TABLE institutes(
                name TEXT, city TEXT, district TEXT, description TEXT
            );
            CREATE TABLE institute_courses(name TEXT, specialization TEXT);
            CREATE TABLE institute_categories(category TEXT);
            CREATE TABLE career_nodes(name TEXT, intro TEXT);
            INSERT INTO institutes VALUES
                ('Govt Autonmous Commerece College', 'Bararbanki', NULL, NULL);
            INSERT INTO institute_courses VALUES
                ('B.Tech Mechnical Enginerring', NULL),
                ('B.Sc', 'Psycology');
            """
        )
        self.assertEqual(
            fix_spellings(connection),
            {
                "institutes.name": 1,
                "institutes.city": 1,
                "institute_courses.name": 1,
                "institute_courses.specialization": 1,
            },
        )
        self.assertEqual(
            connection.execute("SELECT name, city FROM institutes").fetchone(),
            ("Govt Autonomous Commerce College", "Barabanki"),
        )
        self.assertEqual(fix_spellings(connection), {})

    def test_bundled_database_is_already_fixed(self) -> None:
        connection = sqlite3.connect(
            f"file:{DEFAULT_DATABASE}?mode=ro", uri=True
        )
        try:
            self.assertEqual(fix_spellings(connection), {})
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
