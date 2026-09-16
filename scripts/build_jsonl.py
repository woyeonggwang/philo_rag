#!/usr/bin/env python3
"""
코퍼스 .txt -> .jsonl 메타데이터 생성

완성된 .txt 를 역파싱한다. 원본 Gutenberg 파일이 없어도 동작한다.
.txt 안에 필요한 정보가 전부 들어 있기 때문이다.

  머리말                  -> work / subtitle / author / year / translator / pg_id
  "Division N. 제목"      -> division / division_title
  "Chapter N"             -> division (마태복음 형식)
  "<구분>:<절> 본문"      -> ref / section / section_suffix / text
  "[SS n]"                -> author_section (차라투스트라의 저자 구분 표시)

'uid' 가 진짜 고유 키다 ("<파일명>#<파일 내 순번>").
'ref' 는 .txt 에 적힌 그대로 두므로 드물게 중복될 수 있다. 원본 .txt 의 결함이며
고치지 않고 'anomaly' 필드로 표시만 한다 (.txt 와 .jsonl 의 1:1 대응을 깨지 않기 위해).

'numbered' 는 절 번호가 저자 본인의 번호인지를 뜻한다.
각 .txt 머리말의 "Division 0 = Preface. Unnumbered passages get sequential numbers."
규칙에 따라 Division 0 만 False 로 둔다. 그 외에는 저자의 번호다.

사용:
    python scripts/build_jsonl.py                 # backend/data/corpus 전체
    python scripts/build_jsonl.py <파일.txt> ...  # 지정한 파일만
"""
import json
import re
import sys
from pathlib import Path

CORPUS = Path(__file__).resolve().parent.parent / "backend" / "data" / "corpus"

PERSONA = {
    "zarathustra": "nietzsche",
    "beyond_good_and_evil": "nietzsche",
    "genealogy_of_morals": "nietzsche",
    "twilight_of_the_idols": "nietzsche",
    "the_antichrist": "nietzsche",
    "ecce_homo": "nietzsche",
    "mathe": "jesus",
}

DIVISION_RE = re.compile(r"^Division (\d+)\.\s*(.*)$")
CHAPTER_RE = re.compile(r"^Chapter (\d+)\.?\s*(.*)$")
UNIT_RE = re.compile(r"^(\d+):(\d+)([A-Za-z]?)\s+(.*)$")
SS_RE = re.compile(r"^\[SS (\d+)\]$")
PART_RE = re.compile(r"^PART (\d+)$")

# 머리말에서 뽑아낼 것들
YEAR_TRANS_RE = re.compile(
    r"^(?P<author>.+?),?\s*(?:\((?P<life>[\d\-]+)\))?,?\s*"
    r"(?P<year>\d{4})\s*-\s*translated by\s+(?P<translator>.+?)\s*$"
)
PG_RE = re.compile(r"Project Gutenberg eBook #(\d+)")


def parse_header(lines):
    """본문 시작 전까지를 읽어 서지 정보를 뽑는다."""
    meta = {"work": None, "author": None, "year": None,
            "translator": None, "pg_id": None}
    if lines:
        meta["work"] = lines[0].strip()
    for line in lines:
        m = YEAR_TRANS_RE.match(line.strip())
        if m and meta["year"] is None:
            meta["author"] = m.group("author").strip().rstrip(",")
            meta["year"] = int(m.group("year"))
            meta["translator"] = m.group("translator").strip()
        m = PG_RE.search(line)
        if m and meta["pg_id"] is None:
            meta["pg_id"] = int(m.group(1))
    return meta


