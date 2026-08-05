#!/usr/bin/env python3
"""Build the Rajasthan NIRF discovery inventory.

NIRF is authoritative for participation and ranking data. It is not treated as
authoritative for official websites, districts, or course catalogues; those
fields remain pending until an institution's official site is verified.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import urllib.request
from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from bs4 import BeautifulSoup, Tag


BASE_URL = "https://www.nirfindia.org/Rankings/2025/"
STATE = "Rajasthan"

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
}

RANKING_PAGES = {
    "Overall": "OverallRanking.html",
    "University": "UniversityRanking.html",
    "College": "CollegeRanking.html",
    "Engineering": "EngineeringRanking.html",
    "Management": "ManagementRanking.html",
    "Pharmacy": "PharmacyRanking.html",
    "Medical": "MedicalRanking.html",
    "Dental": "DentalRanking.html",
    "Law": "LawRanking.html",
    "Architecture and Planning": "ArchitectureRanking.html",
    "Agriculture and Allied Sectors": "AgricultureRanking.html",
    "Open University": "OPENUNIVERSITYRanking.html",
    "Skill University": "SKILLUNIVERSITYRanking.html",
    "State Public University": "STATEPUBLICUNIVERSITYRanking.html",
}

RANK_BAND_PAGES = {
    "Overall": {
        "101-150": "OverallRanking150.html",
        "151-200": "OverallRanking200.html",
    },
    "University": {
        "101-150": "UniversityRanking150.html",
        "151-200": "UniversityRanking200.html",
    },
    "College": {
        "101-150": "CollegeRanking150.html",
        "151-200": "CollegeRanking200.html",
        "201-300": "CollegeRanking300.html",
    },
    "Engineering": {
        "101-150": "EngineeringRanking150.html",
        "151-200": "EngineeringRanking200.html",
        "201-300": "EngineeringRanking300.html",
    },
    "Management": {"101-125": "ManagementRanking150.html"},
    "Pharmacy": {"102-125": "PharmacyRanking150.html"},
    "State Public University": {
        "51-100": "STATEPUBLICUNIVERSITYRanking100.html"
    },
}

# Only aliases observed in NIRF category pages are collapsed. This intentionally
# avoids broad fuzzy merging of institutions with similar names.
IDENTITY_ALIASES = {
    "birla institute of technology and science pilani": "bits-pilani",
    "bits pilani": "bits-pilani",
    "geetanjali university": "geetanjali-university",
    "jaipuria institute of management": "jaipuria-institute-of-management-jaipur",
    "mahatma gandhi university of medical sciences and technology jaipur": (
        "mahatma-gandhi-university-of-medical-sciences-and-technology"
    ),
    "nims university jaipur": "nims-university-rajasthan",
    "nims university rajasthan": "nims-university-rajasthan",
    "the lnm institute of information technology jaipur": (
        "lnm-institute-of-information-technology"
    ),
}

DATABASE_GROUP_ALIASES = {
    "bits-pilani": {
        "bits-pilani",
        "bits-pilani-pharmacy",
    },
}


@dataclass(frozen=True)
class NirfEntry:
    name: str
    city: str
    category: str
    source: str
    nirf_id: str | None = None
    rank: int | None = None
    rank_band: str | None = None
    score: float | None = None


def normalized_words(value: str) -> str:
    value = value.casefold().replace("&", " and ")
    return re.sub(r"[^a-z0-9]+", " ", value).strip()


def identity_key(name: str) -> str:
    normalized = normalized_words(name)
    if normalized in IDENTITY_ALIASES:
        return IDENTITY_ALIASES[normalized]
    return normalized.replace(" ", "-")


def fetch_html(page: str) -> tuple[str, str]:
    url = BASE_URL + page
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "text/html,application/xhtml+xml",
            "User-Agent": "CareerPathResearch/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return url, response.read().decode("utf-8", errors="replace")


def direct_cells(row: Tag) -> list[Tag]:
    return row.find_all("td", recursive=False)


def direct_rows(table: Tag) -> list[Tag]:
    body = table.find("tbody", recursive=False)
    if body is None:
        return []
    return body.find_all("tr", recursive=False)


def first_cell_text(cell: Tag) -> str:
    strings = list(cell.stripped_strings)
    return strings[0] if strings else ""


def parse_participants(category: str, page: str) -> list[NirfEntry]:
    url, html = fetch_html(page)
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table", id="tblAllInstitutes")
    if not isinstance(table, Tag):
        raise ValueError(f"Participant table not found: {url}")

    entries: list[NirfEntry] = []
    for row in direct_rows(table):
        cells = direct_cells(row)
        if len(cells) != 3:
            continue
        name, city, state = (cell.get_text(" ", strip=True) for cell in cells)
        if state == STATE:
            entries.append(
                NirfEntry(
                    name=name,
                    city=city,
                    category=category,
                    source=url,
                )
            )
    return entries


def parse_rankings(category: str, page: str) -> list[NirfEntry]:
    url, html = fetch_html(page)
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table", id="tbl_overall")
    if not isinstance(table, Tag):
        # Some categories legitimately publish no ranked table.
        return []

    entries: list[NirfEntry] = []
    for row in direct_rows(table):
        cells = direct_cells(row)
        if len(cells) < 6:
            continue
        state = cells[3].get_text(" ", strip=True)
        if state != STATE:
            continue
        entries.append(
            NirfEntry(
                name=first_cell_text(cells[1]),
                city=cells[2].get_text(" ", strip=True),
                category=category,
                source=url,
                nirf_id=cells[0].get_text(" ", strip=True),
                score=float(cells[4].get_text(" ", strip=True)),
                rank=int(cells[5].get_text(" ", strip=True)),
            )
        )
    return entries


def parse_rank_band(
    category: str,
    rank_band: str,
    page: str,
) -> list[NirfEntry]:
    url, html = fetch_html(page)
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table")
    if not isinstance(table, Tag):
        return []

    entries: list[NirfEntry] = []
    for row in direct_rows(table):
        cells = direct_cells(row)
        if len(cells) != 3:
            continue
        name, city, state = (cell.get_text(" ", strip=True) for cell in cells)
        if state == STATE:
            entries.append(
                NirfEntry(
                    name=name,
                    city=city,
                    category=category,
                    source=url,
                    rank_band=rank_band,
                )
            )
    return entries


def load_database_records(database_path: Path) -> list[dict[str, Any]]:
    connection = sqlite3.connect(database_path)
    connection.row_factory = sqlite3.Row
    try:
        nodes = {
            row["id"]: {
                "node_id": row["id"],
                "career_node_slug": row["slug"],
                "career_node_name": row["name"],
                "parent_id": row["parent_id"],
            }
            for row in connection.execute(
                "SELECT id, slug, name, parent_id FROM career_nodes"
            )
        }
        child_counts = {
            row["parent_id"]: row["child_count"]
            for row in connection.execute(
                "SELECT parent_id, COUNT(*) AS child_count "
                "FROM career_nodes WHERE parent_id IS NOT NULL "
                "GROUP BY parent_id"
            )
        }

        def breadcrumb(node_id: int) -> str:
            names: list[str] = []
            seen: set[int] = set()
            current_id: int | None = node_id
            while current_id is not None and current_id not in seen:
                seen.add(current_id)
                node = nodes[current_id]
                names.append(node["career_node_name"])
                current_id = node["parent_id"]
            return " > ".join(reversed(names))

        records = []
        for institute in connection.execute(
            "SELECT id, name, city, website, description FROM institutes"
        ):
            career_path_mappings = [
                {
                    "career_node_id": row["node_id"],
                    "career_node_slug": nodes[row["node_id"]][
                        "career_node_slug"
                    ],
                    "career_node_name": nodes[row["node_id"]][
                        "career_node_name"
                    ],
                    "career_breadcrumb": breadcrumb(row["node_id"]),
                    "is_leaf": child_counts.get(row["node_id"], 0) == 0,
                }
                for row in connection.execute(
                    "SELECT node_id FROM node_institutes "
                    "WHERE institute_id = ? ORDER BY node_id",
                    (institute["id"],),
                )
            ]
            records.append(
                {
                    "id": institute["id"],
                    "name": institute["name"],
                    "city": institute["city"],
                    "website": institute["website"],
                    "description": institute["description"],
                    "career_path_mappings": career_path_mappings,
                }
            )
        return records
    finally:
        connection.close()


def find_database_matches(
    institution_name: str,
    database_records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    target_key = identity_key(institution_name)
    accepted_keys = DATABASE_GROUP_ALIASES.get(target_key, {target_key})
    exact = [
        {
            "match_method": (
                "identity_group_alias"
                if identity_key(record["name"]) != target_key
                else "identity_key"
            ),
            **record,
        }
        for record in database_records
        if identity_key(record["name"]) in accepted_keys
    ]
    if exact:
        return exact

    target_words = normalized_words(institution_name)
    candidates = sorted(
        (
            (
                SequenceMatcher(
                    None,
                    target_words,
                    normalized_words(record["name"]),
                ).ratio(),
                record,
            )
            for record in database_records
        ),
        key=lambda item: item[0],
        reverse=True,
    )
    if candidates and candidates[0][0] >= 0.94:
        return [
            {
                "match_method": f"fuzzy_{candidates[0][0]:.3f}",
                **candidates[0][1],
            }
        ]
    return []


def load_verifications(
    verification_path: Path | None,
) -> dict[str, dict[str, Any]]:
    if verification_path is None or not verification_path.exists():
        return {}
    payload = json.loads(verification_path.read_text(encoding="utf-8"))
    records = payload.get("institutions", [])
    if not isinstance(records, list):
        raise ValueError("Verification file 'institutions' must be a list")
    result: dict[str, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            raise ValueError("Every verification record requires a string id")
        if record["id"] in result:
            raise ValueError(f"Duplicate verification id: {record['id']}")
        result[record["id"]] = record
    return result


def build_inventory(
    database_path: Path,
    verification_path: Path | None = None,
) -> dict[str, Any]:
    participants: list[NirfEntry] = []
    rankings: list[NirfEntry] = []

    for category, page in PARTICIPANT_PAGES.items():
        participants.extend(parse_participants(category, page))
    for category, page in RANKING_PAGES.items():
        rankings.extend(parse_rankings(category, page))
    for category, bands in RANK_BAND_PAGES.items():
        for rank_band, page in bands.items():
            rankings.extend(parse_rank_band(category, rank_band, page))

    grouped: dict[str, dict[str, Any]] = {}
    database_records = load_database_records(database_path)
    verifications = load_verifications(verification_path)

    for entry in participants + rankings:
        key = identity_key(entry.name)
        institution = grouped.setdefault(
            key,
            {
                "id": key,
                "nirf_name": entry.name,
                "nirf_city": entry.city,
                "state": STATE,
                "district": None,
                "district_verification_status": "pending_official_source",
                "participating_categories": set(),
                "rankings": [],
                "official_website": None,
                "website_verification_status": "pending",
                "description": None,
                "description_verification_status": "pending",
                "courses": [],
                "course_catalogue_status": "pending_official_website",
                "verification_sources": [],
                "record_status": "candidate",
                "existing_database_records": [],
            },
        )
        if entry.rank is None and entry.rank_band is None:
            institution["participating_categories"].add(entry.category)
        else:
            ranking = {
                "system": "NIRF",
                "year": 2025,
                "category": entry.category,
                "nirf_institute_id": entry.nirf_id,
                "rank": entry.rank,
                "rank_band": entry.rank_band,
                "score": entry.score,
                "source": entry.source,
            }
            if ranking not in institution["rankings"]:
                institution["rankings"].append(ranking)

    for institution in grouped.values():
        institution["existing_database_records"] = find_database_matches(
            institution["nirf_name"],
            database_records,
        )
        institution["participating_categories"] = sorted(
            institution["participating_categories"]
        )
        institution["rankings"].sort(
            key=lambda ranking: (
                ranking["category"],
                ranking["rank"] if ranking["rank"] is not None else 10_000,
                ranking["rank_band"] or "",
            )
        )

    unknown_verification_ids = sorted(set(verifications) - set(grouped))
    if unknown_verification_ids:
        raise ValueError(
            "Verification records do not match NIRF institutions: "
            + ", ".join(unknown_verification_ids)
        )

    verified_fields = {
        "district",
        "district_verification_status",
        "official_website",
        "website_verification_status",
        "description",
        "description_verification_status",
        "courses",
        "course_catalogue_status",
        "verification_sources",
        "website_search_evidence",
        "agent_notes",
        "allowed_official_domains",
        "record_status",
    }
    for key, verification in verifications.items():
        institution = grouped[key]
        for field in verified_fields:
            if field in verification:
                institution[field] = verification[field]

    institutions = sorted(
        grouped.values(),
        key=lambda institution: (
            institution["nirf_city"].casefold(),
            institution["nirf_name"].casefold(),
        ),
    )
    ranked_count = sum(bool(item["rankings"]) for item in institutions)
    matched_count = sum(
        bool(item["existing_database_records"]) for item in institutions
    )
    matched_record_count = sum(
        len(item["existing_database_records"]) for item in institutions
    )
    website_verified_count = sum(
        item["website_verification_status"] == "verified"
        for item in institutions
    )
    course_verified_count = sum(
        item["course_catalogue_status"] == "verified_official_website"
        for item in institutions
    )
    removal_count = sum(
        item["record_status"] == "remove" for item in institutions
    )
    category_counts: dict[str, int] = defaultdict(int)
    for entry in participants:
        category_counts[entry.category] += 1

    return {
        "metadata": {
            "title": "Rajasthan NIRF 2025 master institution inventory",
            "generated_on": date.today().isoformat(),
            "state": STATE,
            "source_authority": "NIRF, Ministry of Education, Government of India",
            "source_home": BASE_URL + "Ranking.html",
            "scope": (
                "All Rajasthan institutions found in configured NIRF 2025 "
                "participating, ranked, and rank-band pages."
            ),
            "participant_category_row_count": len(participants),
            "unique_institution_count": len(institutions),
            "ranked_or_banded_institution_count": ranked_count,
            "institutions_with_existing_database_records": matched_count,
            "existing_database_record_count": matched_record_count,
            "verified_official_website_count": website_verified_count,
            "verified_course_catalogue_count": course_verified_count,
            "removal_candidate_count": removal_count,
            "participant_counts_by_category": dict(sorted(category_counts.items())),
            "verification_policy": {
                "nirf": [
                    "institution name",
                    "NIRF city",
                    "participating categories",
                    "rank",
                    "rank band",
                    "score",
                ],
                "official_institution_website": [
                    "district",
                    "official website",
                    "description",
                    "exact course catalogue",
                    "course details",
                ],
                "career_path_database": [
                    "career node ID",
                    "career node slug",
                    "career breadcrumb",
                    "course-to-career mapping",
                ],
            },
            "course_contract": {
                "course_id": "stable institution-scoped slug",
                "name": "official course or programme name",
                "level": (
                    "official programme level, normalized to certificate, "
                    "diploma, undergraduate, postgraduate, or doctoral when "
                    "the institution does not use its own level name"
                ),
                "credential": "for example B.Tech, MBBS, MBA, or Ph.D",
                "specialization": "official specialization when applicable",
                "duration": "official duration",
                "mode": "on-campus, online, distance, or hybrid",
                "eligibility": "official summarized eligibility",
                "official_course_url": "official page proving the course",
                "verification_status": "pending or verified",
                "career_path_mappings": [
                    {
                        "career_node_id": "integer ID from career_nodes",
                        "career_node_slug": "stable slug from career_nodes",
                        "career_breadcrumb": "complete career tree breadcrumb",
                        "relation": "direct, specialization, or career_outcome",
                        "confidence": "high, medium, or low",
                        "mapping_status": "pending or verified",
                    }
                ],
            },
        },
        "institutions": institutions,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--database",
        type=Path,
        default=Path("assets/data/career_path.db"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Write JSON to this path; stdout is used when omitted.",
    )
    parser.add_argument(
        "--verifications",
        type=Path,
        default=Path("research/rajasthan_institution_verifications.json"),
        help="Curated official-site verification records to merge when present.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    inventory = build_inventory(args.database, args.verifications)
    rendered = json.dumps(inventory, ensure_ascii=False, indent=2) + "\n"
    if args.output is None:
        sys.stdout.write(rendered)
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
