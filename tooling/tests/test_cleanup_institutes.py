"""Tests for the duplicate / department / family-record clean-up (plan T4)."""

from __future__ import annotations

import contextlib
import csv
import io
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from cleanup_institutes import COLUMNS, apply, main, propose  # noqa: E402
from domain_tiers import SCHEMA as TIER_SCHEMA  # noqa: E402
from institution_taxonomy import apply as apply_taxonomy  # noqa: E402
from load_family_batch import DEFAULT_DATABASE  # noqa: E402

TABLES = ("institutes", "career_nodes", "node_institutes", "institute_courses",
          "institute_categories", "institute_rankings", "streams")


def _database() -> sqlite3.Connection:
    """In-memory copy of the real tables' definitions, the taxonomy and a few rows."""
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
    apply_taxonomy(connection)
    connection.executescript(TIER_SCHEMA)
    connection.executescript(
        """
        INSERT INTO streams (id, slug, name) VALUES (1, 'science', 'Science');
        INSERT INTO career_nodes (id, slug, stream_id, name) VALUES
          (1, 'btech', 1, 'B.Tech'), (2, 'bams', 1, 'BAMS'), (3, 'mba', 1, 'MBA');
        INSERT INTO domains (slug, name, route_type, sort_order) VALUES
          ('engineering', 'Engineering', 'degree', 1), ('ayush', 'AYUSH', 'degree', 2);
        INSERT INTO domain_nodes VALUES (1, 'engineering'), (2, 'ayush');
        INSERT INTO domain_tiers (domain_slug, tier, label, group_codes) VALUES
          ('engineering', 1, 'National', 'G1'), ('ayush', 1, 'Central', 'G3');
        INSERT INTO institutes (id, name, city, source_id) VALUES
          (10, 'Indian Institute of Technology Bombay', 'Mumbai', NULL),
          (11, 'IIT Bombay (Civil)', 'Mumbai', NULL),
          (12, 'Banaras Hindu University', 'Varanasi', NULL),
          (13, 'Banaras Hindu University (Ayurveda)', 'Varanasi', NULL),
          (20, 'MICA', 'Ahmedabad', NULL),
          (21, 'MICA Ahmedabad', 'Ahmedabad', NULL),
          (30, 'Gujarat National Law University', 'Gandhinagar', NULL),
          (31, 'Gujarat National Law University (GNLU)', 'Gandhinagar', NULL),
          (32, 'National Law University Delhi', 'New Delhi', NULL),
          (33, 'National Law University (NLU) Delhi', 'Delhi', NULL),
          (40, 'DIET', 'Various', NULL),
          (41, 'ITI (Industrial Training Institutes)', 'Various', NULL),
          (50, 'CMC Vellore', 'Vellore', NULL),
          (51, 'CMC Vellore (Nursing)', 'Vellore', NULL),
          (60, 'Amity University', 'Noida', NULL),
          (61, 'Amity University (Actuarial Science)', 'Noida', NULL),
          (62, 'Amity University, Gwalior', 'Gwalior', NULL),
          (70, 'Government College, Ratangarh', 'Ratangarh', 'a'),
          (71, 'Government College, Budhni', 'Budhni', 'b');
        INSERT INTO node_institutes VALUES (3, 21), (1, 11), (2, 13);
        INSERT INTO institute_categories VALUES (21, 'Management');
        INSERT INTO institute_classification (institute_id, group_code, family_slug, ownership,
          ugc_verified, ugc_list_name, ugc_checked_at, confidence, source_url, verified_at) VALUES
          (10, 'G1', 'iit', 'central_govt', NULL, NULL, NULL, 'high', 'https://iit', '2026-10-01'),
          (12, 'G3', 'central_university', 'central_govt', NULL, NULL, NULL, 'high', 'https://ugc',
           '2026-10-01'),
          (30, 'G4', 'nlu', 'state_govt', NULL, NULL, NULL, 'high', 'https://nlu', '2026-10-01'),
          (32, 'G4', 'nlu', 'state_govt', NULL, NULL, NULL, 'high', 'https://nlu', '2026-10-01'),
          (33, 'G4', 'nlu', 'state_govt', NULL, NULL, NULL, 'high', 'https://nlu', '2026-10-01'),
          (60, 'G7', 'private_university', 'private', 1, 'UGC private universities', '2026-10-01',
           'high', 'https://ugc', '2026-10-01');
        """
    )
    return connection


def _by_source(proposals):
    return {p.source.id: p for p in proposals}


