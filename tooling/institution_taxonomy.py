#!/usr/bin/env python3
"""Create the institution taxonomy tables and seed their fixed reference data.

Adds the three axes from docs/plans/INSTITUTION_HIERARCHY_PLAN.md next to the
existing tables, without changing them:

* institution group (G1..G11, G10a/G10b, X) and family (IIT, NLU, ITI, ...)
  per institute, with a private-only UGC Yes/No check;
* verification and accreditation records from government sources;
* location: country -> state/UT -> district -> place -> campus.

Seeds the 13 groups, every institution family that exists in India (whether
or not our data has one yet), India and its 36 states/UTs. National counts
stay NULL until a batch confirms them from an official list. Districts,
places and campuses are filled by later tasks.

Safe to re-run: tables are created only if missing and seed rows are upserted.

Usage: python3 tooling/institution_taxonomy.py [--database path]
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS institution_groups (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS families (
  slug TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  group_code TEXT NOT NULL REFERENCES institution_groups(code),
  regulators TEXT,
  official_list_url TEXT,
  national_count INTEGER,
  national_count_as_of TEXT
);

CREATE TABLE IF NOT EXISTS institute_classification (
  institute_id INTEGER PRIMARY KEY REFERENCES institutes(id) ON DELETE CASCADE,
  group_code TEXT NOT NULL REFERENCES institution_groups(code),
  family_slug TEXT REFERENCES families(slug),
  ownership TEXT CHECK (ownership IN
    ('central_govt', 'state_govt', 'govt_aided', 'private', 'trust', 'ppp')),
  statutory_basis TEXT,
  admits_students INTEGER NOT NULL DEFAULT 1,
  parent_institute_id INTEGER REFERENCES institutes(id),
  is_family_record INTEGER NOT NULL DEFAULT 0,
  regulators TEXT,
  listed INTEGER NOT NULL DEFAULT 1,
  ugc_verified INTEGER CHECK (ugc_verified IN (0, 1)),
  ugc_list_name TEXT,
  ugc_reference_id TEXT,
  ugc_source_url TEXT,
  ugc_checked_at TEXT,
  confidence TEXT NOT NULL CHECK (confidence IN ('high', 'medium', 'low')),
  source_url TEXT,
  verified_at TEXT,
  notes TEXT,
  -- Plan §8.6: the UGC Yes/No check is for private institutions only, and
  -- every private institution gets one.
  CHECK (ugc_verified IS NULL OR ownership IN ('private', 'trust')),
  CHECK (ownership IS NULL OR ownership NOT IN ('private', 'trust')
         OR ugc_verified IS NOT NULL),
  -- Only Phase-2 coaching, bodies that do not admit students and national
  -- summary rows are kept out of the app.
  CHECK (listed = 1 OR group_code IN ('G10b', 'X') OR admits_students = 0
         OR is_family_record = 1)
);
CREATE INDEX IF NOT EXISTS idx_classification_group
  ON institute_classification(group_code);
CREATE INDEX IF NOT EXISTS idx_classification_family
  ON institute_classification(family_slug);
CREATE INDEX IF NOT EXISTS idx_classification_parent
  ON institute_classification(parent_institute_id);

CREATE TABLE IF NOT EXISTS institute_verifications (
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  authority TEXT NOT NULL,
  list_name TEXT NOT NULL,
  list_url TEXT NOT NULL,
  list_as_of TEXT,
  reference_id TEXT,
  verified_at TEXT NOT NULL,
  PRIMARY KEY (institute_id, authority, list_name)
);

CREATE TABLE IF NOT EXISTS institute_accreditations (
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (body IN ('NAAC', 'NBA')),
  programme TEXT NOT NULL DEFAULT '',
  grade TEXT,
  status TEXT,
  valid_until TEXT,
  source_url TEXT NOT NULL,
  PRIMARY KEY (institute_id, body, programme)
);

CREATE TABLE IF NOT EXISTS countries (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS states (
  code TEXT PRIMARY KEY,
  lgd_code INTEGER UNIQUE NOT NULL,
  country_code TEXT NOT NULL REFERENCES countries(code),
  name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('state', 'ut')),
  zone TEXT NOT NULL CHECK (zone IN
    ('north', 'south', 'east', 'west', 'central', 'north_east'))
);

CREATE TABLE IF NOT EXISTS districts (
  lgd_code INTEGER PRIMARY KEY,
  state_code TEXT NOT NULL REFERENCES states(code),
  name TEXT NOT NULL,
  UNIQUE (state_code, name)
);
CREATE INDEX IF NOT EXISTS idx_districts_state ON districts(state_code);

CREATE TABLE IF NOT EXISTS places (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  district_lgd INTEGER NOT NULL REFERENCES districts(lgd_code),
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('city', 'town', 'village')),
  is_district_hq INTEGER NOT NULL DEFAULT 0,
  UNIQUE (district_lgd, name)
);
CREATE INDEX IF NOT EXISTS idx_places_district ON places(district_lgd);

CREATE TABLE IF NOT EXISTS place_aliases (
  alias TEXT PRIMARY KEY,
  place_id INTEGER REFERENCES places(id),
  district_lgd INTEGER REFERENCES districts(lgd_code),
  state_code TEXT REFERENCES states(code),
  CHECK ((place_id IS NOT NULL) + (district_lgd IS NOT NULL)
         + (state_code IS NOT NULL) = 1)
);

CREATE TABLE IF NOT EXISTS campuses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  name TEXT,
  place_id INTEGER NOT NULL REFERENCES places(id),
  is_main INTEGER NOT NULL DEFAULT 0,
  source_url TEXT,
  verified_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_campuses_place ON campuses(place_id);
CREATE INDEX IF NOT EXISTS idx_campuses_institute ON campuses(institute_id);
"""

