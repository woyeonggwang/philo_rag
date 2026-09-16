"""FAISS 검색. 임베딩 모델은 프로세스당 한 번만 로딩한다 (2GB, GPU)."""
import json
import logging
import threading
from functools import lru_cache

import faiss
import numpy as np
from sentence_transformers import SentenceTransformer

from .config import get_settings

log = logging.getLogger(__name__)
_lock = threading.Lock()


@lru_cache(maxsize=1)
def _embedder() -> SentenceTransformer:
    s = get_settings()
    log.info("임베딩 모델 로딩: %s (device=%s)", s.embedding_model, s.embedding_device)
    return SentenceTransformer(s.embedding_model, device=s.embedding_device)


@lru_cache(maxsize=8)
def _index(persona: str):
    s = get_settings()
    d = s.index_dir / persona
    if not d.exists():
        raise FileNotFoundError(
            f"{d} 가 없습니다. scripts/build_index.py 를 먼저 실행하세요.")
    idx = faiss.read_index(str(d / "index.faiss"))
    chunks = [json.loads(l) for l in (d / "chunks.jsonl").open(encoding="utf-8")]
    meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    if meta.get("model") != s.embedding_model:
        # 인덱스를 만든 모델과 지금 모델이 다르면 벡터 공간이 달라 검색이 무의미해진다
        raise RuntimeError(
            f"인덱스는 {meta.get('model')} 로 만들어졌는데 설정은 {s.embedding_model} 입니다. "
            f"인덱스를 다시 빌드하세요.")
    log.info("인덱스 로딩: %s (청크 %d개)", persona, len(chunks))
    return idx, chunks


def warmup(personas):
    """서버 기동 시 미리 로딩해 첫 요청이 느려지지 않게 한다."""
    _embedder()
    for p in personas:
        try:
            _index(p)
        except FileNotFoundError as e:
            log.warning("%s 인덱스 없음: %s", p, e)


def search(persona: str, query: str, top_k: int | None = None):
    s = get_settings()
    top_k = top_k or s.top_k
    idx, chunks = _index(persona)

    # BGE-M3 는 질의용 접두사를 붙이지 않는다 (bge-v1.5 계열과 다른 점)
    # SentenceTransformer.encode 는 스레드 안전이 보장되지 않아 잠근다
    with _lock:
        v = _embedder().encode([query], normalize_embeddings=True)
    v = np.asarray(v, dtype="float32")

    scores, ids = idx.search(v, top_k)
    out = []
    for score, i in zip(scores[0].tolist(), ids[0].tolist()):
        if i < 0:
            continue
        c = dict(chunks[i])
        c["score"] = round(float(score), 4)
        out.append(c)
    return out
