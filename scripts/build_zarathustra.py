#!/usr/bin/env python3
"""
Project Gutenberg #1998 (Thus Spake Zarathustra, tr. Thomas Common)
-> RAG corpus in the same shape as the project's mathe.txt (KJV Matthew).

Writes zarathustra.txt - Nietzsche's text only (RAG persona corpus).
Elisabeth Foerster-Nietzsche's introduction (1905) and Anthony M. Ludovici's appendix notes (1909)
are located only to cut them off. They are not written anywhere - excluded text is not kept in this
project (CLAUDE.md 3.2).
"""
import re
import json
import unicodedata
from pathlib import Path

RAW = Path("/home/claude/nietzsche/raw/pg1998_raw.txt")
OUT = Path("/home/claude/nietzsche/clean")
OUT.mkdir(parents=True, exist_ok=True)

text = RAW.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
lines = text.split("\n")


# ---------------------------------------------------------------- utilities
def normalize(s: str) -> str:
    """Curly punctuation -> ASCII. Em/en dashes are kept (meaningful in Nietzsche)."""
    return (s.replace("’", "'").replace("‘", "'")
             .replace("“", '"').replace("”", '"')
             .replace(" ", " "))


ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}


def roman_to_int(s: str) -> int:
    total, prev = 0, 0
    for ch in reversed(s):
        v = ROMAN[ch]
        total = total - v if v < prev else total + v
        prev = max(prev, v)
    return total


def find(pattern, start=0, end=None):
    """Match real headings only: they start at column 0.
    The CONTENTS block repeats every heading indented by 5 spaces."""
    end = len(lines) if end is None else end
    rx = re.compile(pattern)
    for i in range(start, end):
        if rx.match(normalize(lines[i]).rstrip()):
            return i
    raise LookupError(pattern)


# ------------------------------------------------------- section boundaries
i_start = find(r"^\*\*\* START OF THE PROJECT GUTENBERG")
i_intro = find(r"^INTRODUCTION BY MRS FORSTER-NIETZSCHE\.$", i_start)
i_body = find(r"^THUS SPAKE ZARATHUSTRA\.$", i_intro + 1)
i_appx = find(r"^APPENDIX\.$", i_body)
i_end = find(r"^\*\*\* END OF THE PROJECT GUTENBERG", i_appx)

body_lines = lines[i_body + 1:i_appx]     # introduction (i_intro..i_body) and appendix (i_appx..) are dropped


# --------------------------------------------------------------- body parse
PART_RE = re.compile(
    r"^(?:THUS SPAKE ZARATHUSTRA\.\s+)?"
    r"(FIRST|SECOND|THIRD|FOURTH AND LAST) PART\.", re.I)
PART_NUM = {"FIRST": 1, "SECOND": 2, "THIRD": 3, "FOURTH AND LAST": 4}
PROLOGUE_RE = re.compile(r"^ZARATHUSTRA'S PROLOGUE\.$")
DISCOURSES_RE = re.compile(r"^ZARATHUSTRA'S DISCOURSES\.$")
CHAP_RE = re.compile(r"^([IVXL]+)\.\s+([A-Z][A-Z0-9 ,'\"—–.\-!?]+?)\.?$")
SECTION_RE = re.compile(r"^(\d+)\.$")


def titlecase(t: str) -> str:
    small = {"of", "the", "and", "a", "an", "in", "on", "to", "with",
             "or", "for", "at", "by", "from", "out"}
    words = t.lower().split()
    return " ".join(w.capitalize() if i == 0 or w not in small else w
                    for i, w in enumerate(words))


chapters = []          # {part, num, title, units: [(section, text)]}
cur = None
part = None
in_epigraph = False    # after a PART heading, before the first chapter
section = None
block = []


