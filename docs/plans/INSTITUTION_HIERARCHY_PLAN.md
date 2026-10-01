# Institution Groups & College Hierarchy — Plan

Status: **plan only — no DB or code changes made.** Date: 2026-10-01.
Source of every count below: `assets/data/career_path.db` as shipped in `1.5.0+17`, read-only.

Approach, as asked:

1. **Step 1 — Every category that exists in India, and whether we have it.** §3.2 lists **all** Indian institution
   families (IIT … ITI, coaching, foreign campuses), each marked present or missing in our DB. §4 shows which groups
   exist per career domain (Engineering, Doctor, CA, Law, Artist, Management, Civil Services, …).
2. **Step 2 — The hierarchy.** For each domain, the ladder of institutions from top to bottom, where each step sits in
   the DB, and what is missing (§5).
3. **Step 3 — Location.** Every campus sits on an **India → State/UT → District → City** path, so students can filter
   by place together with domain and group (§6).

§1–§3 cover what is wrong with the data today and the model that fixes it. §7–§10 cover schema, migration, app changes
and the task list.

---

## 1. What the DB has today (verified)

| Fact | Value |
|---|---|
| Institutes | 669 (14 not linked to any career node) |
| `institution_type` values | 26 flat labels + **119 NULL** |
| `institute_categories` | 30 labels (NIRF-style: College 92, Engineering 63, Management 63, Overall 61, Pharmacy 28, Law 23, …) |
| `institute_rankings` | 35 rows, NIRF 2025 only |
| Career tree | 3 streams → 17 roots → 84 L2 nodes (the “domains” students pick) |
| Courses | 8 376, only for researched Rajasthan / MP / UP institutes |

### 1.1 Problems found (these decide the plan)

| # | Problem | Evidence | Root cause |
|---|---|---|---|
| D1 | **`government_college` is used as the default for “any college”** | Acropolis Institute, Biyani Institute, Jaipur Engineering College, Dewan Institute and others are all private but typed `government_college`. 119 of 123 rows have no source URL or confidence. | `tooling/discover_nirf_state_inventory.py` (end of `infer_type`): any name containing college/institute/school → `government_college`. |
| D2 | **Substring `"law"` check** | “Government Engineering College, Jhalawar” and “Govt. Birla College, Bhawanimandi, Distt. Jhalawar” are typed `law` (Jha**law**ar). | Same file: `"law" in folded`. Needs a word-boundary match. |
| D3 | **`state_university` mixes state public and state private universities** | GLA, LNCT, Medi-Caps, NIIT University, ICFAI Jaipur, Shobhit, Geetanjali, Bhupal Nobles’, Mahatma Gandhi Univ. of Medical Sciences and others are private universities set up under a state act. | No public/private split. UGC lists them separately (“State Private Universities”). |
| D4 | **Department and programme rows posing as institutes** | 140 names end in “(…)”. Example: `iit` has 52 rows, but 32 of them are departments of 10 IITs (“IIT Bombay (Civil)”, “IIT Bombay (ECE)”, …). Also “IIM A/B/C (MBA Finance)”, “CMC Vellore (Nursing)”. | Research batches stored one row per course and department. |
| D5 | **Family placeholder rows** | 25 rows such as “NITs”, “IIITs”, “AIIMS (All Campuses)”, “ITI (Industrial Training Institutes)”, “DIET”, “State CTEs”, “AICTE Approved Polytechnics”, “Government Polytechnics (Various States)”. | Hand-added summaries; city “Various” or “Online”. |
| D6 | **True duplicates** | NLU Delhi ×3; NALSAR, GNLU, NLSIU, PAU, TNAU, ICAI, CCS University ×2 each; “PGI Chandigarh” and “PGIMER Chandigarh”. | `UNIQUE(name)` lets spelling variants through. |
| D7 | **Bodies that don’t admit students are stored as colleges** | IMD, PRL, INCOIS, ONGC Academy, CFSL, GSI Training Institute, LBSNAA, SVPNPA, NADT, Foreign Service Institute, Sangeet Natak Akademi. | No field for whether a body admits students or is a post-selection training academy. |
| D8 | **Coaching centres mixed with degree institutes** | Vision IAS, Drishti IAS, Vajiram & Ravi, Shankar IAS, KSG, Delta and other defence academies, Arena Animation, Frameboxx, RPTO flying schools sit beside IITs under `specialized` or NULL. | No group for “training provider”. |
| D9 | **Pharmacy has no career node** | 232 pharmacy courses at 62 institutes, and 28 institutes carry the NIRF “Pharmacy” category, but there is no Pharmacy L2 node. | Gap in the career tree. |
| D10 | **PCS root is empty** | `career_nodes` id 351 “PCS” has 0 children. | Gap in the career tree. |
| D11 | Data hygiene | 1 institute name contains phone numbers; mixed-case names (“SHOBHIT UNIVERSITY, GANGOH”). | Raw scrape text. |

**App impact is low.** `institutionType` is only read as display or search text
(`local_ai_grounding_service.dart:438`, `institute_catalog_service.dart:435,512`). `byInstitutionType()` and
`institutionTypes` have no callers. A schema change does not break any screen.

---

## 2. The model: three axes, not one

The pasted proposal puts “National Law Universities” at the top of Law and also says G4 = state universities. Both are
true: an NLU is **legally** a state university but sits at the **top** of the Law domain. A single
`institution_group` column cannot hold both facts. Location is a third, independent question. So the plan uses three axes:

| Axis | Stored on | Question it answers | Example: NLSIU Bengaluru |
|---|---|---|---|
| **Institution group** (G1–G11, X, §3) | institute (one value) | What kind of body is this, legally and by ownership? | G4 — State public university |
| **Domain tier** (§5) | institute × domain | Where does it sit on *this domain’s* ladder? | Law → **T1 Apex (NLU)** |
| **Location** (§6) | campus (one institute can have many) | Where can I study it? | India → Karnataka → Bengaluru Urban → Bengaluru |

All three combine in one filter: *“Law · Tier 1 · Karnataka”* or *“Engineering · G6 government colleges · Jodhpur”*.

Supporting attributes, kept separate as the pasted note suggests:

```text
institution_group      G1..G10, X           (one per institute)
institution_family     IIT, NIT, AIIMS, NLU, IIM, SPA, NID, NIFT, IHM, ICAR-SAU, …
ownership              central_govt | state_govt | govt_aided | private | public_private | trust
statutory_basis        act_of_parliament | state_act | ugc_deemed | ini_act | society | company
admits_students        1 | 0                (0 = research lab, regulator, post-selection academy)
parent_institute_id    for campuses and departments (fixes D4)
is_family_record       1 for “NITs”, “AIIMS (All Campuses)” rows (fixes D5)
regulator(s)           AICTE, UGC, NMC, DCI/NDC, PCI, INC, BCI, CoA, ICAR, NCTE, NCAHP, VCI, NCISM, NCH, DGCA, DGS
ranking                existing institute_rankings (NIRF), still separate
delivery_mode          campus | open | distance | online
route_type (domain)    degree | professional_body | exam | training
```

**Domain tiers are objective, not a quality score.** A tier comes from the group, the family and the domain’s regulator.
NIRF rank is shown next to the tier, never mixed into it. This keeps the app from making claims like “top college”
that it cannot back up.

---

## 3. Institution groups (master list)

Taken from the pasted G1–G10, with four corrections:
(a) G4 and G6 overlapped (“government colleges” was in both), so G4 is now universities only;
(b) state private universities go explicitly in G7;
(c) G10 is split into statutory professional bodies and private training providers;
(d) a new **X** group holds bodies that don’t admit students;
(e) a new **G11** holds foreign-university campuses in India (UGC 2023 regulations, IFSCA GIFT City). No existing group
fits them.

| Group | Name | Includes | Excludes | Primary source of truth |
|---|---|---|---|---|
| **G1** | National flagship / Institutes of National Importance | IIT, IIM, AIIMS, JIPMER, PGIMER, NIMHANS, IISc, IISER, NISER, ISI, NIPER, SPA, NID, ITRA | NIT/IIIT (→ G2) | MoE INI list; the acts |
| **G2** | National technical institutes | NIT, IIIT (MoE + PPP), IIEST | — | MoE CFTI list |
| **G3** | Central universities & central-government institutes | Central universities (DU, BHU, JNU, AMU, Jamia, EFLU, IMU, NSU…), NIFT, NSD, FTII, SRFTI, IIMC, IHM (NCHMCT), ICAR institutes, NDA, IMA, INA, OTA, AFMC, IGRUA | Research labs that don’t admit (→ X) | UGC central list; ministry lists |
| **G4** | State public universities | State universities, state technical, health, agricultural, veterinary and law universities, **NLUs**, state open universities → G9 | State **private** universities (→ G7), colleges (→ G6/G8) | UGC state list |
| **G5** | Deemed-to-be universities | BITS, Manipal (MAHE), Symbiosis, NMIMS, VIT, SRM, TISS, TERI SAS, Banasthali, IIS, Amrita, KIIT, Datta Meghe, DY Patil… | — | UGC deemed list |
| **G6** | Government, aided & autonomous colleges | Govt degree colleges, govt engineering, medical and law colleges, aided colleges, autonomous colleges, university constituent colleges and departments, DIET | Private unaided (→ G8) | AISHE (management type); AICTE; NMC |
| **G7** | Private universities | State private universities (Amity, LPU, Chandigarh Univ., GLA, LNCT, Medi-Caps, NIIT Univ., ICFAI, JK Lakshmipat…) | Deemed (→ G5) | UGC private list |
| **G8** | Private affiliated & standalone colleges | Private unaided colleges; standalone AICTE PGDM institutes (XLRI, SPJIMR, TAPMI, MICA, IFMR); ISB; private design and film schools | — | AISHE; AICTE |
| **G9** | Open, distance, online, skill, diploma | Open universities (IGNOU, VMOU, MP Bhoj), polytechnics, ITI, skill universities, SWAYAM/NPTEL | — | DGT/NCVET; state boards |
| **G10a** | Statutory professional bodies | ICAI, ICSI, ICMAI, NISM, IIBF, Insurance Institute of India, CFA Institute | — | Their acts and charters |
| **G10b** | Private training & coaching | IAS, defence, bank and NEET/JEE coaching, animation, fitness certification, RPTO flying schools | — | **Phase 2** — not listed in Phase 1 (decision 1) |
| **G11** | Foreign-university campuses in India | Deakin & Wollongong (GIFT City), Southampton (Gurugram), later approvals | Online tie-ups and twinning programmes (→ the Indian partner’s group) | UGC foreign-HEI list; IFSCA |
| **X** | Doesn’t admit students | IMD, PRL, INCOIS, CFSL, ONGC Academy, LBSNAA, SVPNPA, NADT, FSI, Sangeet Natak Akademi | — | Kept as *employer* or *post-selection* links, not as colleges |

