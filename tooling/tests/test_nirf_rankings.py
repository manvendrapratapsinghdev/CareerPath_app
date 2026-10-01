"""Tests for parsing NIRF ranked and band pages."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tooling"))

from nirf_rankings import clean_name, parse_page  # noqa: E402

RANKED = """
<table id="tbl_overall">
 <tr><th>Institute ID</th><th>Name</th><th>City</th><th>State</th><th>Score</th><th>Rank</th></tr>
 <tr>
  <td>IR-E-U-0456</td>
  <td>Indian Institute of Technology Madras More Details Close
      <table><tr><td>TLR (100)</td><td>RPC (100)</td></tr><tr><td>95.70</td><td>90.74</td></tr></table>
  </td>
  <td>Chennai</td><td>Tamil Nadu</td><td>88.72</td><td>1</td>
 </tr>
 <tr><td>IR-E-U-0001</td><td>Some Institute</td><td>Pune</td><td>Maharashtra</td>
     <td>Rank Withdrawn*</td><td></td></tr>
 <tr><td>IR-N-N-71</td><td>Faculty of Dental Sciences</td><td>Varanasi</td><td>Uttar Pradesh</td>
     <td>Rank Withdrawn*</td><td>18</td></tr>
 <tr><td>IR-E-U-0899</td><td>Indian Institute of Technology Dharwad</td><td>Dharwad</td>
     <td>Karnataka</td><td>51.20</td><td>77</td></tr>
</table>
"""

BAND = """
<p>NIRF 2016-2025</p><h3>Engineering: Rank-band: 101-150</h3>
<table>
 <tr><th>Name</th><th>City</th><th>State</th></tr>
 <tr><td>Indian Institute of Technology Goa</td><td>Ponda</td><td>Goa</td></tr>
 <tr><td></td><td></td><td></td></tr>
</table>
"""

INNOVATION = """
<table id="tbl_overall">
 <tr><th>Institute ID</th><th>Name</th><th>City</th><th>State</th><th>Rank</th></tr>
 <tr><td>IR-I-U-0456</td><td>Indian Institute of Technology Madras Close</td><td>Chennai</td>
     <td>Tamil Nadu</td><td>1</td></tr>
</table>
"""


class NirfRankingsTest(unittest.TestCase):
    def test_ranked_page_skips_pop_ups_and_withdrawn_ranks(self) -> None:
        entries = parse_page(RANKED, "Engineering", "https://example/Eng.html")
        self.assertEqual(
            [(e["name"], e["rank"], e["score"], e["nirf_institute_id"]) for e in entries],
            [
                ("Indian Institute of Technology Madras", 1, 88.72, "IR-E-U-0456"),
                ("Indian Institute of Technology Dharwad", 77, 51.2, "IR-E-U-0899"),
            ],
        )
        self.assertEqual(entries[0]["city"], "Chennai")
        self.assertIsNone(entries[0]["rank_band"])

    def test_band_page_reads_the_band_from_the_page(self) -> None:
        entries = parse_page(BAND, "Engineering", "https://example/Eng150.html")
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["rank_band"], "101-150")
        self.assertIsNone(entries[0]["rank"])
        self.assertEqual((entries[0]["city"], entries[0]["state"]), ("Ponda", "Goa"))

    def test_pages_without_a_score_column(self) -> None:
        entries = parse_page(INNOVATION, "Innovation", "https://example/Inn.html")
        self.assertEqual((entries[0]["rank"], entries[0]["score"]), (1, None))
        self.assertEqual(entries[0]["name"], "Indian Institute of Technology Madras")

    def test_band_page_without_a_band_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            parse_page("<table><tr><td>A</td><td>B</td><td>C</td></tr></table>", "X", "u")

    def test_clean_name(self) -> None:
        self.assertEqual(
            clean_name("Indian  Institute of Science More Details Close | |"),
            "Indian Institute of Science",
        )


if __name__ == "__main__":
    unittest.main()
