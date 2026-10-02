#!/usr/bin/env python3
"""Propose and apply duplicate, department and family-record clean-ups (plan T4).

Plan §8.3 passes 1–3 (problems D4–D6). The script never guesses silently: it
proposes actions in three classes, each with a confidence and a reason, and a
reviewer copies the rows they accept into an "approved" CSV.

  merge          two rows are one institute ("MICA" / "MICA Ahmedabad",
                 "X (ABBR)" / "X"); the source's links move to the target
                 (load_family_batch.merge_into) and the source is deleted.
  department     "IIT Bombay (Civil)" / "X - Department of Y" rows become
                 children of their parent: they get an institute_classification
                 row with parent_institute_id and the parent's group, family,
                 ownership and UGC check, confidence 'medium'.
  family_record  national summary rows ("DIET", "Government Polytechnics
                 (Various States)") get is_family_record = 1.

Rows classified by a batch (an institute_classification row) are authoritative:
they are never merged away, re-parented or re-flagged. They may only be the
target of a merge or a parent. A department whose parent is not classified yet
is proposed with status "blocked" and becomes ready once a batch classifies
the parent, so the script is meant to be re-run after every wave.

Usage:
  # dry run (default): read the DB, write the review sheet, change nothing
  python3 tooling/cleanup_institutes.py [--database path] [--review path]
  # apply approved rows in one transaction (rolled back unless --write)
  python3 tooling/cleanup_institutes.py --apply research/cleanup/cleanup_approved.csv --write
"""

from __future__ import annotations

import argparse
import csv
import datetime
import json
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from domain_tiers import assign_tiers
from load_family_batch import (
    DEFAULT_DATABASE,
    GOVERNMENT_OWNERSHIP,
    REPO_ROOT,
    BatchError,
    classify,
    link_count,
    merge_into,
    normalize,
)

DEFAULT_REVIEW = REPO_ROOT / "research/cleanup/cleanup_review.csv"

COLUMNS = ("key", "action", "confidence", "status", "source_id", "source_name", "source_city",
           "target_id", "target_name", "target_city", "group_code", "family_slug", "ownership",
           "reason")
CONFIDENCE_ORDER = {"high": 0, "medium": 1, "low": 2}
ACTION_ORDER = {"merge": 0, "department": 1, "family_record": 2}

# Spelling variants of the same city. Both sides map to the first form.
CITY_ALIASES = {
    "bangalore": "bengaluru", "bombay": "mumbai", "new delhi": "delhi", "gurgaon": "gurugram",
    "calcutta": "kolkata", "madras": "chennai", "allahabad": "prayagraj", "mysore": "mysuru",
    "trivandrum": "thiruvananthapuram", "ropar": "rupnagar", "baroda": "vadodara",
    "mangalore": "mangaluru", "jaiselmer": "jaisalmer", "ganganagar": "sri ganganagar",
}
SUMMARY_CITIES = {"various", "online"}
# Parenthesised words that describe the row, not a department ("SVPNPA (Training)").
DESCRIPTORS = {"training", "training academy", "all campuses", "various", "various states",
               "online", "main campus"}
STOPWORDS = {"of", "and", "the", "for", "in", "at"}
DEPARTMENT_HEAD = re.compile(
    r"^(department|dept|faculty|centre|center|division|school|college) of\b", re.IGNORECASE)
STRONG_DEPARTMENT_HEAD = re.compile(r"^(department|dept|faculty) of\b", re.IGNORECASE)
# A bracket names a department only when it names a subject ("(Civil)"), not a
# place ("(M.P.)"), a partner ("(NASM India Partner)") or an old name.
DISCIPLINE = re.compile(
    r"\b(nursing|physiotherapy|pharmacy|geology|marine|optometry|sciences?|engineering|law|"
    r"ayurveda|veterinary|management|mba|bba|civil|mechanical|electrical|electronics|ece|cse|"
    r"chemical|chemistry|physics|mathematics|statistics|biotech\w*|aerospace|architecture|"
    r"design|dental|medical|medicine|education|psychology|economics|commerce|arts|music|"
    r"journalism|media|data|cyber|computer|finance|marketing|actuarial|homoeopathy|unani|"
    r"agricultur\w*|fisheries|forestry|nutrition|department|faculty|programs?|pgp)\b",
    re.IGNORECASE)
