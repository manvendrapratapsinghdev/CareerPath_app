import csv
import sqlite3
import tempfile
import unittest
from pathlib import Path

from tooling.import_locations import (
    LgdDistrict,
    LgdState,
    import_lgd_master,
    populate_institute_campuses,
    read_districts,
    read_states,
)


class ImportLocationsTests(unittest.TestCase):
    def setUp(self):
        self.connection = sqlite3.connect(":memory:")
        self.connection.execute("PRAGMA foreign_keys = ON")
        self.connection.executescript(
            """
            CREATE TABLE states (
                code TEXT PRIMARY KEY,
                lgd_code INTEGER UNIQUE NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL
            );
            CREATE TABLE districts (
                lgd_code INTEGER PRIMARY KEY,
                state_code TEXT NOT NULL REFERENCES states(code),
                name TEXT NOT NULL,
                UNIQUE(state_code, name)
            );
            CREATE TABLE places (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                district_lgd INTEGER NOT NULL REFERENCES districts(lgd_code),
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                is_district_hq INTEGER NOT NULL DEFAULT 0,
                UNIQUE(district_lgd, name)
            );
            CREATE TABLE place_aliases (
                alias TEXT PRIMARY KEY,
                place_id INTEGER REFERENCES places(id),
                district_lgd INTEGER REFERENCES districts(lgd_code),
                state_code TEXT REFERENCES states(code),
                CHECK ((place_id IS NOT NULL) + (district_lgd IS NOT NULL)
                       + (state_code IS NOT NULL) = 1)
            );
            CREATE TABLE institutes (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                city TEXT,
                district TEXT,
                state TEXT,
                website TEXT
            );
            CREATE TABLE institute_classification (
                institute_id INTEGER PRIMARY KEY,
                is_family_record INTEGER,
                listed INTEGER,
                admits_students INTEGER,
                parent_institute_id INTEGER
            );
            CREATE TABLE campuses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                institute_id INTEGER NOT NULL,
                name TEXT,
                place_id INTEGER NOT NULL,
                is_main INTEGER NOT NULL DEFAULT 0,
                source_url TEXT,
                verified_at TEXT
            );
            INSERT INTO states VALUES ('IN-KA', 29, 'Karnataka', 'state');
            INSERT INTO states VALUES ('IN-RJ', 8, 'Rajasthan', 'state');
            """
        )

    def tearDown(self):
        self.connection.close()

    def test_read_lgd_exports_and_import_exact_legacy_campuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            states_path = root / "states.csv"
            districts_path = root / "districts.csv"
            review_path = root / "review.csv"
            states_path.write_text(
                "State Code,State Name (In English),State or UT\n"
                "29,Karnataka,S\n8,Rajasthan,S\n",
                encoding="utf-8",
            )
            districts_path.write_text(
                "State Code,District Code,District Name(In English)\n"
                "29,526,Bengaluru Urban\n8,86,Ajmer\n",
                encoding="utf-8",
            )
            states = read_states(states_path)
            districts = read_districts(districts_path)
            self.assertEqual(len(states), 2)
            self.assertEqual(len(districts), 2)
            self.assertEqual(import_lgd_master(
                self.connection, states, districts, require_complete_states=False
            ), (2, 2))

            self.connection.executemany(
                "INSERT INTO institutes VALUES (?, ?, ?, ?, ?, ?)",
                [
                    (1, "Valid campus", "Bangalore", "Bengaluru Urban", "Karnataka", "https://example.org"),
                    (2, "Missing district", "Jaipur", None, "Rajasthan", None),
                    (3, "Mismatched district", "Jodhpur", "Bikaner", "Rajasthan", None),
                    (4, "National summary", "Various", None, None, None),
                ],
            )
            self.connection.execute(
                "INSERT INTO institute_classification VALUES (4, 1, 1, 1, NULL)"
            )
            with self.connection:
                place_count, campus_count, alias_count = populate_institute_campuses(
                    self.connection, review_path
                )

            self.assertEqual((place_count, campus_count, alias_count), (1, 1, 1))
            self.assertEqual(
                self.connection.execute("SELECT name, is_district_hq FROM places").fetchone(),
                ("Bengaluru", 0),
            )
            self.assertEqual(
                self.connection.execute(
                    "SELECT name, is_main, source_url, verified_at FROM campuses"
                ).fetchone(),
                (None, 1, None, None),
            )
            alias = self.connection.execute(
                "SELECT alias, place_id FROM place_aliases"
            ).fetchone()
            self.assertEqual(alias[0], "bangalore")
            with review_path.open(encoding="utf-8", newline="") as source:
                review = list(csv.DictReader(source))
            self.assertEqual([row["reason"] for row in review], [
                "missing_explicit_district",
                "district_not_found_in_current_lgd",
            ])

            with self.connection:
                import_lgd_master(
                    self.connection, states, districts, require_complete_states=False
                )
                populate_institute_campuses(self.connection, review_path)
            self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM places").fetchone()[0], 1)
            self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM campuses").fetchone()[0], 1)

    def test_import_rejects_unseeded_lgd_codes(self):
        with self.assertRaisesRegex(ValueError, "not seeded"):
            import_lgd_master(
                self.connection,
                [LgdState(999, "Unknown", "state")],
                [LgdDistrict(1, 999, "Example")],
                require_complete_states=False,
            )

    def test_import_rejects_unmatched_district_state_code(self):
        with self.assertRaisesRegex(ValueError, "unknown LGD state codes"):
            import_lgd_master(
                self.connection,
                [LgdState(29, "Karnataka", "state")],
                [LgdDistrict(1, 8, "Ajmer")],
                require_complete_states=False,
            )

    def test_parent_campus_can_be_inherited_without_guessing_conflicting_state(self):
        import_lgd_master(
            self.connection,
            [LgdState(8, "Rajasthan", "state")],
            [LgdDistrict(86, 8, "Ajmer")],
            require_complete_states=False,
        )
        self.connection.executemany(
            "INSERT INTO institutes VALUES (?, ?, ?, ?, ?, ?)",
            [
                (10, "Parent institution", "Ajmer", "Ajmer", "Rajasthan", None),
                (11, "Parent department", "Ajmer", None, None, None),
                (12, "Conflicting child", "Ajmer", None, "Unknown State", None),
            ],
        )
        self.connection.executemany(
            "INSERT INTO institute_classification VALUES (?, 0, 1, 1, ?)",
            [(11, 10), (12, 10)],
        )
        with tempfile.TemporaryDirectory() as tmp:
            review_path = Path(tmp) / "review.csv"
            with self.connection:
                _, campus_count, _ = populate_institute_campuses(
                    self.connection, review_path
                )
            self.assertEqual(campus_count, 2)
            with review_path.open(encoding="utf-8", newline="") as source:
                review = list(csv.DictReader(source))
            self.assertEqual([row["institute_id"] for row in review], ["12"])
            child_place = self.connection.execute(
                "SELECT place_id FROM campuses WHERE institute_id = 11"
            ).fetchone()[0]
            parent_place = self.connection.execute(
                "SELECT place_id FROM campuses WHERE institute_id = 10"
            ).fetchone()[0]
            self.assertEqual(child_place, parent_place)


if __name__ == "__main__":
    unittest.main()
