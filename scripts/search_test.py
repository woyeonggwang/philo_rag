#!/usr/bin/env python3
"""
인덱스 육안 검증. 대표 질문을 던져 어떤 구절이 검색되는지 눈으로 본다.
CLAUDE.md '남은 전처리 계획' 3번.

사용:
    python scripts/search_test.py                      # 기본 질문 세트
    python scripts/search_test.py nietzsche "질문"      # 직접 질의
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "backend" / "data" / "index"

try:
    from dotenv import load_dotenv
    load_dotenv(ROOT / "backend" / ".env")
except ImportError:
    pass

MODEL_NAME = os.getenv("EMBEDDING_MODEL", "BAAI/bge-m3")
DEVICE = os.getenv("EMBEDDING_DEVICE", "cuda")
TOP_K = int(os.getenv("TOP_K", 5))

DEFAULT = [
    ("nietzsche", "삶이 고통스러운데 계속 살아야 할 이유가 있습니까?"),
    ("nietzsche", "신은 죽었다는 말은 무슨 뜻입니까?"),
    ("nietzsche", "남들의 시선이 신경 쓰여 괴롭습니다"),
    ("nietzsche", "동정심은 좋은 것 아닌가요?"),
    ("jesus", "용서할 수 없는 사람을 용서해야 합니까?"),
    ("jesus", "돈 걱정으로 잠이 안 옵니다"),
]


def load(persona):
    import faiss
    d = INDEX / persona
    if not d.exists():
        raise SystemExit(f"[중단] {d} 가 없습니다. build_index.py 를 먼저 실행하세요.")
    idx = faiss.read_index(str(d / "index.faiss"))
    chunks = [json.loads(l) for l in (d / "chunks.jsonl").open(encoding="utf-8")]
    return idx, chunks


def main(argv):
    from sentence_transformers import SentenceTransformer
    import numpy as np

    queries = DEFAULT if len(argv) < 2 else [(argv[0], " ".join(argv[1:]))]
    model = SentenceTransformer(MODEL_NAME, device=DEVICE)
    cache = {}

    for persona, q in queries:
        if persona not in cache:
            cache[persona] = load(persona)
        idx, chunks = cache[persona]
        # BGE-M3 는 질의용 접두사가 필요 없다 (bge-v1.5 계열과 다른 점)
        v = np.asarray(model.encode([q], normalize_embeddings=True), dtype="float32")
        scores, ids = idx.search(v, TOP_K)

        print("=" * 100)
        print(f"[{persona}] {q}")
        print("=" * 100)
        for rank, (s, i) in enumerate(zip(scores[0], ids[0]), 1):
            c = chunks[i]
            head = f"{c['work']} {c['ref_start']}"
            if c["ref_end"] != c["ref_start"]:
                head += f"~{c['ref_end']}"
            print(f"\n {rank}. {s:.3f}  {head}  [{c['division_title']}]  {c['tokens']}토큰")
            body = c["text"].replace("\n", " ")
            print(f"    {body[:300]}{'...' if len(body) > 300 else ''}")
        print()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
