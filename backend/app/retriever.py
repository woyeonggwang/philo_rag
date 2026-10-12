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
    log.info("임베딩 모델 로딩: %s (device=%s, dtype=%s)",
             s.embedding_model, s.embedding_device, s.embedding_dtype)
    kwargs = {}
    if s.embedding_dtype != "float32":
        # 인덱스는 fp32 로 만들었지만 질의만 fp16 으로 인코딩해도 점수 차이가 무시할 수준이다
        kwargs["model_kwargs"] = {"torch_dtype": s.embedding_dtype}
    return SentenceTransformer(s.embedding_model, device=s.embedding_device, **kwargs)


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


@lru_cache(maxsize=8)
def _chunk_map(persona: str) -> dict:
    """chunk_id -> 청크. 번역 요청(/translate)이 청크 하나를 되찾을 때 쓴다."""
    _, chunks = _index(persona)
    return {c["chunk_id"]: c for c in chunks}


def get_chunk(persona: str, chunk_id: str) -> dict:
    """없으면 KeyError. 인덱스가 없으면 FileNotFoundError (그대로 올린다)."""
    return _chunk_map(persona)[chunk_id]


def ref_label(chunk: dict) -> str:
    """앱에 보이는 인용 위치. 단위 하나면 "6:25", 묶음이면 "6:17~6:31"."""
    a, b = chunk["ref_start"], chunk["ref_end"]
    return a if a == b else f"{a}~{b}"


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


def find(persona: str, needles: list[str], query: str):
    """본문에 needles 중 하나가 그대로 들어 있는 청크 (사이비 질문의 고정 구절, rag.py).
    검색으로는 "거짓 선지자를 삼가라"(마 7:15)가 상위에 안 올라와서 문구로 찾는다. 점수는 query 와의 실제 유사도."""
    idx, chunks = _index(persona)
    with _lock:
        v = _embedder().encode([query], normalize_embeddings=True)
    v = np.asarray(v, dtype="float32")[0]
    out = []
    for i, ch in enumerate(chunks):
        if any(n in ch["text"] for n in needles):
            c = dict(ch)
            c["score"] = round(float(idx.reconstruct(i) @ v), 4)
            out.append(c)
    return out
