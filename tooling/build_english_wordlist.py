"""Builds assets/data/english_words.txt for the AI Guide spell corrector.

Real English words must never be "corrected" into CareerPath data words
(e.g. "mother" -> "other"), so the app ships a word list to recognise them.
Source: Webster's Second International (web2, 1934, public domain), shipped
with macOS/FreeBSD at /usr/share/dict/web2. Only lowercase words of 4-12
letters are kept: shorter words are never corrected and longer ones are rare.
Plain text on purpose: the APK/IPA already compresses assets, and it loads
on every platform, including web.

Usage: python3 tooling/build_english_wordlist.py [path/to/web2]
"""

import re
import sys
from pathlib import Path

SOURCE = Path(sys.argv[1] if len(sys.argv) > 1 else "/usr/share/dict/web2")
TARGET = Path(__file__).resolve().parent.parent / "assets/data/english_words.txt"

words = sorted(
    {
        line.strip()
        for line in SOURCE.read_text().splitlines()
        if re.fullmatch(r"[a-z]{4,12}", line.strip())
    }
)
TARGET.write_text("\n".join(words) + "\n")
print(f"{len(words)} words -> {TARGET} ({TARGET.stat().st_size} bytes)")
