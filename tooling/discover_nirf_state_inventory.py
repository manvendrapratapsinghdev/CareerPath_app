#!/usr/bin/env python3
"""Discover state institutions from official NIRF participant directories.

NIRF is used only as a discovery and participation source. The resulting
records remain pending until each institution is independently verified from
its official website by the college agents.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

from bs4 import BeautifulSoup


BASE_URL = "https://www.nirfindia.org/Rankings/2025/"
PARTICIPANT_PAGES = {
    "College": "CollegeRankingALL.html",
    "Engineering": "EngineeringRankingALL.html",
    "Management": "ManagementRankingALL.html",
    "Pharmacy": "PharmacyRankingALL.html",
    "Medical": "MedicalRankingALL.html",
    "Dental": "DentalRankingALL.html",
    "Law": "LawRankingALL.html",
    "Architecture and Planning": "ArchitectureRankingALL.html",
    "Agriculture and Allied Sectors": "AgricultureRankingALL.html",
    "Open University": "OPENUNIVERSITYRankingALL.html",
    "Skill University": "SKILLUNIVERSITYRankingALL.html",
    "University": "UniversityRankingALL.html",
    "Overall": "OverallRankingALL.html",
}

# This is the requested discovery order. Private universities and colleges
# share one tier; specialized institutes follow agriculture.
TYPE_PRIORITY = {
    "iit": 0,
    "iim": 1,
    "nit": 2,
    "iiit": 2,
    "central_institute": 3,
    "central_university": 3,
    "state_university": 4,
    "private_university": 5,
    "private_college": 5,
    "government_college": 6,
    "government_aided_college": 6,
    "aided_college": 6,
    "government_polytechnic": 7,
    "polytechnic": 7,
    "medical": 8,
    "law": 9,
    "agriculture": 10,
    "specialized": 11,
    "other": 12,
}

PRIVATE_MARKERS = (
    "amity",
    "bennett",
    "galgotias",
    "gla university",
    "integral university",
    "j p information technology",
    "jaypee",
    "jss academy",
    "sharda",
    "shiv nadar",
    "sanskriti university",
    "noida international",
    "university of petroleum",
)

CENTRAL_MARKERS = (
    "banaras hindu",
    "aligarh muslim",
    "babasaheb bhimrao ambedkar",
    "central university",
    "national institute",
    "indian institute",
)

SPECIALIZED_CATEGORIES = {
    "architecture and planning",
    "pharmacy",
    "open university",
    "skill university",
}


def identity_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.casefold()).strip("-")


def institution_type(name: str, categories: list[str]) -> str:
    folded = name.casefold()
    category_text = {category.casefold() for category in categories}
    if "indian institute of technology" in folded or re.search(r"\biit\b", folded):
        return "iit"
    if "indian institute of management" in folded or folded.startswith("iim "):
        return "iim"
    if "indian institute of information technology" in folded or re.search(r"\biiit\b", folded):
        return "iiit"
    if "national institute of technology" in folded or re.search(r"\bnit\b", folded):
        return "nit"
    if any(marker in folded for marker in CENTRAL_MARKERS):
        return "central_university" if "university" in folded else "central_institute"
    if any(marker in folded for marker in PRIVATE_MARKERS):
        return "private_university" if "university" in folded else "private_college"
    if "university" in folded:
        return "state_university"
    if "polytechnic" in folded or "polytechnic" in category_text:
        return "government_polytechnic"
    if any("medical" in category or "dental" in category for category in category_text):
        return "medical"
    if "law" in category_text or "law" in folded:
        return "law"
    if any("agriculture" in category or "agri" in category for category in category_text):
        return "agriculture"
    if category_text.intersection(SPECIALIZED_CATEGORIES):
        return "specialized"
    if "aided" in folded:
        return "government_aided_college"
    if any(word in folded for word in ("college", "institute", "school")):
        return "government_college"
    return "other"


def fetch_participants(category: str, page: str, state: str) -> list[dict[str, Any]]:
    url = BASE_URL + page
    request = Request(url, headers={"User-Agent": "CareerPathResearch/1.0"})
    with urlopen(request, timeout=60) as response:
        html = response.read().decode("utf-8", errors="replace")
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table", id="tblAllInstitutes")
    if table is None:
        raise ValueError(f"NIRF participant table not found: {url}")
    records: list[dict[str, Any]] = []
    for row in table.find_all("tr")[1:]:
        cells = [cell.get_text(" ", strip=True) for cell in row.find_all("td")]
        if len(cells) < 3 or cells[2].casefold() != state.casefold():
            continue
        name, city = cells[0].strip(), cells[1].strip()
        if not name or not city:
            continue
        records.append(
            {
                "name": name,
                "city": city,
                "state": state,
                "category": category,
                "source_url": url,
            }
        )
    return records


def discover(state: str, limit: int | None = None) -> dict[str, Any]:
    grouped: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for category, page in PARTICIPANT_PAGES.items():
        try:
            records = fetch_participants(category, page, state)
        except Exception as exc:
            errors.append(f"{category}: {type(exc).__name__}: {exc}")
            continue
        for record in records:
            key = identity_key(record["name"])
            institution = grouped.setdefault(
                key,
                {
                    "id": key,
                    "name": record["name"],
                    "city": record["city"],
                    "state": state,
                    "institution_type": institution_type(record["name"], []),
                    "participating_categories": [],
                    "discovery_sources": [],
                },
            )
            if record["category"] not in institution["participating_categories"]:
                institution["participating_categories"].append(record["category"])
            if record["source_url"] not in institution["discovery_sources"]:
                institution["discovery_sources"].append(record["source_url"])

    institutions = list(grouped.values())
    for item in institutions:
        item["institution_type"] = institution_type(
            item["name"], item["participating_categories"]
        )
        item["participating_categories"].sort()
        item["discovery_sources"].sort()
    institutions.sort(
        key=lambda item: (
            TYPE_PRIORITY.get(item["institution_type"], TYPE_PRIORITY["other"]),
            item["name"].casefold(),
            item["id"],
        )
    )
    if limit is not None:
        if limit < 1:
            raise ValueError("limit must be positive")
        institutions = institutions[:limit]
    return {
        "metadata": {
            "title": f"{state} NIRF participant discovery inventory",
            "state": state,
            "source_authority": "National Institutional Ranking Framework, Ministry of Education",
            "source_home": BASE_URL,
            "scope": "NIRF 2025 participant directories across configured higher-education categories; official-site verification remains pending.",
            "discovered_institution_count": len(grouped),
            "selected_institution_count": len(institutions),
            "selection_limit": limit,
            "source_errors": errors,
            "verification_policy": {
                "official_site_required_before_import": True,
                "discovery_only": True,
            },
        },
        "institutions": institutions,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True)
    parser.add_argument("--limit", type=int, help="Optional selection limit, e.g. 150")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = discover(args.state, args.limit)
    args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.output.resolve().write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"Discovered {payload['metadata']['discovered_institution_count']} "
        f"and selected {len(payload['institutions'])} {args.state} institutions"
    )
    for error in payload["metadata"]["source_errors"]:
        print(f"WARNING: {error}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
