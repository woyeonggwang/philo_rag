"""요금제와 하루 사용량 제한 (2026-09-30).

요금제는 둘이다. 가격과 결제 방식(월 구독 / 크레딧)은 아직 정하지 않았으므로 여기에 넣지 않는다.
    personal  하루 5건
    pro       제한 없음

로그인은 아직 없다 (사용자 결정: 제한 기능만 만들고 로그인 시스템은 도입하지 않는다).
사용자는 앱이 처음 실행될 때 만들어 저장하는 무작위 ID(`X-User-Id` 헤더)로 구분한다.
앱을 지웠다 다시 깔면 새 ID 가 되므로 제한을 피해 갈 수 있다 — 로그인을 붙이면 계정 ID 로 바꾼다.

누가 어떤 요금제인지는 plan_for() 한 곳에서만 정한다. 지금은 설정값 DEFAULT_PLAN 하나를 모두가 받는다.
**테스트 단계라 기본값은 pro** 다. .env 에서 DEFAULT_PLAN=personal 로 바꾸면 하루 5건 제한이 걸린다.

사용량은 backend/data/usage.db (SQLite, gitignore) 에 (사용자, 날짜) 별로 센다. 서버를 껐다 켜도 유지된다.
하루의 경계는 한국 시간 자정이다. 제한이 없는 pro 도 횟수는 센다 (나중에 크레딧·통계에 쓸 수 있게).
"""
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from .config import get_settings

# 한국은 서머타임이 없어 고정 +9 로 충분하다. zoneinfo 는 Windows 에서 tzdata 패키지가 따로 필요하다.
KST = timezone(timedelta(hours=9))

ANONYMOUS = "anonymous"          # X-User-Id 없이 온 요청 (/docs 에서 직접 시험할 때 등). 모두 한 칸을 같이 쓴다
_USER_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


@dataclass(frozen=True)
class Plan:
    key: str
    name: str                  # 화면에 보일 이름
    daily_limit: int | None    # None 이면 제한 없음


PLANS: dict[str, Plan] = {
    "personal": Plan("personal", "Personal", 5),
    "pro": Plan("pro", "Pro", None),
}


@dataclass(frozen=True)
class Usage:
    plan: Plan
    day: str                   # 한국 날짜 "2026-09-30". 환불할 때 같은 날에 돌려주려고 들고 다닌다
    used: int                  # 오늘 쓴 건수 (이번 요청 포함)

    def as_dict(self) -> dict:
        return {"plan": self.plan.key, "plan_name": self.plan.name,
                "used_today": self.used, "daily_limit": self.plan.daily_limit}


class QuotaExceeded(Exception):
    def __init__(self, usage: Usage):
        self.usage = usage
        super().__init__(
            f"오늘 사용할 수 있는 질문 {usage.plan.daily_limit}건을 모두 썼습니다 "
            f"({usage.plan.name} 요금제). 한국 시간 자정에 다시 채워집니다.")


class InvalidUserId(ValueError):
    pass


def normalize_user_id(raw: str | None) -> str:
    """헤더 값을 검사한다. 없으면 ANONYMOUS. 형식이 이상하면 InvalidUserId."""
    if raw is None or raw.strip() == "":
        return ANONYMOUS
    raw = raw.strip()
    if not _USER_ID.match(raw):
        raise InvalidUserId("X-User-Id 는 영문·숫자·'-'·'_' 1~64자여야 합니다.")
    return raw


def plan_for(user_id: str) -> Plan:
    """사용자의 요금제. 로그인이 없으니 지금은 모두 DEFAULT_PLAN 이다. 계정이 생기면 여기만 바꾼다."""
    key = get_settings().default_plan
    if key not in PLANS:
        raise RuntimeError(f"DEFAULT_PLAN='{key}' 는 없는 요금제다. {list(PLANS)} 중 하나로 할 것.")
    return PLANS[key]


def _today() -> str:
    return datetime.now(KST).date().isoformat()


def _connect() -> sqlite3.Connection:
    path = get_settings().usage_db
    path.parent.mkdir(parents=True, exist_ok=True)
    # isolation_level=None 으로 두고 트랜잭션은 직접 연다 (BEGIN IMMEDIATE — 읽고 올리는 사이에 끼어들지 못하게)
    con = sqlite3.connect(path, timeout=10, isolation_level=None)
    con.execute("CREATE TABLE IF NOT EXISTS usage ("
                " user_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL,"
                " PRIMARY KEY (user_id, day))")
    return con


def _count(con: sqlite3.Connection, user_id: str, day: str) -> int:
    row = con.execute("SELECT count FROM usage WHERE user_id=? AND day=?", (user_id, day)).fetchone()
    return row[0] if row else 0


def status(user_id: str) -> Usage:
    """오늘 사용량을 읽기만 한다."""
    day = _today()
    con = _connect()
    try:
        return Usage(plan_for(user_id), day, _count(con, user_id, day))
    finally:
        con.close()


def reserve(user_id: str) -> Usage:
    """질문 1건을 미리 센다. 한도에 닿았으면 QuotaExceeded.
    LLM 호출 전에 올려 두어야 동시에 여러 건을 보내도 한도를 넘지 못한다. 실패하면 refund() 로 돌려준다."""
    plan = plan_for(user_id)
    day = _today()
    con = _connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        used = _count(con, user_id, day)
        if plan.daily_limit is not None and used >= plan.daily_limit:
            con.execute("ROLLBACK")
            raise QuotaExceeded(Usage(plan, day, used))
        con.execute("INSERT INTO usage (user_id, day, count) VALUES (?, ?, 1) "
                    "ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1", (user_id, day))
        con.execute("COMMIT")
        return Usage(plan, day, used + 1)
    finally:
        con.close()


def refund(user_id: str, day: str) -> None:
    """답을 돌려주지 못한 요청(LLM 오류 등)은 세지 않는다. reserve() 가 준 day 에 돌려준다 (자정을 넘겨도 맞게)."""
    con = _connect()
    try:
        con.execute("UPDATE usage SET count = count - 1 WHERE user_id=? AND day=? AND count > 0",
                    (user_id, day))
    finally:
        con.close()
