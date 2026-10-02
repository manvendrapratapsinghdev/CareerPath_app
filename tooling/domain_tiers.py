#!/usr/bin/env python3
"""Domains, their tier ladders and each institute's tier per domain.

The second axis of docs/plans/INSTITUTION_HIERARCHY_PLAN.md: the group
(G1..G11) says what kind of body an institute is; the tier says where it sits
on one subject's ladder. NLSIU is a G4 state university but Law tier 1; IIT
Kharagpur is Engineering tier 1 and Law tier 2 (its law school).

* domains:       the subject areas students choose (engineering, law, ca ...).
* domain_nodes:  which career-tree node belongs to which domain. A node's
                 descendants inherit its domain.
* domain_tiers:  each domain's ladder. Optional "apex" tiers pick institutes
                 by family (National Law Universities first in Law); the rest
                 follow the group order.
* institute_domain_tiers: derived. For every classified top-level institute
                 and every domain it is linked to through node_institutes.

A tier is never a quality score: it comes only from group and family. NIRF
rank is shown next to it, never mixed into it.

Safe to re-run; the derived table is rebuilt. The batch loader calls
assign_tiers() after every batch.

Usage: python3 tooling/domain_tiers.py [--database path]
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS domains (
  slug TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  route_type TEXT NOT NULL CHECK (route_type IN ('degree', 'professional_body', 'exam', 'mixed')),
  regulators TEXT,
  entrance_exams TEXT,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS domain_nodes (
  node_id INTEGER PRIMARY KEY REFERENCES career_nodes(id) ON DELETE CASCADE,
  domain_slug TEXT NOT NULL REFERENCES domains(slug)
);
CREATE INDEX IF NOT EXISTS idx_domain_nodes_domain ON domain_nodes(domain_slug);

CREATE TABLE IF NOT EXISTS domain_tiers (
  domain_slug TEXT NOT NULL REFERENCES domains(slug),
  tier INTEGER NOT NULL,
  label TEXT NOT NULL,
  group_codes TEXT NOT NULL,              -- 'G4' or 'G5,G7'
  family_slugs TEXT,                      -- 'nlu': an apex tier picks these families only
  entry_exams TEXT,
  PRIMARY KEY (domain_slug, tier)
);

CREATE TABLE IF NOT EXISTS institute_domain_tiers (
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  domain_slug TEXT NOT NULL,
  tier INTEGER NOT NULL,
  PRIMARY KEY (institute_id, domain_slug),
  FOREIGN KEY (domain_slug, tier) REFERENCES domain_tiers(domain_slug, tier)
);
CREATE INDEX IF NOT EXISTS idx_institute_domain_tiers_order
  ON institute_domain_tiers(domain_slug, tier);
"""