def _approved(proposals, *source_ids):
    rows = [p.csv_row() for p in proposals if p.source.id in source_ids]
    return [{k: str(v) for k, v in row.items()} for row in rows]


class ProposeTest(unittest.TestCase):
    def test_proposes_each_action_class_with_confidence(self) -> None:
        proposals = _by_source(propose(_database()))
        merge = proposals[21]
        self.assertEqual((merge.action, merge.confidence, merge.target.id), ("merge", "high", 20))
        # A classified row is the target of an unclassified duplicate.
        self.assertEqual((proposals[31].action, proposals[31].target.id), ("merge", 30))
        department = proposals[13]
        self.assertEqual((department.action, department.confidence, department.status,
                          department.target.id, department.group_code),
                         ("department", "high", "ready", 12, "G3"))
        # "IIT Bombay" is found through its initials, which is less certain.
        self.assertEqual((proposals[11].target.id, proposals[11].confidence), (10, "medium"))
        family = proposals[40]
        self.assertEqual((family.action, family.confidence, family.family_slug, family.ownership,
                          family.group_code),
                         ("family_record", "high", "teacher_education_govt", "state_govt", "G6"))
        self.assertTrue(proposals[41].status.startswith("blocked: mixed ownership"))

    def test_never_proposes_changes_to_classified_rows(self) -> None:
        proposals = propose(_database())
        sources = {p.source.id for p in proposals}
        self.assertFalse(sources & {10, 12, 30, 32, 33, 60})
        # Two classified spellings of one university are left to their batch.
        self.assertFalse(any({p.source.id, getattr(p.target, "id", None)} == {32, 33}
                             for p in proposals))

    def test_blocks_departments_of_unclassified_parents_and_ignores_other_cities(self) -> None:
        proposals = _by_source(propose(_database()))
        self.assertEqual(proposals[51].target.id, 50)
        self.assertTrue(proposals[51].status.startswith("blocked: parent not classified"))
        # Same name in another city is another campus, and a city cut off a
        # generic name ("Government College") is not a duplicate.
        self.assertNotIn(62, proposals)
        self.assertNotIn(70, proposals)
        self.assertNotIn(71, proposals)


