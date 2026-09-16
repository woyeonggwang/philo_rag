#!/usr/bin/env python3
"""
Build RAG corpora for 4 Nietzsche works from Project Gutenberg sources.

Principle: Nietzsche's own published text ONLY.
Removed: translator prefaces/introductions/footnotes, editor's notes,
         tables of contents, title pages, PG boilerplate,
         posthumous Nachlass compilations, and passages that merely
         duplicate text already held in the Zarathustra corpus.
Removed material is not deleted - it is written to excluded/ for reference.
"""
import re
import json
from pathlib import Path

RAW = Path("/home/claude/nietzsche/raw")
OUT = Path("/home/claude/nietzsche/clean")
EXC = Path("/home/claude/nietzsche/excluded")
OUT.mkdir(parents=True, exist_ok=True)
EXC.mkdir(parents=True, exist_ok=True)


# --------------------------------------------------------------- load / clean
def load(name):
    t = Path(RAW / name).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    t = (t.replace("’", "'").replace("‘", "'")
          .replace("“", '"').replace("”", '"')
          .replace(" ", " "))
    t = re.sub(r"_([^_\n]{1,200}?)_", r"\1", t)   # _italics_ markup -> plain
    # translator footnotes embedded mid-text -> delete the whole bracketed span
    t = re.sub(r"\[Footnote.*?\]", "", t, flags=re.S | re.I)
    t = re.sub(r"\[Illustration.*?\]", "", t, flags=re.S | re.I)
    return t.split("\n")


def pg_body(lines):
    """Slice between the PG start/end markers, also cutting the old-style
    'End of Project Gutenberg's ...' trailer that precedes the marker."""
    s = next(i for i, l in enumerate(lines) if l.startswith("*** START OF THE PROJECT GUTENBERG"))
    e = next(i for i, l in enumerate(lines) if l.startswith("*** END OF THE PROJECT GUTENBERG"))
    body = lines[s + 1:e]
    for i, l in enumerate(body):
        if re.match(r"^End of (the )?Project Gutenberg", l.strip(), re.I):
            return body[:i]
    return body


def idx(lines, pattern, start=0, occurrence=1):
    rx = re.compile(pattern)
    hits = 0
    for i in range(start, len(lines)):
        if rx.match(lines[i].rstrip()):
            hits += 1
            if hits == occurrence:
                return i
    raise LookupError(f"{pattern!r} #{occurrence}")


# ------------------------------------------------------------------ the parser
SIGNATURE = re.compile(
    r"^(FRIEDRICH NIETZSCHE\.|TURIN\b.*|Sils-Maria.*|Nice\b.*|"
    r"ANTHONY M\. LUDOVICI\.|H\. B\. S\.|THE END\.|"
    r"Translated by .*|By F\.? ?W\.? Nietzsche)$", re.I)
FOOT_NUM = re.compile(r"^\[\d+\]")
FOOT_BRACKET = re.compile(r"^\[Footnote\b")
ILLUSTRATION = re.compile(r"^\[Illustration")


SMALL = {"of","the","and","a","an","in","on","to","with","or","for","at","by","from","out","as","is"}


def titlecase(t):
    ws = t.lower().split()
    return " ".join(w.capitalize() if i == 0 or w not in SMALL else w
                    for i, w in enumerate(ws))


