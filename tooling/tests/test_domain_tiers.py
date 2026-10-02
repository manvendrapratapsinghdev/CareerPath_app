"""Tests for domains, tier ladders and institute tiers."""

from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from domain_tiers import DOMAINS, NODE_DOMAINS, assign_tiers, ladder, seed, tier_for  # noqa: E402
from institution_taxonomy import apply  # noqa: E402
from load_family_batch import DEFAULT_DATABASE  # noqa: E402

TABLES = ("institutes", "career_nodes", "node_institutes", "streams")


def _database() -> sqlite3.Connection:
    """The real career tree, an empty institute list and the taxonomy."""
    source = sqlite3.connect(DEFAULT_DATABASE)
    ddl = [row[0] for row in source.execute(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL "
        f"AND name IN ({','.join('?' * len(TABLES))})", TABLES)]
    streams = source.execute("SELECT id, slug, name FROM streams").fetchall()
    nodes = source.execute("SELECT id, slug, stream_id, parent_id, name FROM career_nodes").fetchall()
    source.close()
    connection = sqlite3.connect(":memory:")
    for statement in ddl:
        connection.execute(statement)
    connection.executemany("INSERT INTO streams (id, slug, name) VALUES (?, ?, ?)", streams)
    connection.executemany(
        "INSERT INTO career_nodes (id, slug, stream_id, parent_id, name) VALUES (?, ?, ?, ?, ?)", nodes)
    connection.execute("PRAGMA foreign_keys = ON")  # parents are inserted in any order above
    apply(connection)
    seed(connection)
    return connection


def _node(connection: sqlite3.Connection, slug: str) -> int:
    return connection.execute("SELECT id FROM career_nodes WHERE slug = ?", (slug,)).fetchone()[0]


def _add(connection, institute_id, name, group, family, nodes, parent=None, family_record=0):
    connection.execute("INSERT INTO institutes (id, name) VALUES (?, ?)", (institute_id, name))
    connection.execute(
        "INSERT INTO institute_classification (institute_id, group_code, family_slug, ownership, "
        "parent_institute_id, is_family_record, confidence) VALUES (?, ?, ?, 'central_govt', ?, ?, 'high')",
        (institute_id, group, family, parent, family_record))
    for slug in nodes:
        connection.execute("INSERT INTO node_institutes (node_id, institute_id) VALUES (?, ?)",
                           (_node(connection, slug), institute_id))


class DomainTiersTest(unittest.TestCase):
    def test_seed_maps_every_node_and_builds_every_ladder(self) -> None:
        connection = _database()
        count = lambda sql: connection.execute(sql).fetchone()[0]
        self.assertEqual(count("SELECT COUNT(*) FROM domains"), len(DOMAINS))
        self.assertEqual(count("SELECT COUNT(*) FROM domain_nodes"), len(NODE_DOMAINS))
        self.assertEqual(count("SELECT COUNT(DISTINCT domain_slug) FROM domain_tiers"), len(DOMAINS))
        self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])
        # Every L2 node of the real tree belongs to a domain.
        unmapped = connection.execute(
            "SELECT c.slug FROM career_nodes c JOIN career_nodes r ON r.id = c.parent_id "
            "WHERE r.parent_id IS NULL AND c.id NOT IN (SELECT node_id FROM domain_nodes)").fetchall()
        self.assertEqual(unmapped, [])

    def test_law_puts_national_law_universities_above_institutes_of_national_importance(self) -> None:
        rows = ladder("law")
        self.assertEqual(rows[0], (1, "National Law Universities", "G4", "nlu"))
        self.assertEqual(rows[1][1:3], ("Institutes of National Importance", "G1"))
        compact = [(tier, groups, families) for tier, _, groups, families in rows]
        self.assertEqual(tier_for(compact, "G4", "nlu"), 1)
        self.assertEqual(tier_for(compact, "G1", "iit"), 2)
        self.assertEqual(tier_for(compact, "G4", "state_university"), 5)
        self.assertIsNone(tier_for(compact, "G10b", "coaching_civil_services"))

    def test_assigns_tiers_from_career_links_including_departments(self) -> None:
        connection = _database()
        _add(connection, 1, "IIT Kharagpur", "G1", "iit", ["btech"])
        _add(connection, 2, "IIT Kharagpur law school", "G1", "iit", ["ba_llb"], parent=1)
        _add(connection, 3, "NIT Rourkela", "G2", "nit", ["btech_civil"])  # a branch below B.Tech
        _add(connection, 4, "NLSIU", "G4", "nlu", ["ba_llb"])
        _add(connection, 5, "IITs", "G1", "iit", ["btech"], family_record=1)
        report = assign_tiers(connection)
        self.assertEqual(
            connection.execute(
                "SELECT institute_id, domain_slug, tier FROM institute_domain_tiers ORDER BY 1, 2").fetchall(),
            [(1, "engineering", 1), (1, "law", 2), (3, "engineering", 2), (4, "law", 1)],
        )
        self.assertEqual(report, {"institute_tiers": 4, "unplaced": 0})

    def test_professional_bodies_close_the_ladders_they_teach(self) -> None:
        connection = _database()
        _add(connection, 1, "ICAI", "G10a", "icai", ["ca", "accountant"])
        _add(connection, 2, "IAI", "G10a", "iai", ["actuarial_science"])
        _add(connection, 3, "NISM", "G10a", "finance_certification_body", ["financial_analyst"])
        report = assign_tiers(connection)
        domains = connection.execute(
            "SELECT institute_id, domain_slug FROM institute_domain_tiers ORDER BY 1, 2").fetchall()
        self.assertIn((1, "commerce_finance"), domains)
        self.assertIn((2, "science"), domains)
        self.assertIn((3, "management"), domains)
        self.assertEqual(report["unplaced"], 0)
        last = ladder("management")[-1]
        self.assertEqual(last[2:], ("G10a", "finance_certification_body"))

    def test_seed_rejects_an_unknown_apex_family(self) -> None:
        connection = _database()
        connection.execute("DELETE FROM families WHERE slug = 'nlu'")
        with self.assertRaisesRegex(ValueError, "unknown apex families: \\['nlu'\\]"):
            seed(connection)

    def test_rerun_rebuilds_the_derived_table(self) -> None:
        connection = _database()
        _add(connection, 1, "IIT Bombay", "G1", "iit", ["btech"])
        assign_tiers(connection)
        connection.execute("DELETE FROM node_institutes")
        self.assertEqual(assign_tiers(connection), {"institute_tiers": 0, "unplaced": 0})
        seed(connection)  # reseeding is safe too
        self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])


if __name__ == "__main__":
    unittest.main()