# Name keys made by cutting a city off: they only match rows in the same city
# ("Government College, Ratangarh" is not "Government College, Budhni").
CITY_RULES = {"city_suffix", "place_suffix"}

# Summary rows: (pattern, family slug, ownership or None when the family is mixed).
FAMILY_HINTS: list[tuple[re.Pattern[str], str | None, str | None]] = [
    (re.compile(r"\bDIETs?\b"), "teacher_education_govt", "state_govt"),
    (re.compile(r"\bState CTEs?\b", re.IGNORECASE), "teacher_education_govt", "state_govt"),
    (re.compile(r"\bGovernment Polytechnics\b", re.IGNORECASE), "polytechnic", "state_govt"),
    (re.compile(r"\bPolytechnics\b", re.IGNORECASE), "polytechnic", None),
    (re.compile(r"\bITIs?\b|Industrial Training Institutes", re.IGNORECASE), "iti", None),
    (re.compile(r"\bNIELIT\b|\bDOEACC\b", re.IGNORECASE), "nielit", "central_govt"),
    (re.compile(r"\bB\.?\s?Ed\b", re.IGNORECASE), None, None),
    (re.compile(r"MicroMasters|Coursera|\bedX\b", re.IGNORECASE), "commercial_mooc", "private"),
]
# A summary row names a kind of institution, not one institute.
GENERIC_NAME = re.compile(
    r"(\b[A-Z]{2,}s\b|\bDIET\b|\bCTEs?\b|Colleges|Institutes|Polytechnics|Universities|"
    r"All Campuses|Various)")


class CleanupError(Exception):
    """The approved sheet cannot be applied as written."""


@dataclass
class Row:
    id: int
    name: str
    city: str
    source_id: str | None
    classified: bool
    parent_id: int | None = None
    family_record: bool = False


@dataclass
class Proposal:
    action: str
    confidence: str
    source: Row
    target: Row | None = None
    reason: str = ""
    status: str = "ready"
    group_code: str = ""
    family_slug: str = ""
    ownership: str = ""

    def csv_row(self) -> dict[str, Any]:
        return {
            "key": f"{self.action}:{self.source.id}",
            "action": self.action, "confidence": self.confidence, "status": self.status,
            "source_id": self.source.id, "source_name": scrub(self.source.name),
            "source_city": self.source.city,
            "target_id": self.target.id if self.target else "",
            "target_name": scrub(self.target.name) if self.target else "",
            "target_city": self.target.city if self.target else "",
            "group_code": self.group_code, "family_slug": self.family_slug,
            "ownership": self.ownership, "reason": self.reason,
        }


# --------------------------------------------------------------------------- names

def scrub(name: str) -> str:
    """Names go into a committed CSV: long digit runs (phone numbers) are cut."""
    return re.sub(r"\d[\d\s-]{5,}\d", "[number removed]", name)


def compact(text: str) -> str:
    """normalize(), plus "Xavier's" = "Xaviers" and "J.J." / "J J" = "JJ"."""
    out: list[str] = []
    previous_single = False
    for word in normalize(re.sub(r"['`’]", "", text)).split():
        single = len(word) == 1 and word.isalpha()
        if single and previous_single:
            out[-1] += word
        else:
            out.append(word)
        previous_single = single
    return " ".join(out)


def city_key(city: str | None) -> str:
    text = normalize(re.sub(r"[\d-]+", " ", city or ""))
    return CITY_ALIASES.get(text, text)


def strip_city(name_key: str, city: str | None) -> str:
    """Drop a trailing city ("christ university bangalore" in Bengaluru)."""
    target = city_key(city)
    if not target:
        return name_key
    words = name_key.split()
    for size in (3, 2, 1):
        if len(words) > size and city_key(" ".join(words[-size:])) == target \
                and words[-size - 1] not in STOPWORDS:
            return " ".join(words[:-size])
    return name_key