### 3.1 Provisional distribution (heuristic classifier, see §8.2)

| G1 | G2 | G3 | G4 | G5 | G6 | G7 | G8 | G9 | G10a | G10b |
|---|---|---|---|---|---|---|---|---|---|---|
| 96 | 11 | 87 | 61 | 37 | 82 | 59 | 182 | 11 | 9 | 34 |

G1 is inflated by department rows (D4). The G6/G8 split is **unreliable** until ownership is checked against AISHE
(D1). Everything else is a fair first cut.

### 3.2 Complete all-India catalogue — every family, present or missing

This is the full list of institution **families** in India, not only the ones in our DB. It is what the `families`
lookup table (§7) will hold. Each family belongs to exactly one group.

- **≈ All-India**: approximate size from public official lists, as of 2025. Confirm against the official list in T2
  before showing it in the app.
- **In our DB**: distinct institutes, checked by name match against `career_path.db` and hand-corrected for false
  matches. ✅ present · ⚠️ only a summary row or 1 example · ❌ missing.

#### G1 — National flagship / Institutes of National Importance
| Family | Domains | Regulator / official list | ≈ All-India | In our DB |
|---|---|---|---|---|
| IIT (incl. IIT-ISM Dhanbad) | Engineering, science, design, management, HSS | MoE · IIT Act | 23 | ✅ 10 distinct (52 rows — D4) |
| IIM | Management | MoE · IIM Act 2017 | 21 | ✅ ~9 + programme rows |
| AIIMS | Medical, nursing, allied | MoHFW | ~20 functional | ✅ 4 campuses + summary row |
| JIPMER · PGIMER · NIMHANS | Medical | MoHFW | 3 | ✅ all 3 |
| IISc *(deemed by statute, flagship by role)* | Science, engineering | MoE | 1 | ✅ |
| IISER | Science | MoE | 7 | ⚠️ 1 (Bhopal) |
| NISER / HBNI | Science | DAE | 1 | ❌ |
| ISI | Statistics | MoSPI · ISI Act | 1 (+ centres) | ✅ |
| NIPER | Pharmacy | Dept. of Pharmaceuticals | 7 | ⚠️ 1 summary row |
| SPA | Architecture & planning | MoE · SPA Act | 3 | ✅ 3 |
| NID (INI campuses) | Design | DPIIT · NID Act | 5 | ✅ 2 + summary row |
| ITRA Jamnagar *(correction: AIIA New Delhi is an autonomous Ayush institute, G3)* | AYUSH | Ministry of AYUSH · ITRA Act 2020 | 1 | ✅ (loaded in A5b) |
| NIFTEM | Food technology | MoFPI | 2 | ✅ 1 |
| National Forensic Sciences Univ. | Forensic science | MHA | 1 (+ campuses) | ✅ (as “Gujarat Forensic Sciences Univ.” — rename) |
| Rashtriya Raksha University | Police, security | MHA | 1 | ❌ |
| Kalakshetra | Performing arts | Ministry of Culture | 1 | ✅ (move G3 → G1) |

#### G2 — National technical institutes
| Family | Domains | Regulator | ≈ All-India | In our DB |
|---|---|---|---|---|
| NIT | Engineering, architecture, science, management | MoE · NIT Act | 31 | ✅ 6 + “NITs” summary row |
| IIIT (MoE-funded + PPP) | Computing, ECE | MoE · IIIT Acts | ~26 | ✅ 3 (Gwalior, Allahabad …) + summary row |
| IIEST Shibpur | Engineering | MoE | 1 | ❌ |
| *Note* | IIIT Hyderabad and IIIT Bangalore are **deemed** (G5), not G2 | | | ✅ present, regroup |

#### G3 — Central universities & central-government institutes
| Family | Domains | Regulator | ≈ All-India | In our DB |
|---|---|---|---|---|
| Central universities | All | UGC · Central Universities Act | ~56 | ✅ ~12 (DU, BHU, JNU, AMU, Jamia, UoH, Visva-Bharati, EFLU, IMU, IGNTU, MGAHV, NSU) |
| Central Sanskrit universities | Sanskrit, Indology | UGC | 3 | ❌ |
| Central agricultural universities | Agriculture | ICAR | 3 | ❌ |
| NIFT | Fashion design | Ministry of Textiles · NIFT Act | 19 campuses | ⚠️ 1 summary row |
| FDDI | Footwear & design | Ministry of Commerce | 12 campuses | ❌ |
| NSD · FTII · SRFTI | Theatre, film | Ministry of Culture / I&B | 3 (+ centres) | ✅ all 3 |
| IIMC | Journalism | Ministry of I&B | 1 (+ ~5 regional) | ✅ |
| Central IHMs (NCHMCT) · IITTM | Hospitality, tourism | Ministry of Tourism | ~21 · 1 | ✅ 3 · ✅ |
| NCERT RIEs | Teacher education | NCERT | 5 | ⚠️ summary row |
| NIELIT | Computing diplomas | MeitY | ~50 centres | ⚠️ summary row |
| CIPET · CLRI · MSME tool rooms | Polymer, leather, tool-making | various | ~45 · 1 · ~18 | ❌ |
| National rehab institutes | Rehabilitation (RCI) | MoSJE | 9 | ✅ 2 |
| AYUSH national institutes (AIIA, NIA, NIH, NIUM, NIS, MDNIY) | AYUSH, yoga | Ministry of AYUSH | ~7 | ✅ 3 (AIIA loaded in A5b) |
| Defence academies (NDA, IMA, INA, AFA, OTA) | Defence | MoD | 5 | ✅ all 5 (NDA duplicated) |
| AFMC | Medical (defence) | MoD | 1 | ✅ |
| Sainik Schools · RIMC | Defence prep (school-level) | MoD | ~33 + new · 1 | ❌ (school-level, see §3.3) |
| IGRUA · NFTI | Aviation | MoCA | 2 | ✅ both |
| IIFT · IIFM · IIPA | Management, public policy | various | 3 | ✅ 2 · IIPA ❌ |
| NIS Patiala (SAI) | Sports coaching | MoYAS | 1 (+ SAI centres) | ✅ |
| Kendriya Hindi Sansthan | Hindi | MoE | 1 | ✅ |

#### G4 — State public universities
| Family | Domains | Regulator | ≈ All-India | In our DB |
|---|---|---|---|---|
| State general universities | All | UGC (state list) | ~480 (all G4 kinds) | ✅ ~25 |
| State technical universities (RTU, AKTU, RGPV, GTU, VTU …) | Engineering | AICTE / state act | ~30 | ⚠️ 2 (RGPV, DTU); RTU, AKTU ❌ |
| National Law Universities | Law | BCI · state acts | ~26 | ✅ ~10 distinct (duplicates) |
| State agricultural universities | Agriculture | ICAR | ~63 | ✅ ~9 |
| State veterinary universities | Veterinary | VCI | ~16 | ⚠️ 1 (DUVASU); RAJUVAS, TANUVAS ❌ |
| State health-science universities | Medical, dental, nursing | NMC etc. | ~20 | ✅ 3 (KGMU, MPMSU, UPUMS) |
| State AYUSH universities | AYUSH | NCISM / NCH | ~8 | ✅ 3 |
| State sports universities | Sports | — | ~8 | ✅ 2 |
| State music & arts universities (IKSV Khairagarh, RMT Gwalior) | Arts | — | ~4 | ❌ |
| State women’s universities | All | UGC | ~15 | ✅ 1 (SNDT) |
| State law universities (non-NLU, e.g. TNDALU) | Law | BCI | few | ❌ |

#### G5 — Deemed-to-be universities (~145 in all)
| Family | In our DB |
|---|---|
| Private deemed (BITS, MAHE, Symbiosis, NMIMS, VIT, SRM, Amrita, KIIT, Datta Meghe, DY Patil, Bharati Vidyapeeth, Banasthali, Christ) | ✅ ~15 |
| Government-funded deemed (TISS, ICT Mumbai, Jamia Hamdard, LNIPE, IIST, DIAT, HBNI, IIIT-H/B) | ✅ TISS, ICT, Jamia Hamdard, LNIPE, IIST, IIIT-H/B · DIAT ❌ · HBNI ❌ |
| ICAR deemed (IARI, NDRI, IVRI, CIFE) | ✅ IARI, IVRI · NDRI ⚠️ · CIFE ❌ |

#### G6 — Government, aided & autonomous colleges (~45 000 colleges nationally, all kinds — AISHE)
| Family | Regulator | ≈ All-India | In our DB |
|---|---|---|---|
| Govt degree colleges (arts, science, commerce) | UGC / state | ~10 000+ | ✅ ~65 (Rajasthan, MP) |
| Govt & aided engineering colleges | AICTE | ~500 | ✅ ~6 (D1 hides more) |
| Govt medical colleges | NMC | ~400 of ~780 | ✅ ~6 |
| Govt dental colleges | DCI | ~50 of ~320 | ⚠️ 2 |
| Govt AYUSH colleges | NCISM / NCH | ~250 | ❌ |
| Govt nursing colleges | INC | ~600 | ❌ |
| Govt pharmacy colleges | PCI | ~300 | ⚠️ few |
| Govt law colleges | BCI | ~100 | ⚠️ 2 |
| Govt art colleges | — | ~50 | ✅ ~5 |
| Govt agri & vet colleges (constituent) | ICAR / VCI | ~300 | ✅ ~5 |
| State IHMs / food-craft institutes | NCHMCT | ~30 | ❌ |
| DIETs · CTEs · IASEs | NCTE | ~600 · ~100 · ~30 | ⚠️ summary rows |
| Aided & autonomous colleges | UGC | ~900 autonomous | ⚠️ 4 (D1 hides more) |

#### G7 — Private universities (~500 state private universities)
✅ ~50 in our DB (Amity, LPU, Chandigarh Univ., GLA, LNCT, Medi-Caps, ICFAI, Jaipur National, Poornima, JECRC, Jindal, UPES …).
Missing: most universities outside Rajasthan, MP and UP.

#### G8 — Private affiliated & standalone colleges
| Family | Regulator | ≈ All-India | In our DB |
|---|---|---|---|
| Private engineering colleges | AICTE | ~2 500 | ✅ ~35 |
| Private medical colleges | NMC | ~380 | ✅ ~9 |
| Private dental colleges | DCI | ~270 | ✅ 5 |
| Private nursing colleges | INC | ~5 000 | ⚠️ 2 |
| Private pharmacy colleges | PCI | ~2 500+ | ✅ several |
| Private law colleges | BCI | ~1 500 | ✅ 3 |
| Private B.Ed colleges | NCTE | ~15 000 | ⚠️ summary row |
| Standalone PGDM institutes (XLRI, SPJIMR, MDI, MICA, IMT, FORE, IRMA …) + ISB | AICTE | ~400 | ✅ ~15 |
| Private design, film & media schools | — | ~200 | ✅ ~20 |
| Private hotel-management colleges | AICTE | ~300 | ✅ several |
| DGCA flying-training organisations | DGCA | ~35 | ✅ several |
| DG Shipping maritime institutes | DGS | ~150 | ✅ 2–3 |
| Private degree colleges (Mahavidyalaya) | UGC / state | ~30 000 | ✅ ~20 |

