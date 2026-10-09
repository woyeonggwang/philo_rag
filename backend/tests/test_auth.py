"""로그인 토큰 확인 (auth.py, /ask). Google 공개키·LLM 없이 돈다 — 토큰 검증과 rag.answer 를 가짜로 바꾼다.

실행: backend 폴더에서  python -m pytest tests/test_auth.py -q
"""
import pytest
from fastapi.testclient import TestClient

from app import auth, plans, rag
from app.config import get_settings
from app.main import app

FAKE = {
    "persona": "jesus", "persona_name": "예수", "question": "q", "answer": "보라, 염려하지 말라.",
    "safety": False, "grounded": True, "retries": 0, "glossary": [], "sources": [],
}
GOOD = "good-token"
UID = "AbCdEf0123456789AbCdEf012345"     # Firebase uid 는 보통 영문·숫자 28자


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(rag, "answer", lambda persona, q, top_k=None: {**FAKE, "persona": persona, "question": q})
    monkeypatch.setattr(get_settings(), "firebase_project_id", "philo-rag-test")

    def _verify(token, request, audience):
        if token != GOOD:
            raise ValueError("bad signature")
        return {"iss": f"https://securetoken.google.com/{audience}", "sub": UID, "aud": audience}
    monkeypatch.setattr(auth.id_token, "verify_firebase_token", _verify)
    return TestClient(app)


def _ask(client, headers):
    return client.post("/ask", json={"persona": "jesus", "question": "q"}, headers=headers)


def test_valid_token_counts_under_account(client):
    r = _ask(client, {"Authorization": f"Bearer {GOOD}", "X-User-Id": "device-1"})
    assert r.status_code == 200, r.text
    assert plans.status(f"fb_{UID}").used == 1
    assert plans.status("device-1").used == 0       # 토큰이 있으면 기기 ID 는 쓰지 않는다


def test_bad_token_is_401_even_when_not_required(client):
    r = _ask(client, {"Authorization": "Bearer forged"})
    assert r.status_code == 401
    assert "다시 로그인" in r.json()["detail"]


def test_malformed_header_is_401(client):
    assert _ask(client, {"Authorization": GOOD}).status_code == 401          # Bearer 없음
    assert _ask(client, {"Authorization": "Bearer "}).status_code == 401


def test_no_token_falls_back_to_device_id_by_default(client):
    """AUTH_REQUIRED=false (기본): Firebase 설정 전·개발용 로그인 우회로도 시험할 수 있다."""
    r = _ask(client, {"X-User-Id": "device-1"})
    assert r.status_code == 200
    assert plans.status("device-1").used == 1


def test_no_token_rejected_when_required(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "auth_required", True)
    r = _ask(client, {"X-User-Id": "device-1"})
    assert r.status_code == 401
    assert r.json()["detail"] == "로그인이 필요합니다."
    assert _ask(client, {"Authorization": f"Bearer {GOOD}"}).status_code == 200


def test_token_without_project_id_is_401(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "firebase_project_id", "")
    r = _ask(client, {"Authorization": f"Bearer {GOOD}"})
    assert r.status_code == 401
    assert "FIREBASE_PROJECT_ID" in r.json()["detail"]


def test_token_from_other_project_is_401(client, monkeypatch):
    monkeypatch.setattr(auth.id_token, "verify_firebase_token",
                        lambda t, r, audience: {"iss": "https://securetoken.google.com/other", "sub": UID})
    assert _ask(client, {"Authorization": f"Bearer {GOOD}"}).status_code == 401


def test_user_key_fits_plan_id_format():
    assert auth.user_key(UID) == f"fb_{UID}"
    odd = auth.user_key("weird/uid with spaces" * 5)
    assert plans.normalize_user_id(odd) == odd     # 형식이 맞아 plans 가 받아들인다
