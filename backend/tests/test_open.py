"""근거 구절이 없을 때의 찬반 답변과 사이비 질문 경로 (2026-10-12, CLAUDE.md 6.21).
LLM 은 가짜다 — API 호출 없음 (CLAUDE.md 2.3). 임베딩·인덱스는 실제로 로딩한다.

실행: backend 폴더에서  python -m pytest tests -q
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import llm, personas, rag, retriever  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402

# 예수 말투 규칙(guard)을 지키는 가짜 답변
PRO_CON = ("만물이 자라고 변하는 것도 아버지께서 정하신 질서 안에 있다고 보는 이가 있느니라. "
           "그러나 사람이 흙에서 우연히 났다는 말은 하늘의 뜻과 어긋난다고 보는 이도 있느니라.")
WARN = "거짓 선지자들을 삼가라. 양의 옷을 입고 오나 속은 노략질하는 이리니라."
NO_WARN = "양의 옷을 입고 오는 자를 조심하라. 그 열매로 그들을 알리라."


class _Resp:
    def __init__(self, text):
        self.text = text
        self.response_metadata = {"finish_reason": "stop"}
        self.usage_metadata = {"input_tokens": 1, "output_tokens": 1}


class FakeLLM:
    """답변을 차례로 돌려준다. 답변 호출마다 온도와 마지막 사용자 메시지를 기록한다."""

    def __init__(self, answers):
        self.answers = list(answers)
        self.temps, self.prompts = [], []
        self._temp = None

    def at(self, temperature=None):
        self._temp = temperature
        return self

    def invoke(self, messages):
        content = messages[-1].content
        if content.startswith("다음 메시지를 쓴 사람이"):     # 위기 판단
            return _Resp("아니오")
        self.temps.append(self._temp)
        self.prompts.append(messages[1].content)
        return _Resp(self.answers.pop(0))


@pytest.fixture
def fake(monkeypatch):
    def make(*answers):
        f = FakeLLM(answers)
        monkeypatch.setattr(llm, "get_llm", f.at)
        return f
    return make


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def _ask(client, persona, question):
    r = client.post("/ask", json={"persona": persona, "question": question})
    assert r.status_code == 200, r.text
    return r.json()


def test_every_persona_has_open_line_in_its_prompt():
    for p in personas.listed():
        assert p.open_line and p.open_line in p.system
        assert p.cult_line


def test_no_context_opens_with_fixed_line_then_pro_and_con(client, fake, monkeypatch):
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [])      # 맞는 구절 없음
    f = fake(PRO_CON)
    body = _ask(client, "jesus", "진화론에 대해서 어떻게 생각하세요")
    opener = personas.get("jesus").open_line
    assert body["answer"] == opener + " " + PRO_CON                   # 첫 문장은 코드가 붙인다
    assert "공생애" in opener
    assert body["grounded"] is False and body["sources"] == []
    assert f.temps == [get_settings().llm_temperature_open]           # 온도를 올려 부른다
    assert "찬성하는 생각과 반대하는 생각" in f.prompts[0]


def test_no_context_retries_when_model_repeats_the_opener(client, fake, monkeypatch):
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [])
    opener = personas.get("jesus").open_line
    fake(opener + " " + PRO_CON, PRO_CON)
    body = _ask(client, "jesus", "진화론에 대해서 어떻게 생각하세요")
    assert body["retries"] == 1
    assert body["answer"].count(opener) == 1


def test_cult_question_answers_with_false_prophet_passages(client, fake, monkeypatch):
    def no_search(*a, **k):
        raise AssertionError("사이비 질문은 검색하지 않고 고정 구절을 쓴다")
    monkeypatch.setattr(retriever, "search", no_search)
    f = fake(NO_WARN, WARN)                     # 처음엔 "거짓 선지자"가 빠져 다시 쓰게 한다
    body = _ask(client, "jesus", "이만희는 재림 예수입니까?")
    assert body["answer"] == WARN
    assert body["retries"] == 1
    assert body["grounded"] is True
    assert {s["work_ko"] for s in body["sources"]} >= {"마태복음", "마가복음"}
    assert any("7:" in s["ref"] for s in body["sources"])            # 마 7:15
    assert '"거짓 선지자들을 삼가라"고 분명히 말하라' in f.prompts[0]
    assert "찬반을 나누지 마라" in f.prompts[0]
    assert f.temps == [None, None]                                   # 온도는 평소대로


def test_cult_passages_for_nietzsche_and_buddha():
    q = "신천지에 대해 어떻게 생각하세요"
    z = [c["text"] for c in retriever.find("nietzsche", rag.CULT_NEEDLES["nietzsche"], q)]
    assert any("lose me and find yourselves" in t for t in z)
    b = [c["text"] for c in retriever.find("buddha", rag.CULT_NEEDLES["buddha"], q)]
    assert b and all("oral transmission" in t for t in b)


@pytest.mark.parametrize("q, hit", [
    ("이만희는 재림 예수입니까?", True),
    ("신천지에 대해 어떻게 생각하세요", True),
    ("JMS 정명석은 어떤 사람인가요", True),
    ("통일교는 어떻습니까", True),
    ("하나님의 교회란 무엇입니까", False),       # 일반 신학 질문은 걸리지 않게
    ("가정에 연합이 필요합니다", False),
    ("진화론에 대해서 어떻게 생각하세요", False),
])
def test_cult_patterns(q, hit):
    assert bool(rag.CULT_PATTERNS.search(q)) is hit