#### G9 — Open, distance, online, skill, diploma
| Family | Regulator | ≈ All-India | In our DB |
|---|---|---|---|
| IGNOU | UGC-DEB | 1 | ✅ (programme row) |
| State open universities | UGC-DEB | ~17 | ✅ 2 (VMOU, MP Bhoj) |
| Online degrees (UGC-entitled universities) | UGC-DEB | ~100 universities | ❌ |
| Polytechnics | AICTE / state boards | ~3 000+ | ⚠️ 3 + summary rows |
| ITIs | DGT / NCVT | ~14 000 | ⚠️ summary row |
| National Skill Training Institutes | DGT | ~33 | ❌ |
| Skill universities (state) | state acts | ~10 | ❌ (the one in DB, BSDU, is private → G7) |
| Community colleges · PMKVY / JSS centres | UGC / NSDC | many | ❌ |
| SWAYAM · NPTEL | MoE | 2 | ❌ |
| Commercial MOOCs (Coursera / edX) | — | — | ✅ 1 |

#### G10a — Statutory and professional bodies (route owners)
| Body | Route | In our DB |
|---|---|---|
| ICAI | CA | ✅ (duplicated) |
| ICSI | CS | ✅ |
| ICMAI | CMA | ✅ |
| Institute of Actuaries of India | Actuary | ✅ |
| NISM · IIBF · Insurance Institute of India | Securities, banking, insurance certificates | ✅ all 3 |
| Institution of Engineers (AMIE) · IETE (AMIETE) | Degree-equivalent engineering route | ❌ |
| CFA Institute · ACCA · CIMA · CPA (foreign bodies) | Finance and accounting | ❌ |

#### G10b — Private training & coaching
| Kind | In our DB |
|---|---|
| Civil-services coaching | ✅ 6 |
| Defence coaching | ✅ 6 |
| JEE / NEET coaching | ❌ |
| Banking / SSC coaching | ❌ |
| CA / CS / CMA coaching | ⚠️ |
| Design / NID / NIFT entrance coaching | ❌ |
| Animation & VFX (Arena, MAAC, Frameboxx) | ✅ 3 |
| Fitness & yoga certification | ✅ 5 |
| Drone RPTOs | ✅ several |
| Foreign-language institutes (Alliance Française, Goethe-Institut) | ❌ |

#### G11 — Foreign-university campuses
Deakin, Wollongong, Southampton (operational) and later approvals — **❌ none in our DB**.

#### X — Doesn’t admit students (employer, research or post-selection links)
CSIR / DST / DAE / ISRO / DRDO labs ✅ ~12 · ICMR institutes ❌ · civil-service academies (LBSNAA, SVPNPA, NADT, FSI,
NACIN) ✅ 5 · PSU academies (ONGC, RBI Staff College) ✅ 2 · Sangeet Natak Akademi ✅.

### 3.3 Status flags (attributes, not groups)
An institute keeps its group but can carry any of these. They come from official lists and are shown as badges:
Institution of Eminence · Autonomous (UGC) · NAAC grade · NBA-accredited programmes · NIRF rank (existing table) ·
minority institution · women-only · central/state reservation applicable.

**Out of scope:** school-level institutions (CBSE/state boards, JNV, KV, Sainik schools, NIOS), unless we later add a
“before 12th” section.

---

## 4. Step 1 — Which groups exist per domain

Each cell is the number of distinct institutes linked to that domain’s career nodes (`node_institutes`) in that group.

Legend: **✅ ≥3** present · **⚠️ 1–2** thin · **❌ 0** expected but missing · **—** not applicable (no such institutions
exist in India for this domain). Counts are provisional (§3.1).

| Domain (career L2 nodes) | G1 | G2 | G3 | G4 | G5 | G6 | G7 | G8 | G9 | G10a | G10b |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Engineering** (B.Tech, Diploma) | ✅44 | ✅9 | ✅12 | ✅16 | ✅6 | ✅6 | ✅47 | ✅36 | ✅8 | — | ⚠️1 |
| **Computing / Data / AI** (BCA, B.Sc CS/AI/DS) | ✅8 | ⚠️2 | ✅5 | ✅10 | ✅4 | ✅12 | ✅42 | ✅43 | ✅3 | — | ❌0 |
| **Pure science & research** (Maths, Physics, Chem, Bio, Stats, Geo, Integrated M.Sc…) | ✅31 | ✅3 | ✅30 | ✅23 | ✅4 | ✅48 | ✅43 | ✅43 | ✅6 | — | — |
| **Doctor — Medical** (MBBS) | ✅9 | — | ✅3 | ✅14 | ✅4 | ✅5 | ✅30 | ✅9 | — | — | ❌0 |
| **Doctor — Dental** (BDS) | ⚠️2 | — | ⚠️1 | ⚠️2 | ⚠️1 | ⚠️2 | ✅5 | ✅5 | — | — | — |
| **Doctor — AYUSH** (BAMS, BHMS) | ✅3 | — | ⚠️2 | ✅3 | ⚠️1 | **❌0** | ✅7 | ⚠️2 | ⚠️1 | — | — |
| **Nursing & allied health** (B.Sc Nursing, BPT, Optometry, Radiology, DMLT) | ✅7 | — | ✅3 | ✅7 | ✅3 | ⚠️1 | ✅21 | ✅13 | ⚠️1 | — | — |
| **Pharmacy** (no career node — D9) | node missing | — | — | — | — | — | — | — | — | — | — |
| **Veterinary** (B.V.Sc) | ⚠️1 | — | ⚠️1 | ✅4 | ⚠️1 | **❌0** | — | ✅3 | ⚠️1 | — | — |
| **Agriculture & food** (B.Sc Agri, Food Tech) | ⚠️2 | — | ✅6 | ✅20 | ✅4 | ✅5 | ✅27 | ✅7 | ⚠️1 | — | — |
| **Architecture & planning** (B.Arch) | ✅8 | ⚠️1 | ⚠️2 | ⚠️2 | ⚠️2 | ⚠️2 | ✅12 | ⚠️2 | — | — | — |
| **Design & fashion** (B.Des, NID, NIFT) | ✅8 | — | ✅3 | ✅4 | ✅6 | ⚠️2 | ✅18 | ✅10 | ⚠️1 | — | ⚠️1 |
| **Management** (BBA streams, entrepreneurship) | ✅11 | ⚠️1 | ✅5 | ✅12 | ✅5 | ✅9 | ✅39 | ✅50 | ✅3 | ⚠️2 | — |
| **Commerce & finance** (B.Com, CFA, FinTech, Crypto) | ✅9 | ⚠️1 | ✅3 | ✅8 | ✅5 | ✅34 | ✅31 | ✅39 | ⚠️2 | ✅3 | — |
| **CA / CMA / CS** | — | — | **❌0** | **❌0** | ✅4 | **❌0** | **❌0** | ✅9 | **❌0** | ✅4 | ✅4 |
| **Banking & insurance** (Bank PO, RBI Gr B, Insurance, Wealth) | ✅3 | — | ✅3 | **❌0** | ✅3 | ⚠️1 | ⚠️2 | ✅10 | — | ✅3 | **❌0** |
| **Law** (BA/BBA/B.Com LLB, Cyber, IPR) | ⚠️1 | — | ✅3 | ✅23 | ✅4 | ⚠️2 | ✅31 | ✅3 | ⚠️1 ⚑ | — | — |
| **Civil services & govt jobs** (UPSC, SSC/State; PCS empty — D10) | — | — | ⚠️2 (X) | — | — | — | — | ✅4 (X) | — | — | ✅6 |
| **Defence** (NDA, CDS/TES) | ⚠️1 | — | ✅7 | ⚠️1 | — | ⚠️1 | — | ✅3 | — | — | ✅5 |
| **Aviation & maritime** (Pilot, Merchant Navy) | ⚠️1 | — | ✅5 | **❌0** | ⚠️1 | ⚠️1 | ⚠️1 | ✅5 | — | — | ✅6 |
| **Media, journalism & film** (BJMC, Film & TV, Digital) | **❌0** | — | ✅6 | ✅6 | ✅5 | **❌0** | ✅18 | ✅14 | ✅3 | — | **❌0** |
| **Artist — fine & performing arts** (BFA, Music, Dance, Theatre) | ✅3 | — | ✅8 | ✅7 | ✅8 | ✅9 | ✅12 | ✅21 | **❌0** | — | ✅3 |
| **Humanities & social sciences** (Econ, History, Pol Sci, Psych, Socio) | ✅6 | — | ✅10 | ✅13 | ✅10 | ✅52 | ✅35 | ✅32 | ⚠️2 | — | — |
| **Languages & literature** | ⚠️1 | — | ✅13 | ✅11 | ✅4 | ✅45 | ✅27 | ✅27 | ⚠️2 | — | — |
| **Education / teaching** (B.Ed) | ⚠️1 | — | ✅9 | ✅9 | ✅4 | ⚠️2 | ✅19 | ✅16 | ⚠️2 | — | — |
| **Sports & physical education** | — | — | ✅10 | ✅12 | ✅4 | ⚠️2 | ✅11 | ✅11 | ⚠️2 | — | ✅5 |
| **Hospitality & tourism** | — | — | ✅7 | ✅8 | ✅3 | **❌0** | ✅13 | ✅8 | ✅5 | — | ⚠️2 |

⚑ Law × G9 = 1 is a **data error to check**: BCI does not recognise open or distance LLB.
“(X)” = the rows are post-selection academies (LBSNAA, SVPNPA, NADT, FSI). They don’t admit students; they move to group X.

### 4.1 Domains not in the DB at all (no career node)

| Candidate domain | Why it matters | Evidence in DB |
|---|---|---|
| **Pharmacy** (B.Pharm, D.Pharm, Pharm.D) | Large UG route after PCB/PCM | 232 courses at 62 institutes, NIRF Pharmacy category ×28, NIPER present — **only the node is missing** |
| *(correction)* Civil and other engineering branches | You asked about “civil” | **Already present**: B.Tech has 10 branch nodes (Civil 55 institutes, Mechanical 64, CSE 82, Electrical 57, ECE 59, IT 42, AI & ML 46, Chemical 15, Biotech 19, Aerospace 4). Nothing to add. |
| **PCS / state civil services** | Root exists, is empty (D10) | Add UPPSC, RPSC, MPPSC and others as L2 nodes, or merge into “Civil services” |
| Judicial services (PCS-J / civil judge) | Natural next step after LLB | — |
| Police / CAPF / Railways / Teaching exams (CTET, NET) | Common govt-job routes | — |
| Social work (BSW/MSW) | TISS is in the DB but has no node | TISS row |
| Library science, fisheries, dairy technology, actuarial science | Smaller routes | Dairy college, Amity actuarial rows exist |
| Animation & VFX, culinary arts, cosmetology | Skill routes | Arena, Frameboxx, INIFD rows exist |

