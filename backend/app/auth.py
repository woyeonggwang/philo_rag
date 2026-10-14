"""로그인 토큰 확인 (2026-10-10). Firebase Authentication — 구글·애플·이메일.

앱은 Firebase 로 로그인하고, 요청마다 `Authorization: Bearer <Firebase ID 토큰>` 을 보낸다.
서버는 그 토큰을 Google 공개키로 검증해 사용자 uid 를 꺼낸다. 서비스 계정 키는 필요 없다 — 프로젝트 ID 만 있으면 된다.
요금제 한도(plans.py)는 이 uid 로 센다 ("fb_<uid>").

AUTH_REQUIRED=false (기본) 이면 토큰 없는 요청도 받는다. 이때는 예전처럼 X-User-Id(기기 ID)로 센다 —
Firebase 설정 전에도, 개발용 "로그인 없이 계속" 으로도 시험할 수 있게. 설정을 마치면 true 로 바꾼다.
토큰이 왔는데 틀리면(만료·위조·다른 프로젝트) AUTH_REQUIRED 와 상관없이 401 이다.
"""
import hashlib
import logging
import re

import requests
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

from . import plans
from .config import get_settings

log = logging.getLogger(__name__)

# 공개키를 받아 오는 HTTP 세션. 연결을 재사용한다 (요청마다 키를 다시 받지만 LLM 호출에 비하면 미미하다)
_request = google_requests.Request(session=requests.Session())
_SAFE = re.compile(r"^[A-Za-z0-9]{1,60}$")


class AuthError(Exception):
    """401 로 돌려줄 문장. 앱이 그대로 보여준다."""


def verify_token(token: str) -> str:
    """Firebase ID 토큰을 검증하고 uid 를 돌려준다."""
    return _verify(token)[0]


def _verify(token: str) -> tuple[str, dict]:
    """(uid, 토큰 내용)."""
    project = get_settings().firebase_project_id
    if not project:
        raise AuthError("서버에 FIREBASE_PROJECT_ID 가 설정되지 않아 로그인을 확인할 수 없습니다.")
    try:
        claims = id_token.verify_firebase_token(token, _request, audience=project)
    except Exception as e:      # 만료·서명 불일치·형식 오류 등
        log.info("토큰 검증 실패: %s", e)
        raise AuthError("로그인 정보가 올바르지 않거나 만료됐습니다. 다시 로그인하세요.") from e
    if not claims or claims.get("iss") != f"https://securetoken.google.com/{project}":
        raise AuthError("다른 프로젝트의 로그인 정보입니다. 다시 로그인하세요.")
    uid = claims.get("sub") or claims.get("user_id")
    if not uid:
        raise AuthError("로그인 정보에 사용자 ID 가 없습니다.")
    return uid, claims


def user_key(uid: str) -> str:
    """요금제 사용량에 쓸 키. plans 의 형식(영문·숫자·'-'·'_' 64자)에 맞춘다. 일반 uid 는 영문·숫자 28자다."""
    if _SAFE.match(uid):
        return f"fb_{uid}"
    return "fb_" + hashlib.sha256(uid.encode()).hexdigest()[:40]


def resolve_user(authorization: str | None, x_user_id: str | None) -> str:
    """요청한 사용자. 토큰이 있으면 계정, 없으면 (허용될 때만) 기기 ID."""
    return resolve(authorization, x_user_id)[0]


def resolve(authorization: str | None, x_user_id: str | None) -> tuple[str, str | None]:
    """(사용자 ID, 인증된 이메일 또는 None). 이메일은 토큰이 email_verified 일 때만 준다 —
    이메일 가입은 인증 메일을 보내지 않아 남의 주소로도 가입되기 때문이다 (CLAUDE.md 4.8)."""
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token.strip():
            raise AuthError("Authorization 헤더는 'Bearer <토큰>' 꼴이어야 합니다.")
        uid, claims = _verify(token.strip())
        email = claims.get("email") if claims.get("email_verified") else None
        return user_key(uid), email
    if get_settings().auth_required:
        raise AuthError("로그인이 필요합니다.")
    return plans.normalize_user_id(x_user_id), None


def is_admin(user_id: str, email: str | None) -> bool:
    """신고 내역을 볼 수 있는 개발자인가 (.env 의 ADMIN_USERS, 2026-10-12)."""
    allowed = {a.strip().lower() for a in get_settings().admin_users.split(",") if a.strip()}
    if user_id == plans.ANONYMOUS:
        return False
    return user_id.lower() in allowed or (email is not None and email.lower() in allowed)