# (slug, name, route_type, regulators, entrance exams). Plan §4.
DOMAINS = [
    ("engineering", "Engineering", "degree", "AICTE", "JEE Advanced; JEE Main; state CETs"),
    ("computing", "Computing, Data and AI", "degree", "AICTE; UGC", "JEE Main; CUET; university tests"),
    ("science", "Pure science and research", "degree", "UGC", "IAT; NEST; CUET; JAM"),
    ("medical", "Medicine (MBBS)", "degree", "NMC", "NEET-UG"),
    ("dental", "Dental (BDS)", "degree", "DCI", "NEET-UG"),
    ("ayush", "AYUSH (BAMS, BHMS ...)", "degree", "NCISM; NCH", "NEET-UG"),
    ("nursing_allied", "Nursing and allied health", "degree", "INC; NCAHP", "State and university tests"),
    ("pharmacy", "Pharmacy", "degree", "PCI", "State CETs; GPAT; NIPER JEE"),
    ("veterinary", "Veterinary science", "degree", "VCI", "NEET-UG; state tests"),
    ("agriculture", "Agriculture and food", "degree", "ICAR", "ICAR AIEEA (CUET); state tests"),
    ("architecture", "Architecture and planning", "degree", "CoA", "JEE Main Paper 2; NATA"),
    ("design", "Design and fashion", "degree", None, "NID DAT; NIFT; UCEED"),
    ("management", "Management", "degree", "AICTE; UGC", "CAT; XAT; IPMAT; CMAT"),
    ("commerce_finance", "Commerce and finance", "degree", "UGC", "CUET; university tests"),
    ("ca_cma_cs", "CA, CMA and CS", "professional_body", "ICAI; ICMAI; ICSI", "CA Foundation; CMA Foundation; CSEET"),
    ("banking_insurance", "Banking and insurance", "exam", "RBI; IRDAI", "IBPS; SBI; RBI Grade B"),
    ("law", "Law", "degree", "BCI", "CLAT; AILET; university tests"),
    ("civil_services", "Civil services and government jobs", "exam", None, "UPSC CSE; state PCS; SSC"),
    ("defence", "Defence", "exam", None, "UPSC NDA; CDS; AFCAT"),
    ("aviation_maritime", "Aviation and maritime", "mixed", "DGCA; DGS", "IGRUA test; IMU CET"),
    ("media", "Media, journalism and film", "degree", None, "IIMC; FTII JET; university tests"),
    ("fine_performing_arts", "Fine and performing arts", "degree", None, "Auditions; university tests"),
    ("humanities", "Humanities and social sciences", "degree", "UGC", "CUET"),
    ("languages", "Languages and literature", "degree", "UGC", "CUET"),
    ("education", "Education and teaching", "degree", "NCTE", "State B.Ed tests"),
    ("sports", "Sports and physical education", "degree", None, "Institute tests"),
    ("hospitality", "Hospitality and tourism", "degree", "NCHMCT", "NCHM JEE"),
]

# Career node slug -> domain. Descendants inherit. Root nodes are mapped only
# when every child belongs to the same domain.
NODE_DOMAINS = {
    "btech": "engineering", "diploma_engg": "engineering",
    "bca": "computing", "bsc_cs": "computing", "bsc_ai": "computing", "bsc_ds": "computing",
    "science_data": "computing",
    "bsc_electronics": "science", "bsc_geology": "science", "bsc_maths": "science", "bsc_meteorology": "science",
    "bsc_oceanography": "science", "bsc_stats": "science", "integrated_msc": "science", "bsc_bio": "science",
    "bsc_chemistry": "science", "bsc_env": "science", "bsc_forensic": "science", "bsc_physics": "science",
    "bsc_biochem": "science", "bsc_microbio": "science",
    "mbbs": "medical", "bds": "dental", "bams": "ayush", "bhms": "ayush",
    "bsc_nursing": "nursing_allied", "bpt": "nursing_allied", "bsc_optometry": "nursing_allied",
    "bsc_radiology": "nursing_allied", "dmlt": "nursing_allied",
    "bpharm": "pharmacy", "bvsc": "veterinary",
    "bsc_agriculture": "agriculture", "bsc_food_tech": "agriculture",
    "barch_sci": "architecture", "barch": "architecture",
    "bdes": "design", "nid": "design", "nift": "design",
    "bba": "management", "bba_hr": "management", "bba_marketing": "management", "entrepreneurship": "management",
    "bba_finance": "management", "commerce_management": "management",
    "bcom": "commerce_finance", "bcom_finance": "commerce_finance", "cfa_course": "commerce_finance",
    "crypto_analyst": "commerce_finance", "fintech_analyst": "commerce_finance",
    "ca": "ca_cma_cs", "cma_course": "ca_cma_cs", "cs_course": "ca_cma_cs",
    "bank_po": "banking_insurance", "insurance_sector": "banking_insurance", "rbi_grade_b": "banking_insurance",
    "wealth_manager": "banking_insurance", "commerce_banking": "banking_insurance",
    "bba_llb": "law", "bcom_llb": "law", "cyber_lawyer_comm": "law", "ipr_lawyer": "law", "ba_llb": "law",
    "commerce_law": "law",
    "upsc": "civil_services", "ssc_cgl": "civil_services", "pcs": "civil_services",
    "nda": "defence", "cds_course": "defence",
    "merchant_navy": "aviation_maritime", "pilot_training": "aviation_maritime",
    "bjmc": "media", "bsc_film": "media", "digital_media": "media",
    "bfa": "fine_performing_arts", "dance_course": "fine_performing_arts", "music_course": "fine_performing_arts",
    "theatre_course": "fine_performing_arts",
    "ba_economics": "humanities", "ba_history": "humanities", "ba_polsci": "humanities",
    "ba_psychology": "humanities", "ba_sociology": "humanities",
    "ba_english": "languages", "ba_foreign_lang": "languages", "ba_hindi": "languages", "art_languages": "languages",
    "ba_education": "education", "sports_career": "sports", "hotel_mgmt": "hospitality",
}