---

## 5. Step 2 — Hierarchy per domain

Each ladder runs from the top (T1) down. **Group** links back to §3. **In DB?** uses §4 and the named rows checked.
Regulator and entrance exam are the facts the app needs to say *how* you enter each step.

### 5.1 Engineering (incl. civil, mechanical, CSE, …)
Regulator: AICTE (UG/PG), state boards (diploma), DGT (ITI). Entrance: JEE Advanced → JEE Main → state CETs → university tests.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | IITs, IISc | G1 | ✅ 10 IITs, but as 52 rows (D4); IISc ✅ |
| T2 | NITs, IIITs, IIEST, other CFTIs | G2 | ✅ 9 (incl. “NITs”/“IIITs” family rows — D5) |
| T3 | Central-university engineering faculties | G3 | ✅ 12 |
| T4 | State technical universities & their university campuses (RTU, RGPV, AKTU, DTU, Jadavpur, CUSAT) | G4 | ✅ 16 |
| T5 | Deemed engineering universities (BITS, VIT, Manipal, SRM) | G5 | ✅ 6 |
| T6 | Govt & aided engineering colleges | G6 | ✅ 6 — **far too few** (D1 hides the real number) |
| T7 | Private universities | G7 | ✅ 47 |
| T8 | Private affiliated engineering colleges | G8 | ✅ 36 |
| T9 | Polytechnic / diploma | G9 | ✅ 8 (mostly family rows) |
| T10 | ITI | G9 | ⚠️ 1 family row only |
| Branch | Civil / Mechanical / Electrical / CSE / ECE / IT / AI-ML / Chemical / Biotech / Aerospace | — | ✅ 10 branch nodes exist under B.Tech |

### 5.2 Doctor — Medical (MBBS / MD)
Regulator: **NMC**. Entrance: **NEET-UG** (all seats, incl. AIIMS and JIPMER). Add an `nmc_recognised` field.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | AIIMS (all), JIPMER, PGIMER, NIMHANS | G1 | ✅ 9 (AIIMS has a family row plus campus rows) |
| T2 | Central-govt medical colleges (AFMC, BHU IMS, AMU JNMC, UCMS/MAMC Delhi) | G3 | ✅ 3 |
| T3 | State health universities & state govt medical colleges (KGMU, SMS Jaipur, SN Jodhpur, Madras MC) | G4 / G6 | ✅ 14 / 5 |
| T4 | Deemed medical universities (KMC Manipal, DY Patil, Datta Meghe) | G5 | ✅ 4 |
| T5 | Private medical universities | G7 | ✅ 30 (verify: some may be non-MBBS) |
| T6 | Private medical colleges (incl. CMC Vellore/Ludhiana — minority, private) | G8 | ✅ 9 |

### 5.3 Doctor — Dental (BDS)
Regulator: DCI (moving to NDC). Entrance: NEET-UG.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | AIIMS dental / central dental institutes (MAIDS Delhi) | G1 / G3 | ⚠️ 2 / 1 |
| T2 | Govt dental colleges | G4 / G6 | ⚠️ 2 / 2 |
| T3 | Deemed (Manipal CODS, SDM) | G5 | ⚠️ 1 |
| T4 | Private dental colleges (Rajasthan set: Surendera, Darshan, Pacific, MGSDC) | G7 / G8 | ✅ 5 / 5 |

### 5.4 Doctor — AYUSH (BAMS, BHMS, BUMS, BSMS, BNYS)
Regulator: NCISM (Ayurveda/Unani/Siddha), NCH (Homoeopathy). Entrance: NEET-UG.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | ITRA Jamnagar (G1); AIIA Delhi, NIA Jaipur, NIH Kolkata (G3) | G1 / G3 | ✅ ITRA / ✅ AIIA, NIA |
| T2 | State AYUSH universities (Rajasthan Ayurved Univ., Gujarat Ayurved Univ., Homoeopathy Univ. Jaipur) | G4 | ✅ 3 |
| T3 | Govt AYUSH colleges | G6 | **❌ 0** |
| T4 | Private AYUSH colleges & universities | G7 / G8 | ✅ 7 / ⚠️ 2 |
| Gap | BUMS, BSMS, BNYS have no nodes | — | ❌ |

### 5.5 Nursing, allied & paramedical
Regulator: INC (nursing), NCAHP (allied health), RCI (rehab). Entrance: state or university tests; AIIMS B.Sc Nursing.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | AIIMS / PGIMER / NIMHANS colleges of nursing & allied | G1 | ✅ 7 |
| T2 | National rehab institutes (AYJNISHD, NIEPMD) | G3 | ✅ 3 |
| T3 | State health universities & govt nursing colleges | G4 / G6 | ✅ 7 / ⚠️ 1 |
| T4 | Deemed / private | G5 / G7 / G8 | ✅ 3 / 21 / 13 |
| T5 | Diploma (GNM, ANM, DMLT) | G9 | ⚠️ 1 |

### 5.6 Pharmacy — *new domain*
Regulator: PCI. Entrance: state CETs, university tests; GPAT/NIPER JEE for PG.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | NIPERs, IIT (BHU) pharma | G1 | ✅ NIPER row present |
| T2 | Central-university pharmacy depts; Jamia Hamdard, ICT Mumbai (deemed) | G3 / G5 | ✅ Jamia Hamdard, ICT present |
| T3 | Govt & aided pharmacy colleges (Bombay College of Pharmacy — aided) | G6 | ✅ BCP present |
| T4 | Private pharmacy colleges (Arya College of Pharmacy …) | G8 | ✅ present (bulk of the 62) |
| T5 | D.Pharm | G9 | ✅ in courses |
| **Action** | Add L2 node “B.Pharm / D.Pharm” under Biology/PCB (also reachable from PCM) and link the 62 institutes through their courses | | |

### 5.7 Veterinary (B.V.Sc & A.H.)
Regulator: VCI. Entrance: NEET-UG (VCI 15 % quota), state tests.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | IVRI (deemed / ICAR) | G1 / G5 | ⚠️ 1 / 1 |
| T2 | State veterinary universities (DUVASU Mathura, RAJUVAS, TANUVAS) | G4 | ✅ 4 |
| T3 | Govt veterinary colleges | G6 | **❌ 0** (TANUVAS college typed govt, but not linked) |
| T4 | Private | G8 | ✅ 3 |

### 5.8 Agriculture, horticulture, forestry, food tech
Regulator / accreditor: ICAR. Entrance: **ICAR AIEEA** (CUET-ICAR), state tests.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | IARI, NDRI, IVRI (ICAR deemed) | G1 / G5 | ⚠️ 2 / ✅ 4 |
| T2 | Central agricultural universities, ICAR institutes, NIFTEM, CFTRI | G3 | ✅ 6 |
| T3 | State agricultural universities (PAU, TNAU, GBPUAT, JNKVV, SKNAU, MPUAT, ANDUAT) | G4 | ✅ 20 |
| T4 | Govt / constituent agri colleges (RCA Udaipur, College of Dairy & Food Tech) | G6 | ✅ 5 |
| T5 | Private agri colleges & universities | G7 / G8 | ✅ 27 / 7 |

### 5.9 Architecture & planning
Regulator: **CoA**. Entrance: JEE Main Paper 2 (IIT/NIT/SPA), **NATA** (others).

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | SPA Delhi/Bhopal/Vijayawada; IIT Kharagpur & Roorkee arch | G1 | ✅ 8 |
| T2 | NIT architecture depts | G2 | ⚠️ 1 |
| T3 | Central / state univ arch schools (JMI, Sir JJ, CET Trivandrum, Chandigarh CoA) | G3 / G4 / G6 | ⚠️ 2 / 2 / 2 |
| T4 | Deemed / private (CEPT, Manipal) | G5 / G7 / G8 | ⚠️ 2 / ✅ 12 / ⚠️ 2 |

### 5.10 Design & fashion
Regulator: none (NID and NIFT are statutory). Entrance: NID DAT, NIFT test, UCEED/CEED (IIT), UID, institute tests.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | NIDs, IIT design (IDC Bombay, IIT Delhi/Guwahati/Hyderabad) | G1 | ✅ 8 |
| T2 | NIFT (all campuses), FDDI | G3 | ✅ 3 (NIFT family row; FDDI ❌ missing) |
| T3 | State design institutes / univ depts | G4 / G6 | ✅ 4 / ⚠️ 2 |
| T4 | Deemed (Symbiosis SID, MIT-ID is private) | G5 | ✅ 6 |
| T5 | Private design schools (Pearl, UID, MIT-ID) | G7 / G8 | ✅ 18 / 10 |
| T6 | Short-term fashion and interior training (INIFD) | G9 / G10b | ⚠️ |

### 5.11 Management (BBA → MBA)
Regulator: AICTE (PGDM), UGC (MBA). Entrance: **CAT**, XAT, GMAT, MAT, CMAT, IPMAT (IIM IPM), NMAT, SNAP.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | IIMs (21) | G1 | ✅ 11 (some are programme rows — D4) |
| T2 | IIT / NIT management schools (SJMSOM, DMS IITD, VGSoM) | G1 / G2 | ⚠️ 1 |
| T3 | Central-university departments (FMS Delhi, IIFT, IIFM) | G3 | ✅ 5 |
| T4 | State-university departments (JBIMS, PUMBA, IMS DAVV) | G4 / G6 | ✅ 12 / 9 |
| T5 | Deemed (NMIMS, SIBM, TISS, MAHE) | G5 | ✅ 5 |
| T6 | Standalone private autonomous (XLRI, SPJIMR, MDI, ISB, TAPMI, MICA, IFMR, Great Lakes) | G8 (sub-family `standalone_pgdm`) | ✅ present |
| T7 | Private universities & affiliated MBA colleges | G7 / G8 | ✅ 39 / 50 |
| T8 | Distance MBA (IGNOU, NMIMS-CDOE) | G9 | ✅ 3 |

### 5.12 CA / CMA / CS — a professional route, not a college ladder
These are **route stages** run by a statutory body (G10a). Colleges are only *supporting* options.

| Route | Body (G10a) | Stages (new `route_stages` table) | In DB? |
|---|---|---|---|
| **CA** | ICAI | Foundation → Intermediate → Articleship (practical training) → Final → Membership | ✅ ICAI (×2 — dedupe) · stages ❌ |
| **CMA** | ICMAI | Foundation → Intermediate → Final (+ practical training) | ✅ ICMAI · stages ❌ |
| **CS** | ICSI | CSEET → Executive → Professional (+ training) | ✅ ICSI · stages ❌ |
| **CFA** | CFA Institute (outside India) | Level I → II → III | ❌ body missing |