def split_parenthesis(name: str) -> tuple[str, str] | None:
    """("National Law University Delhi", "NLU") for "National Law University (NLU) Delhi"."""
    match = re.fullmatch(r"\s*(.*?)\s*\(([^()]*)\)\s*(.*?)\s*", name)
    if not match or not match.group(1):
        return None
    base = " ".join(part for part in (match.group(1), match.group(3)) if part)
    return base, match.group(2).strip()


def initials(words: Iterable[str]) -> str:
    return "".join(word[0] for word in words if word not in STOPWORDS).upper()


def is_acronym(acronym: str, text: str) -> bool:
    """"NALSAR" for "National Academy of Legal Studies and Research": the letters
    are word starts in order, a word may give several leading letters."""
    letters = re.sub(r"[^A-Za-z]", "", acronym).upper()
    if len(letters) < 2 or not re.fullmatch(r"[A-Z][A-Za-z]*", acronym.replace(" ", "")) \
            or sum(c.isupper() for c in acronym) < 2:
        return False
    words = normalize(text).upper().split()

    def match(rest: str, start: int) -> bool:
        if not rest:
            return True
        for index in range(start, len(words)):
            word = words[index]
            for size in range(1, len(word) + 1):
                if rest.startswith(word[:size]) and match(rest[size:], index + 1):
                    return True
                if not rest.startswith(word[:size]):
                    break
        return False

    return match(letters, 0)


def expands(short_key: str, long_key: str) -> bool:
    """"iiit bangalore" vs "international institute of information technology
    bangalore": the short name's first word is the strict initials of the long
    name's leading words and the remaining words are equal."""
    short = short_key.split()
    long = long_key.split()
    if not short or len(short[0]) < 3 or not short[0].isalpha():
        return False
    head, rest = short[0].upper(), short[1:]
    if rest and long[-len(rest):] != rest:
        return False
    lead = long[: len(long) - len(rest)] if rest else long
    return len(lead) > 1 and initials(lead) == head


# --------------------------------------------------------------------------- reading

def read_rows(connection: sqlite3.Connection) -> list[Row]:
    return [
        Row(row_id, name, city or "", source_id, classified is not None, parent, bool(record))
        for row_id, name, city, source_id, classified, parent, record in connection.execute(
            "SELECT i.id, i.name, i.city, i.source_id, c.institute_id, c.parent_institute_id, "
            "COALESCE(c.is_family_record, 0) FROM institutes i "
            "LEFT JOIN institute_classification c ON c.institute_id = i.id ORDER BY i.id"
        )
    ]


def name_keys(row: Row) -> dict[str, str]:
    """Every key a duplicate of this row could share with it, by rule."""
    keys = {"exact": compact(row.name)}
    city_free = strip_city(compact(row.name), row.city)
    if city_free != keys["exact"] and city_free:
        keys["city_suffix"] = city_free
    for separator in (",", " - "):
        if separator in row.name:
            head, tail = row.name.split(separator, 1)
            if city_key(row.city) and city_key(row.city) in normalize(tail) and \
                    not DEPARTMENT_HEAD.match(head.strip()) and not DEPARTMENT_HEAD.match(tail.strip()):
                keys["place_suffix"] = compact(head)
    split = split_parenthesis(row.name)
    if split:
        base, inner = split
        if is_acronym(inner, f"{base} {row.city}"):
            keys["acronym_in_brackets"] = strip_city(compact(base), row.city)
        elif is_acronym(base, inner):
            keys["expansion_in_brackets"] = compact(inner)
        elif normalize(inner) in DESCRIPTORS or city_key(inner) == city_key(row.city):
            keys["descriptor_in_brackets"] = strip_city(compact(base), row.city)
    return keys


def base_key(row: Row) -> str:
    """The name without its city and without a descriptive bracket."""
    keys = name_keys(row)
    return keys.get("descriptor_in_brackets") or strip_city(compact(row.name), row.city)


def abbreviation(row: Row) -> str | None:
    split = split_parenthesis(row.name)
    if split and is_acronym(split[1], f"{split[0]} {row.city}"):
        return normalize(split[1])
    if split and is_acronym(split[0], split[1]):
        return normalize(split[0])
    return None


