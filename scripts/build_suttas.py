#!/usr/bin/env python3
"""SuttaCentral bilara-data (Bhikkhu Sujato 영역, CC0) -> 부처 코퍼스 .txt (규모 A, CLAUDE.md 3.3).

출처: https://github.com/suttacentral/bilara-data  (translation/en/sujato/sutta/…)
라이선스: CC0 1.0 — 저작권 완전 포기. Gutenberg 와 달리 raw.githubusercontent.com 은 셸에서 바로 받힌다.

수록 (경장만. 논장·율장·주석서·본생담·대승경전·Carus 편집물은 제외 — 니체 기준의 부처 판):
  소부 핵심 4종  법구경(Dhp) / 숫타니파타(Snp) / 우다나(Ud) / 여시어경(Iti)
  핵심 설법 4편  초전법륜경(SN 56.11) / 염처경(MN 10) / 깔라마경(AN 3.65) / 대반열반경(DN 16)
  (자애경 Snp 1.8 은 숫타니파타에 포함)

세그먼트 키 -> 프로젝트 단위 매핑:
  dhp{절}:{행}          -> Division = 장(파일 순), 절 = 게송 번호, 행을 이어 붙임
  snp1.8:{게송}.{행}    -> PART = 품(vagga), Division = 경 일련번호(제목에 "1.8 …"), 절 = 게송
  mn10:{문단}.{문장}    -> Division 1, 절 = 문단
  dn16:{장}.{문단}.{문장} -> Division = 장, 절 = 문단
  *:0.x 는 제목(구분 제목으로 씀), *.0 은 소제목(본문에서 제외)

사용법:  python scripts/build_suttas.py
이어서:  python scripts/build_jsonl.py backend/data/corpus/{dhammapada,sutta_nipata,udana,itivuttaka,
         satipatthana,dhammacakkappavattana,kalama,mahaparinibbana}.txt
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

CORPUS = Path(__file__).resolve().parent.parent / "backend" / "data" / "corpus"
RAW = "https://raw.githubusercontent.com/suttacentral/bilara-data/published/translation/en/sujato/sutta"
API = "https://api.github.com/repos/suttacentral/bilara-data/contents/translation/en/sujato/sutta"

TAG = re.compile(r"<[^>]+>")
SPACES = re.compile(r"\s+")


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode("utf-8")


CACHE = Path(__file__).resolve().parent / ".cache" / "bilara_sujato_tree.json"
_tree: list[str] | None = None


def tree() -> list[str]:
    """translation/en/sujato/sutta 아래 전체 경로 목록. API 를 3~4회만 쓰고 파일로 캐시한다.
    무인증 GitHub API 는 시간당 60회라 디렉터리마다 조회하면 금방 바닥난다 (2026-09-19 실측)."""
    global _tree
    if _tree is not None:
        return _tree
    if CACHE.exists():
        _tree = json.loads(CACHE.read_text(encoding="utf-8"))
        return _tree
    # 1) 루트 트리에서 translation/en/sujato/sutta 의 sha 를 찾아간다 (3회)
    sha = "published"
    for name in ("translation", "en", "sujato", "sutta"):
        t = json.loads(fetch(f"https://api.github.com/repos/suttacentral/bilara-data/git/trees/{sha}"))
        sha = next(e["sha"] for e in t["tree"] if e["path"] == name)
    # 2) 그 하위 트리를 재귀로 한 번에 (1회)
    t = json.loads(fetch(f"https://api.github.com/repos/suttacentral/bilara-data/git/trees/{sha}?recursive=1"))
    if t.get("truncated"):
        raise SystemExit("[중단] 트리가 잘렸다. 하위 디렉터리별로 나눠 받아야 한다.")
    _tree = [e["path"] for e in t["tree"] if e["type"] == "blob"]
    CACHE.parent.mkdir(exist_ok=True)
    CACHE.write_text(json.dumps(_tree), encoding="utf-8")
    return _tree


def listing(path: str) -> list[str]:
    """디렉터리 바로 아래 파일 이름 목록 (캐시된 트리에서)."""
    prefix = path.rstrip("/") + "/"
    return sorted({p[len(prefix):] for p in tree() if p.startswith(prefix) and "/" not in p[len(prefix):]})


def subdirs(path: str) -> list[str]:
    prefix = path.rstrip("/") + "/"
    return sorted({p[len(prefix):].split("/")[0] for p in tree() if p.startswith(prefix) and "/" in p[len(prefix):]})


def clean(t: str) -> str:
    t = TAG.sub("", t)
    t = (t.replace("’", "'").replace("‘", "'")
          .replace("“", '"').replace("”", '"')
          .replace(" ", " ").replace("—", "—"))
    return SPACES.sub(" ", t).strip()


def load_segments(rel: str) -> dict[str, str]:
    """{키: 문장}. 키의 uid 접두("dn16:")는 떼고 "1.6.1" 같은 좌표만 남긴다."""
    data = json.loads(fetch(f"{RAW}/{rel}"))
    out = {}
    for k, v in data.items():
        out[k.split(":", 1)[1]] = v
    return out


def sutta_title(seg: dict) -> str:
    """경 제목 = 0.x 중 마지막 것. 0.1 은 모음집 이름이고 그 사이는 모음집마다 다르다
    (ud/snp/mn/dn 은 0.2 가 제목, an/sn 은 0.2 가 품 이름·0.3 이 제목, iti 는 0.4 가 제목, dhp 는 0.3 이 장 제목)."""
    vals = [clean(seg[k]) for k in sorted((k for k in seg if k.startswith("0.")), key=lambda k: int(k.split(".")[1]))]
    vals = [v for v in vals if v]                       # dhp 는 0.4 가 빈 문자열
    return re.sub(r"^\d+\.\s*", "", vals[-1]) if vals else ""     # "1. Pairs" -> "Pairs"


def _num(part: str) -> int:
    """문단 번호. mn10 은 반복 생략 구간을 "18-23" 처럼 범위로 적는다 -> 시작 번호를 쓴다."""
    return int(part.split("-")[0])


def group_units(seg: dict, levels: int) -> dict[tuple, list[str]]:
    """좌표를 (division, section) 으로 묶는다. levels=2: a.b -> (None, a) / levels=3: a.b.c -> (a, b)"""
    units: dict[tuple, list[str]] = {}
    for key, text in seg.items():
        parts = key.split(".")
        if parts[0] == "0":
            continue                                    # 제목 줄
        if levels == 3:
            if len(parts) != 3 or parts[2] == "0":
                continue                                # 소제목
            k = (_num(parts[0]), _num(parts[1]))
        else:
            if len(parts) != 2 or parts[1] == "0":
                continue
            k = (None, _num(parts[0]))
        t = clean(text)
        if t:
            units.setdefault(k, []).append(t)
    return units


def emit(path: Path, header: list[str], blocks: list[str]):
    body = "\n".join(header) + "\n\n" + "\n".join(blocks).rstrip() + "\n"
    # newline="\n" 필수 — 기존 코퍼스는 전부 LF (build_gospels.py 참조)
    path.write_text(body, encoding="utf-8", newline="\n")


def header(title: str, subtitle: str, cite: str) -> list[str]:
    return [title, subtitle,
            "Gotama Buddha, 2021 - translated by Bhikkhu Sujato",
            "Source: SuttaCentral bilara-data (CC0 1.0) https://github.com/suttacentral/bilara-data",
            "",
            "Sutta Pitaka only. Section headings and translator's apparatus removed.",
            f"Citation format:  {cite}"]


# ── 1) 법구경: 26장, 파일 = 장 ──────────────────────────────────────
def build_dhammapada():
    files = listing("kn/dhp")
    files.sort(key=lambda n: int(re.match(r"dhp(\d+)", n).group(1)))
    blocks, n_units, n_words = [], 0, 0
    for ch, fname in enumerate(files, 1):
        seg = load_segments(f"kn/dhp/{fname}")
        ch_title = sutta_title(seg)
        ch_title = re.sub(r"^\d+\.\s*", "", ch_title)     # "1. Pairs" -> "Pairs"
        blocks.append(f"Chapter {ch}. {ch_title}")
        blocks.append("")
        # 키가 "dhp{절}:{행}" 이라 split 후 좌표는 "{행}" 만 남는다 -> uid 에서 절을 꺼내야 한다
        data = json.loads(fetch(f"{RAW}/kn/dhp/{fname}"))
        verses: dict[int, list[str]] = {}
        for k, v in data.items():
            uid, coord = k.split(":", 1)
            verse = int(uid[3:])
            if coord.startswith("0"):
                continue
            t = clean(v)
            if t:
                verses.setdefault(verse, []).append(t)
        for verse in sorted(verses):
            text = " ".join(verses[verse])
            blocks.append(f"{ch}:{verse} {text}")
            n_units += 1; n_words += len(text.split())
        blocks.append("")
    emit(CORPUS / "dhammapada.txt",
         header("THE DHAMMAPADA", "Sayings of the Dhamma (Khuddaka Nikaya)", "<chapter>:<verse>"), blocks)
    print(f"  dhammapada        장 {len(files):>3}  단위 {n_units:>5}  단어 {n_words:>7,}")


# ── 2) 품(vagga) 아래 경들이 있는 모음집: 숫타니파타·우다나·여시어경 ─────
def build_vagga_collection(key: str, out: str, title: str, subtitle: str, levels: int = 2):
    vaggas = sorted(subdirs(f"kn/{key}"), key=lambda n: int(re.search(r"\d+", n).group()))
    blocks, n_units, n_words, div = [], 0, 0, 0
    for pi, vg in enumerate(vaggas, 1):
        blocks.append(f"PART {pi}")
        blocks.append("")
        files = listing(f"kn/{key}/{vg}")
        # snp1.8 / ud1.1 은 "품.경", iti1 은 단일 번호 — 숫자를 전부 뽑아 정렬
        files.sort(key=lambda n: [int(x) for x in re.findall(r"\d+", n.split("_")[0])])
        for fname in files:
            seg = load_segments(f"kn/{key}/{vg}/{fname}")
            num = re.sub(r"^[a-z]+", "", fname.split("_")[0])       # "snp1.8" -> "1.8", "iti1" -> "1"
            t2 = sutta_title(seg)
            div += 1
            blocks.append(f"Division {div}. {num} {t2}".rstrip())
            blocks.append("")
            for (_, sec), lines in sorted(group_units(seg, levels).items(), key=lambda kv: kv[0][1]):
                text = " ".join(lines)
                blocks.append(f"{div}:{sec} {text}")
                n_units += 1; n_words += len(text.split())
            blocks.append("")
    emit(CORPUS / f"{out}.txt", header(title, subtitle, "<discourse>:<verse>"), blocks)
    print(f"  {out:<17} 품 {len(vaggas):>3}  경 {div:>3}  단위 {n_units:>5}  단어 {n_words:>7,}")


# ── 3) 단일 경: 문단 = 절. dn16 은 장이 있어 3단계 ─────────────────────
def build_single(rel: str, out: str, title: str, subtitle: str, levels: int):
    seg = load_segments(rel)
    t2 = sutta_title(seg)
    units = group_units(seg, levels)
    blocks, n_units, n_words = [], 0, 0
    if levels == 3:
        chapters = sorted({d for d, _ in units})
        for ch in chapters:
            blocks.append(f"Division {ch}. Chapter {ch}")
            blocks.append("")
            for (d, sec), lines in sorted((kv for kv in units.items() if kv[0][0] == ch), key=lambda kv: kv[0][1]):
                text = " ".join(lines)
                blocks.append(f"{d}:{sec} {text}")
                n_units += 1; n_words += len(text.split())
            blocks.append("")
    else:
        blocks.append(f"Division 1. {t2}")
        blocks.append("")
        for (_, sec), lines in sorted(units.items(), key=lambda kv: kv[0][1]):
            text = " ".join(lines)
            blocks.append(f"1:{sec} {text}")
            n_units += 1; n_words += len(text.split())
    emit(CORPUS / f"{out}.txt", header(title, subtitle, "<chapter>:<paragraph>"), blocks)
    print(f"  {out:<17} 구분 {len({d for d,_ in units}) if levels==3 else 1:>3}  단위 {n_units:>5}  단어 {n_words:>7,}")


def main():
    CORPUS.mkdir(parents=True, exist_ok=True)
    print("SuttaCentral -> corpus")
    build_dhammapada()
    build_vagga_collection("snp", "sutta_nipata", "THE SUTTA NIPATA", "Anthology of Discourses (Khuddaka Nikaya)")
    build_vagga_collection("ud", "udana", "THE UDANA", "Heartfelt Sayings (Khuddaka Nikaya)")
    build_vagga_collection("iti", "itivuttaka", "THE ITIVUTTAKA", "So It Was Said (Khuddaka Nikaya)")
    build_single("sn/sn56/sn56.11_translation-en-sujato.json", "dhammacakkappavattana",
                 "THE DHAMMACAKKAPPAVATTANA SUTTA", "Rolling Forth the Wheel of Dhamma (Samyutta Nikaya 56.11)", 2)
    build_single("mn/mn10_translation-en-sujato.json", "satipatthana",
                 "THE SATIPATTHANA SUTTA", "Mindfulness Meditation (Majjhima Nikaya 10)", 2)
    build_single("an/an3/an3.65_translation-en-sujato.json", "kalama",
                 "THE KALAMA SUTTA", "With the Kalamas of Kesamutta (Anguttara Nikaya 3.65)", 2)
    build_single("dn/dn16_translation-en-sujato.json", "mahaparinibbana",
                 "THE MAHAPARINIBBANA SUTTA", "The Great Discourse on the Buddha's Extinguishment (Digha Nikaya 16)", 3)
    print("\n이어서: python scripts/build_jsonl.py backend/data/corpus/{dhammapada,sutta_nipata,udana,"
          "itivuttaka,dhammacakkappavattana,satipatthana,kalama,mahaparinibbana}.txt")


if __name__ == "__main__":
    main()