Supporting institutions, shown as “study B.Com alongside”: central or state university B.Com (G3/G4 — **❌ 0 linked**),
deemed/private (G5 ✅4), open universities (G9 — **❌ 0**, the usual choice for CA students), and ICAI-run or ICAI-accredited
coaching (G10b ✅ 4).

### 5.13 Banking & insurance — exam routes
| Route | Body | In DB? |
|---|---|---|
| SBI PO/Clerk, IBPS PO/Clerk/RRB, RBI Grade B, NABARD, SEBI Grade A, LIC AAO, NIACL | Exam bodies (new `exam_routes`) | ❌ stored as career nodes only |
| Training & certification | IIBF, NISM, Insurance Institute of India (G10a) | ✅ 3 |
| Supporting degrees | B.Com/BBA/any graduate (G4–G8) | ✅ |
| Post-selection academies | RBI Staff College, SBI academies (X) | ✅ (move to X) |

### 5.14 Law
Regulator: **BCI**. Entrance: **CLAT** (NLUs), AILET (NLU Delhi), LSAT-India, state / university tests (DU LLB, MH-CET Law).

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 Apex | **National Law Universities** (NLSIU, NALSAR, NLU Delhi, NUJS, GNLU, NUALS, RMLNLU, NLIU, DNLU …) | G4 + family `NLU` | ✅ ~10 (with duplicates — D6) |
| T2 | INI law schools (RGSoIPL IIT Kharagpur) | G1 | ⚠️ 1 |
| T3 | Central-university law faculties (DU Faculty of Law, BHU, AMU, Jamia) | G3 | ✅ 3 |
| T4 | State-university law depts & govt law colleges (GLC Mumbai, USLLS GGSIPU, ILS Pune — aided) | G4 / G6 | ✅ ~13 / 2 |
| T5 | Deemed (Symbiosis Law School, NMIMS) | G5 | ✅ 4 |
| T6 | Private universities (Jindal, Amity, Nirma) | G7 | ✅ 31 |
| T7 | Private law colleges (Biyani Law College) | G8 | ✅ 3 |
| Next | Judicial services, AIBE (Bar exam) | exam route | ❌ |

### 5.15 Civil services & govt jobs (“civil”) — exam routes, not colleges
| Route | Exam body | Training (X, post-selection) | Coaching (G10b) | In DB? |
|---|---|---|---|---|
| IAS/IPS/IFS/IRS (UPSC CSE) | UPSC | LBSNAA, SVPNPA, FSI, NADT | Vision, Drishti, Vajiram, Shankar, Chanakya, KSG | ✅ node + ✅ academies + ✅ coaching |
| State PCS | UPPSC, RPSC, MPPSC, … | State admin academies | — | ❌ PCS root empty (D10) |
| SSC (CGL, CHSL) | SSC | — | — | ✅ node |
| Judiciary, CAPF, Railways, Teaching (CTET/NET) | various | — | — | ❌ |

UI rule: show these as **steps (eligibility → exam stages → training academy)**, never as “colleges”.
Degree advice is “any graduation”, which comes from the Humanities, Commerce and Science ladders.

### 5.16 Defence
| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | NDA (after 12th; UPSC NDA exam) | G3 | ✅ (duplicate “Nation Defence Academy Pune” — D6) |
| T2 | IMA, INA, AFA, OTA (CDS / TES / AFCAT entry) | G3 | ✅ IMA, INA, OTA, AFA |
| T3 | AFMC (medical, via NEET) | G3 | ✅ |
| Prep | RIMC, Sainik Schools | G3 | ❌ missing |
| Coaching | Defence academies (Delta, Target, Centurion …) | G10b | ✅ 5 |

### 5.17 Aviation & maritime
| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | IGRUA Amethi (govt flying), NFTI Gondia | G3 | ✅ |
| T2 | Indian Maritime University & its campuses (T.S. Chanakya) | G3 | ✅ |
| T3 | Private DGCA flying-training organisations, DG Shipping-approved maritime colleges | G8 | ✅ 5 |
| Skill | Drone RPTOs, flying clubs, aviation academies | G10b | ✅ 6 |
| Field | DGCA / DGS approval | — | ❌ add `regulator` |

### 5.18 Media, journalism & film
Entrance: IIMC test, FTII/SRFTI JET, university tests, CUET.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | — (no INI for media) | G1 | — |
| T2 | IIMC, FTII, SRFTI, central-university media depts (Jamia AJK MCRC) | G3 | ✅ 6 |
| T3 | State university media depts (MCU Bhopal ❌ missing) | G4 / G6 | ✅ 6 / ❌ 0 |
| T4 | Deemed (Symbiosis SIMC, MAHE MIC) | G5 | ✅ 5 |
| T5 | Private (Whistling Woods, AAFT, Times School, LV Prasad) | G7 / G8 | ✅ 18 / 14 |
| T6 | Digital media / animation short courses | G9 / G10b | ✅ 3 / ❌ 0 (Arena, Frameboxx sit under arts) |

### 5.19 Artist — fine & performing arts
Entrance: NSD test, institute auditions, university tests.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 Apex | **NSD, FTII (acting), Kalakshetra, Kala Bhavana (Visva-Bharati)** | G3 + family `national_arts` | ✅ 8 |
| T2 | INI (IIT design arts) | G1 | ✅ 3 |
| T3 | State arts & music universities (Bhatkhande ✅; IKSV Khairagarh ❌ missing) | G4 | ✅ 7 |
| T4 | Govt art colleges (JJ School of Art, GCFA Chennai, MSU Faculty of Fine Arts) | G6 | ✅ 9 |
| T5 | Deemed / private (Banasthali, ITC SRA, Nalanda Dance) | G5 / G7 / G8 | ✅ 8 / 12 / 21 |
| T6 | Diploma & hobby (Prayag Sangeet Samiti, Gandharva) | G9 | **❌ 0** |
| Non-admitting | Sangeet Natak Akademi | X | ✅ (move to X) |

### 5.20 Humanities & social sciences, languages, education
Entrance: **CUET-UG** (central universities), state or university admission.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | IIT/IISER HSS programmes (IIT Madras MA) | G1 | ✅ 6 / ⚠️ 1 (languages) |
| T2 | Central universities (DU colleges, JNU, BHU, EFLU, Central Hindi Institute) | G3 | ✅ 10 / 13 / 9 |
| T3 | State universities | G4 | ✅ |
| T4 | Govt & aided colleges (the large Rajasthan/MP govt college set) | G6 | ✅ 52 / 45 / ⚠️ 2 |
| T5 | Deemed (TISS, Banasthali) / private | G5 / G7 / G8 | ✅ |
| T6 | Open (IGNOU, VMOU) | G9 | ⚠️ 2 |
| Teaching | B.Ed, D.El.Ed (DIET), Regional Institutes of Education (NCERT), NCTE recognition | G3 / G6 | ⚠️ DIET, RIE, CTE summary rows only |

### 5.21 Sports & physical education
| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | National Sports University (Imphal), LNIPE Gwalior, NIS Patiala (SAI) | G3 / G5 | ✅ 10 / 4 |
| T2 | State sports universities (Swarnim Gujarat, TNPESU) | G4 | ✅ 12 |
| T3 | Private (IISM, fitness institutes) | G7 / G8 | ✅ |
| Cert | Fitness certifications (ACFIT, IIFEM) | G10b | ✅ 5 |

### 5.22 Hospitality & tourism
Entrance: **NCHM JEE** (IHMs), university tests.

| Tier | Step | Group | In DB? |
|---|---|---|---|
| T1 | Central IHMs (NCHMCT), IITTM | G3 | ✅ 7 |
| T2 | State IHMs / state univ hotel management | G4 / G6 | ✅ 8 / **❌ 0** |
| T3 | Private (IHM Aurangabad-Taj, WGSHA Manipal, Oberoi STEP) | G5 / G7 / G8 | ✅ |
| T4 | Food craft institutes, diploma | G9 | ✅ 5 |

---

## 6. Step 3 — Location hierarchy (India → State/UT → District → City → Campus)

### 6.1 What the DB has today (verified)

| Fact | Value |
|---|---|
| Location columns | `institutes.city`, `district`, `state` (free text, on the institute, not the campus) |
| States / UTs present | **22 of 36** (19 of 28 states, 3 of 8 UTs) |
| States / UTs with **0** institutes | **Bihar**, Chhattisgarh, Himachal Pradesh, Arunachal Pradesh, Meghalaya, Mizoram, Nagaland, Sikkim, Tripura, Jammu & Kashmir, Ladakh, Andaman & Nicobar, Dadra & Nagar Haveli and Daman & Diu, Lakshadweep. So IIT Patna, AIIMS Patna, NIT Patna, NIT Srinagar, IIT Jammu, IIT Bhilai, AIIMS Raipur and others are all missing. |
| `district` NULL | **429 of 669** (the existing rule is “never guess a district”) |
| `state` NULL | 25 (all “Various” / “Online” summary rows — D5) |
| Distinct city strings | 184, with **14 case variants** (`JAIPUR`/`Jaipur` 43 rows, `LUCKNOW`/`Lucknow`, `INDORE`/`Indore` …) and **renamed-city splits** (`Bangalore` 9 vs `Bengaluru` 12) |
| Delhi | all 74 rows have city “New Delhi”. New Delhi is one district of the NCT, so district-level filtering in Delhi doesn’t work today. |
| Multi-campus institutes | stored once with one city (or “Various”): NIFT (19 campuses), AIIMS, IITs, Amity (several) |

**How the app uses location today.** The Institutes list (`sub_option_screen.dart:493–540`) builds a **flat** chip filter
from `district ?? city`, so “JAIPUR” and “Jaipur” are separate chips, and there is no state or country level.
AI chat and voice match places through `InstituteCatalogService.idsInPlace` (`institute_catalog_service.dart:336`),
which uses its own token matching and has no alias for Bangalore/Bengaluru.

### 6.2 Coverage today: state × group

Shows what a student in each state would find today. The last row lists the states and UTs that are missing entirely.