def same_city(a: Row, b: Row) -> bool:
    return not a.city or not b.city or city_key(a.city) == city_key(b.city)


def lower(confidence: str) -> str:
    return {"high": "medium", "medium": "low", "low": "low"}[confidence]


# --------------------------------------------------------------------------- proposing

def _department_parts(row: Row) -> tuple[str, str, bool] | None:
    """(parent name, department, strong) when the name reads as a department."""
    split = split_parenthesis(row.name)
    if split:
        base, inner = split
        if DISCIPLINE.search(inner) and not (
                is_acronym(inner, f"{base} {row.city}") or is_acronym(base, inner)
                or normalize(inner) in DESCRIPTORS or "various" in normalize(inner)):
            return base, inner, True
    if " - " in row.name:
        head, tail = (part.strip() for part in row.name.split(" - ", 1))
        if DEPARTMENT_HEAD.match(tail):
            return head, tail, bool(STRONG_DEPARTMENT_HEAD.match(tail))
    if ", " in row.name:
        head, tail = (part.strip() for part in row.name.split(", ", 1))
        if STRONG_DEPARTMENT_HEAD.match(head):
            return tail, head, True
    return None


def _find_parent(rows: list[Row], child: Row, parent_name: str) -> tuple[Row, str] | None:
    """The single row named [parent_name], directly or by its short form."""
    wanted = compact(parent_name)
    candidates = [r for r in rows if r.id != child.id]
    exact = [r for r in candidates if r.parent_id is None and not r.family_record and (
        compact(r.name) == wanted
        or strip_city(compact(r.name), r.city) == strip_city(wanted, child.city))]
    # Several rows (the parent and its duplicates): a classified one, else the
    # one with exactly that name in the child's city. Apply follows merges.
    for narrowed in (exact, [r for r in exact if r.classified],
                     [r for r in exact if compact(r.name) == wanted and same_city(r, child)]):
        if len(narrowed) == 1:
            return narrowed[0], "exact"
    if exact:
        return None
    shorts = {wanted, strip_city(wanted, child.city)}
    expanded = [r for r in candidates if r.parent_id is None and not r.family_record and any(
        expands(short, long) for short in shorts
        for long in (compact(r.name), strip_city(compact(r.name), r.city)))]
    if len(expanded) == 1:
        return expanded[0], "short form"
    return None


def _family_proposal(row: Row, families: dict[str, str]) -> Proposal | None:
    split = split_parenthesis(row.name)
    summary_city = city_key(row.city) in SUMMARY_CITIES
    summary_name = bool(split and ("various" in normalize(split[1])
                                   or normalize(split[1]) == "all campuses"))
    if not (summary_city or summary_name):
        return None
    for pattern, family, ownership in FAMILY_HINTS:
        if pattern.search(row.name):
            break
    else:
        family = ownership = None
    proposal = Proposal("family_record", "low", row,
                        family_slug=family or "", ownership=ownership or "",
                        group_code=families.get(family or "", ""))
    generic = bool(GENERIC_NAME.search(row.name))
    where = f"city '{row.city}'" if summary_city else "name says several campuses"
    if family is None:
        proposal.status = "blocked: no family matches the name"
        proposal.reason = f"{where}; one row for many institutions, but its family is unclear"
        if not generic:
            proposal.reason = f"{where}; looks like a brand with many centres, not a family summary"
        return proposal
    if ownership in (None, "private", "trust"):
        proposal.confidence = "medium"
        proposal.status = ("blocked: mixed ownership; classify() needs one value"
                           if ownership is None else
                           "blocked: a private family record needs a UGC check from its batch")
    else:
        proposal.confidence = "high" if generic else "medium"
    proposal.reason = f"{where}; the name is a kind of institution ({family})"
    return proposal


