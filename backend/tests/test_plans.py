"""요금제·하루 한도 (plans.py, main.py /ask). LLM·임베딩 없이 돈다 — rag.answer 를 가짜로 바꾼다.

실행: backend 폴더에서  python -m pytest tests/test_plans.py -q   (몇 초)
TestClient 를 with 없이 쓰면 lifespan(모델 로딩)이 돌지 않는다.
"""
import pytest
from fastapi.testclient import TestClient

from app import plans, rag
from app.config import get_settings
from app.main import app

FAKE = {
    "persona": "jesus", "persona_name": "예수", "question": "q", "answer": "보라, 염려하지 말라.",
    "safety": False, "grounded": True, "retries": 0, "glossary": [], "sources": [],
}


@pytest.fixture
def client():
    return TestClient(app)          # with 없이: lifespan 을 건너뛴다


@pytest.fixture
def fake_answer(monkeypatch):
    calls = []

    def _fake(persona, question, top_k=None):
        calls.append(question)
        return {**FAKE, "persona": persona, "question": question}
    monkeypatch.setattr(rag, "answer", _fake)
    return calls


@pytest.fixture
def personal(monkeypatch):
    monkeypatch.setattr(get_settings(), "default_plan", "personal")


def _ask(client, user="user-a", q="돈 걱정으로 잠이 안 옵니다"):
    return client.post("/ask", json={"persona": "jesus", "question": q}, headers={"X-User-Id": user})


def test_default_plan_is_pro_and_unlimited(client, fake_answer):
    """테스트 단계 기본값: pro. 5건을 넘어도 막히지 않는다."""
    for i in range(8):
        r = _ask(client)
        assert r.status_code == 200, r.text
    u = r.json()["usage"]
    assert u == {"plan": "pro", "plan_name": "Pro", "used_today": 8, "daily_limit": None}


def test_personal_blocks_sixth_question(client, fake_answer, personal):
    for i in range(1, 6):
        r = _ask(client)
        assert r.status_code == 200, r.text
        assert r.json()["usage"]["used_today"] == i
        assert r.json()["usage"]["daily_limit"] == 5
    r = _ask(client)
    assert r.status_code == 429
    assert "5건" in r.json()["detail"]
    assert len(fake_answer) == 5            # 6번째는 LLM 까지 가지 않았다


def test_limit_is_per_user(client, fake_answer, personal):
    for _ in range(5):
        assert _ask(client, user="user-a").status_code == 200
    assert _ask(client, user="user-a").status_code == 429
    assert _ask(client, user="user-b").status_code == 200   # 다른 사용자는 따로 센다


def test_resets_next_day(client, fake_answer, personal, monkeypatch):
    monkeypatch.setattr(plans, "_today", lambda: "2026-09-30")
    for _ in range(5):
        _ask(client)
    assert _ask(client).status_code == 429
    monkeypatch.setattr(plans, "_today", lambda: "2026-10-01")
    r = _ask(client)
    assert r.status_code == 200
    assert r.json()["usage"]["used_today"] == 1


def test_failed_answer_is_refunded(client, personal, monkeypatch):
    """LLM 오류로 답을 못 준 요청은 세지 않는다."""
    def _boom(*a, **k):
        raise Exception("503 UNAVAILABLE")
    monkeypatch.setattr(rag, "answer", _boom)
    for _ in range(7):
        assert _ask(client).status_code == 502
    assert plans.status("user-a").used == 0


def test_crisis_message_still_gets_safety_notice_over_limit(client, fake_answer, personal):
    """한도를 넘었어도 위기 신호가 명백하면 상담전화 안내는 나간다. LLM 은 부르지 않고 사용량에도 안 센다."""
    for _ in range(5):
        _ask(client)
    r = _ask(client, q="죽고 싶어요")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["safety"] is True and "109" in body["answer"]
    assert body["usage"]["used_today"] == 5
    assert len(fake_answer) == 5
    # 위기 신호가 아닌 질문은 그대로 막힌다
    assert _ask(client, q="원수를 어떻게 대해야 합니까").status_code == 429


def test_missing_header_is_anonymous(client, fake_answer):
    r = client.post("/ask", json={"persona": "jesus", "question": "q"})
    assert r.status_code == 200
    assert plans.status(plans.ANONYMOUS).used == 1


def test_bad_user_id_rejected(client, fake_answer):
    r = client.post("/ask", json={"persona": "jesus", "question": "q"}, headers={"X-User-Id": "a b/c"})
    assert r.status_code == 400


def test_unknown_default_plan_fails_loudly(monkeypatch):
    monkeypatch.setattr(get_settings(), "default_plan", "gold")
    with pytest.raises(RuntimeError, match="gold"):
        plans.plan_for("user-a")


def test_chat_test_page_is_served(client):
    """개발용 채팅 테스트 화면 (GET /chat). /ask 를 부르고 X-User-Id 를 보낸다."""
    r = client.get("/chat")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/html")
    assert "철학 RAG 테스트" in r.text and 'fetch("/ask"' in r.text and "X-User-Id" in r.text


def test_usage_reads_without_counting(client, fake_answer, personal):
    """GET /usage — 설정 화면의 남은 사용량. 읽기만 하고 세지 않는다."""
    r = client.get("/usage", headers={"X-User-Id": "user-a"})
    assert r.status_code == 200
    assert r.json() == {"plan": "personal", "plan_name": "Personal", "used_today": 0, "daily_limit": 5}
    _ask(client); _ask(client)
    r = client.get("/usage", headers={"X-User-Id": "user-a"})
    assert r.json()["used_today"] == 2
    client.get("/usage", headers={"X-User-Id": "user-a"})
    assert plans.status("user-a").used == 2          # 조회는 횟수를 올리지 않는다
