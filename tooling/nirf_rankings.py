#!/usr/bin/env python3
"""Snapshot one year of NIRF rankings (Ministry of Education) into JSON.

NIRF is the only ranking the app shows. Each category has a ranked page
(institute ID, name, city, state, score, rank) and, for some categories, band
pages that list only name, city and state; the band ("101-150") is read
from the page itself because it is not always a round range.

The snapshot is committed under research/official_lists/nirf/ so batch loads
are reproducible and reviewable without re-fetching.

Usage:
  python3 tooling/nirf_rankings.py --year 2025 \
      --output research/official_lists/nirf/nirf_2025.json [--cache-dir DIR]
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import date
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from bs4 import BeautifulSoup

BASE_URL = "https://www.nirfindia.org/Rankings/{year}/"

# Category label (as stored in institute_rankings) -> page prefix.
CATEGORIES = {
    "Overall": "Overall",
    "University": "University",
    "College": "College",
    "Research": "Research",
    "Engineering": "Engineering",
    "Management": "Management",
    "Pharmacy": "Pharmacy",
    "Medical": "Medical",
    "Dental": "Dental",
    "Law": "Law",
    "Architecture and Planning": "Architecture",
    "Agriculture and Allied Sectors": "Agriculture",
    "Innovation": "Innovation",
    "Open University": "OPENUNIVERSITY",
    "Skill University": "SKILLUNIVERSITY",
    "State Public University": "STATEPUBLICUNIVERSITY",
    "SDG Institutions": "SDGInstitutions",
}

# Band pages are found from the ranked page's own links ("EngineeringRanking150.html").
BAND_LINK = r'href="({prefix}Ranking\d+\.html)"'
BAND = re.compile(r"Rank[- ]?band\s*:?\s*(\d{1,3})\s*-\s*(\d{1,3})", re.IGNORECASE)
ANY_RANGE = re.compile(r"\b(\d{2,3})\s*-\s*(\d{2,3})\b")


def clean_name(text: str) -> str:
    """The name cell also holds a pop-up ("More Details", "Close"); keep the name only."""
    name = re.split(r"\s+More Details\b", text, maxsplit=1)[0]
    name = re.sub(r"(?:\s+Close)?[\s|]*$", "", name)
    return re.sub(r"\s+", " ", name).strip()


def _number(text: str) -> float | None:
    try:
        return float(text)
    except ValueError:
        return None


def _rows(table: Any) -> list[list[str]]:
    rows = []
    for row in table.find_all("tr"):
        if row.find_parent("table") is not table:
            continue  # nested pop-up tables
        cells = row.find_all("td", recursive=False)
        if cells:
            rows.append([cell.get_text(" ", strip=True) for cell in cells])
    return rows


def parse_page(html: str, category: str, source_url: str) -> list[dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table", id="tbl_overall")
    entries: list[dict[str, Any]] = []
    if table is not None:  # ranked page
        header = [
            cell.get_text(" ", strip=True)
            for cell in table.find("tr").find_all(["th", "td"], recursive=False)
        ]
        has_score = "Score" in header
        for cells in _rows(table):
            if len(cells) < (6 if has_score else 5):
                continue
            # A withdrawn rank ("Rank Withdrawn*") is not shown, even when the
            # rank column still holds a number.
            if not cells[-1].isdigit() or any("withdrawn" in c.casefold() for c in cells):
                continue
            entries.append(
                {
                    "category": category,
                    "nirf_institute_id": cells[0],
                    "name": clean_name(cells[1]),
                    "city": cells[2],
                    "state": cells[3],
                    "score": _number(cells[4]) if has_score else None,
                    "rank": int(cells[-1]),
                    "rank_band": None,
                    "source_url": source_url,
                }
            )
        return entries
    text = soup.get_text(" ", strip=True)
    band = BAND.search(text) or ANY_RANGE.search(text)
    if band is None:
        raise ValueError(f"no rank band on band page {source_url}")
    table = soup.find("table")
    for cells in _rows(table):
        if len(cells) < 3 or not cells[0]:
            continue
        entries.append(
            {
                "category": category,
                "nirf_institute_id": None,
                "name": clean_name(cells[0]),
                "city": cells[1],
                "state": cells[2],
                "score": None,
                "rank": None,
                "rank_band": f"{band.group(1)}-{band.group(2)}",
                "source_url": source_url,
            }
        )
    return entries


def fetch(url: str, cache_dir: Path | None) -> str | None:
    cached = cache_dir / url.rsplit("/", 1)[-1] if cache_dir else None
    if cached and cached.exists():
        return cached.read_text(encoding="utf-8")
    request = Request(url, headers={"User-Agent": "CareerPathResearch/1.0"})
    try:
        with urlopen(request, timeout=60) as response:
            html = response.read().decode("utf-8", errors="replace")
    except HTTPError as error:
        if error.code == 404:
            return None
        raise
    if cached:
        cached.parent.mkdir(parents=True, exist_ok=True)
        cached.write_text(html, encoding="utf-8")
    return html


def snapshot(year: int, cache_dir: Path | None = None) -> dict[str, Any]:
    base = BASE_URL.format(year=year)
    entries: list[dict[str, Any]] = []
    pages: list[str] = []
    for category, prefix in CATEGORIES.items():
        ranked_url = f"{base}{prefix}Ranking.html"
        ranked = fetch(ranked_url, cache_dir)
        if ranked is None:
            continue
        band_pages = sorted(
            set(re.findall(BAND_LINK.format(prefix=re.escape(prefix)), ranked)),
            key=lambda page: int(re.search(r"(\d+)\.html$", page).group(1)),
        )
        for url, html in [(ranked_url, ranked)] + [
            (base + page, fetch(base + page, cache_dir)) for page in band_pages
        ]:
            if html is None:
                continue
            found = parse_page(html, category, url)
            if found:
                pages.append(url)
                entries.extend(found)
    return {
        "metadata": {
            "source_authority": "National Institutional Ranking Framework, Ministry of Education",
            "year": year,
            "fetched_on": date.today().isoformat(),
            "pages": pages,
            "entry_count": len(entries),
        },
        "entries": entries,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache-dir", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = snapshot(args.year, args.cache_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{payload['metadata']['entry_count']} entries from {len(payload['metadata']['pages'])} pages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