def propose(connection: sqlite3.Connection) -> list[Proposal]:
    rows = read_rows(connection)
    by_id = {row.id: row for row in rows}
    families = dict(connection.execute("SELECT slug, group_code FROM families"))
    proposals: list[Proposal] = []

    family_rows = {}
    for row in rows:
        if row.classified:
            continue
        proposal = _family_proposal(row, families)
        if proposal:
            family_rows[row.id] = proposal

    # Departments first: "Amity University (Actuarial Science)" is not a duplicate.
    department_ids: set[int] = set()
    for row in rows:
        if row.classified or row.id in family_rows:
            continue
        parts = _department_parts(row)
        if not parts:
            continue
        parent_name, department, strong = parts
        department_ids.add(row.id)
        found = _find_parent(rows, row, parent_name)
        proposal = Proposal("department", "high", row)
        if found is None:
            if not strong or not split_parenthesis(row.name):
                continue  # a comma in an address is too weak without a parent
            proposal.confidence = "low"
            proposal.status = "blocked: no parent row"
            proposal.reason = f"'{department}' reads as a department of '{parent_name}', which has no row"
            proposals.append(proposal)
            department_ids.add(row.id)
            continue
        parent, how = found
        proposal.target = parent
        proposal.reason = f"'{department}' is a department of '{parent.name}' (parent found by {how} name)"
        if how != "exact" or not strong:
            proposal.confidence = "medium"
        if not same_city(row, parent):
            proposal.confidence = lower(proposal.confidence)
            proposal.reason += f"; cities differ ({row.city} / {parent.city})"
        if not parent.classified:
            proposal.status = "blocked: parent not classified yet (re-run after its batch)"
        elif parent.parent_id is not None or parent.family_record:
            proposal.status = "blocked: parent is itself a child or a family record"
        else:
            proposal.group_code, proposal.family_slug = connection.execute(
                "SELECT group_code, COALESCE(family_slug, '') FROM institute_classification "
                "WHERE institute_id = ?", (parent.id,)).fetchone()
        proposals.append(proposal)
        department_ids.add(row.id)

    proposals.extend(_merge_proposals(connection, rows, by_id, department_ids | set(family_rows)))
    proposals.extend(family_rows.values())
    proposals.sort(key=lambda p: (ACTION_ORDER[p.action], CONFIDENCE_ORDER[p.confidence],
                                  p.status != "ready", p.source.name.casefold()))
    return proposals


def _merge_proposals(connection: sqlite3.Connection, rows: list[Row], by_id: dict[int, Row],
                     excluded: set[int]) -> list[Proposal]:
    candidates = [r for r in rows if r.id not in excluded
                  and (r.classified or not r.family_record)]
    index: dict[str, list[tuple[Row, str]]] = {}
    for row in candidates:
        for rule, value in name_keys(row).items():
            index.setdefault(value, []).append((row, rule))
        short = abbreviation(row)
        if short:
            index.setdefault(short, []).append((row, "abbreviation"))

    edges: dict[tuple[int, int], tuple[str, str]] = {}

    def add(a: Row, b: Row, confidence: str, reason: str) -> None:
        if a.id == b.id or (a.classified and b.classified):
            return
        pair = (min(a.id, b.id), max(a.id, b.id))
        if not same_city(a, b):
            confidence = lower(confidence)
            reason += f"; cities differ ({a.city} / {b.city})"
        old = edges.get(pair)
        if old is None or CONFIDENCE_ORDER[confidence] < CONFIDENCE_ORDER[old[0]]:
            edges[pair] = (confidence, reason)

    for value, members in index.items():
        for i, (a, rule_a) in enumerate(members):
            for b, rule_b in members[i + 1:]:
                if {rule_a, rule_b} & CITY_RULES and not same_city(a, b):
                    continue
                described = " + ".join(sorted({rule_a, rule_b}))
                add(a, b, "high", f"same name after removing noise ({described}): '{value}'")

    # Short forms without brackets: "CMI Chennai" / "Chennai Mathematical Institute",
    # "IIIT Bangalore" / "International Institute of Information Technology Bangalore".
    plain = [(r, base_key(r)) for r in candidates
             if not (r.classified and (r.parent_id or r.family_record))]
    for a, short in plain:
        words = short.split()
        if not words or len(words[0]) < 3 or not a.name.split()[0].isupper():
            continue
        for b, long in plain:
            if b.id != a.id and len(long.split()) > len(words) and same_city(a, b) and (
                    expands(short, long) or expands(compact(a.name), compact(b.name))):
                add(a, b, "high", f"'{a.name.split()[0]}' is the initials of '{b.name}'")

    # One name is the other plus words: "SP Jain" / "SP Jain Institute of Management".
    for a, short in plain:
        if not short:
            continue
        starts = {short} if (len(short.split()) >= 2 or a.name.split()[0].isupper()) else set()
        if abbreviation(a):
            starts.add(abbreviation(a))
        for b, long in plain:
            if b.id == a.id or not same_city(a, b) or (a.classified and b.classified):
                continue
            for start in starts:
                if long.startswith(start + " "):
                    add(a, b, "medium", f"'{a.name}' is the start of '{b.name}' in the same city")

    return _cluster(connection, edges, by_id)


