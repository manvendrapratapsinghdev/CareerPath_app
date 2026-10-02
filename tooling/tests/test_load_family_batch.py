"""Tests for loading an institution batch."""

from __future__ import annotations

import copy
import sqlite3
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from institution_taxonomy import apply  # noqa: E402
from load_family_batch import DEFAULT_DATABASE, BatchError, load  # noqa: E402

TABLES = ("institutes", "career_nodes", "node_institutes", "institute_courses",
          "institute_categories", "institute_rankings", "streams")

SNAPSHOT = {
    "metadata": {"year": 2025},
    "entries": [
        {"category": "Engineering", "nirf_institute_id": "IR-E-U-0306",
         "name": "Indian Institute of Technology Bombay", "city": "Mumbai",
         "state": "Maharashtra", "score": 81.0, "rank": 3, "rank_band": None,
         "source_url": "https://nirf/Eng.html"},
        {"category": "Overall", "nirf_institute_id": "IR-O-U-0306",
         "name": "Indian Institute of Technology Bombay", "city": "Mumbai",
         "state": "Maharashtra", "score": 79.0, "rank": 3, "rank_band": None,
         "source_url": "https://nirf/Overall.html"},
        {"category": "Engineering", "nirf_institute_id": None,
         "name": "Indian Institute of Technology Goa", "city": "Ponda", "state": "Goa",
         "score": None, "rank": None, "rank_band": "101-150",
         "source_url": "https://nirf/Eng150.html"},
        {"category": "Engineering", "nirf_institute_id": None, "name": "Amity University",
         "city": "Noida", "state": "Uttar Pradesh", "score": None, "rank": None,
         "rank_band": "151-200", "source_url": "u"},
        {"category": "Engineering", "nirf_institute_id": None, "name": "Amity University",
         "city": "Jaipur", "state": "Rajasthan", "score": None, "rank": None,
         "rank_band": "201-300", "source_url": "u"},
    ],
}

BATCH = {
    "batch": "T",
    "verified_at": "2026-10-01",
    "verification": {"authority": "MoE", "list_name": "IIT Council list of IITs",
                     "list_url": "https://www.iitsystem.ac.in/", "list_as_of": "2026-10-01"},
    "defaults": {"family": "iit", "group": "G1", "ownership": "central_govt",
                 "legacy_type": "iit", "nodes": ["btech"]},
    "families": {"iit": {"national_count": 2, "as_of": "2026-10-01",
                         "official_list_url": "https://www.iitsystem.ac.in/"}},
    "institutes": [
        {"key": "iit-bombay", "name": "Indian Institute of Technology Bombay",
         "website": "https://www.iitb.ac.in", "existing": ["IIT Bombay"],
         "departments": ["IIT Bombay (Civil)",
                         {"name": "Industrial Design Centre (IDC), IIT Bombay",
                          "existing": ["IDC IIT Bombay"], "city": "Panaji", "state": "Goa"}]},
        {"key": "iit-goa", "name": "Indian Institute of Technology Goa"},
    ],
    "summary_rows": [{"name": "IITs"}],
}


def _database() -> sqlite3.Connection:
    """In-memory copy of the real tables' definitions, plus the taxonomy."""
    source = sqlite3.connect(DEFAULT_DATABASE)
    ddl = [
        row[0]
        for row in source.execute(
            "SELECT sql FROM sqlite_master WHERE type IN ('table', 'index') AND sql IS NOT NULL "
            f"AND tbl_name IN ({','.join('?' * len(TABLES))})",
            TABLES,
        )
    ]
    source.close()
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    for statement in sorted(ddl, key=lambda s: not s.startswith("CREATE TABLE")):
        connection.execute(statement)
    apply(connection)
    connection.executescript(
        """
        INSERT INTO streams (id, slug, name) VALUES (1, 'science', 'Science');
        INSERT INTO career_nodes (id, slug, stream_id, name) VALUES (1, 'btech', 1, 'B.Tech'),
                                                                    (2, 'civil', 1, 'Civil');
        INSERT INTO institutes (id, name, city, state, district, description) VALUES
          (10, 'IIT Bombay', 'Mumbai', 'Maharashtra', NULL, 'old'),
          (11, 'Indian Institute of Technology Bombay', 'Bombay', NULL, 'Mumbai', 'dup'),
          (12, 'IIT Bombay (Civil)', 'Mumbai', NULL, NULL, 'dept'),
          (13, 'IDC IIT Bombay', 'Mumbai', NULL, NULL, 'dept'),
          (14, 'Industrial Design Centre (IDC), IIT Bombay', 'Mumbai', NULL, NULL, 'dept'),
          (15, 'IITs', 'Various', NULL, NULL, 'summary');
        INSERT INTO node_institutes VALUES (2, 10), (2, 11), (2, 13);
        INSERT INTO institute_categories VALUES (11, 'Engineering');
        """
    )
    return connection