def flush_block():
    """Turn the accumulated raw block into one numbered unit."""
    global block
    if not block:
        return
    raw = [normalize(b) for b in block]
    block = []
    if cur is None or in_epigraph:
        return
    is_verse = sum(1 for l in raw if l.startswith("     ")) >= max(1, len(raw) // 2)
    if is_verse:
        body = "\n".join(l.rstrip() for l in raw)
    else:
        body = " ".join(l.strip() for l in raw)
        body = re.sub(r"\s+", " ", body).strip()
    if body:
        cur["units"].append((section, body))


for raw_line in body_lines:
    line = normalize(raw_line).rstrip()
    stripped = line.strip()

    if not stripped:
        flush_block()
        continue

    m = PART_RE.match(stripped)
    if m:
        flush_block()
        part = PART_NUM[m.group(1).upper()]
        in_epigraph = True
        cur = None
        section = None
        continue

    if PROLOGUE_RE.match(stripped):
        flush_block()
        in_epigraph = False
        section = None
        cur = {"part": part, "num": 0, "title": "Zarathustra's Prologue", "units": []}
        chapters.append(cur)
        continue

    if DISCOURSES_RE.match(stripped):
        flush_block()
        cur = None
        continue

    m = CHAP_RE.match(stripped)
    if m and stripped == stripped.upper():
        flush_block()
        in_epigraph = False
        section = None
        cur = {"part": part, "num": roman_to_int(m.group(1)),
               "title": titlecase(m.group(2)), "units": []}
        chapters.append(cur)
        continue

    m = SECTION_RE.match(stripped)
    if m and cur is not None and not in_epigraph:
        flush_block()
        section = int(m.group(1))
        continue

    block.append(line)

flush_block()


# ------------------------------------------------------------------- output
header = [
    "THUS SPAKE ZARATHUSTRA",
    "A Book for All and None",
    "Friedrich Nietzsche (1844-1900), translated by Thomas Common (1850-1919)",
    "Source: Project Gutenberg eBook #1998 - public domain",
    "",
    "Nietzsche's text only. The 1905 introduction by Elisabeth Foerster-Nietzsche",
    "and the 1909 appendix notes by Anthony M. Ludovici have been removed",
    "and are not kept in this project.",
    "",
    "Citation format:  <chapter>:<paragraph>   e.g. 1:14 = chapter I, paragraph 14",
    "Prologue is chapter 0.  [SS n] marks an author-numbered section within a chapter.",
    "",
]

out, records = list(header), []
cur_part = None
for ch in chapters:
    if ch["part"] != cur_part:
        cur_part = ch["part"]
        out += ["", "", f"PART {cur_part}", ""]
    out += ["", f"Chapter {ch['num']}. {ch['title']}", ""]
    last_section = None
    for idx, (sec, body) in enumerate(ch["units"], start=1):
        if sec != last_section and sec is not None:
            out.append(f"[SS {sec}]")
            last_section = sec
        ref = f"{ch['num']}:{idx}"
        out.append(f"{ref} {body}")
        records.append({
            "ref": ref, "part": ch["part"], "chapter": ch["num"],
            "chapter_title": ch["title"], "section": sec,
            "paragraph": idx, "text": body,
        })
    out.append("")

(OUT / "zarathustra.txt").write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
(OUT / "zarathustra_units.jsonl").write_text(
    "\n".join(json.dumps(r, ensure_ascii=False) for r in records) + "\n", encoding="utf-8")

# -------------------------------------------------------------------- stats
words = sum(len(r["text"].split()) for r in records)
print(f"chapters parsed : {len(chapters)} (expect 81 = prologue + 80)")
print(f"numbered units  : {len(records)}")
print(f"words (body)    : {words:,}")
print(f"~tokens (x1.33) : {int(words * 1.33):,}")
for p in (1, 2, 3, 4):
    n = [c for c in chapters if c["part"] == p]
    print(f"  part {p}: {len(n):>2} chapters, "
          f"{sum(len(c['units']) for c in n):>4} units, "
          f"ch {min(c['num'] for c in n)}-{max(c['num'] for c in n)}")
empty = [f"{c['num']}. {c['title']}" for c in chapters if not c["units"]]
print("EMPTY CHAPTERS:", empty if empty else "none")