# (code, name, description) in display order.
GROUPS = [
    ("G1", "National flagship / Institutes of National Importance",
     "IIT, IIM, AIIMS, JIPMER, PGIMER, NIMHANS, IISc, IISER, NISER, ISI, NIPER, SPA, NID and similar."),
    ("G2", "National technical institutes", "NIT, IIIT and IIEST."),
    ("G3", "Central universities and central-government institutes",
     "Central universities and institutes run by a central ministry (NIFT, NSD, IHM, NDA ...)."),
    ("G4", "State public universities",
     "State general, technical, health, agricultural, veterinary and law universities, including NLUs."),
    ("G5", "Deemed-to-be universities", "Institutions deemed to be universities by UGC."),
    ("G6", "Government, aided and autonomous colleges",
     "Government and aided colleges, autonomous and constituent colleges, DIETs."),
    ("G7", "Private universities", "Private universities set up under a state act."),
    ("G8", "Private affiliated and standalone colleges",
     "Private unaided colleges and standalone private institutes such as PGDM schools."),
    ("G9", "Open, distance, online, skill and diploma",
     "Open universities, polytechnics, ITIs, skill institutes and online platforms."),
    ("G10a", "Statutory professional bodies", "ICAI, ICSI, ICMAI and similar route owners."),
    ("G10b", "Private training and coaching", "Coaching and certification providers (Phase 2)."),
    ("G11", "Foreign-university campuses in India", "Campuses under the UGC 2023 regulations or IFSCA."),
    ("X", "Does not admit students",
     "Research labs, employers and post-selection training academies."),
]