def _quality(connection: sqlite3.Connection, row: Row) -> tuple:
    """Sort key for the row a cluster keeps (smallest wins)."""
    noise = 0
    noise += "(" in row.name
    noise += strip_city(compact(row.name), row.city) != compact(row.name)
    noise += row.name.isupper() and len(row.name) > 6
    noise += " - " in row.name or "," in row.name
    noise += len(row.name.split()) == 1 or row.name.split()[0].isupper() and len(row.name.split()) <= 2
    return (not row.classified, row.source_id is None, noise,
            -link_count(connection, row.id), row.id)


def _cluster(connection: sqlite3.Connection, edges: dict[tuple[int, int], tuple[str, str]],
             by_id: dict[int, Row]) -> list[Proposal]:
    parent: dict[int, int] = {}

    def find(x: int) -> int:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    # Strong links build clusters; weaker links only point between them.
    for (a, b), (confidence, _) in edges.items():
        if confidence == "high":
            parent[find(a)] = find(b)
    clusters: dict[int, list[int]] = {}
    for a, b in edges:
        for x in (a, b):
            clusters.setdefault(find(x), [])
            if x not in clusters[find(x)]:
                clusters[find(x)].append(x)
    proposals: list[Proposal] = []
    keep_of: dict[int, Row] = {}
    for root, members in clusters.items():
        rows = [by_id[m] for m in members]
        keep = min(rows, key=lambda r: _quality(connection, r))
        keep_of[root] = keep
        for row in rows:
            if row.id == keep.id:
                continue
            if len([r for r in rows if r.classified]) > 1:
                continue  # two batch rows in one cluster: a batch must decide
            pair = (min(row.id, keep.id), max(row.id, keep.id))
            confidence, reason = edges.get(pair, ("high", "linked through another duplicate"))
            proposals.append(_merge(row, keep, confidence, reason))
    done = {p.source.id for p in proposals}
    for (a, b), (confidence, reason) in edges.items():
        if confidence == "high" or find(a) == find(b):
            continue
        keep_a, keep_b = keep_of[find(a)], keep_of[find(b)]
        keep, drop_root = sorted((keep_a, keep_b), key=lambda r: _quality(connection, r))
        drop_rows = [by_id[m] for m in clusters[find(drop_root.id)]]
        for row in drop_rows:
            if row.id not in done and row.id != keep.id:
                proposals.append(_merge(row, keep, confidence, reason))
                done.add(row.id)
    return proposals


def _merge(row: Row, keep: Row, confidence: str, reason: str) -> Proposal:
    proposal = Proposal("merge", confidence, row, keep, reason)
    if row.classified:
        proposal.status = "blocked: the source is classified by a batch"
    elif row.source_id and keep.source_id and row.source_id != keep.source_id:
        proposal.confidence = lower(confidence) if confidence == "high" else confidence
        proposal.reason += ("; both rows carry a research source_id, so a re-import would "
                            "bring the merged one back")
    return proposal


