"""대화 신고와 개발자 확인 (2026-10-12, reports.py · main.py /reports /me).
LLM·임베딩을 쓰지 않는다. 신고 DB 는 conftest 가 임시 파일로 돌린다.

실행: backend 폴더에서  python -m pytest tests -q
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import auth  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402

REPORT = {
    "persona": "jesus",
    "reason": "예수의 사상과 맞지 않음",
    "question": "바람직한 삶이란 무엇입니까?",
    "answer": "이는 내가 공생애 동안 가르친 바가 아니니라. …",
    "extra": {"grounded": False, "sources": []},
}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(get_settings(), "admin_users", "dev-device-1, boss@example.com")
    monkeypatch.setattr(get_settings(), "firebase_project_id", "philo-rag-test")
    with TestClient(app) as c:
        yield c


def _token(monkeypatch, uid, email, verified):
    claims = {"iss": "https://securetoken.google.com/philo-rag-test", "sub": uid,
              "email": email, "email_verified": verified}
    monkeypatch.setattr(auth.id_token, "verify_firebase_token", lambda *a, **k: claims)
    return {"Authorization": "Bearer t"}


def test_report_is_stored_with_conversation_and_only_admin_reads_it(client):
    r = client.post("/reports", json={**REPORT, "detail": None}, headers={"X-User-Id": "someone"})
    assert r.status_code == 200, r.text
    r = client.post("/reports", json={**REPORT, "reason": "기타", "detail": "  말투가 이상합니다  "},
                    headers={"X-User-Id": "someone"})
    assert r.status_code == 200

    assert client.get("/reports", headers={"X-User-Id": "someone"}).status_code == 403
    assert client.get("/me", headers={"X-User-Id": "someone"}).json() == {"user_id": "someone", "admin": False}
    assert client.get("/me", headers={"X-User-Id": "dev-device-1"}).json()["admin"] is True

    rows = client.get("/reports", headers={"X-User-Id": "dev-device-1"}).json()
    assert [row["reason"] for row in rows] == ["기타", "예수의 사상과 맞지 않음"]   # 최근 것부터
    assert rows[0]["detail"] == "말투가 이상합니다"
    assert rows[0]["question"] == REPORT["question"] and rows[0]["answer"] == REPORT["answer"]
    assert rows[0]["user_id"] == "someone" and rows[0]["extra"] == {"grounded": False, "sources": []}


def test_admin_by_email_only_when_verified(client, monkeypatch):
    h = _token(monkeypatch, "uid1", "boss@example.com", verified=True)
    assert client.get("/me", headers=h).json()["admin"] is True
    # 이메일 가입은 인증 메일이 없어 남의 주소로도 가입된다 — 인증 안 된 이메일은 인정하지 않는다
    h = _token(monkeypatch, "uid2", "boss@example.com", verified=False)
    assert client.get("/me", headers=h).json()["admin"] is False
    assert client.get("/reports", headers=h).status_code == 403


def test_report_validation(client):
    assert client.post("/reports", json={**REPORT, "persona": "socrates"},
                       headers={"X-User-Id": "a"}).status_code == 404
    assert client.post("/reports", json={**REPORT, "reason": ""}, headers={"X-User-Id": "a"}).status_code == 422
    assert client.post("/reports", json={**REPORT, "detail": "x" * 1001},
                       headers={"X-User-Id": "a"}).status_code == 422


def test_anonymous_is_never_admin(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "admin_users", "anonymous")
    assert client.get("/me").json() == {"user_id": "anonymous", "admin": False}
