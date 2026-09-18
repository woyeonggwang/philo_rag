#!/usr/bin/env python3
"""Project Gutenberg KJV 낱권 파일 -> 프로젝트 코퍼스 .txt (mathe.txt 와 같은 모양).

원본 형식:   42:001:001 Forasmuch as many have taken in hand to set forth in order
                        a declaration of ...        <- 줄바꿈되고 들여쓰기됨
출력 형식:   Chapter 1
             1:1 Forasmuch as many have taken in hand to set forth in order a declaration of ...

사용법:
    python scripts/build_gospels.py <원본_PG_파일이_있는_디렉터리>
    예) python scripts/build_gospels.py C:/Users/USER/Downloads

**JSONL 은 여기서 만들지 않는다.** `.txt` 를 만든 뒤 `scripts/build_jsonl.py` 를 돌린다.
JSONL 스키마의 단일 출처는 build_jsonl.py 이고, 여기서 따로 만들면 필드가 어긋난다
(uid / seq / anomaly 등이 빠진다. CLAUDE.md 3절·6.3 참조).

build_books.py / build_zarathustra.py 와 달리 경로를 인자로 받는다 — 그 둘은 컨테이너
경로(`/home/claude/...`)가 박혀 있어 로컬에서 그대로 돌아가지 않는다.
"""
import re
import sys
from pathlib import Path

CORPUS = Path(__file__).resolve().parent.parent / "backend" / "data" / "corpus"

VERSE = re.compile(r"^(\d{1,2}):(\d{1,3}):(\d{1,3}) (.*)$")

BOOKS = [
    dict(key="mark", file="Mark.txt", pg_id=8041,
         title="THE GOSPEL ACCORDING TO MARK", chapters=16, verses=678),
    dict(key="luke", file="Luke.txt", pg_id=8042,
         title="THE GOSPEL ACCORDING TO LUKE", chapters=24, verses=1151),
]


def build(raw_dir: Path, b: dict) -> list[dict]:
    src = raw_dir / b["file"]
    if not src.exists():
        print(f"  [건너뜀] {src} 없음")
        return []

    text = src.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    # 곡선 따옴표·비분리 공백을 ASCII 로 (CLAUDE.md 3절)
    text = (text.replace("\u2019", "'").replace("\u2018", "'")
                .replace("\u201c", '"').replace("\u201d", '"')
                .replace("\u00a0", " "))
    lines = text.split("\n")
    s = next(i for i, l in enumerate(lines) if l.startswith("*** START OF THE PROJECT GUTENBERG"))
    e = next(i for i, l in enumerate(lines) if l.startswith("*** END OF THE PROJECT GUTENBERG"))

    verses, cur = [], None
    for line in lines[s + 1:e]:
        m = VERSE.match(line)
        if m:
            if cur:
                verses.append(cur)
            cur = dict(chapter=int(m.group(2)), verse=int(m.group(3)), parts=[m.group(4).strip()])
        elif cur is not None and line.startswith("    ") and line.strip():
            cur["parts"].append(line.strip())              # 줄바꿈된 뒷부분
    if cur:
        verses.append(cur)

    for v in verses:
        v["text"] = re.sub(r"\s+", " ", " ".join(v["parts"])).strip()

    out = [b["title"], "King James Version", "", ""]
    last_ch = None
    for v in verses:
        if v["chapter"] != last_ch:
            if last_ch is not None:
                out.append("")
            last_ch = v["chapter"]
            out += [f"Chapter {last_ch}", ""]
        out.append(f"{v['chapter']}:{v['verse']} {v['text']}")
    # newline="\n" 필수. 윈도우 파이썬은 기본이 CRLF 라 기존 코퍼스(전부 LF)와 어긋난다.
    # .gitattributes 가 backend/data/** 를 -text 로 두어 바이트를 그대로 보존하므로, 한번 섞이면 그대로 남는다.
    (CORPUS / f"{b['key']}.txt").write_text("\n".join(out).rstrip() + "\n",
                                            encoding="utf-8", newline="\n")

    # 검증: 장 결번과 절 번호 연속성
    chs = sorted({v["chapter"] for v in verses})
    gaps = [c for c in range(1, b["chapters"] + 1) if c not in chs]
    bad = [c for c in chs
           if sorted(v["verse"] for v in verses if v["chapter"] == c)
           != list(range(1, sum(1 for v in verses if v["chapter"] == c) + 1))]
    words = sum(len(v["text"].split()) for v in verses)
    print(f"  {b['key']:6s} 장 {len(chs):>3}/{b['chapters']}  "
          f"절 {len(verses):>5}/{b['verses']}  단어 {words:>7,}"
          f"{'  [결번] ' + str(gaps) if gaps else ''}"
          f"{'  [절번호 불연속] ' + str(bad) if bad else ''}"
          f"  -> {b['key']}.txt")
    return verses


def main(argv):
    if not argv:
        raise SystemExit(__doc__)
    raw_dir = Path(argv[0])
    total = []
    for b in BOOKS:
        total += build(raw_dir, b)
    print(f"  {'합계':6s} 절 {len(total):>5}  단어 {sum(len(v['text'].split()) for v in total):,}")
    print("\n이어서 실행: python scripts/build_jsonl.py "
          "backend/data/corpus/mark.txt backend/data/corpus/luke.txt")


if __name__ == "__main__":
    main(sys.argv[1:])