class ApplyTest(unittest.TestCase):
    def test_applies_merges_departments_and_family_records(self) -> None:
        connection = _database()
        proposals = propose(connection)
        report = apply(connection, _approved(proposals, 21, 31, 13, 11, 61, 40), "2026-10-02")
        self.assertEqual(report["refused"], [])
        self.assertIsNone(connection.execute("SELECT 1 FROM institutes WHERE id = 21").fetchone())
        self.assertEqual(connection.execute(
            "SELECT node_id FROM node_institutes WHERE institute_id = 20").fetchall(), [(3,)])
        self.assertEqual(connection.execute(
            "SELECT category FROM institute_categories WHERE institute_id = 20").fetchall(),
            [("Management",)])
        self.assertIsNone(connection.execute("SELECT 1 FROM institutes WHERE id = 31").fetchone())
        child = connection.execute(
            "SELECT parent_institute_id, group_code, family_slug, ownership, confidence, "
            "is_family_record FROM institute_classification WHERE institute_id = 13").fetchone()
        self.assertEqual(child, (12, "G3", "central_university", "central_govt", "medium", 0))
        # A private parent's UGC check is copied, as the schema requires.
        self.assertEqual(connection.execute(
            "SELECT parent_institute_id, ugc_verified, ugc_list_name FROM institute_classification "
            "WHERE institute_id = 61").fetchone(), (60, 1, "UGC private universities"))
        self.assertEqual(connection.execute(
            "SELECT group_code, family_slug, is_family_record, ownership FROM "
            "institute_classification WHERE institute_id = 40").fetchone(),
            ("G6", "teacher_education_govt", 1, "state_govt"))
        # Tiers are rebuilt: the departments' career links count for their parents.
        self.assertEqual(sorted(connection.execute(
            "SELECT institute_id, domain_slug, tier FROM institute_domain_tiers")),
            [(10, "engineering", 1), (12, "ayush", 1)])
        self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_refuses_to_touch_classified_rows(self) -> None:
        connection = _database()
        row = {column: "" for column in COLUMNS}
        attempts = [
            {**row, "action": "merge", "source_id": "33",
             "source_name": "National Law University (NLU) Delhi", "target_id": "20",
             "target_name": "MICA"},
            {**row, "action": "department", "source_id": "30",
             "source_name": "Gujarat National Law University", "target_id": "12",
             "target_name": "Banaras Hindu University"},
            {**row, "action": "family_record", "source_id": "32",
             "source_name": "National Law University Delhi", "family_slug": "nlu",
             "ownership": "state_govt"},
        ]
        before = connection.execute("SELECT * FROM institute_classification ORDER BY 1").fetchall()
        report = apply(connection, attempts, "2026-10-02")
        self.assertEqual(len(report["refused"]), 3)
        self.assertEqual(
            connection.execute("SELECT * FROM institute_classification ORDER BY 1").fetchall(),
            before)
        self.assertIsNotNone(connection.execute("SELECT 1 FROM institutes WHERE id = 33").fetchone())

    def test_refuses_stale_names_and_unclassified_parents(self) -> None:
        connection = _database()
        proposals = propose(connection)
        approved = _approved(proposals, 21, 51)
        connection.execute("UPDATE institutes SET name = 'MICA, Ahmedabad' WHERE id = 21")
        report = apply(connection, approved, "2026-10-02")
        self.assertEqual(len(report["refused"]), 2)
        self.assertIn("now named", report["refused"][0] + report["refused"][1])
        self.assertIn("not classified", report["refused"][0] + report["refused"][1])
        self.assertIsNotNone(connection.execute("SELECT 1 FROM institutes WHERE id = 21").fetchone())

    def test_rerun_is_idempotent(self) -> None:
        connection = _database()
        proposals = propose(connection)
        approved = _approved(proposals, 21, 31, 13, 40)
        apply(connection, approved, "2026-10-02")
        snapshot = [connection.execute(f"SELECT * FROM {t} ORDER BY 1, 2").fetchall()
                    for t in ("institutes", "institute_classification", "node_institutes",
                              "institute_domain_tiers")]
        report = apply(connection, approved, "2026-10-02")
        self.assertEqual(len(report["already_applied"]), 4)
        self.assertEqual(report["refused"], [])
        self.assertEqual(snapshot, [connection.execute(f"SELECT * FROM {t} ORDER BY 1, 2").fetchall()
                                    for t in ("institutes", "institute_classification",
                                              "node_institutes", "institute_domain_tiers")])
        # A new dry run no longer proposes what was applied.
        self.assertFalse({p.source.id for p in propose(connection)} & {21, 31, 13, 40})

    def test_a_department_of_a_merged_parent_follows_the_merge(self) -> None:
        connection = _database()
        connection.execute(
            "INSERT INTO institutes (id, name, city) VALUES (14, 'Banaras Hindu University Varanasi', "
            "'Varanasi')")
        row = {column: "" for column in COLUMNS}
        approved = [
            {**row, "action": "department", "source_id": "13",
             "source_name": "Banaras Hindu University (Ayurveda)", "target_id": "14",
             "target_name": "Banaras Hindu University Varanasi"},
            {**row, "action": "merge", "source_id": "14",
             "source_name": "Banaras Hindu University Varanasi", "target_id": "12",
             "target_name": "Banaras Hindu University"},
        ]
        report = apply(connection, approved, "2026-10-02")
        self.assertEqual(report["refused"], [])
        self.assertEqual(connection.execute(
            "SELECT parent_institute_id FROM institute_classification WHERE institute_id = 13"
        ).fetchone(), (12,))


class CommandLineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.database = root / "career_path.db"
        self.review = root / "review.csv"
        source = _database()
        target = sqlite3.connect(self.database)
        source.backup(target)
        target.close()

    def _run(self, *argv: str) -> int:
        with contextlib.redirect_stdout(io.StringIO()):
            return main(["--database", str(self.database), *argv])

    def _count(self) -> int:
        connection = sqlite3.connect(self.database)
        try:
            return connection.execute("SELECT COUNT(*) FROM institutes").fetchone()[0]
        finally:
            connection.close()

    def test_dry_run_is_the_default(self) -> None:
        before = self._count()
        self.assertEqual(self._run("--review", str(self.review)), 0)
        self.assertEqual(self._count(), before)
        with self.review.open(encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(tuple(rows[0]), COLUMNS)
        approved = Path(self.directory.name) / "approved.csv"
        with approved.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=COLUMNS)
            writer.writeheader()
            writer.writerows(r for r in rows if r["key"] == "merge:21")
        # --apply without --write rolls back.
        self.assertEqual(self._run("--apply", str(approved)), 0)
        self.assertEqual(self._count(), before)
        self.assertEqual(self._run("--apply", str(approved), "--write"), 0)
        self.assertEqual(self._count(), before - 1)

    def test_write_needs_apply(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self._run("--write")


if __name__ == "__main__":
    unittest.main()