# The common ladder after any apex tiers: the group order of plan §3.
GROUP_LADDER = [
    ("G1", "Institutes of National Importance"),
    ("G2", "National technical institutes (NIT, IIIT, IIEST)"),
    ("G3", "Central universities and central-government institutes"),
    ("G4", "State public universities"),
    ("G5", "Deemed-to-be universities"),
    ("G6", "Government and aided colleges"),
    ("G7", "Private universities"),
    ("G11", "Foreign-university campuses"),
    ("G8", "Private colleges"),
    ("G9", "Open, distance and skill institutions"),
]

# Domain -> apex tiers placed above the group ladder: (label, families, groups).
APEX = {
    "law": [("National Law Universities", "nlu", "G4")],
    "ca_cma_cs": [("Statutory professional bodies (ICAI, ICMAI, ICSI)", "icai,icmai,icsi", "G10a")],
    "banking_insurance": [("Banking and insurance bodies (IIBF, NISM, III)", "finance_certification_body", "G10a")],
    "fine_performing_arts": [("National arts institutions (NSD, FTII, SRFTI, Kalakshetra)",
                              "kalakshetra,national_arts_film", "G1,G3")],
    "defence": [("Defence academies (NDA, IMA, INA, AFA, OTA)", "defence_academy", "G3")],
}

# Exam and professional routes also list the professional bodies that teach them.
PROFESSIONAL_BODIES = {
    "commerce_finance": [("Professional and certification bodies",
                          "icai,icmai,icsi,iai,finance_certification_body,foreign_professional_body", "G10a")],
    "management": [("Professional and certification bodies", "finance_certification_body", "G10a")],
    # Actuarial science sits under science; the Institute of Actuaries teaches it.
    "science": [("Professional bodies", "iai", "G10a")],
}


def ladder(domain: str) -> list[tuple[int, str, str, str | None]]:
    """(tier, label, group_codes, family_slugs) from the top."""
    rows = [(label, groups, families) for label, families, groups in APEX.get(domain, [])]
    rows += [(label, group, None) for group, label in GROUP_LADDER]
    rows += [(label, groups, families) for label, families, groups in PROFESSIONAL_BODIES.get(domain, [])]
    return [(i, label, groups, families) for i, (label, groups, families) in enumerate(rows, 1)]


