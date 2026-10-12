"""대화 신고 (2026-10-12, 사용자 결정).

앱에서 철학자의 답을 길게 눌러 "대화내용 신고"를 고르면 사유와 함께 그 질문·답이 여기로 온다.
사유는 앱이 정한 항목("니체의 사상과 맞지 않음", "폭력적인 발화" …) 또는 "기타"의 직접 입력.
신고 내역은 개발자(.env 의 ADMIN_USERS)만 앱 설정 화면에서 본다 (main.py GET /reports).

backend/data/reports.db (SQLite, gitignore). 신고는 대화 내용을 담고 있어 커밋하지 않는다.
"""
import json
import sqlite3
from datetime import datetime

from .config import get_settings
from .plans import KST


def _connect() -> sqlite3.Connection:
    path = get_settings().reports_db
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("CREATE TABLE IF NOT EXISTS reports ("
                " id INTEGER PRIMARY KEY AUTOINCREMENT,"
                " created_at TEXT NOT NULL,"      # 한국 시간 ISO
                " user_id TEXT NOT NULL,"
                " persona TEXT NOT NULL,"
                " reason TEXT NOT NULL,"
                " detail TEXT,"                   # "기타" 직접 입력
                " question TEXT NOT NULL,"
                " answer TEXT NOT NULL,"
                " extra TEXT)")                   # 답의 근거 구절 위치·근거 여부 등 (JSON)
    return con


def add(*, user_id: str, persona: str, reason: str, detail: str | None,
        question: str, answer: str, extra: dict | None = None) -> int:
    with _connect() as con:
        cur = con.execute(
            "INSERT INTO reports (created_at, user_id, persona, reason, detail, question, answer, extra)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (datetime.now(KST).isoformat(timespec="seconds"), user_id, persona, reason,
             detail, question, answer, json.dumps(extra, ensure_ascii=False) if extra else None))
        return int(cur.lastrowid)


def recent(limit: int = 200) -> list[dict]:
    """최근 신고부터."""
    with _connect() as con:
        rows = con.execute("SELECT * FROM reports ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        d["extra"] = json.loads(d["extra"]) if d["extra"] else None
        out.append(d)
    return out
