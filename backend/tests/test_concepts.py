"""개념어 사전으로 검색어 보강, 답에 "구절"이 나오면 다시 쓰기 (2026-10-12, concepts.py · guard.py).
LLM 은 가짜다 — API 호출 없음.

실행: backend 폴더에서  python -m pytest tests -q
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import concepts, guard, llm, retriever  # noqa: E402
from app.main import app  # noqa: E402

NIETZSCHE_OK = "운명을 사랑하라. 필연을 견디는 것으로 모자라고, 그것을 사랑해야 한다."


@pytest.mark.parametrize("persona, q, expanded", [
    ("nietzsche", "아모르파티란 무엇인가요", "아모르파티란 무엇인가요 (amor fati)"),
    ("nietzsche", "아모르 파티를 어떻게 살아야 하나", "아모르 파티를 어떻게 살아야 하나 (amor fati)"),
    ("nietzsche", "초인과 영원회귀는 어떤 관계입니까", "초인과 영원회귀는 어떤 관계입니까 (eternal recurrence, Superman)"),
    ("buddha", "열반에 이르려면 어떻게 해야 합니까", "열반에 이르려면 어떻게 해야 합니까 (extinguishment)"),
    ("buddha", "사성제가 무엇입니까", "사성제가 무엇입니까 (four noble truths)"),
    ("jesus", "팔복을 설명해 주세요", "팔복을 설명해 주세요 (Blessed are the poor in spirit)"),
    ("jesus", "십자가를 지고 가실 때 어떠셨습니까?", "십자가를 지고 가실 때 어떠셨습니까? (cross, Golgotha)"),
    # 낱말 경계 — 다른 뜻으로 쓰인 글자는 건드리지 않는다
    ("buddha", "무상으로 받을 수 있나요", "무상으로 받을 수 있나요"),
    ("buddha", "사업이 망했습니다", "사업이 망했습니다"),
    ("nietzsche", "열반이란 무엇입니까", "열반이란 무엇입니까"),       # 부처의 사전이다
    ("jesus", "돈 걱정으로 잠이 안 옵니다", "돈 걱정으로 잠이 안 옵니다"),
])
def test_expand(persona, q, expanded):
    assert concepts.expand(persona, q) == expanded


class _Resp:
    def __init__(self, text):
        self.text = text
        self.response_metadata = {"finish_reason": "stop"}
        self.usage_metadata = {}


class _Fake:
    def __init__(self, *answers):
        self.answers, self.prompts = list(answers), []

    def invoke(self, messages):
        if messages[-1].content.startswith("다음은 ") and "여섯 가지" in messages[-1].content:
            return _Resp("일반")
        self.prompts.append(messages[1].content)
        return _Resp(self.answers.pop(0))


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def _hit():
    return {"chunk_id": "nietzsche#1", "work": "ECCE HOMO", "ref_start": "2:10", "ref_end": "2:10",
            "division": 2, "division_title": "Why I Am So Clever", "text": "My formula for greatness in a man is amor fati",
            "score": 0.478}


def test_search_uses_expanded_query_but_model_sees_the_original(client, monkeypatch):
    seen = {}

    def search(persona, query, top_k=None):
        seen["query"] = query
        return [_hit()]
    monkeypatch.setattr(retriever, "search", search)
    fake = _Fake(NIETZSCHE_OK)
    monkeypatch.setattr(llm, "get_llm", lambda *a, **k: fake)
    r = client.post("/ask", json={"persona": "nietzsche", "question": "아모르파티란 무엇인가요"})
    assert r.status_code == 200, r.text
    assert seen["query"] == "아모르파티란 무엇인가요 (amor fati)"
    assert "질문: 아모르파티란 무엇인가요" in fake.prompts[0] and "(amor fati)" not in fake.prompts[0]
    assert r.json()["grounded"] is True


def test_word_gubeol_in_answer_is_rewritten(client, monkeypatch):
    """ "그대가 제시한 구절들에 따르면" 처럼 시스템이 준 재료를 드러내면 다시 쓰게 한다."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [_hit()])
    fake = _Fake("그대가 제시한 구절들에 따르면 운명을 사랑하라는 뜻이다.", NIETZSCHE_OK)
    monkeypatch.setattr(llm, "get_llm", lambda *a, **k: fake)
    body = client.post("/ask", json={"persona": "nietzsche", "question": "아모르파티란 무엇인가요"}).json()
    assert body["retries"] == 1 and body["answer"] == NIETZSCHE_OK


def test_guard_allows_biblical_riyo():
    """「무슨 상이 있으리요」는 성경체다 — ~요체로 잡아 세 번 재생성했었다 (30문항 평가 J01, 2026-10-14)."""
    ok = "너희를 사랑하는 자만 사랑한다면 무슨 상이 있으리요. 너희도 긍휼히 여기라."
    assert not any("~요체" in v for v in guard.check("jesus", ok, safety=False))
    assert any("~요체" in v for v in guard.check("jesus", "원수를 사랑하세요. 그게 좋아요.", safety=False))


def test_guard_flags_gubeol():
    assert any("구절" in v for v in guard.check("nietzsche", "이 구절들만으로는 설명할 수 없다.", safety=False))
    assert not any("구절" in v for v in guard.check("nietzsche", NIETZSCHE_OK, safety=False))