| State | G1 | G2 | G3 | G4 | G5 | G6 | G7 | G8 | G9 | G10a | G10b | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
|Rajasthan|3|2|2|6|5|31|23|49|2|·|·|123|
|Maharashtra|15|·|13|2|15|10|·|26|1|5|11|98|
|Madhya Pradesh|5|2|2|9|1|33|13|10|1|·|1|77|
|Uttar Pradesh|8|·|11|13|1|1|16|22|1|·|3|76|
|Delhi|13|·|20|4|5|2|·|18|1|3|8|74|
|Tamil Nadu|12|1|5|3|1|1|3|19|1|·|2|48|
|Karnataka|6|3|3|3|7|·|1|5|·|·|·|28|
|*Summary rows (no state)*|6|·|5|·|·|2|·|4|4|·|4|25|
|West Bengal|10|·|4|4|1|·|·|2|·|1|·|22|
|Telangana|·|2|8|2|·|·|·|9|·|·|1|22|
|Gujarat|3|·|1|6|·|1|1|3|·|·|1|16|
|Uttarakhand|3|·|4|1|·|·|·|3|·|·|2|13|
|Punjab|1|·|2|3|·|·|2|1|·|·|1|10|
|Kerala|1|1|1|2|1|·|·|3|·|·|·|9|
|Haryana|1|·|4|·|·|·|·|3|·|·|·|8|
|Jharkhand|2|·|·|·|·|·|·|3|·|·|·|5|
|Chandigarh|2|·|·|·|·|·|·|2|·|·|·|4|
|Assam|3|·|·|·|·|·|·|·|·|·|·|3|
|Andhra Pradesh|1|·|·|1|·|·|·|·|·|·|·|2|
|Goa|·|·|1|1|·|·|·|·|·|·|·|2|
|Odisha|·|·|·|1|·|1|·|·|·|·|·|2|
|Puducherry|1|·|·|·|·|·|·|·|·|·|·|1|
|Manipur|·|·|1|·|·|·|·|·|·|·|·|1|
| Bihar, Chhattisgarh, HP, Arunachal, Meghalaya, Mizoram, Nagaland, Sikkim, Tripura, J&K, Ladakh, A&N, DNH&DD, Lakshadweep (14) | · | · | · | · | · | · | · | · | · | · | · | **0** |

`·` = none. Groups are provisional (§3.1). For filtering, the useful takeaway: depth exists only for **Rajasthan, MP and UP**
(the researched states). Elsewhere we have mostly national flagships.

### 6.3 Target model

```text
Country (IN)                         -- one row now; the column keeps “study abroad” possible later
 └─ State / UT  (36)                 -- LGD state code + ISO 3166-2 (IN-RJ), type state|ut, zone (North, South, East, West, Central, North-East)
     └─ District (~780)              -- LGD district code; the official list, never free text
         └─ City / town              -- canonical name + aliases (Bangalore→Bengaluru, Bombay→Mumbai, Gurgaon→Gurugram,
                                        Allahabad→Prayagraj, Calcutta→Kolkata, Madras→Chennai, Trivandrum→Thiruvananthapuram,
                                        Baroda→Vadodara, Poona→Pune, Cochin→Kochi, Mysore→Mysuru, Benares→Varanasi …)
             └─ Campus               -- the thing a student actually goes to; belongs to one institute
                                        (exact pincode / lat-lng for “near me” → Phase 2)
```

Rules:
1. **Location lives on the campus, not the institute.** An institute has ≥ 1 campus, and exactly one is `is_main`.
   NIFT gets 19 campus rows instead of one “Various” row. An IIT department row points to its parent’s campus.
2. **Online / distance-only** institutes (IGNOU online, Coursera) have no campus. They appear under an **“All India /
   Online”** option at the top of the filter, plus study centres if we add them.
3. **National summary rows** (“NITs”, “AIIMS (All Campuses)”) have no location. They stay as explainer cards and are
   replaced by real campus rows in the all-India load.
4. **District comes from the official LGD directory**, not a guess. City → district is filled automatically only when
   the city is that district’s headquarters, or the AISHE/official record names the district. Everything else goes to
   a review sheet. This keeps the existing “never guess a district” rule.
5. **Names are canonical**: title case, current official name, old names kept as aliases for search (§6.6).

### 6.4 Filter UX (one shared component)

```
[ All India ▾ ]  →  [ Rajasthan (123) ▾ ]  →  [ Jodhpur (8) ▾ ]  →  [ Jodhpur city ▾ ]
   “All India / Online” chip always first          counts update with the other filters
```

- **Cascading**: picking a state shows only its districts; picking a district shows only its cities. Each level has
  “All”. Breadcrumb chips can be removed one by one.
- **Combines with the other two axes**: Domain → Group / Tier → Location, all on one sheet. Counts are always campus
  counts after dedupe, excluding summary rows.
- **Empty states are honest**: “No government medical colleges in our list for Bihar yet”. Never fall back silently to
  another state.
- **Zone shortcut** (North / South / North-East …) on the state level, for students willing to move.
- **Remembered**: the last location pick goes in a new prefs key `institute_location_filter` (state code, district code).
  Add the key to `VOICE_AGENT_CONTEXT.md` §8.5.
- **Voice / chat**: “government engineering colleges in Jodhpur” → place resolver (§6.6) → same filter → same counts
  as the UI.

### 6.5 Schema (location part — added to §7)

```sql
CREATE TABLE countries (code TEXT PRIMARY KEY, name TEXT NOT NULL);        -- 'IN'

CREATE TABLE states (
  code TEXT PRIMARY KEY,                    -- ISO 3166-2, e.g. 'IN-RJ'
  lgd_code INTEGER UNIQUE NOT NULL,
  country_code TEXT NOT NULL REFERENCES countries(code),
  name TEXT NOT NULL, kind TEXT NOT NULL,   -- state | ut
  zone TEXT NOT NULL                        -- north | south | east | west | central | north_east
);

CREATE TABLE districts (
  lgd_code INTEGER PRIMARY KEY,
  state_code TEXT NOT NULL REFERENCES states(code),
  name TEXT NOT NULL,
  UNIQUE (state_code, name)
);

CREATE TABLE places (                       -- cities and towns that host at least one campus
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  district_lgd INTEGER NOT NULL REFERENCES districts(lgd_code),
  name TEXT NOT NULL,                       -- canonical: 'Bengaluru'
  kind TEXT NOT NULL,                       -- city | town | village
  is_district_hq INTEGER NOT NULL DEFAULT 0,
  UNIQUE (district_lgd, name)
);

CREATE TABLE place_aliases (                -- also feeds search_aliases / spell correction
  alias TEXT PRIMARY KEY,                   -- 'bangalore', 'bombay', 'gurgaon', 'new delhi' …
  place_id INTEGER REFERENCES places(id),
  district_lgd INTEGER REFERENCES districts(lgd_code),
  state_code TEXT REFERENCES states(code)   -- exactly one of the three is set
);

CREATE TABLE campuses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  name TEXT,                                -- 'NIFT Jodhpur'; NULL = same as institute
  place_id INTEGER NOT NULL REFERENCES places(id),
  is_main INTEGER NOT NULL DEFAULT 0,
  source_url TEXT, verified_at TEXT
);  -- idx_campuses_place(place_id), idx_campuses_institute(institute_id)
```

`institutes.city/district/state` stay for one release as read-only legacy columns, filled from the main campus, so
current screens and tests keep working during migration.

### 6.6 Place resolver (shared by UI search, chat, voice)

`LocationService.resolve("bangalore")` → `{state: IN-KA, district: Bengaluru Urban, place: Bengaluru}`.
Order: exact place → alias → district → state → state abbreviation (RJ, MP, UP, TN …).
It replaces the token logic in `idsInPlace` / `_requestedState` / `_requestedPlaces`, so typed and voice queries get
the same answer. `tooling/build_search_aliases.py` also emits place aliases, so spelling correction knows “Jodpur” → Jodhpur.

### 6.7 Location data work
1. Load the **LGD** state and district master (official codes) into `states` and `districts`.
2. Normalise the 184 city strings (case, spacing, renamed cities) and map each to a `place`. Fill district only by
   rule 6.3-4; the rest goes to `research/location_review.csv`.
3. Create one `campus` per institute (main) from today’s city. Expand multi-campus families (NIFT, AIIMS, IITs, NITs,
   IIMs, Amity …) from their official campus lists.
4. Split Delhi rows into their real NCT districts.
5. Fill the missing 14 states/UTs at least at **G1–G4 depth** (IIT, NIT, AIIMS, central and state universities, NLUs,
   SAUs, govt medical colleges). That gives every student some coverage. This is part of the all-India data-scope
   decision.

---

## 7. Schema design

New tables. Existing columns stay in place during the transition, and `institution_type` is kept for one release as a
read-only legacy field.

```sql
CREATE TABLE institution_groups (          -- 13 rows, §3 (G1..G9, G10a, G10b, G11, X)
  code TEXT PRIMARY KEY,                   -- G1..G9, G10a, G10b, G11, X
  name TEXT NOT NULL, description TEXT, sort_order INTEGER NOT NULL
);

CREATE TABLE families (                    -- every family in §3.2, including ones with 0 institutes in our DB
  slug TEXT PRIMARY KEY,                   -- iit, nit, aiims, nlu, iim, spa, nid, nift, ihm, sau, iti, nsti, foreign_campus …
  name TEXT NOT NULL,
  group_code TEXT NOT NULL REFERENCES institution_groups(code),
  regulators TEXT, official_list_url TEXT,
  national_count INTEGER,                  -- from the official list (T2); NULL until confirmed
  national_count_as_of TEXT
);

CREATE TABLE domains (                     -- ~26 rows, §4
  slug TEXT PRIMARY KEY,                   -- engineering, medical, dental, ayush, pharmacy, law, ca_cma_cs, civil_services, …
  name TEXT NOT NULL,
  route_type TEXT NOT NULL,                -- degree | professional_body | exam | mixed
  regulators TEXT,                         -- 'NMC' | 'BCI' | 'AICTE,UGC' …
  entrance_exams TEXT,                     -- 'NEET-UG' | 'CLAT,AILET' …
  sort_order INTEGER NOT NULL
);

CREATE TABLE domain_nodes (                -- career node → domain; descendants inherit (built: tooling/domain_tiers.py)
  node_id INTEGER PRIMARY KEY REFERENCES career_nodes(id) ON DELETE CASCADE,
  domain_slug TEXT NOT NULL REFERENCES domains(slug)
);

CREATE TABLE domain_tiers (                -- the ladders in §5
  domain_slug TEXT NOT NULL REFERENCES domains(slug),
  tier INTEGER NOT NULL,                   -- 1 = top
  label TEXT NOT NULL,                     -- 'National Law Universities'
  group_codes TEXT NOT NULL,               -- 'G4' | 'G1,G3'
  family_slugs TEXT,                       -- apex tier only: 'nlu' | 'icai,icmai,icsi' (CSV; seed checks each
                                           -- exists in families); NULL = every family of those groups
  entry_exams TEXT,
  PRIMARY KEY (domain_slug, tier)
);                                         -- ladder = apex tiers, then G1, G2, G3, G4, G5, G6, G7, G11, G8, G9

CREATE TABLE institute_classification (    -- one row per institute
  institute_id INTEGER PRIMARY KEY REFERENCES institutes(id) ON DELETE CASCADE,
  group_code TEXT NOT NULL REFERENCES institution_groups(code),
  family_slug TEXT REFERENCES families(slug),
  ownership TEXT,                          -- central_govt | state_govt | govt_aided | private | trust | ppp
  statutory_basis TEXT,
  admits_students INTEGER NOT NULL DEFAULT 1,
  parent_institute_id INTEGER REFERENCES institutes(id),   -- campus/department → parent (D4)
  is_family_record INTEGER NOT NULL DEFAULT 0,             -- D5
  listed INTEGER NOT NULL DEFAULT 1,       -- 0 only for Phase-2 rows (coaching) and non-admitting bodies
  ugc_verified INTEGER,                    -- private only: 1 = Yes, 0 = No; NULL = government (§8.6)
  ugc_list_name TEXT, ugc_reference_id TEXT, ugc_source_url TEXT, ugc_checked_at TEXT,
  regulators TEXT,                         -- recognitions held: 'NMC' | 'BCI' | 'PCI,AICTE'
  confidence TEXT NOT NULL,                -- high (official list) | medium (official site) | low (heuristic)
  source_url TEXT, verified_at TEXT, notes TEXT
);

CREATE TABLE institute_domain_tiers (      -- derived, rebuilt by every batch load; the app does no rule logic
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  domain_slug TEXT NOT NULL,
  tier INTEGER NOT NULL,
  PRIMARY KEY (institute_id, domain_slug),
  FOREIGN KEY (domain_slug, tier) REFERENCES domain_tiers(domain_slug, tier)
);                                         -- a department's career links count for its parent

CREATE TABLE professional_routes (         -- CA, CMA, CS, CFA, UPSC, SSC, banking exams, NDA …
  slug TEXT PRIMARY KEY, name TEXT NOT NULL,
  route_type TEXT NOT NULL,                -- professional_body | exam
  body_institute_id INTEGER REFERENCES institutes(id),     -- ICAI, ICSI … (G10a)
  domain_slug TEXT REFERENCES domains(slug),
  eligibility TEXT, official_url TEXT NOT NULL
);

CREATE TABLE route_stages (
  route_slug TEXT NOT NULL REFERENCES professional_routes(slug) ON DELETE CASCADE,
  stage_order INTEGER NOT NULL, name TEXT NOT NULL,        -- Foundation, Intermediate, Articleship, Final
  description TEXT, duration TEXT,
  PRIMARY KEY (route_slug, stage_order)
);
```