# (slug, name, group, regulators): every family in plan §3.2.
# School-level families (Sainik Schools, RIMC) are out of scope (plan §3.3).
FAMILIES = [
    ("iit", "Indian Institutes of Technology", "G1", "MoE"),
    ("iim", "Indian Institutes of Management", "G1", "MoE"),
    ("aiims", "All India Institutes of Medical Sciences", "G1", "MoHFW"),
    ("national_medical_ini", "JIPMER, PGIMER and NIMHANS", "G1", "MoHFW"),
    ("iisc", "Indian Institute of Science", "G1", "MoE"),
    ("iiser", "Indian Institutes of Science Education and Research", "G1", "MoE"),
    ("niser", "National Institute of Science Education and Research", "G1", "DAE"),
    ("isi", "Indian Statistical Institute", "G1", "MoSPI"),
    ("niper", "National Institutes of Pharmaceutical Education and Research", "G1",
     "Department of Pharmaceuticals"),
    ("spa", "Schools of Planning and Architecture", "G1", "MoE"),
    ("nid", "National Institutes of Design", "G1", "DPIIT"),
    ("aiia", "All India Institute of Ayurveda", "G1", "Ministry of AYUSH"),
    ("niftem", "National Institutes of Food Technology, Entrepreneurship and Management", "G1",
     "MoFPI"),
    ("nfsu", "National Forensic Sciences University", "G1", "MHA"),
    ("rru", "Rashtriya Raksha University", "G1", "MHA"),
    ("kalakshetra", "Kalakshetra Foundation", "G1", "Ministry of Culture"),
    ("nit", "National Institutes of Technology", "G2", "MoE"),
    ("iiit", "Indian Institutes of Information Technology", "G2", "MoE"),
    ("iiest", "Indian Institute of Engineering Science and Technology", "G2", "MoE"),
    ("central_university", "Central universities", "G3", "UGC"),
    ("central_sanskrit_university", "Central Sanskrit universities", "G3", "UGC"),
    ("central_agricultural_university", "Central agricultural universities", "G3", "ICAR"),
    ("nift", "National Institute of Fashion Technology", "G3", "Ministry of Textiles"),
    ("fddi", "Footwear Design and Development Institute", "G3", "Ministry of Commerce"),
    ("national_arts_film", "NSD, FTII and SRFTI", "G3", "Ministry of Culture; Ministry of I&B"),
    ("iimc", "Indian Institute of Mass Communication", "G3", "Ministry of I&B"),
    ("central_ihm", "Central Institutes of Hotel Management", "G3", "NCHMCT"),
    ("iittm", "Indian Institute of Tourism and Travel Management", "G3", "Ministry of Tourism"),
    ("ncert_rie", "NCERT Regional Institutes of Education", "G3", "NCERT"),
    ("nielit", "National Institute of Electronics and IT", "G3", "MeitY"),
    ("central_skill_institute", "CIPET, CLRI and MSME tool rooms", "G3", "various ministries"),
    ("national_rehab_institute", "National rehabilitation institutes", "G3", "MoSJE; RCI"),
    ("ayush_national_institute", "AYUSH national institutes", "G3", "Ministry of AYUSH"),
    ("icar_institute", "ICAR research institutes", "G3", "ICAR"),
    ("defence_academy", "NDA, IMA, INA, AFA and OTA", "G3", "MoD"),
    ("afmc", "Armed Forces Medical College", "G3", "MoD"),
    ("national_aviation_institute", "IGRUA and NFTI", "G3", "MoCA"),
    ("central_management_institute", "IIFT, IIFM and IIPA", "G3", "various ministries"),
    ("national_sports_institute", "NIS Patiala and SAI centres", "G3", "MoYAS"),
    ("central_language_institute", "Central language institutes", "G3", "MoE"),
    ("state_university", "State general universities", "G4", "UGC"),
    ("state_technical_university", "State technical universities", "G4", "AICTE; UGC"),
    ("nlu", "National Law Universities", "G4", "BCI"),
    ("state_agricultural_university", "State agricultural universities", "G4", "ICAR"),
    ("state_veterinary_university", "State veterinary universities", "G4", "VCI"),
    ("state_health_university", "State health-science universities", "G4", "NMC; DCI; INC"),
    ("state_ayush_university", "State AYUSH universities", "G4", "NCISM; NCH"),
    ("state_sports_university", "State sports universities", "G4", None),
    ("state_arts_university", "State music and arts universities", "G4", None),
    ("state_womens_university", "State women's universities", "G4", "UGC"),
    ("state_law_university", "State law universities (non-NLU)", "G4", "BCI"),
    ("private_deemed", "Private deemed universities", "G5", "UGC"),
    ("government_deemed", "Government-funded deemed universities", "G5", "UGC"),
    ("icar_deemed", "ICAR deemed universities", "G5", "UGC; ICAR"),
    ("govt_degree_college", "Government degree colleges", "G6", "UGC"),
    ("govt_engineering_college", "Government and aided engineering colleges", "G6", "AICTE"),
    ("govt_medical_college", "Government medical colleges", "G6", "NMC"),
    ("govt_dental_college", "Government dental colleges", "G6", "DCI"),
    ("govt_ayush_college", "Government AYUSH colleges", "G6", "NCISM; NCH"),
    ("govt_nursing_college", "Government nursing colleges", "G6", "INC"),
    ("govt_pharmacy_college", "Government pharmacy colleges", "G6", "PCI"),
    ("govt_law_college", "Government law colleges", "G6", "BCI"),
    ("govt_art_college", "Government art colleges", "G6", None),
    ("govt_agri_vet_college", "Government agricultural and veterinary colleges", "G6",
     "ICAR; VCI"),
    ("state_ihm", "State institutes of hotel management", "G6", "NCHMCT"),
    ("teacher_education_govt", "DIETs, CTEs and IASEs", "G6", "NCTE"),
    ("aided_autonomous_college", "Aided and autonomous colleges", "G6", "UGC"),
    ("private_university", "State private universities", "G7", "UGC"),
    ("private_engineering_college", "Private engineering colleges", "G8", "AICTE"),
    ("private_medical_college", "Private medical colleges", "G8", "NMC"),
    ("private_dental_college", "Private dental colleges", "G8", "DCI"),
    ("private_nursing_college", "Private nursing colleges", "G8", "INC"),
    ("private_pharmacy_college", "Private pharmacy colleges", "G8", "PCI"),
    ("private_law_college", "Private law colleges", "G8", "BCI"),
    ("private_bed_college", "Private B.Ed colleges", "G8", "NCTE"),
    ("standalone_pgdm", "Standalone PGDM institutes", "G8", "AICTE"),
    ("private_design_media_school", "Private design, film and media schools", "G8", None),
    ("private_hotel_management", "Private hotel-management colleges", "G8", "AICTE"),
    ("dgca_fto", "DGCA flying-training organisations", "G8", "DGCA"),
    ("dgs_maritime_institute", "DG Shipping maritime institutes", "G8", "DGS"),
    ("private_degree_college", "Private degree colleges", "G8", "UGC"),
    ("ignou", "Indira Gandhi National Open University", "G9", "UGC-DEB"),
    ("state_open_university", "State open universities", "G9", "UGC-DEB"),
    ("online_degree", "UGC-entitled online degree programmes", "G9", "UGC-DEB"),
    ("polytechnic", "Polytechnics", "G9", "AICTE; state boards"),
    ("iti", "Industrial Training Institutes", "G9", "DGT"),
    ("nsti", "National Skill Training Institutes", "G9", "DGT"),
    ("skill_university", "State skill universities", "G9", None),
    ("community_skill_centre", "Community colleges and skill centres", "G9", "UGC; NSDC"),
    ("swayam_nptel", "SWAYAM and NPTEL", "G9", "MoE"),
    ("commercial_mooc", "Commercial MOOC platforms", "G9", None),
    ("icai", "Institute of Chartered Accountants of India", "G10a", "Act of Parliament"),
    ("icsi", "Institute of Company Secretaries of India", "G10a", "Act of Parliament"),
    ("icmai", "Institute of Cost Accountants of India", "G10a", "Act of Parliament"),
    ("iai", "Institute of Actuaries of India", "G10a", "Act of Parliament"),
    ("finance_certification_body", "NISM, IIBF and Insurance Institute of India", "G10a",
     "SEBI; RBI; IRDAI"),
    ("engineering_professional_body", "Institution of Engineers and IETE", "G10a", None),
    ("foreign_professional_body", "CFA Institute, ACCA, CIMA and CPA", "G10a", None),
    ("coaching_civil_services", "Civil-services coaching", "G10b", None),
    ("coaching_defence", "Defence coaching", "G10b", None),
    ("coaching_jee_neet", "JEE and NEET coaching", "G10b", None),
    ("coaching_banking_ssc", "Banking and SSC coaching", "G10b", None),
    ("coaching_professional", "CA, CS and CMA coaching", "G10b", None),
    ("coaching_design_entrance", "Design entrance coaching", "G10b", None),
    ("animation_training", "Animation and VFX training", "G10b", None),
    ("fitness_certification", "Fitness and yoga certification", "G10b", None),
    ("drone_rpto", "Drone remote-pilot training organisations", "G10b", "DGCA"),
    ("language_institute", "Foreign-language institutes", "G10b", None),
    ("foreign_campus", "Foreign-university campuses", "G11", "UGC; IFSCA"),
    ("research_lab", "Government research laboratories", "X", None),
    ("civil_service_academy", "Civil-service training academies", "X", None),
    ("psu_academy", "PSU and employer academies", "X", None),
    ("cultural_akademi", "National cultural akademis", "X", "Ministry of Culture"),
]