def parse(lines, divisions, unit_mode):
    """divisions: list of (compiled regex, title or None -> use matched text)
    unit_mode: 'standalone' (number alone on a line) or 'inline' ('12. text')"""
    div_res = [(re.compile(p), t) for p, t in divisions]
    out, cur = [], None
    unit = None          # {'num': int|None, 'paras': [str]}
    block = []
    skipping_footnote = False
    auto = 0

    def close_unit():
        nonlocal unit
        if cur is not None and unit is not None and unit["paras"]:
            cur["units"].append(unit)
        unit = None

    def close_block():
        nonlocal block
        if not block:
            return
        raw, block = block, []
        if cur is None or unit is None or skipping_footnote:
            return
        verse = sum(1 for l in raw if l.startswith("    ")) >= max(1, len(raw) // 2)
        if verse:
            para = "\n".join(l.rstrip() for l in raw)
        else:
            para = re.sub(r"\s+", " ", " ".join(l.strip() for l in raw)).strip()
            para = re.sub(r"\s*\[\d{1,2}\]", "", para)      # inline footnote refs
        if para:
            unit["paras"].append(para)

    for line in lines:
        s = line.strip()

        if not s:
            close_block()
            continue

        # -- new division?
        hit = next(((rx, t) for rx, t in div_res if rx.match(line.rstrip())), None)
        if hit:
            close_block(); close_unit()
            skipping_footnote = False
            auto = 0
            title = hit[1] if hit[1] else titlecase(s)
            cur = {"title": title, "units": []}
            out.append(cur)
            continue

        # -- footnote / illustration blocks: skip until next division
        if FOOT_NUM.match(s) or FOOT_BRACKET.match(s) or ILLUSTRATION.match(s):
            close_block(); close_unit()
            skipping_footnote = True
            continue
        if skipping_footnote:
            continue

        if SIGNATURE.match(s):
            close_block(); close_unit()
            continue

        # -- new unit?  (both layouts occur: "12" alone, and "12. text" / "12.--text")
        if cur is not None:
            m = re.match(r"^(\d{1,3})([A-Z]?)\.?$", s)
            if m:
                close_block(); close_unit()
                unit = {"num": int(m.group(1)), "sfx": m.group(2), "paras": []}
                continue
            m = re.match(r"^(\d{1,3})([A-Z]?)\.(?:\s+|--|\u2014)(.*)$", s)
            if m and not block:
                close_block(); close_unit()
                unit = {"num": int(m.group(1)), "sfx": m.group(2), "paras": []}
                block.append(m.group(3))
                continue

        if cur is not None and unit is None:       # unnumbered text (prefaces)
            auto += 1
            unit = {"num": None, "sfx": "", "paras": []}
        block.append(line)

    close_block(); close_unit()
    return [d for d in out if d["units"]]


# ------------------------------------------------------------------- emitters
def emit(key, meta, divisions):
    head = [
        meta["title"].upper(),
        meta.get("subtitle", ""),
        f"Friedrich Nietzsche, {meta['year']} - translated by {meta['translator']}",
        f"Source: Project Gutenberg eBook #{meta['pg_id']} - public domain",
        "",
        "Nietzsche's own text only. " + meta["removed"],
        "",
        "Citation format:  <division>:<section>   section = Nietzsche's own numbering",
        "Division 0 = Preface.  Unnumbered passages get sequential numbers.",
        "",
    ]
    head = [h for h in head if h is not None]
    body, records = list(head), []
    for di, d in enumerate(divisions):
        body += ["", "", f"Division {di}. {d['title']}", ""]
        seq = 0
        for u in d["units"]:
            seq += 1
            num = u["num"] if u["num"] is not None else seq
            ref = f"{di}:{num}{u.get('sfx','')}"
            text = "\n".join(u["paras"])
            first, *rest = text.split("\n")
            body.append(f"{ref} {first}")
            body += rest
            body.append("")
            records.append({
                "ref": ref, "work": meta["title"], "work_key": key,
                "year": meta["year"], "translator": meta["translator"],
                "pg_id": meta["pg_id"], "division": di,
                "division_title": d["title"],
                "section": u["num"], "section_suffix": u.get("sfx", ""),
                "numbered": u["num"] is not None,
                "text": text,
            })
    (OUT / f"{key}.txt").write_text("\n".join(body).rstrip() + "\n", encoding="utf-8")
    with (OUT / f"{key}.jsonl").open("w", encoding="utf-8") as fh:
        for r in records:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    words = sum(len(r["text"].split()) for r in records)
    print(f"  {key:26s} divisions {len(divisions):>3}  units {len(records):>5}  words {words:>7,}")
    return records


def dump_excluded(name, lines, why):
    (EXC / name).write_text(
        f"EXCLUDED FROM THE PERSONA CORPUS\n{why}\n\n" + "\n".join(lines).strip() + "\n",
        encoding="utf-8")


# =========================================================== 1. Beyond Good and Evil
L = pg_body(load("pg4363_bge.txt"))
a = idx(L, r"^PREFACE$")
dump_excluded("bge_transcriber_and_toc.txt", L[:a],
              "Transcriber's note and table of contents (Project Gutenberg #4363).")
bge = parse(L[a:], [
    (r"^PREFACE$", "Preface"),
    (r"^CHAPTER [IVX]+\. (.+)$", None),
    (r"^FROM THE HEIGHTS$", "From the Heights (Aftersong)"),
], unit_mode="inline")
for d in bge:
    t = re.sub(r"^Chapter [IVXivx]+\.\s*", "", d["title"])
    d["title"] = t[:1].upper() + t[1:]
r1 = emit("beyond_good_and_evil", dict(
    title="Beyond Good and Evil", subtitle="Prelude to a Philosophy of the Future",
    year=1886, translator="Helen Zimmern", pg_id=4363,
    removed="Transcriber's note and table of contents removed."), bge)

# =========================================================== 2. Genealogy of Morals
L = pg_body(load("pg52319_gm.txt"))
a = idx(L, r"^PREFACE\.$")
b = idx(L, r"^PEOPLES AND COUNTRIES\. Translated", a)
dump_excluded("gm_editor_note_and_toc.txt", L[:a],
              "Oscar Levy's editor's note, title page and contents (Project Gutenberg #52319).")
dump_excluded("gm_peoples_and_countries_nachlass.txt", L[b:],
              "'Peoples and Countries' - 27 posthumous notebook fragments (Nachlass),\n"
              "translated by J. M. Kennedy. Nietzsche's own words but never published\n"
              "by him; excluded on the same grounds as The Will to Power.")
gm = parse(L[a:b], [
    (r"^PREFACE\.$", "Preface"),
    (r"^FIRST ESSAY\..*$", 'First Essay: "Good and Evil", "Good and Bad"'),
    (r"^SECOND ESSAY\..*$", 'Second Essay: "Guilt", "Bad Conscience" and the Like'),
    (r"^THIRD ESSAY\.?$", "Third Essay: What Do Ascetic Ideals Mean?"),
], unit_mode="standalone")
r2 = emit("genealogy_of_morals", dict(
    title="The Genealogy of Morals", subtitle="A Polemic",
    year=1887, translator="Horace B. Samuel", pg_id=52319,
    removed="Editor's note, contents, translator's footnotes and the posthumous\n"
            "'Peoples and Countries' fragments removed."), gm)

# ================================================ 3. Twilight of the Idols + Antichrist
L = pg_body(load("pg52263_ti_ac.txt"))
lud_end = idx(L, r"^ANTHONY M\. LUDOVICI\.$")
ti_a = idx(L, r"^PREFACE$", lud_end)
ac_a = idx(L, r"^THE ANTICHRIST$", ti_a)
er_a = idx(L, r"^THE ETERNAL RECURRENCE$", ac_a)
ti_end = idx(L, r"^THE END\.$", ti_a)

dump_excluded("ti_ludovici_translator_preface.txt", L[:lud_end + 1],
              "Anthony M. Ludovici's translator's preface (Project Gutenberg #52263).")
dump_excluded("ti_hammer_speaketh_duplicate.txt", L[ti_end:ac_a],
              "'The Hammer Speaketh' - Nietzsche quoting his own Zarathustra III.29.\n"
              "Removed as a verbatim duplicate of text already in zarathustra.txt.")
dump_excluded("ac_eternal_recurrence_nachlass.txt", L[er_a:],
              "'The Eternal Recurrence' and 'Explanatory Notes to Thus Spake Zarathustra'\n"
              "- posthumous notebook material with Ludovici's translator's preface.\n"
              "Excluded on the same grounds as The Will to Power.")

ti = parse(L[ti_a:ti_end], [
    (r"^PREFACE$", "Preface"),
    (r"^MAXIMS AND MISSILES$", "Maxims and Missiles"),
    (r"^THE PROBLEM OF SOCRATES$", "The Problem of Socrates"),
    (r'^"REASON" IN PHILOSOPHY$', '"Reason" in Philosophy'),
    (r'^HOW THE "TRUE WORLD" ULTIMATELY BECAME A FABLE$',
     'How the "True World" Ultimately Became a Fable'),
    (r"^THE HISTORY OF AN ERROR$", "The History of an Error"),
    (r"^MORALITY AS THE ENEMY OF NATURE$", "Morality as the Enemy of Nature"),
    (r"^THE FOUR GREAT ERRORS$", "The Four Great Errors"),
    (r'^THE "IMPROVERS" OF MANKIND$', 'The "Improvers" of Mankind'),
    (r"^THINGS THE GERMANS LACK$", "Things the Germans Lack"),
    (r"^SKIRMISHES IN A WAR WITH THE AGE$", "Skirmishes in a War with the Age"),
    (r"^THINGS I OWE TO THE ANCIENTS$", "Things I Owe to the Ancients"),
], unit_mode="standalone")
r3 = emit("twilight_of_the_idols", dict(
    title="The Twilight of the Idols",
    subtitle="or, How to Philosophize with the Hammer",
    year=1889, translator="Anthony M. Ludovici", pg_id=52263,
    removed="Translator's preface, translator's footnotes and 'The Hammer Speaketh'\n"
            "(a verbatim Zarathustra quotation) removed."), ti)

ac_lines = list(L[ac_a:er_a])
_p = idx(ac_lines, r"^PREFACE$")
_b = next(i for i in range(_p, len(ac_lines)) if ac_lines[i].rstrip() == "1")
ac_lines.insert(_b, "THE ANTICHRIST BODY")      # synthetic division break
ac = parse(ac_lines, [
    (r"^PREFACE$", "Preface"),
    (r"^THE ANTICHRIST BODY$", "The Antichrist"),
    (r"^THE ANTICHRIST$", "__title__"),
], unit_mode="standalone")
ac = [d for d in ac if d["title"] != "__title__"]
r4 = emit("the_antichrist", dict(
    title="The Antichrist", subtitle="A Curse on Christianity",
    year=1895, translator="Anthony M. Ludovici", pg_id=52263,
    removed="Translator's preface, translator's footnotes and the posthumous\n"
            "'Eternal Recurrence' notes removed."), ac)

# =========================================================== 4. Ecce Homo
L = pg_body(load("pg52190_eh.txt"))
ti_intro = idx(L, r"^TRANSLATOR'S INTRODUCTION$", 40)
pref = idx(L, r"^PREFACE$", ti_intro)
poetry = idx(L, r"^EDITORIAL NOTE TO POETRY$", pref)
dump_excluded("eh_ludovici_translator_introduction.txt", L[:pref],
              "Title page, contents and Anthony M. Ludovici's translator's introduction\n"
              "(Project Gutenberg #52190).")
dump_excluded("eh_poetry_appendix.txt", L[poetry:],
              "Oscar Levy's editorial note and the poetry appendix he assembled from\n"
              "Nietzsche's notebooks. Excluded because it is editor-curated Nachlass;\n"
              "'Hymn to Life' is explicitly credited in the source as WORDS BY LOU SALOME.")
eh = parse(L[pref:poetry], [
    (r"^PREFACE$", "Preface"),
    (r"^WHY I AM SO WISE$", "Why I Am So Wise"),
    (r"^WHY I AM SO CLEVER$", "Why I Am So Clever"),
    (r"^WHY I WRITE SUCH EXCELLENT BOOKS$", "Why I Write Such Excellent Books"),
    (r'^"THE BIRTH O[fF] TRAGEDY"$', "On The Birth of Tragedy"),
    (r'^"THOUGHTS OUT OF SEASON"$', "On Thoughts Out of Season"),
    (r'^"HUMAN, ALL-TOO-HUMAN"$', "On Human, All-Too-Human"),
    (r'^"THE DAWN OF DAY:?$', "On The Dawn of Day"),
    (r'^"JOYFUL WISDOM.*$', "On Joyful Wisdom"),
    (r'^"THUS SPAKE ZARATHUSTRA.*$', "On Thus Spake Zarathustra"),
    (r"^BEYOND GOOD AND EVIL:?$", "On Beyond Good and Evil"),
    (r'^"THE GENEALOGY OF MORALS.*$', "On The Genealogy of Morals"),
    (r'^"THE TWILIGHT OF THE IDOLS:?$', "On The Twilight of the Idols"),
    (r'^"THE CASE OF WAGNER.*$', "On The Case of Wagner"),
    (r"^WHY I AM A FATALITY$", "Why I Am a Fatality"),
], unit_mode="standalone")
r5 = emit("ecce_homo", dict(
    title="Ecce Homo", subtitle="How One Becomes What One Is",
    year=1908, translator="Anthony M. Ludovici / Paul V. Cohn", pg_id=52190,
    removed="Translator's introduction, translator's footnotes, the editor's note\n"
            "and the editor-assembled poetry appendix removed."), eh)

# ----------------------------------------------------------------------- totals
allr = r1 + r2 + r3 + r4 + r5
print(f"\n  TOTAL (4 new books): {len(allr):,} units, "
      f"{sum(len(r['text'].split()) for r in allr):,} words")
