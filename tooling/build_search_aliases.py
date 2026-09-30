"""Builds assets/data/search_aliases.json for the AI Guide search.

Merges the hand-written tooling/search_aliases.txt with aliases derived from
assets/data/career_path.db:
  * "Name (ABBR)" / "ABBR (Name)" pairs in career, institute and course names
    ("Armed Forces Medical College (AFMC)", "BAMS (Ayurveda)").
  * Initials of multi-word institute names that the data also uses on their
    own ("Banaras Hindu University" -> "bhu", because "BHU (Geology)" exists).

Derived keys, and hand-written keys of up to three letters, are dropped
when they are everyday English words (so "it", "up", "me" never expand)
unless the hand-written key is prefixed with "!". Every expansion is
checked against the data vocabulary; ones that can match nothing are
reported. Re-run whenever the database or the hand-written list changes:

    python3 tooling/build_search_aliases.py
"""

import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "assets/data/career_path.db"
CURATED = ROOT / "tooling/search_aliases.txt"
DICTIONARY = ROOT / "assets/data/english_words.txt"
TARGET = ROOT / "assets/data/search_aliases.json"

# Short everyday words (the dictionary only holds words of 4+ letters).
COMMON_SHORT = set(
    "a an am as at be by do go he hi if in is it me my no of oh ok on or so "
    "to up us we and are but can did for get got had has her him his how its "
    "let may new not now old one our out own put say see she the too two use "
    "was way who why yes yet you all any ask big day end far few fun job lot "
    "low man men off pay run set sit top try war win bad bus car cut die eat "
    "fit hot key lab law map mom dad pen art act add age ago air arm bag bat "
    "bed box boy buy cap cat cow cry dog dry ear egg eye fan fat fee fly gas "
    "god gun hat ice ink kid leg lip mad mat mix mud net oil pan pet pin pot "
    "raw red rod sad sea sky son spa tea tie toy van web wet win".split()
)
STOP = {"of", "and", "the", "for", "in", "at", "&", "to", "on"}


def spells(acronym, full):
    """True when [acronym]'s letters start [full]'s words in order ("iiit" ->
    Indian Institute of Information Technology), optionally continuing into
    the same word ("btech" -> B. Tech, "cftri" -> Central Food ...)."""
    parts = [w for w in words(full) if w not in STOP]
    letters = acronym.lower()

    def match(i, j):
        if i == len(letters):
            return j == len(parts)
        if j == len(parts):
            return False
        word = parts[j]
        # Take 1..n leading letters of this word, then move to the next word.
        for n in range(1, len(word) + 1):
            if i + n > len(letters) or letters[i : i + n] != word[:n]:
                break
            if match(i + n, j + 1):
                return True
        return False

    return match(0, 0)


def words(text):
    return re.findall(r"[a-z0-9]+", text.lower().replace(".", ""))


def norm(text):
    return " ".join(words(text))


def main():
    db = sqlite3.connect(DB)
    names = [
        row[0]
        for sql in (
            "select name from streams",
            "select name from career_nodes",
            "select name from institutes",
            "select name from institute_courses",
            "select name from job_sectors",
        )
        for row in db.execute(sql)
        if row[0]
    ]
    vocabulary = {
        w
        for sql in (
            "select name || ' ' || coalesce(intro, '') from career_nodes",
            "select name || ' ' || coalesce(city, '') || ' ' || "
            "coalesce(district, '') || ' ' || coalesce(state, '') || ' ' || "
            "coalesce(description, '') from institutes",
            "select name || ' ' || coalesce(specialization, '') "
            "from institute_courses",
            "select name || ' ' || coalesce(description, '') from job_sectors",
            "select name from streams",
        )
        for (text,) in db.execute(sql)
        for w in words(text or "")
    }
    dictionary = set(DICTIONARY.read_text().split())
    # The bundled list stops at 4 letters; the full one also knows "dip".
    web2 = Path("/usr/share/dict/web2")
    if web2.exists():
        dictionary |= {w for w in web2.read_text().split() if len(w) <= 3 and w.islower()}

    def everyday(key):
        return all(w in COMMON_SHORT or w in dictionary for w in key.split())

    aliases = defaultdict(list)
    dropped = []

    def add(key, expansion, forced=False, source="curated"):
        key, expansion = norm(key), norm(expansion)
        if not key or not expansion or key == expansion:
            return
        # A hand-written key longer than three letters is a deliberate
        # synonym ("doctor" -> "medical"); short ones ("it", "me") and
        # everything derived automatically must not be everyday words.
        # Hand-written short keys only clash with common words; obscure
        # dictionary entries such as "nit" or "ca" are the acronyms meant.
        if source == "curated":
            clash = " " not in key and len(key) <= 3 and key in COMMON_SHORT
        else:
            clash = everyday(key)
        if not forced and clash:
            dropped.append(f"{key} ({source})")
            return
        if expansion not in aliases[key]:
            aliases[key].append(expansion)

    # Hand-written.
    for line in CURATED.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, _, rest = line.partition("=")
        forced = key.strip().startswith("!")
        for expansion in rest.split(";"):
            add(key.strip().lstrip("!"), expansion, forced)

    # "Name (ABBR)" and "ABBR (Name)".
    derived = 0
    for name in names:
        for outer, inner in re.findall(r"^([^()]+?)\s*\(([^()]+)\)", name):
            outer, inner = outer.strip(), inner.strip()
            for short, full in ((inner, outer), (outer, inner)):
                compact = short.replace(".", "").replace(" ", "")
                if (
                    re.fullmatch(r"[A-Z][A-Za-z]{2,7}", compact)
                    and sum(c.isupper() for c in compact) >= 2
                    and len(words(full)) >= 2
                    and spells(compact, full)
                ):
                    before = len(aliases.get(compact.lower(), []))
                    add(compact, full, source="db")
                    derived += len(aliases.get(compact.lower(), [])) > before

    # Initials of institute names, when the data uses them on their own.
    # Institutes whose name starts with an abbreviation, by city
    # ("BHU (Geology)" in Varanasi) — the evidence an initials alias needs.
    institutes = [
        (name, (city or "").strip().lower())
        for name, city in db.execute("select name, city from institutes")
    ]
    leading = defaultdict(set)
    for name, city in institutes:
        if words(name) and city:
            leading[words(name)[0]].add(city)
    for name, city in institutes:
        base = re.split(r"[(,]", name)[0]
        parts = [w for w in re.findall(r"[A-Za-z]+", base) if w.lower() not in STOP]
        if len(parts) < 3 or not all(p[0].isupper() for p in parts):
            continue
        initials = "".join(p[0] for p in parts).lower()
        if city and city in leading.get(initials, ()) and initials not in aliases:
            before = len(aliases.get(initials, []))
            add(initials, base, source="initials")
            derived += len(aliases.get(initials, [])) > before

    # Expansions must be able to match something.
    unmatched = sorted(
        f"{k} = {e}"
        for k, exps in aliases.items()
        for e in exps
        if not any(w in vocabulary for w in e.split())
    )

    TARGET.write_text(
        json.dumps(dict(sorted(aliases.items())), indent=1, ensure_ascii=False)
        + "\n"
    )
    total = sum(len(v) for v in aliases.values())
    print(f"{len(aliases)} keys, {total} expansions ({derived} from the database) -> {TARGET}")
    if dropped:
        print(f"dropped {len(dropped)} everyday-word keys: {', '.join(sorted(set(dropped)))}")
    if unmatched:
        print(f"WARNING {len(unmatched)} expansions match no data word:")
        for item in unmatched:
            print(f"  {item}")


if __name__ == "__main__":
    main()