def parse_file(path: Path):
    raw = path.read_text(encoding="utf-8")
    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")

    # 첫 구분(Division/Chapter) 제목이 나오는 지점까지가 머리말.
    # 머리말에도 "Division 0 = Preface" 같은 설명문이 있으므로
    # 정규식이 끝까지 맞아떨어지는 줄(제목 형식)만 본문 시작으로 인정한다.
    body_start = len(lines)
    for i, line in enumerate(lines):
        if DIVISION_RE.match(line) or CHAPTER_RE.match(line):
            body_start = i
            break

    meta = parse_header(lines[:body_start])
    stem = path.stem
    persona = PERSONA.get(stem)
    if persona is None:
        raise SystemExit(f"[중단] {stem} 의 persona 가 PERSONA 표에 없습니다. 먼저 추가하세요.")

    records = []
    seen_refs = {}
    division = None
    division_title = ""
    part = None
    author_section = None
    cur = None  # 여러 줄에 걸친 단위를 모으는 중인 레코드

    def flush():
        nonlocal cur
        if cur is not None:
            # 운문은 줄바꿈과 들여쓰기를 보존하고, 산문은 한 줄로 합친다.
            # 첫 줄의 들여쓰기는 .txt 에서 "<ref> " 접두사에 먹혔으므로
            # 이어지는 줄들의 공통 들여쓰기를 첫 줄에 되돌려준다.
            tail = cur["_lines"][1:]
            is_verse = any(l.startswith("  ") for l in tail)
            if is_verse:
                indents = [len(l) - len(l.lstrip(" ")) for l in tail if l.strip()]
                pad = " " * min(indents) if indents else ""
                lines_out = [pad + cur["_lines"][0]] + tail
                body = "\n".join(lines_out).rstrip()
            else:
                body = "\n".join(cur["_lines"]).rstrip()
                body = re.sub(r"\s+", " ", body.replace("\n", " ")).strip()
            cur["text"] = body
            del cur["_lines"]
            cur["seq"] = len(records) + 1
            cur["uid"] = f"{path.stem}#{cur['seq']}"
            ref = cur["ref"]
            if ref in seen_refs:
                # 원본 .txt 결함. 두 유형이 있다.
                #   - 부제/제사가 절 번호를 받은 경우 (대문자로 시작하거나 아주 짧다)
                #   - 앞 절의 뒷부분이 다음 절 번호를 받은 경우 (소문자로 시작한다)
                prev = records[seen_refs[ref]]
                kind = ("fragment_of_previous_section"
                        if prev["text"][:1].islower() else "epigraph_or_subtitle")
                prev["anomaly"] = kind
                cur["anomaly"] = "duplicate_ref_in_source"
            else:
                seen_refs[ref] = len(records)
            cur.setdefault("anomaly", None)
            records.append(cur)
            cur = None

    for line in lines[body_start:]:
        stripped = line.strip()

        m = PART_RE.match(stripped)
        if m:
            flush()
            part = int(m.group(1))
            continue

        m = DIVISION_RE.match(line) or CHAPTER_RE.match(line)
        if m:
            flush()
            division = int(m.group(1))
            division_title = m.group(2).strip()
            author_section = None
            continue

        m = SS_RE.match(stripped)
        if m:
            flush()
            author_section = int(m.group(1))
            continue

        m = UNIT_RE.match(line)
        if m:
            flush()
            div, sec, suffix, text = m.groups()
            cur = {
                "ref": f"{div}:{sec}{suffix}",
                "persona": persona,
                "work": meta["work"],
                "author": meta["author"],
                "year": meta["year"],
                "translator": meta["translator"],
                "pg_id": meta["pg_id"],
                "part": part,
                "division": int(div),
                "division_title": division_title,
                "section": int(sec),
                "section_suffix": suffix or None,
                "author_section": author_section,
                "numbered": int(div) != 0,
                "_lines": [text],
            }
            continue

        if cur is not None:
            if stripped:
                cur["_lines"].append(line.rstrip())
            else:
                flush()

    flush()
    return records, meta


def main(argv):
    targets = ([Path(a) for a in argv]
               if argv else sorted(CORPUS.glob("*.txt")))
    if not targets:
        raise SystemExit(f"[중단] {CORPUS} 에 .txt 가 없습니다.")

    total = 0
    for path in targets:
        records, meta = parse_file(path)
        out = path.with_name(f"{path.stem}_units.jsonl")
        out.write_text(
            "\n".join(json.dumps(r, ensure_ascii=False) for r in records) + "\n",
            encoding="utf-8")
        words = sum(len(r["text"].split()) for r in records)
        dup = len(records) - len({r["ref"] for r in records})
        anomalies = [r for r in records if r.get("anomaly")]
        for r in anomalies:
            print(f"    [주의] {r['uid']} ref={r['ref']} {r['anomaly']}: "
                  f"{r['text'][:60]}...")
        total += len(records)
        print(f"{path.name:<30} 단위 {len(records):>5}  단어 {words:>7,}  "
              f"구분 {len({r['division'] for r in records}):>3}  "
              f"중복ref {dup}  uid고유 {len({r['uid'] for r in records}) == len(records)}"
              f"  -> {out.name}")
    print(f"{'합계':<30} 단위 {total:>5}")


if __name__ == "__main__":
    main(sys.argv[1:])
