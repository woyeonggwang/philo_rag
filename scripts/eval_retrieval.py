#!/usr/bin/env python3
"""
검색 품질 A/B 측정.

두 가지를 동시에 비교한다.
  가로축: 청크 목표 크기 (기본 256 vs 512)
  세로축: 질의 언어 (한국어 원문 vs 영어 번역)

코퍼스가 영어이므로 질의를 영어로 바꾸면 나아질 수 있다.
그렇다면 백엔드에서 LLM 으로 질의를 영어로 옮긴 뒤 검색하면 된다.
근거 없이 정하지 않기 위해 측정한다.

'정답'은 질문마다 사람이 지정한 (작품, 구분)이다. 상위 K 안에 그 구분의 청크가
들어오면 적중으로 센다. 지표는 MRR(첫 적중 순위의 역수)과 Hit@5 다.

사용:
    python scripts/eval_retrieval.py
    python scripts/eval_retrieval.py 256 512 768     # 비교할 청크 크기 지정
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "backend" / "data" / "corpus"
sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from dotenv import load_dotenv
    load_dotenv(ROOT / "backend" / ".env")
except ImportError:
    pass

MODEL_NAME = os.getenv("EMBEDDING_MODEL", "BAAI/bge-m3")
DEVICE = os.getenv("EMBEDDING_DEVICE", "cuda")
TOP_K = 5

# (페르소나, 한국어 질의, 영어 질의, 정답 구분 목록)
# 정답 구분은 실제 본문을 확인해 지정한 것이다.
QUESTIONS = [
    ("nietzsche",
     "삶이 고통스러운데 계속 살아야 할 이유가 있습니까?",
     "Is there any reason to go on living when life is nothing but suffering?",
     [("THUS SPAKE ZARATHUSTRA", 9)]),           # 죽음의 설교자
    ("nietzsche",
     "신은 죽었다는 말은 무슨 뜻입니까?",
     "What does it mean to say that God is dead?",
     [("THUS SPAKE ZARATHUSTRA", 0),             # 서문 - 신은 죽었다
      ("THUS SPAKE ZARATHUSTRA", 66)]),          # 퇴직한 교황
    ("nietzsche",
     "동정심은 좋은 것 아닌가요?",
     "Is pity not a virtue? Why do you attack compassion?",
     [("THUS SPAKE ZARATHUSTRA", 25),            # 동정하는 자
      ("BEYOND GOOD AND EVIL", 7)]),             # 우리의 덕
    ("nietzsche",
     "무리를 따르지 않고 혼자 서는 법을 알고 싶습니다",
     "How can I stand alone instead of following the herd?",
     [("THUS SPAKE ZARATHUSTRA", 8),             # 산 위의 나무
      ("BEYOND GOOD AND EVIL", 9)]),             # 고귀함이란 무엇인가
    ("jesus",
     "용서할 수 없는 사람을 용서해야 합니까?",
     "Must I forgive someone I cannot forgive?",
     [("THE GOSPEL ACCORDING TO MATTHEW", 18)]),
    ("jesus",
     "돈 걱정으로 잠이 안 옵니다",
     "I cannot sleep because I am worried about money.",
     [("THE GOSPEL ACCORDING TO MATTHEW", 6)]),
    ("jesus",
     "원수를 어떻게 대해야 합니까?",
     "How should I treat my enemies?",
     [("THE GOSPEL ACCORDING TO MATTHEW", 5)]),
]


def build(target, ntok):
    """지정한 목표 크기로 메모리 안에서만 청킹한다. 디스크 인덱스는 건드리지 않는다."""
    import build_index as bi
    bi.TARGET = target
    bi.MAXTOK = int(target * 1.25)
    bi.OVERLAP = max(32, target // 6)

    by = {}
    for f in sorted(CORPUS.glob("*_units.jsonl")):
        for line in f.open(encoding="utf-8"):
            r = json.loads(line)
            by.setdefault(r["persona"], {}).setdefault((r["work"], r["division"]), []).append(r)

    out = {}
    for persona, groups in by.items():
        chunks = []
        for (work, division), units in groups.items():
            units.sort(key=lambda r: r["seq"])
            for g in bi.chunk_units(units, ntok):
                chunks.append({
                    "work": work, "division": division,
                    "division_title": g[0]["division_title"],
                    "ref_start": g[0]["ref"], "ref_end": g[-1]["ref"],
                    "text": "\n\n".join(u["text"] for u in g),
                })
        out[persona] = chunks
    return out


def main(argv):
    from sentence_transformers import SentenceTransformer
    import numpy as np
    import faiss

    targets = [int(a) for a in argv] or [256, 512]
    model = SentenceTransformer(MODEL_NAME, device=DEVICE)
    tok = model.tokenizer
    ntok = lambda t: len(tok.encode(t, add_special_tokens=False))

    results = {}
    for target in targets:
        chunked = build(target, ntok)
        indexes = {}
        for persona, chunks in chunked.items():
            print(f"[{target}] {persona}: 청크 {len(chunks)}개 임베딩 중...")
            v = np.asarray(model.encode([c["text"] for c in chunks], batch_size=8,
                                        normalize_embeddings=True), dtype="float32")
            idx = faiss.IndexFlatIP(v.shape[1])
            idx.add(v)
            indexes[persona] = (idx, chunks)
        results[target] = indexes

    print()
    header = f"{'질문':<34}"
    for target in targets:
        header += f"{'  ' + str(target) + ' 한국어':>14}{'  ' + str(target) + ' 영어':>13}"
    print(header)
    print("-" * len(header))

    totals = {(t, lang): [] for t in targets for lang in ("ko", "en")}

    for persona, ko, en, gold in QUESTIONS:
        row = f"{ko[:32]:<34}"
        for target in targets:
            idx, chunks = results[target][persona]
            for lang, q in (("ko", ko), ("en", en)):
                v = np.asarray(model.encode([q], normalize_embeddings=True), dtype="float32")
                _, ids = idx.search(v, TOP_K)
                rank = None
                for r, i in enumerate(ids[0], 1):
                    c = chunks[i]
                    if (c["work"], c["division"]) in gold:
                        rank = r
                        break
                totals[(target, lang)].append(1.0 / rank if rank else 0.0)
                row += f"{('  ' + str(rank) + '위' if rank else '  실패'):>14}"
        print(row)

    print("-" * len(header))
    for metric, fn in (("MRR", lambda v: sum(v) / len(v)),
                       ("Hit@5", lambda v: sum(1 for x in v if x > 0) / len(v))):
        row = f"{metric:<34}"
        for target in targets:
            for lang in ("ko", "en"):
                row += f"{fn(totals[(target, lang)]):>14.3f}"
        print(row)
    print("\nMRR: 정답이 1위면 1.0, 2위면 0.5, 5위 밖이면 0. 높을수록 좋다.")
    print("Hit@5: 상위 5개 안에 정답 구분이 들어온 질문의 비율.")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
