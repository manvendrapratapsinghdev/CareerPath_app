#!/usr/bin/env python3
"""Tests for the isolated college-agent runner and assignment contract."""

from __future__ import annotations

import json
import stat
import tempfile
import unittest
from pathlib import Path

import sys


TOOLING_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLING_ROOT))

from college_agents.common import (  # noqa: E402
    INVENTORY_PATH,
    load_json,
    normalize_agent_result,
    validate_agent_result,
)
from prepare_college_agent_manifest import build_manifest  # noqa: E402
from run_college_agent import run_agent  # noqa: E402


FAKE_CODEX = r"""#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

args = sys.argv[1:]
output = Path(args[args.index("--output-last-message") + 1])
prompt = sys.stdin.read()
match = re.search(r'"id":\s*"([^"]+)"', prompt)
if match is None:
    raise SystemExit("institution id not found in prompt")
institution_id = match.group(1)
name_match = re.search(r'"nirf_name":\s*"([^"]+)"', prompt)
payload = {
    "institution_id": institution_id,
    "nirf_name": name_match.group(1) if name_match else institution_id,
    "verification_outcome": "manual_review",
    "district": None,
    "district_verification_status": "pending_official_source",
    "official_website": None,
    "website_verification_status": "ambiguous",
    "description": None,
    "description_verification_status": "pending",
    "record_status": "manual_review",
    "allowed_official_domains": [],
    "verification_sources": [],
    "website_search_evidence": [],
    "course_catalogue_status": "not_found",
    "courses": [],
    "agent_notes": ["Deterministic fake-agent result for orchestration testing."]
}
output.write_text(json.dumps(payload), encoding="utf-8")
print(json.dumps({"type": "fake_agent_completed"}))
"""


class CollegeAgentOrchestrationTest(unittest.TestCase):
    def test_course_ids_are_prefixed_deterministically(self) -> None:
        result = {
            "courses": [
                {
                    "course_id": "btech-computer-science",
                    "career_path_mappings": [],
                }
            ]
        }
        normalized = normalize_agent_result(result, "example-institute")
        self.assertEqual(
            normalized["courses"][0]["course_id"],
            "example-institute-btech-computer-science",
        )
        normalize_agent_result(normalized, "example-institute")
        self.assertEqual(
            normalized["courses"][0]["course_id"],
            "example-institute-btech-computer-science",
        )

    def test_mapping_labels_are_loaded_from_authoritative_tree(self) -> None:
        result = {
            "courses": [
                {
                    "course_id": "example-institute-course",
                    "career_path_mappings": [
                        {
                            "career_node_id": 342,
                            "career_node_slug": "wrong",
                            "career_breadcrumb": "wrong",
                        }
                    ],
                    "mapping_gap": "Incorrect stale gap.",
                }
            ]
        }
        normalized = normalize_agent_result(result, "example-institute")
        mapping = normalized["courses"][0]["career_path_mappings"][0]
        self.assertNotEqual(mapping["career_node_slug"], "wrong")
        self.assertNotEqual(mapping["career_breadcrumb"], "wrong")
        self.assertIsNone(normalized["courses"][0]["mapping_gap"])

    def test_incomplete_verified_result_is_downgraded(self) -> None:
        result = {
            "verification_outcome": "verified",
            "record_status": "verified",
            "website_verification_status": "verified",
            "district": "Nohar",
            "district_verification_status": "pending_official_source",
            "description": "Description",
            "description_verification_status": "verified_official_website",
            "course_catalogue_status": "verified_official_website",
            "verification_sources": [{}, {}],
            "courses": [],
            "agent_notes": [],
        }
        normalized = normalize_agent_result(result, "example-institute")
        self.assertEqual(
            normalized["verification_outcome"],
            "manual_review",
        )
        self.assertEqual(normalized["record_status"], "manual_review")

    def test_parent_official_domain_is_allowed_from_source(self) -> None:
        result = {
            "official_website": "https://college.example.org/",
            "allowed_official_domains": [],
            "verification_sources": [
                {"url": "https://example.org/college-directory"}
            ],
            "courses": [],
        }
        normalized = normalize_agent_result(result, "example-institute")
        self.assertEqual(
            normalized["allowed_official_domains"],
            ["example.org"],
        )

    def test_manifest_contains_up_to_one_hundred_unique_assignments(self) -> None:
        manifest = build_manifest(batch_count=10, batch_size=10)
        assignments = manifest["assignments"]
        inventory = load_json(INVENTORY_PATH)
        eligible_count = sum(
            institution.get("website_verification_status") != "verified"
            and institution.get("record_status") != "remove"
            for institution in inventory["institutions"]
        )
        expected_count = min(100, eligible_count)
        self.assertEqual(len(assignments), expected_count)
        self.assertEqual(
            len({item["institution_id"] for item in assignments}),
            expected_count,
        )
        expected_batch_count = (expected_count + 9) // 10
        for batch in range(1, expected_batch_count + 1):
            expected_batch_size = min(
                10,
                expected_count - ((batch - 1) * 10),
            )
            self.assertEqual(
                sum(item["batch"] == batch for item in assignments),
                expected_batch_size,
            )

    def test_manifest_excludes_previously_attempted_institutions(self) -> None:
        first_manifest = build_manifest(batch_count=1, batch_size=10)
        excluded_ids = {
            item["institution_id"] for item in first_manifest["assignments"]
        }
        next_manifest = build_manifest(
            batch_count=1,
            batch_size=10,
            excluded_ids=excluded_ids,
        )
        next_ids = {
            item["institution_id"] for item in next_manifest["assignments"]
        }
        self.assertTrue(excluded_ids.isdisjoint(next_ids))

    def test_one_institution_runs_in_isolation_and_validates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            fake_codex = temporary_root / "fake-codex"
            fake_codex.write_text(FAKE_CODEX, encoding="utf-8")
            fake_codex.chmod(
                fake_codex.stat().st_mode
                | stat.S_IXUSR
                | stat.S_IXGRP
                | stat.S_IXOTH
            )
            run_dir = temporary_root / "run"
            metrics = run_agent(
                "indian-institute-of-technology-jodhpur",
                run_dir,
                timeout_seconds=30,
                codex_bin=str(fake_codex),
            )
            self.assertEqual(metrics["status"], "completed")
            result_path = (
                run_dir
                / "results"
                / "indian-institute-of-technology-jodhpur.json"
            )
            result = json.loads(result_path.read_text(encoding="utf-8"))
            self.assertEqual(
                validate_agent_result(
                    result,
                    "indian-institute-of-technology-jodhpur",
                ),
                [],
            )


if __name__ == "__main__":
    unittest.main()
