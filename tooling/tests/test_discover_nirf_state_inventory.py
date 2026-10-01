"""Tests for the institution type inferred from a NIRF participant name."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from discover_nirf_state_inventory import institution_type  # noqa: E402


class InstitutionTypeTest(unittest.TestCase):
    def test_law_needs_a_whole_word(self) -> None:
        self.assertEqual(
            institution_type("Government Engineering College, Jhalawar", []),
            "government_college",
        )
        self.assertEqual(
            institution_type("Govt. Birla College, Bhawanimandi, Distt. Jhalawar", []),
            "government_college",
        )
        self.assertEqual(institution_type("Lawrence College, Ghaziabad", []), "other")
        self.assertEqual(institution_type("Biyani Law College", []), "law")
        self.assertEqual(institution_type("Shri LLB Institute", []), "law")
        self.assertEqual(institution_type("Any College", ["Law"]), "law")

    def test_colleges_are_not_government_unless_the_name_says_so(self) -> None:
        for name in (
            "Acropolis Institute Of Technology And Research",
            "Jaipur Engineering College & Research Center, jaipur",
            "Dewan Institute of Management Studies, Meerut",
            "Biyani Institute of Science & Management",
        ):
            with self.subTest(name=name):
                self.assertEqual(institution_type(name, []), "other")
        for name in (
            "Government College, Ratangarh",
            "BBD GOVT PG COLLEGE CHIMANPURA, JAIPUR",
            "Rajkiya Mahavidyalaya, Sikar",
        ):
            with self.subTest(name=name):
                self.assertEqual(institution_type(name, []), "government_college")

    def test_aided_colleges_keep_their_type(self) -> None:
        self.assertEqual(
            institution_type("Shri Ram Aided College", []), "government_aided_college"
        )

    def test_national_types_are_unchanged(self) -> None:
        self.assertEqual(institution_type("Indian Institute of Technology Jodhpur", []), "iit")
        self.assertEqual(institution_type("Malaviya National Institute of Technology", []), "nit")
        self.assertEqual(institution_type("Indian Institute of Management Udaipur", []), "iim")


if __name__ == "__main__":
    unittest.main()