class LoadFamilyBatchTest(unittest.TestCase):
    def test_merges_duplicates_and_keeps_their_links(self) -> None:
        connection = _database()
        report = load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        rows = connection.execute(
            "SELECT id, name, city, state, district, description FROM institutes "
            "WHERE name LIKE 'Indian Institute of Technology%' ORDER BY name"
        ).fetchall()
        # The exact-name row is kept; the old short-name row is merged into it.
        self.assertEqual(rows[0][:5], (11, "Indian Institute of Technology Bombay",
                                       "Mumbai", "Maharashtra", None))
        self.assertEqual(rows[0][5], "dup")  # existing descriptions are kept
        self.assertIsNone(connection.execute("SELECT 1 FROM institutes WHERE id = 10").fetchone())
        self.assertEqual(
            connection.execute(
                "SELECT node_id FROM node_institutes WHERE institute_id = 11 ORDER BY node_id"
            ).fetchall(),
            [(1,), (2,)],
        )
        self.assertEqual(
            connection.execute(
                "SELECT category FROM institute_categories WHERE institute_id = 11"
            ).fetchall(),
            [("Engineering",)],
        )
        self.assertIn("IIT Bombay -> Indian Institute of Technology Bombay", report["merged"])
        # The kept row already had the official name, so nothing was renamed.
        self.assertEqual(report["renamed"], [])

    def test_reports_renames_and_takes_confidence_from_the_spec(self) -> None:
        connection = _database()
        connection.execute("DELETE FROM institutes WHERE id = 11")
        batch = copy.deepcopy(BATCH)
        batch["institutes"][1]["confidence"] = "medium"
        report = load(connection, batch, SNAPSHOT)
        self.assertEqual(report["renamed"], ["IIT Bombay -> Indian Institute of Technology Bombay"])
        self.assertEqual(
            connection.execute(
                "SELECT c.confidence FROM institute_classification c JOIN institutes i "
                "ON i.id = c.institute_id WHERE i.name = 'Indian Institute of Technology Goa'"
            ).fetchone(),
            ("medium",),
        )

    def test_inserts_new_institutes_with_a_verified_description(self) -> None:
        connection = _database()
        load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        name, city, state, description, source_id = connection.execute(
            "SELECT name, city, state, description, source_id FROM institutes "
            "WHERE name = 'Indian Institute of Technology Goa'"
        ).fetchone()
        self.assertEqual((city, state, source_id), ("Ponda", "Goa", None))
        self.assertIsNone(connection.execute(
            "SELECT website FROM institutes WHERE name = 'Indian Institute of Technology Goa'"
        ).fetchone()[0])
        self.assertIn("IIT Council list of IITs", description)
        self.assertIn("band 101-150 in Engineering", description)

    def test_records_classification_verification_and_rankings(self) -> None:
        connection = _database()
        load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        self.assertEqual(
            connection.execute(
                "SELECT group_code, family_slug, ownership, ugc_verified, listed, confidence "
                "FROM institute_classification WHERE institute_id = 11"
            ).fetchone(),
            ("G1", "iit", "central_govt", None, 1, "high"),
        )
        self.assertEqual(
            connection.execute(
                "SELECT authority, list_url FROM institute_verifications WHERE institute_id = 11"
            ).fetchone(),
            ("MoE", "https://www.iitsystem.ac.in/"),
        )
        self.assertEqual(
            connection.execute(
                "SELECT institution_type_source_url, institution_type_notes FROM institutes "
                "WHERE id = 11"
            ).fetchone(),
            ("https://www.iitsystem.ac.in/", "Verified against IIT Council list of IITs (batch T)."),
        )
        self.assertEqual(
            connection.execute(
                "SELECT category, rank FROM institute_rankings WHERE institute_id = 11 "
                "ORDER BY category"
            ).fetchall(),
            [("Engineering", 3), ("Overall", 3)],
        )
        self.assertEqual(
            connection.execute("SELECT national_count FROM families WHERE slug = 'iit'").fetchone(),
            (2,),
        )

    def test_departments_become_children_and_summary_rows_are_marked(self) -> None:
        connection = _database()
        load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        children = connection.execute(
            "SELECT i.name, c.parent_institute_id, c.confidence, i.state FROM institutes i "
            "JOIN institute_classification c ON c.institute_id = i.id "
            "WHERE c.parent_institute_id IS NOT NULL ORDER BY i.name"
        ).fetchall()
        self.assertEqual(
            children,
            [("IIT Bombay (Civil)", 11, "medium", "Maharashtra"),
             ("Industrial Design Centre (IDC), IIT Bombay", 11, "medium", "Goa")],
        )
        self.assertEqual(
            connection.execute("SELECT city FROM institutes WHERE id = 14").fetchone(), ("Panaji",)
        )
        # The duplicate department row is merged, with its career-node link.
        self.assertIsNone(connection.execute("SELECT 1 FROM institutes WHERE id = 13").fetchone())
        self.assertEqual(
            connection.execute("SELECT node_id FROM node_institutes WHERE institute_id = 14")
            .fetchall(),
            [(2,)],
        )
        self.assertEqual(
            connection.execute(
                "SELECT is_family_record, listed FROM institute_classification WHERE institute_id = 15"
            ).fetchone(),
            (1, 1),
        )

    def test_rerun_is_stable(self) -> None:
        connection = _database()
        load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        before = connection.execute("SELECT COUNT(*) FROM institute_rankings").fetchone()
        report = load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        self.assertEqual(connection.execute("SELECT COUNT(*) FROM institute_rankings").fetchone(), before)
        self.assertEqual(report["inserted"], [])
        self.assertEqual(report["merged"], [])

    def test_rejects_a_count_that_does_not_match_the_official_list(self) -> None:
        batch = copy.deepcopy(BATCH)
        batch["families"]["iit"]["national_count"] = 23
        with self.assertRaisesRegex(BatchError, "official count is 23"):
            load(_database(), batch, SNAPSHOT)

    def test_rejects_institutes_without_a_nirf_entry_or_unknown_departments(self) -> None:
        batch = copy.deepcopy(BATCH)
        batch["institutes"][1]["name"] = "Indian Institute of Technology Nowhere"
        with self.assertRaisesRegex(BatchError, "no NIRF 2025 entry"):
            load(_database(), batch, SNAPSHOT)
        batch = copy.deepcopy(BATCH)
        batch["institutes"][0]["departments"] = ["IIT Bombay (Missing)"]
        with self.assertRaisesRegex(BatchError, "department not found"):
            load(_database(), batch, SNAPSHOT)

    def test_a_name_in_several_cities_needs_nirf_city(self) -> None:
        batch = copy.deepcopy(BATCH)
        batch["families"] = {}
        amity = {"key": "amity-jaipur", "name": "Amity University Rajasthan",
                 "nirf_names": ["Amity University"], "website": "https://amity.edu/jaipur",
                 "family": "private_university", "group": "G7", "ownership": "private",
                 "ugc": {"verified": True, "list_name": "UGC private universities",
                         "source_url": "https://ugc"}}
        batch["institutes"] = [dict(amity)]
        with self.assertRaisesRegex(BatchError, "set nirf_city"):
            load(_database(), batch, SNAPSHOT)
        batch["institutes"] = [dict(amity, nirf_city="Jaipur")]
        connection = _database()
        load(connection, batch, SNAPSHOT)
        self.assertEqual(
            connection.execute(
                "SELECT i.city, r.rank_band, c.ugc_verified FROM institutes i "
                "JOIN institute_rankings r ON r.institute_id = i.id "
                "JOIN institute_classification c ON c.institute_id = i.id "
                "WHERE i.name = 'Amity University Rajasthan'"
            ).fetchone(),
            ("Jaipur", "201-300", 1),
        )

    def test_missing_ownership_is_a_batch_error(self) -> None:
        batch = copy.deepcopy(BATCH)
        del batch["defaults"]["ownership"]
        batch["institutes"] = batch["institutes"][1:]
        batch["families"] = {}
        batch["institutes"][0]["ownership"] = "central_govt"
        with self.assertRaisesRegex(BatchError, "IITs: no ownership given"):
            load(_database(), batch, SNAPSHOT)

    def test_ugc_check_only_and_always_for_private(self) -> None:
        batch = copy.deepcopy(BATCH)
        batch["institutes"][1]["ugc"] = {"verified": True}
        with self.assertRaisesRegex(BatchError, "private institutions only"):
            load(_database(), batch, SNAPSHOT)
        batch = copy.deepcopy(BATCH)
        batch["institutes"][1]["ownership"] = "private"
        with self.assertRaisesRegex(BatchError, "need a UGC Yes/No check"):
            load(_database(), batch, SNAPSHOT)


    def test_overlapping_names_in_one_batch_are_an_error(self) -> None:
        batch = copy.deepcopy(BATCH)
        batch["institutes"][1]["existing"] = ["IIT Bombay"]
        with self.assertRaisesRegex(BatchError, "already belongs to another institute"):
            load(_database(), batch, SNAPSHOT)
        batch = copy.deepcopy(BATCH)
        batch["institutes"][0]["departments"] = [
            {"name": "IIT Bombay (Civil)", "existing": ["IIT Bombay"]}]
        with self.assertRaisesRegex(BatchError, "already belongs to another institute"):
            load(_database(), batch, SNAPSHOT)
        batch = copy.deepcopy(BATCH)
        batch["summary_rows"] = [{"name": "IIT Bombay (Civil)"}]
        with self.assertRaisesRegex(BatchError, "also a listed institute"):
            load(_database(), batch, SNAPSHOT)

    def test_merge_keeps_source_id_courses_and_other_years(self) -> None:
        connection = _database()
        connection.executescript(
            """
            UPDATE institutes SET source_id = 'legacy-iitb' WHERE id = 10;
            INSERT INTO institute_courses (source_id, institute_id, name, level,
              official_course_url, verification_status)
              VALUES ('c1', 10, 'B.Tech Civil', 'UG', 'https://iitb/c1', 'verified');
            INSERT INTO institute_rankings (institute_id, system, year, category, rank, source_url)
              VALUES (10, 'NIRF', 2024, 'Engineering', 3, 'u'),
                     (11, 'NIRF', 2025, 'Law', 9, 'stale');
            """
        )
        load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        self.assertEqual(
            connection.execute("SELECT source_id FROM institutes WHERE id = 11").fetchone(),
            ("legacy-iitb",),
        )
        self.assertEqual(
            connection.execute("SELECT institute_id FROM institute_courses").fetchall(), [(11,)]
        )
        # Other years are kept; this year's rows are replaced by the snapshot.
        self.assertEqual(
            connection.execute(
                "SELECT year, category FROM institute_rankings WHERE institute_id = 11 "
                "ORDER BY year, category"
            ).fetchall(),
            [(2024, "Engineering"), (2025, "Engineering"), (2025, "Overall")],
        )

    def test_an_institute_still_being_built_is_listed_as_not_admitting(self) -> None:
        connection = _database()
        batch = copy.deepcopy(BATCH)
        batch["institutes"][1]["admits_students"] = False
        load(connection, batch, SNAPSHOT)
        self.assertEqual(
            connection.execute(
                "SELECT c.admits_students, c.listed FROM institute_classification c "
                "JOIN institutes i ON i.id = c.institute_id "
                "WHERE i.name = 'Indian Institute of Technology Goa'"
            ).fetchone(),
            (0, 1),
        )
        self.assertEqual(
            connection.execute(
                "SELECT admits_students FROM institute_classification WHERE institute_id = 11"
            ).fetchone(),
            (1,),
        )

    def test_a_one_member_family_is_described_by_its_group(self) -> None:
        connection = _database()
        batch = copy.deepcopy(BATCH)
        batch["families"] = {"iisc": {"national_count": 1, "as_of": "2026-10-01",
                                      "official_list_url": "https://ugc"}}
        batch["institutes"] = [dict(batch["institutes"][1], family="iisc")]
        load(connection, batch, SNAPSHOT)
        self.assertEqual(
            connection.execute(
                "SELECT description FROM institutes WHERE name = 'Indian Institute of Technology Goa'"
            ).fetchone()[0],
            "Indian Institute of Technology Goa — National flagship / Institutes of National "
            "Importance. Verified against IIT Council list of IITs. NIRF 2025: band 101-150 in Engineering.",
        )

    def test_a_spec_description_replaces_the_old_one_and_departments_keep_own_notes(self) -> None:
        connection = _database()
        batch = copy.deepcopy(BATCH)
        batch["institutes"][0]["description"] = "Official description."
        batch["institutes"][0]["notes"] = "Parent note."
        batch["institutes"][0]["departments"][0] = {"name": "IIT Bombay (Civil)", "notes": "Civil note."}
        load(connection, batch, SNAPSHOT)
        self.assertEqual(
            connection.execute("SELECT description FROM institutes WHERE id = 11").fetchone(),
            ("Official description.",),
        )
        self.assertEqual(
            connection.execute(
                "SELECT notes FROM institute_classification WHERE institute_id IN (11, 12, 14) "
                "ORDER BY institute_id"
            ).fetchall(),
            [("Parent note.",), ("Civil note.",), (None,)],
        )

    def test_an_update_without_a_website_keeps_the_known_one(self) -> None:
        connection = _database()
        connection.execute("UPDATE institutes SET website = 'https://www.iitb.ac.in' WHERE id = 11")
        batch = copy.deepcopy(BATCH)
        del batch["institutes"][0]["website"]
        load(connection, batch, SNAPSHOT)
        self.assertEqual(
            connection.execute("SELECT website FROM institutes WHERE id = 11").fetchone(),
            ("https://www.iitb.ac.in",),
        )

    def test_district_is_kept_only_when_city_and_state_are_unchanged(self) -> None:
        connection = _database()
        connection.executescript(
            """
            INSERT INTO institutes (id, name, city, state, district, description)
              VALUES (20, 'Indian Institute of Technology Goa', 'Ponda', 'Goa', 'North Goa', 'x');
            UPDATE institutes SET state = NULL, district = 'Mumbai' WHERE id = 12;
            """
        )
        load(connection, copy.deepcopy(BATCH), SNAPSHOT)
        self.assertEqual(
            connection.execute("SELECT district FROM institutes WHERE id = 20").fetchone(),
            ("North Goa",),
        )
        self.assertEqual(
            connection.execute("SELECT district, state FROM institutes WHERE id = 12").fetchone(),
            (None, "Maharashtra"),
        )

    def test_a_new_campus_is_inserted_as_a_child_and_an_unknown_one_still_fails(self) -> None:
        batch = copy.deepcopy(BATCH)
        batch["institutes"][0]["departments"].append(
            {"name": "IIT Bombay Campus Kochi", "new": True, "city": "Kochi", "state": "Kerala"})
        connection = _database()
        report = load(connection, batch, SNAPSHOT)
        self.assertIn("IIT Bombay Campus Kochi", report["inserted"])
        self.assertEqual(
            connection.execute(
                "SELECT i.city, i.state, i.website, c.parent_institute_id, c.family_slug "
                "FROM institutes i JOIN institute_classification c ON c.institute_id = i.id "
                "WHERE i.name = 'IIT Bombay Campus Kochi'"
            ).fetchone(),
            ("Kochi", "Kerala", "https://www.iitb.ac.in", 11, "iit"),
        )
        # A rerun finds the campus by name instead of inserting it again.
        self.assertEqual(load(connection, copy.deepcopy(batch), SNAPSHOT)["inserted"], [])
        batch["institutes"][0]["departments"][-1].pop("new")
        batch["institutes"][0]["departments"][-1]["name"] = "IIT Bombay Campus Nowhere"
        with self.assertRaisesRegex(BatchError, "department not found"):
            load(_database(), batch, SNAPSHOT)


if __name__ == "__main__":
    unittest.main()