Plus `institute_verifications` and `institute_accreditations` (§8.6), and the location tables in §6.5 (`countries`, `states`, `districts`, `places`, `place_aliases`, `campuses`).

Indexes: `institute_classification(group_code)`, `institute_classification(family_slug)`,
`institute_domain_tiers(domain_slug, tier)`, `campuses(place_id)`, `places(district_lgd)`, `districts(state_code)`.

**Why `families` holds categories we don’t have.** The app can then say *“There are 31 NITs in India; we list 6 so
far”* or *“No AYUSH government colleges in our list yet”*, instead of acting as if the category doesn’t exist. Coverage
reports (§4, §6.2) become one SQL query instead of a script.

---

## 8. Migration & data work

### 8.1 Fix the importers first, so bad types stop coming back
- `discover_nirf_state_inventory.py`: replace the `"college|institute|school" → government_college` default with
  `unknown`; match `law` on word boundaries (`\blaw\b`, `\bllb\b`); emit `ownership` only from an official field.
- Same audit for `prepare_college_agent_manifest.py` (`govt_college` → `government_college` alias) and
  `enrich_institution_types.py` / `backfill_institution_types.py`.

### 8.2 Classifier (`tooling/classify_institution_groups.py`, new)
Order of evidence (highest wins), and each result stores its `confidence` and `source_url`:
1. **Override CSV** `research/institution_groups_overrides.csv` (hand-checked; always wins).
2. **Official lists** checked in under `research/official_lists/`: MoE INI/CFTI, UGC central / state / state-private /
   deemed lists, NMC college list, BCI, PCI, CoA, ICAR, NCHMCT → `high`.
3. Existing `institution_type` where it is reliable (`iit, iim, nit, iiit, central_university, private_university,
   deemed_*`) → `medium`.
4. Name rules (a prototype was used for §4) → `low`, and listed for review.

The prototype gave 0 unresolved rows but low confidence for the G6/G8 split. That split needs AISHE management type or
the official sites.

### 8.3 Clean-up passes (each its own script and commit)
1. **Dedupe** (D6): merge 28 probable clusters (≈ 20–30 real duplicates after review), re-pointing `node_institutes`,
   `institute_courses`, `institute_categories` and `institute_rankings` to the surviving id.
2. **Departments → parent** (D4): 140 “Name (Dept)” rows get `parent_institute_id`. Keep the row (it carries course and
   node links) but list only the parent in group views.
3. **Family rows** (D5): set `is_family_record = 1`. They stay as explainers (“There are 31 NITs”) and are excluded from counts.
4. **Non-admitting bodies** (D7) → group X, `admits_students = 0`.
5. **Hygiene** (D11): strip phone numbers from names, title-case.
6. Re-run `fix_data_spellings.py`, `fill_institute_states.py`, then `build_search_aliases.py`.
7. **Location** (§6.7): LGD master → places → one main campus per institute → multi-campus expansion → Delhi districts.
   `fill_institute_states.py` (curated `CITY_STATES`) is replaced by the `places` table.

### 8.4 Data scope — catalogue vs listings
- **Catalogue (always all-India):** all ~80 families in §3.2 go into `families`, with their official national counts.
  It is small (one row per family) and is loaded once, in Phase 0.
- **Listings (actual institutes and campuses):** loaded **top to bottom, one group at a time, in domain batches** (§8.5).

### 8.5 Load order — group by group, in domain batches (decision 2)

Each **batch** is one family list for one domain, for example “IITs” or “IIMs”. It is loaded from the official list,
verified (§8.6), placed on a city (§6), ranked (§8.6) and committed on its own. A wave (one group) finishes before the
next wave starts. Batches inside a wave can run in parallel. The existing 669 rows are not loaded separately: each one
is re-checked inside the batch it belongs to. Rows that no batch claims stay hidden until reviewed.

| Wave | Group | Batch | Domain(s) | Official list | ≈ Size |
|---|---|---|---|---|---|
| **A** | G1 | A1 IIT + IISc | Engineering, science | MoE INI list | 24 |
| | | A2 IIM | Management | MoE INI list | 21 |
| | | A3 AIIMS + JIPMER, PGIMER, NIMHANS | Medical, nursing, allied | MoHFW / MoE INI list | ~24 |
| | | A4 IISER, NISER, ISI | Science | MoE / DAE / MoSPI | 9 |
| | | A5 NIPER · SPA · NID · NIFTEM · ITRA · NFSU · RRU · Kalakshetra (+ AIIA, G3) | Pharmacy, architecture, design, food, AYUSH, forensic, police, arts | MoE INI list | ~25 |
| **B** | G2 | B1 NIT | Engineering, architecture | MoE CFTI list | 31 |
| | | B2 IIIT (MoE + PPP) + IIEST | Computing, engineering | MoE | ~27 |
| **C** | G3 | C1 Central universities | All (departments as children) | UGC central list | ~56 |
| | | C2 NIFT · FDDI · NSD · FTII · SRFTI · IIMC | Design, arts, media | ministry lists | ~40 campuses |
| | | C3 Central IHMs · IITTM | Hospitality | NCHMCT | ~22 |
| | | C4 ICAR institutes + central agricultural universities | Agriculture, veterinary | ICAR | ~20 |
| | | C5 NDA · IMA · INA · AFA · OTA · AFMC | Defence | MoD | 6 |
| | | C6 IGRUA · NFTI · IMU campuses | Aviation, maritime | MoCA / MoS | ~8 |
| | | C7 IIFT · IIFM · IIPA · RIEs · NIS · AYUSH & rehab national institutes | Management, education, sports, AYUSH, rehab | ministry lists | ~30 |
| **D** | G4 | D1 NLUs | Law | CLAT consortium / BCI | ~26 |
| | | D2 State technical universities | Engineering | AICTE / UGC | ~30 |
| | | D3 State agricultural + veterinary universities | Agriculture, veterinary | ICAR / VCI | ~80 |
| | | D4 State health-science + AYUSH universities | Medical, dental, nursing, AYUSH | UGC / NMC | ~28 |
| | | D5 State general universities, **state by state** | All | UGC state list | ~300 |
| | | D6 State sports, arts, women’s universities | Sports, arts | UGC | ~25 |
| **E** | G5 | E1 Government-funded deemed (TISS, ICT, IARI, NDRI, IVRI, CIFE, IIST, DIAT, HBNI, LNIPE) | mixed | UGC deemed list | ~25 |
| | | E2 Private deemed, by domain (engineering → medical → management → others) | mixed | UGC deemed list | ~120 |
| **F** | G7 | F1… Private universities, **state by state** (RJ, MP, UP first, then by size) | All | UGC private list | ~500 |
| **G** | G6 | G1… Govt & aided colleges, by **domain × state**: medical → engineering → dental → pharmacy → nursing → law → AYUSH → agri/vet → arts/science/commerce degree → teacher education | per domain | NMC, AICTE, DCI, PCI, INC, BCI, NCISM/NCH, ICAR, UGC 2(f)/12(B), NCTE | thousands |
| **H** | G8 | H1… Private colleges, same domain × state order | per domain | same as G | thousands |
| **I** | G9 | I1 IGNOU + state open universities · I2 polytechnics (state by state) · I3 ITIs + NSTIs | Diploma, skill | UGC-DEB, AICTE, DGT | ~17 · ~3 000 · ~14 000 |
| **J** | G10a, G11 | J1 ICAI · ICSI · ICMAI · IAI · NISM · IIBF · III with their route stages · J2 foreign campuses | CA/CS/CMA, finance · all | their Acts · UGC / IFSCA | ~10 · ~3 |

Notes:
- Wave J is small and the CA/CS/CMA steps screens depend on it, so it can run alongside Wave A.
- Waves G–I are large. They ship state by state, so each app release gets fuller without waiting for all of India.
- **Phase 2 (not now):** G10b coaching (decision 1), exact geo-location / “near me” (decision 5).

### 8.6 Verification & ranking policy (decision 4)

**Verification: a UGC Yes/No check on private institutions (decision 4).** Nothing is dropped because of it.
Every private institution stays listed and simply shows its result.

| Ownership | `ugc_verified` | How it is decided | Shown in app |
|---|---|---|---|
| **Private** (G7 private universities, G8 private colleges, private deemed in G5, G11) | **Yes** / **No** | **Yes** if the institution is on the UGC list (private / deemed university list), or it is a college on the UGC 2(f)/12(B) list, or it is affiliated to a UGC-listed university (taken from that university’s official affiliated-college list). Otherwise **No**. | “UGC verified ✓” or “Not UGC verified” |
| **Government / public** (G1–G4, G6, government-funded deemed) | not applicable (NULL) | not checked; these come from their own government lists in §8.5 | no UGC badge |

Expected **No** results in today’s data: standalone AICTE PGDM schools (XLRI, SPJIMR, MDI, ISB, MICA, IMT, Great Lakes,
TAPMI, IFMR), private design and film schools awarding their own diplomas (Pearl, Whistling Woods, MIT-ID unless the
degree comes from a partner university), and private flying or maritime schools. They stay listed and show “Not UGC verified”.