# (ISO 3166-2 code, LGD/Census 2011 state code, name, kind, zone). Zones follow
# the MHA zonal councils (Sikkim: North Eastern Council). Andaman and Nicobar
# and Lakshadweep belong to no council, so they are placed by geography.
STATES = [
    ("IN-JK", 1, "Jammu and Kashmir", "ut", "north"),
    ("IN-HP", 2, "Himachal Pradesh", "state", "north"),
    ("IN-PB", 3, "Punjab", "state", "north"),
    ("IN-CH", 4, "Chandigarh", "ut", "north"),
    ("IN-UK", 5, "Uttarakhand", "state", "central"),
    ("IN-HR", 6, "Haryana", "state", "north"),
    ("IN-DL", 7, "Delhi", "ut", "north"),
    ("IN-RJ", 8, "Rajasthan", "state", "north"),
    ("IN-UP", 9, "Uttar Pradesh", "state", "central"),
    ("IN-BR", 10, "Bihar", "state", "east"),
    ("IN-SK", 11, "Sikkim", "state", "north_east"),
    ("IN-AR", 12, "Arunachal Pradesh", "state", "north_east"),
    ("IN-NL", 13, "Nagaland", "state", "north_east"),
    ("IN-MN", 14, "Manipur", "state", "north_east"),
    ("IN-MZ", 15, "Mizoram", "state", "north_east"),
    ("IN-TR", 16, "Tripura", "state", "north_east"),
    ("IN-ML", 17, "Meghalaya", "state", "north_east"),
    ("IN-AS", 18, "Assam", "state", "north_east"),
    ("IN-WB", 19, "West Bengal", "state", "east"),
    ("IN-JH", 20, "Jharkhand", "state", "east"),
    ("IN-OD", 21, "Odisha", "state", "east"),
    ("IN-CG", 22, "Chhattisgarh", "state", "central"),
    ("IN-MP", 23, "Madhya Pradesh", "state", "central"),
    ("IN-GJ", 24, "Gujarat", "state", "west"),
    ("IN-MH", 27, "Maharashtra", "state", "west"),
    ("IN-AP", 28, "Andhra Pradesh", "state", "south"),
    ("IN-KA", 29, "Karnataka", "state", "south"),
    ("IN-GA", 30, "Goa", "state", "west"),
    ("IN-LD", 31, "Lakshadweep", "ut", "south"),
    ("IN-KL", 32, "Kerala", "state", "south"),
    ("IN-TN", 33, "Tamil Nadu", "state", "south"),
    ("IN-PY", 34, "Puducherry", "ut", "south"),
    ("IN-AN", 35, "Andaman and Nicobar Islands", "ut", "east"),
    ("IN-TG", 36, "Telangana", "state", "south"),
    ("IN-LA", 37, "Ladakh", "ut", "north"),
    ("IN-DH", 38, "Dadra and Nagar Haveli and Daman and Diu", "ut", "west"),
]