def write_review(proposals: list[Proposal], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        for proposal in proposals:
            writer.writerow(proposal.csv_row())


def summarize(proposals: list[Proposal]) -> dict[str, dict[str, int]]:
    summary: dict[str, dict[str, int]] = {}
    for proposal in proposals:
        counts = summary.setdefault(proposal.action, {"total": 0, "ready_high": 0})
        counts["total"] += 1
        counts[proposal.confidence] = counts.get(proposal.confidence, 0) + 1
        if proposal.status != "ready":
            counts["blocked"] = counts.get("blocked", 0) + 1
        elif proposal.confidence == "high":
            counts["ready_high"] += 1
    return summary


# --------------------------------------------------------------------------- applying

def read_approved(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        if row.get("action") not in ACTION_ORDER:
            raise CleanupError(f"unknown action in {path}: {row.get('action')!r}")
    return rows


def _institute(connection: sqlite3.Connection, institute_id: int) -> tuple[str, Any] | None:
    return connection.execute(
        "SELECT i.name, c.institute_id IS NOT NULL, c.parent_institute_id, "
        "COALESCE(c.is_family_record, 0) FROM institutes i "
        "LEFT JOIN institute_classification c ON c.institute_id = i.id WHERE i.id = ?",
        (institute_id,),
    ).fetchone()


def apply(connection: sqlite3.Connection, approved: list[dict[str, str]],
          verified_at: str) -> dict[str, Any]:
    """Apply approved rows: merges, then departments, then family records.

    A row whose source is classified by a batch, or whose names no longer
    match the database, is refused (listed in the report, nothing touched);
    only a target that a batch has since classified may carry a new name.
    A row that is already applied is skipped, so a re-run changes nothing."""
    report: dict[str, Any] = {"merged": [], "departments": [], "family_records": [],
                              "already_applied": [], "refused": [], "target_renamed": []}
    moved: dict[int, int] = {}

    def refuse(row: dict[str, str], why: str) -> None:
        report["refused"].append(f"{row['action']} {row['source_id']} '{row['source_name']}': {why}")

    def live(row_id: int) -> int:
        while row_id in moved:
            row_id = moved[row_id]
        return row_id

    ordered = sorted(approved, key=lambda r: ACTION_ORDER[r["action"]])
    for row in ordered:
        action = row["action"]
        source_id = int(row["source_id"])
        target_id = int(row["target_id"]) if row.get("target_id") else None
        source = _institute(connection, source_id)
        target = _institute(connection, live(target_id)) if target_id else None

        if action in ("merge", "department"):
            if target_id is None:
                refuse(row, "no target")
                continue
            if target is None:
                refuse(row, f"target {target_id} no longer exists")
                continue
            if target_id == live(target_id) and scrub(target[0]) != row["target_name"]:
                # Ids are never reused (AUTOINCREMENT): a batch that classified the
                # target may have given it its official name. Anything else is stale.
                if not target[1]:
                    refuse(row, f"target {target_id} is now named '{target[0]}'")
                    continue
                report["target_renamed"].append(
                    f"{target_id}: '{row['target_name']}' is now '{target[0]}'")
        if source is None:
            if action == "merge" and target is not None:
                report["already_applied"].append(f"merge {source_id} -> {target_id}")
            else:
                refuse(row, "source no longer exists")
            continue
        name, classified, parent, family_record = source
        if scrub(name) != row["source_name"]:
            refuse(row, f"source is now named '{name}'")
            continue

        if action == "merge":
            if classified:
                refuse(row, "classified rows are never merged away")
                continue
            keep = live(target_id)
            if keep == source_id:
                refuse(row, "source and target are the same row")
                continue
            merge_into(connection, keep, source_id)
            moved[source_id] = keep
            report["merged"].append(f"{name} -> {target[0]}")

        elif action == "department":
            keep = live(target_id)
            if classified:
                if parent == keep:
                    report["already_applied"].append(f"department {source_id} -> {keep}")
                else:
                    refuse(row, "the row is classified by a batch")
                continue
            parent_row = connection.execute(
                "SELECT group_code, family_slug, ownership, statutory_basis, admits_students, "
                "regulators, ugc_verified, ugc_list_name, ugc_reference_id, ugc_source_url, "
                "source_url, verified_at, parent_institute_id, is_family_record "
                "FROM institute_classification WHERE institute_id = ?", (keep,)).fetchone()
            if parent_row is None:
                refuse(row, "the parent is not classified yet")
                continue
            (group, family, ownership, statutory_basis, admits, regulators, ugc_verified,
             ugc_list, ugc_reference, ugc_url, source_url, parent_verified_at,
             grandparent, parent_is_record) = parent_row
            if grandparent is not None or parent_is_record:
                refuse(row, "the parent is itself a child or a family record")
                continue
            spec = {
                "name": name, "group": group, "family": family, "ownership": ownership,
                "statutory_basis": statutory_basis, "admits_students": bool(admits),
                "regulators": regulators, "verified_at": parent_verified_at or verified_at,
                "verification": {"list_url": source_url},
                "ugc": None if ugc_verified is None else {
                    "verified": ugc_verified, "list_name": ugc_list,
                    "reference_id": ugc_reference, "source_url": ugc_url},
                "notes": f"Department of {target[0]}; attached by "
                         f"tooling/cleanup_institutes.py on {verified_at}.",
            }
            try:
                classify(connection, source_id, spec, parent_id=keep, confidence="medium")
            except BatchError as error:
                refuse(row, str(error))
                continue
            report["departments"].append(f"{name} -> {target[0]}")

        else:  # family_record
            if classified:
                if family_record:
                    report["already_applied"].append(f"family record {source_id}")
                else:
                    refuse(row, "the row is classified by a batch")
                continue
            family = row.get("family_slug", "")
            ownership = row.get("ownership", "")
            family_row = connection.execute(
                "SELECT group_code, official_list_url FROM families WHERE slug = ?", (family,)
            ).fetchone()
            if family_row is None:
                refuse(row, f"unknown family '{family}'")
                continue
            if ownership not in GOVERNMENT_OWNERSHIP:
                refuse(row, "a family record needs a government ownership here; private "
                            "families get their UGC check from a batch")
                continue
            classify(connection, source_id, {
                "name": name, "group": family_row[0], "family": family,
                "ownership": ownership, "verified_at": verified_at,
                "verification": {"list_url": family_row[1]},
                "notes": f"National summary row; flagged by tooling/cleanup_institutes.py "
                         f"on {verified_at}.",
            }, family_record=True, confidence="medium")
            report["family_records"].append(name)

    if connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'domain_tiers'"
    ).fetchone():
        report["tiers"] = assign_tiers(connection)
    problems = connection.execute("PRAGMA foreign_key_check").fetchall()
    if problems:
        raise CleanupError(f"foreign key problems: {problems[:5]}")
    return report


# --------------------------------------------------------------------------- CLI

def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--review", type=Path, default=DEFAULT_REVIEW,
                        help="where the dry run writes the proposals")
    parser.add_argument("--apply", type=Path, metavar="APPROVED_CSV",
                        help="apply the rows of this approved sheet")
    parser.add_argument("--write", action="store_true",
                        help="commit the --apply transaction (default: dry run, rolled back)")
    parser.add_argument("--dry-run", action="store_true",
                        help="the default; kept so the intent can be spelled out")
    parser.add_argument("--verified-at", default=datetime.date.today().isoformat())
    args = parser.parse_args(argv)
    if args.write and args.dry_run:
        parser.error("--write and --dry-run contradict each other")
    if args.write and not args.apply:
        parser.error("--write needs --apply")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.apply:
        connection = sqlite3.connect(f"file:{args.database}?mode=ro", uri=True)
        try:
            proposals = propose(connection)
        finally:
            connection.close()
        write_review(proposals, args.review)
        print(json.dumps(summarize(proposals), indent=1))
        print(f"wrote {len(proposals)} proposals to {args.review} (database not changed)")
        return 0

    approved = read_approved(args.apply)
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        connection.execute("BEGIN")
        report = apply(connection, approved, args.verified_at)
        if args.write:
            connection.commit()
        else:
            connection.rollback()
    except (CleanupError, BatchError, sqlite3.Error) as error:
        connection.rollback()
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    finally:
        connection.close()
    print(json.dumps(report, ensure_ascii=False, indent=1))
    print("written" if args.write else "(dry run: nothing written; add --write to commit)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