Stored on `institute_classification`: `ugc_verified INTEGER` (1 = Yes, 0 = No, NULL = government, not applicable),
`ugc_list_name`, `ugc_reference_id`, `ugc_source_url`, `ugc_checked_at`.
Programme approval for professional degrees (NMC for MBBS, BCI for law, PCI for pharmacy, CoA for B.Arch, INC for
nursing, NCTE for B.Ed, AICTE for B.Tech/MBA) is recorded separately in `institute_verifications` as information. It
doesn’t hide anything either.

**Ranking: government sources only. No private rankings** (QS, THE, India Today, Outlook and similar are excluded).

| Source | Run by | What it gives | Coverage |
|---|---|---|---|
| **NIRF** | Ministry of Education | rank or rank band per category (Overall, University, Colleges, Research, Engineering, Management, Pharmacy, Medical, Dental, Law, Architecture, Agriculture, Innovation, Open University, Skill University, State Public University) | only the top ~100–300 per category |
| **NAAC** | UGC’s accreditation council | institution grade or accreditation status, valid until a date | most universities and many colleges |
| **NBA** | AICTE’s accreditation board | programme-level accreditation (B.Tech, MBA, Pharmacy …) | technical programmes |

**UGC does not publish a ranking.** NIRF is the government ranking. NAAC is the UGC-side quality signal.

How the app shows ranking for **every** institute:
1. **Domain-matched NIRF rank** (e.g. NIRF Engineering for an engineering ladder), then NIRF Overall / University /
   Colleges if there is no domain rank. Show the year. Store the last 3 years (2023–2025) so we can show a trend.
2. **Top highlight:** NIRF top 10 in that category → **“Top 10 · NIRF 2025 Engineering”** badge. Top 100 (or the
   first band) → **“NIRF Top 100”**. Shown on cards, in ladders and in chat answers.
3. **No NIRF rank** → show the **NAAC grade / status** (and NBA for the programme, if any).
4. **Neither** → **“Not ranked”**. Never invent or borrow a rank.

Sorting within a tier: NIRF rank → NIRF band → NAAC grade → name. The tier itself never changes because of rank.

Schema: extend `institute_rankings` (already NIRF-only, PK institute + system + year + category) with 2023–2024 rows,
and add `institute_accreditations(institute_id, body NAAC|NBA, programme NULL|name, grade, status, valid_until,
source_url)`.

### 8.7 Career tree additions (D9, D10, §4.1)
Add Pharmacy L2 (+ B.Pharm, D.Pharm, Pharm.D leaves), PCS children, BUMS/BSMS/BNYS, Social Work, Judicial Services. Link institutes
through their courses (`course_career_nodes`).

---

## 9. App changes (Flutter)

Follows CLAUDE.md: no new state management, manual DI, one test per new service and model.

| Layer | Change |
|---|---|
| Models | `InstitutionGroup`, `InstitutionFamily`, `Domain`, `DomainTier`, `InstituteClassification`, `ProfessionalRoute`, `RouteStage`, `IndianState`, `District`, `Place`, `Campus`, `LocationFilter` — each with `fromJson`/`toJson` and parser tests |
| `LocalDatabase` | queries for groups, families, domains, tiers, routes, states/districts/places/campuses; join classification and main campus into `getInstituteCatalog` |
| New `LocationService` | loads the state → district → place tree once; `resolve(text)` (aliases, abbreviations); `childrenOf(level)`; `countsFor(filter)` — replaces `idsInPlace` / `_requestedState` / `_requestedPlaces` logic in `InstituteCatalogService` |
| `InstituteCatalogService` (location) | `filter(domain?, group?, tier?, family?, location?)` as the single query used by UI, chat and voice; `coveredStates` reads from `states` |
| `InstituteCatalogService` | `byGroup(code)`, `byDomainTier(domain, tier)`, `ladderFor(domain)` → `[tier → institutes]`, excluding family and department rows; remove unused `byInstitutionType` once replaced |
| New `RouteService` | `routeFor(slug)` → stages + body + supporting institutions |
| Grounding (`local_ai_grounding_service.dart:438`, catalog `:435,512`) | swap raw `institution_type` text for “Group: State public university · Law tier 1: National Law University · Regulator: BCI” |
| Voice / typed chat | answer “top law colleges in Rajasthan” from the ladder (tier, then NIRF rank, then name); add the group or family names to `search_aliases.txt` (e.g. “NLU” → National Law University) |
| UI | Domain screen gets a **“College ladder”** section (tiers as cards with counts) and, for CA/CS/CMA/UPSC, a **“Steps”** timeline instead |
| UI (location) | Replace the flat `district ?? city` chips in `sub_option_screen.dart:493–540` with a cascading **India → State → District → City** filter sheet (with an “All India / Online” chip) inside `ResourceListScreen`; same component on the ladder view; remembered via prefs key `institute_location_filter` |
| UI (rank & trust) | Every institute card shows its ranking line (NIRF rank with year → NAAC grade → “Not ranked”), a **Top 10 / Top 100** highlight, and and, for **private** institutions, a **UGC verified ✓ / Not UGC verified** line (government ones show none). An optional “UGC verified only” filter toggle; chat and voice mention the status when listing a private college (§8.6) |
| UI (catalogue) | Ladder tiers show “31 NITs in India · 6 listed” using `families.national_count`; empty tiers say so plainly |
| Docs | Update `docs/context/VOICE_AGENT_CONTEXT.md` §8 (schema, row counts, traps) in the same commit; bump `pubspec.yaml` when the DB asset changes |

---

## 10. Task breakdown (one commit each, through the agent pipeline)

### Phase 0 — foundations (before any batch)
| # | Task | Output | Depends on |
|---|---|---|---|
| T1 | Fix importer type bugs (D1, D2) + tests in `tooling/tests` | `fix(tooling): …` | — |
| T2 | Commit official reference lists under `research/official_lists/` (MoE INI/CFTI, UGC university + 2(f)/12(B), NMC, BCI, PCI, CoA, ICAR, NCHMCT, NCTE, NIRF 2023–25, NAAC) | data | — |
| T3 | `classify_institution_groups.py` + override CSV + tests | script | T2 |
| T4 | Dedupe + department → parent + family flags (D4–D6) | DB asset | T3 |
| T5 | All new tables (§6.5, §7, §8.6): groups, families, domains, tiers, classification, verifications, accreditations, location | DB asset | T4 |
| T6 | Fill `families` (all ~80, national counts) + `domains`, `domain_nodes`, `domain_tiers` — **done** (`tooling/domain_tiers.py`: 27 domains, ladders = apex families + group order; `institute_domain_tiers` derived and rebuilt by every batch) | DB asset | T5 |
| T7 | Location master: LGD `states` + `districts`, `places` + `place_aliases` | DB asset | T5 |
| T8 | Career tree additions §8.7 + course-based linking | DB asset | T5 |
| T9 | Batch loader `tooling/load_family_batch.py`: official list → institutes + campuses (city) + verification + NIRF/NAAC + tier → UGC Yes/No for private rows → review sheet → DB. One command per batch. | script + tests | T5–T7 |

### Phase 1a — app support (can start once T5 is done)
| # | Task | Output | Depends on |
|---|---|---|---|
| T10 | Dart models + `LocalDatabase` queries + parser tests | code | T5 |
| T11 | `InstituteCatalogService` ladder + filter APIs, `LocationService`, `RouteService` + tests | code | T10 |
| T12 | Ranking line (top highlight, NAAC fallback, “Not ranked”) + private-only UGC Yes/No badge + “UGC verified only” filter + widget tests | code | T11 |
| T13 | “College ladder” + “Steps” UI; cascading India → State → District → City filter; chat/voice switched to the shared filter | code | T11 |
| T14 | Grounding / voice text (group, tier, rank, verification) + search aliases rebuild | code + asset | T11 |

### Phase 1b — data waves (each batch = one commit, §8.5)
| # | Wave | Release gate |
|---|---|---|
| T15 | Wave A (G1) + Wave J (professional bodies, foreign campuses) | ship release 1: all national flagships + CA/CS/CMA steps |
| T16 | Wave B (G2) | |
| T17 | Wave C (G3) | ship release 2: every state/UT has G1–G3 coverage |
| T18 | Wave D (G4) | |
| T19 | Wave E (G5) + Wave F (G7) | ship release 3: all universities |
| T20+ | Waves G, H, I — domain × state batches | ship per state group |

Each release: update `VOICE_AGENT_CONTEXT.md` (schema, counts, prefs key `institute_location_filter`), bump
`pubspec.yaml`, run the Play build.

### Phase 2 (agreed, not now)
- G10b coaching centres (the 34 current rows stay hidden until then).
- Exact geo-location: pincode, latitude/longitude, “near me” (needs location permission + privacy review).

### Acceptance criteria
- Every **private** institution has `ugc_verified` = 1 or 0 with a source (list URL or affiliating university); every
  government institution has NULL. 0 private rows left unchecked.
- Every listed institute has exactly one `group_code`, one main campus with a city, and a ranking display
  (NIRF → NAAC → “Not ranked”). Rankings come only from NIRF / NAAC / NBA.
- No private institute in G4 or G6; no coaching centre listed in Phase 1; no non-admitting body outside X.
- `families` holds every family in §3.2, each with a confirmed national count or an explicit NULL.
- All 36 states/UTs and all LGD districts exist; 0 case or alias duplicates among places; districts never guessed.
- The same query gives the same count in the location filter, typed chat and voice (shared test).
- CA, CMA, CS and UPSC show stages, not colleges.
- `flutter analyze` clean; `flutter test` green; `tooling/tests` green.

### Decisions (confirmed 2026-10-01)
1. **Coaching (G10b):** not in Phase 1 → Phase 2. Existing coaching rows stay in the DB with `listed = 0`.
2. **Load order:** top to bottom, one group at a time, in domain batches (IIT, IIM, AIIMS … then NIT … then central,
   state …) as in §8.5.
3. **Department rows → keep as children of the parent (best for search).**
   - Search: a query like “IIT Bombay civil engineering” matches the department row exactly, and the semantic index
     gets one focused entry per department instead of one blurred entry per institute.
   - Lists: results are grouped under the parent (“IIT Bombay → Civil, Electrical …”), so ladders and counts show each
     institute once.
   - Data: courses and career-node links stay on the department, so nothing is lost.
   - Collapsing them into the parent would lose all three.
4. **Ranking for all institutes, government sources only, top highlighted**: NIRF (MoE), then NAAC (UGC), then NBA
   (§8.6). **UGC check for private institutions only**, stored and shown as **Yes / No**. Nothing is hidden because of
   it, and government institutions aren’t checked.
5. **Location depth:** state → district → city only. Exact geo-location → Phase 2.