def seed(connection: sqlite3.Connection) -> dict[str, int]:
    connection.executescript(SCHEMA)
    connection.executemany(
        "INSERT INTO domains (slug, name, route_type, regulators, entrance_exams, sort_order) "
        "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(slug) DO UPDATE SET name = excluded.name, "
        "route_type = excluded.route_type, regulators = excluded.regulators, "
        "entrance_exams = excluded.entrance_exams, sort_order = excluded.sort_order",
        [(*row, order) for order, row in enumerate(DOMAINS, 1)],
    )
    nodes = dict(connection.execute("SELECT slug, id FROM career_nodes"))
    missing = sorted(set(NODE_DOMAINS) - set(nodes))
    if missing:
        raise ValueError(f"unknown career node slugs: {missing}")
    families = {row[0] for row in connection.execute("SELECT slug FROM families")}
    apex = {f for rows in (*APEX.values(), *PROFESSIONAL_BODIES.values()) for _, fams, _ in rows
            for f in fams.split(",")}
    if apex - families:
        raise ValueError(f"unknown apex families: {sorted(apex - families)}")
    connection.execute("DELETE FROM domain_nodes")
    connection.executemany(
        "INSERT INTO domain_nodes (node_id, domain_slug) VALUES (?, ?)",
        [(nodes[slug], domain) for slug, domain in NODE_DOMAINS.items()],
    )
    connection.execute("DELETE FROM institute_domain_tiers")
    connection.execute("DELETE FROM domain_tiers")
    for slug, *_ in DOMAINS:
        connection.executemany(
            "INSERT INTO domain_tiers (domain_slug, tier, label, group_codes, family_slugs) "
            "VALUES (?, ?, ?, ?, ?)",
            [(slug, *row) for row in ladder(slug)],
        )
    return {"domains": len(DOMAINS), "domain_nodes": len(NODE_DOMAINS)}


def tier_for(rows: list[tuple[int, str, str | None]], group: str, family: str | None) -> int | None:
    """The first tier that takes this family (apex) or this group (ladder)."""
    for tier, groups, families in rows:
        if families is not None:
            if family in families.split(",") and group in groups.split(","):
                return tier
        elif group in groups.split(","):
            return tier
    return None


def assign_tiers(connection: sqlite3.Connection) -> dict[str, int]:
    """Rebuild institute_domain_tiers from classification + career links."""
    parent = dict(connection.execute("SELECT id, parent_id FROM career_nodes"))
    node_domain = dict(connection.execute("SELECT node_id, domain_slug FROM domain_nodes"))

    def domain_of(node_id: int | None) -> str | None:
        while node_id is not None:
            if node_id in node_domain:
                return node_domain[node_id]
            node_id = parent.get(node_id)
        return None

    ladders: dict[str, list[tuple[int, str, str | None]]] = {}
    for domain, tier, groups, families in connection.execute(
        "SELECT domain_slug, tier, group_codes, family_slugs FROM domain_tiers ORDER BY domain_slug, tier"
    ):
        ladders.setdefault(domain, []).append((tier, groups, families))

    institutes = connection.execute(
        "SELECT institute_id, group_code, family_slug FROM institute_classification "
        "WHERE parent_institute_id IS NULL AND is_family_record = 0 AND listed = 1"
    ).fetchall()
    # A department is part of its parent: IIT Kharagpur's law school puts the
    # IIT on the Law ladder.
    owner = dict(connection.execute(
        "SELECT institute_id, parent_institute_id FROM institute_classification "
        "WHERE parent_institute_id IS NOT NULL"
    ))
    links: dict[int, set[str]] = {}
    for node_id, institute_id in connection.execute("SELECT node_id, institute_id FROM node_institutes"):
        domain = domain_of(node_id)
        if domain:
            links.setdefault(owner.get(institute_id, institute_id), set()).add(domain)

    connection.execute("DELETE FROM institute_domain_tiers")
    rows, unplaced = [], 0
    for institute_id, group, family in institutes:
        for domain in sorted(links.get(institute_id, ())):
            tier = tier_for(ladders[domain], group, family)
            if tier is None:
                unplaced += 1
                continue
            rows.append((institute_id, domain, tier))
    connection.executemany(
        "INSERT INTO institute_domain_tiers (institute_id, domain_slug, tier) VALUES (?, ?, ?)", rows
    )
    return {"institute_tiers": len(rows), "unplaced": unplaced}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys = ON")
    with connection:
        counts = {**seed(connection), **assign_tiers(connection)}
    connection.close()
    print(", ".join(f"{count} {name}" for name, count in counts.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
