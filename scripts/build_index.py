#!/usr/bin/env python3
"""
코퍼스 JSONL -> 청킹 -> BGE-M3 임베딩 -> 페르소나별 FAISS 인덱스

청킹 원칙 (CLAUDE.md 3.6):
  1. 아포리즘·절의 경계를 자르지 않는다. 고정 길이 분할 금지.
  2. 짧은 단위는 같은 구분(division) 안에서 연속으로 묶는다.
     차라투스트라·마태복음은 단위 중앙값이 30토큰 안팎이라 그대로는 문맥이 없다.
  3. 목표 크기를 넘는 단위만 문장 경계에서 분할한다.
     도덕의 계보는 한 절이 2,000토큰을 넘기도 한다.
  4. 서로 다른 구분·작품·페르소나를 한 청크에 섞지 않는다.

페르소나별로 인덱스를 분리한다. 니체 질문에 마태복음이 섞여 나오는 것을 막기 위해서다.

출력: backend/data/index/<persona>/{index.faiss, chunks.jsonl, meta.json}
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "backend" / "data" / "corpus"
INDEX = ROOT / "backend" / "data" / "index"

# .env 가 있으면 읽는다
try:
    from dotenv import load_dotenv
    load_dotenv(ROOT / "backend" / ".env")
except ImportError:
    pass

MODEL_NAME = os.getenv("EMBEDDING_MODEL", "BAAI/bge-m3")
DEVICE = os.getenv("EMBEDDING_DEVICE", "cuda")
TARGET = int(os.getenv("CHUNK_TARGET_TOKENS", 512))   # 묶을 때의 목표 크기
MAXTOK = int(os.getenv("CHUNK_MAX_TOKENS", 640))      # 이보다 긴 단위는 분할한다
OVERLAP = int(os.getenv("CHUNK_OVERLAP_TOKENS", 96))  # 분할 시에만 적용

SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z\"'(])")


def sentences(text):
    """문장 단위로 쪼갠다. 니체는 '--' 를 많이 쓰므로 그것도 경계 후보로 둔다."""
    parts = [s for s in SENT_SPLIT.split(text) if s.strip()]
    out = []
    for p in parts:
        if len(p.split()) > 120:                     # 한 문장이 지나치게 길면
            out += [q for q in re.split(r"(?<=--)\s*", p) if q.strip()]
        else:
            out.append(p)
    return out or [text]


def chunk_units(units, ntok):
    """같은 (work, division) 묶음 안에서만 호출된다."""
    chunks, buf, buf_tok = [], [], 0

    def flush():
        nonlocal buf, buf_tok
        if buf:
            chunks.append(list(buf))
            buf, buf_tok = [], 0

    for u in units:
        t = ntok(u["text"])
        if t > MAXTOK:
            # 긴 단위는 혼자 문장 경계에서 쪼갠다
            flush()
            sents, cur, cur_tok = sentences(u["text"]), [], 0
            pieces = []
            for s in sents:
                st = ntok(s)
                if cur and cur_tok + st > TARGET:
                    pieces.append(" ".join(cur))
                    # 오버랩: 뒤쪽 문장 몇 개를 다음 조각 앞에 남긴다
                    back, back_tok = [], 0
                    for prev in reversed(cur):
                        pt = ntok(prev)
                        if back_tok + pt > OVERLAP:
                            break
                        back.insert(0, prev)
                        back_tok += pt
                    cur, cur_tok = list(back), back_tok
                cur.append(s)
                cur_tok += st
            if cur:
                pieces.append(" ".join(cur))
            for i, piece in enumerate(pieces):
                chunks.append([dict(u, text=piece, _part=i + 1, _parts=len(pieces))])
            continue

        if buf_tok + t > TARGET:
            flush()
        buf.append(u)
        buf_tok += t
    flush()
    return chunks


def main():
    from sentence_transformers import SentenceTransformer
    import numpy as np
    import faiss

    files = sorted(CORPUS.glob("*_units.jsonl"))
    if not files:
        raise SystemExit(f"[중단] {CORPUS} 에 *_units.jsonl 이 없습니다. build_jsonl.py 를 먼저 실행하세요.")

    print(f"모델 로딩: {MODEL_NAME} (device={DEVICE})")
    model = SentenceTransformer(MODEL_NAME, device=DEVICE)
    tok = model.tokenizer

    def ntok(text):
        return len(tok.encode(text, add_special_tokens=False))

    # 페르소나 -> (work, division) -> 단위 목록
    by_persona = {}
    for f in files:
        for line in f.open(encoding="utf-8"):
            r = json.loads(line)
            key = (r["work"], r["division"])
            by_persona.setdefault(r["persona"], {}).setdefault(key, []).append(r)

    for persona, groups in by_persona.items():
        all_chunks = []
        for (work, division), units in groups.items():
            units.sort(key=lambda r: r["seq"])
            for group in chunk_units(units, ntok):
                first, last = group[0], group[-1]
                text = "\n\n".join(u["text"] for u in group)
                all_chunks.append({
                    "chunk_id": f"{persona}#{len(all_chunks) + 1}",
                    "persona": persona,
                    "work": work,
                    "author": first["author"],
                    "translator": first["translator"],
                    "division": division,
                    "division_title": first["division_title"],
                    "ref_start": first["ref"],
                    "ref_end": last["ref"],
                    "uids": [u["uid"] for u in group],
                    "n_units": len(group),
                    "part": first.get("_part"),
                    "parts": first.get("_parts"),
                    "tokens": ntok(text),
                    "text": text,
                })

        toks = [c["tokens"] for c in all_chunks]
        print(f"\n[{persona}] 청크 {len(all_chunks)}개  "
              f"토큰 중앙값 {sorted(toks)[len(toks)//2]}  최대 {max(toks)}  합계 {sum(toks):,}")

        print(f"[{persona}] 임베딩 중...")
        vecs = model.encode([c["text"] for c in all_chunks],
                            batch_size=8, show_progress_bar=True,
                            normalize_embeddings=True)
        vecs = np.asarray(vecs, dtype="float32")

        # 정규화했으므로 내적 = 코사인 유사도.
        # 수천 개 규모라 근사 인덱스가 필요 없다. Flat 이 정확하고 충분히 빠르다.
        idx = faiss.IndexFlatIP(vecs.shape[1])
        idx.add(vecs)

        out = INDEX / persona
        out.mkdir(parents=True, exist_ok=True)
        faiss.write_index(idx, str(out / "index.faiss"))
        with (out / "chunks.jsonl").open("w", encoding="utf-8") as fh:
            for c in all_chunks:
                fh.write(json.dumps(c, ensure_ascii=False) + "\n")
        (out / "meta.json").write_text(json.dumps({
            "persona": persona,
            "model": MODEL_NAME,
            "dim": int(vecs.shape[1]),
            "chunks": len(all_chunks),
            "tokens": int(sum(toks)),
            "chunk_target": TARGET,
            "chunk_max": MAXTOK,
            "chunk_overlap": OVERLAP,
            "works": sorted({c["work"] for c in all_chunks}),
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[{persona}] 저장 완료 -> {out}")


if __name__ == "__main__":
    sys.exit(main())
