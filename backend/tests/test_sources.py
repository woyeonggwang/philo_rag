"""근거 구절 목록의 한글 작품명·원문 — LLM 을 가짜로 바꿔 API 호출 없이 검증한다
(CLAUDE.md 2.3: 호출은 사용자가 지시할 때만).

실행: backend 폴더에서  python -m pytest tests -q
임베딩 모델과 인덱스는 실제로 로딩한다 (CPU 에서 10~40초).
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import llm, works  # noqa: E402
from app.main import app  # noqa: E402

ANSWER = "보라 하늘의 새를 보라. 너희 하늘 아버지께서 기르시느니라. 그러므로 내일 일을 위하여 염려하지 말라."


class _Resp:
    def __init__(self, text):
        self.text = text
        self.response_metadata = {"finish_reason": "stop"}
        self.usage_metadata = {"input_tokens": 1, "output_tokens": 1}


class FakeLLM:
    def __init__(self):
        self.calls = 0

    def invoke(self, messages):
        self.calls += 1
        content = messages[-1].content
        if content.startswith("다음은 ") and "여섯 가지" in content:
            return _Resp("일반")
        return _Resp(ANSWER)


@pytest.fixture
def fake_llm(monkeypatch):
    fake = FakeLLM()
    monkeypatch.setattr(llm, "get_llm", lambda *a, **k: fake)
    return fake


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_work_ko_table():
    assert works.work_ko("THE GOSPEL ACCORDING TO MATTHEW") == "마태복음"
    assert works.work_ko("THUS SPAKE ZARATHUSTRA") == "차라투스트라는 이렇게 말했다"
    assert works.work_ko("THE DHAMMAPADA") == "법구경"
    assert works.work_ko("Unknown Work") == "Unknown Work"   # 모르는 제목은 그대로


def test_every_indexed_work_has_korean_name():
    """인덱스에 있는 작품은 전부 표에 있어야 한다. 코퍼스를 늘리면 works.py 도 늘릴 것."""
    import json
    from app.config import get_settings
    index_dir = get_settings().index_dir
    for persona_dir in index_dir.iterdir():
        meta = json.loads((persona_dir / "meta.json").read_text(encoding="utf-8"))
        for w in meta["works"]:
            assert w in works.WORK_KO, f"{persona_dir.name}: '{w}' 의 한글 제목이 works.py 에 없다"


def test_ask_sources_carry_korean_work_only(client, fake_llm):
    r = client.post("/ask", json={"persona": "jesus", "question": "돈 걱정으로 잠이 안 옵니다"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["answer"] == ANSWER
    srcs = body["sources"]
    assert len(srcs) >= 1
    for s in srcs:
        assert s["chunk_id"].startswith("jesus#")
        assert s["work_ko"] in ("마태복음", "마가복음", "누가복음")
        # 본문도, 본문 번역도 보내지 않는다 (사용자 결정 2026-09-22: 목록은 위치만)
        assert "text" not in s and "text_ko" not in s
    # 위기 판단 1회 + 답변 1회. 번역 호출은 없다
    assert fake_llm.calls == 2