def apply(connection: sqlite3.Connection) -> dict[str, int]:
    """Create the tables if missing and upsert the seed rows."""
    connection.executescript(SCHEMA)
    connection.executemany(
        "INSERT INTO institution_groups (code, name, description, sort_order) "
        "VALUES (?, ?, ?, ?) ON CONFLICT(code) DO UPDATE SET name = excluded.name, "
        "description = excluded.description, sort_order = excluded.sort_order",
        [(code, name, text, order) for order, (code, name, text) in enumerate(GROUPS, 1)],
    )
    # Counts and list URLs are owned by the batch loader, so they survive a re-run.
    connection.executemany(
        "INSERT INTO families (slug, name, group_code, regulators) VALUES (?, ?, ?, ?) "
        "ON CONFLICT(slug) DO UPDATE SET name = excluded.name, "
        "group_code = excluded.group_code, regulators = excluded.regulators",
        FAMILIES,
    )
    connection.execute(
        "INSERT INTO countries (code, name) VALUES ('IN', 'India') "
        "ON CONFLICT(code) DO UPDATE SET name = excluded.name"
    )
    connection.executemany(
        "INSERT INTO states (code, lgd_code, country_code, name, kind, zone) "
        "VALUES (?, ?, 'IN', ?, ?, ?) ON CONFLICT(code) DO UPDATE SET "
        "lgd_code = excluded.lgd_code, name = excluded.name, kind = excluded.kind, "
        "zone = excluded.zone",
        STATES,
    )
    return {"groups": len(GROUPS), "families": len(FAMILIES), "states": len(STATES)}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys = ON")
    with connection:
        counts = apply(connection)
    connection.close()
    print(", ".join(f"{count} {name}" for name, count in counts.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
