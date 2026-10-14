"""FastAPI 서버.

앱은 {persona, question} 만 보낸다. 검색·프롬프트 조립·LLM 호출·API 키 보관은 전부 여기서 한다.
(CLAUDE.md 4.2 — 앱에 키를 넣지 않는 이유)

실행:
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
문서:
    http://localhost:8000/docs
"""
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from . import auth, personas, plans, rag, reports, retriever
from .config import get_settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s | %(message)s")
log = logging.getLogger("philo_rag")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 첫 요청에서 2GB 모델을 로딩하면 그 요청만 수십 초 걸린다. 기동 때 미리 올린다.
    log.info("모델과 인덱스를 미리 로딩합니다...")
    retriever.warmup([p.key for p in personas.listed() if p.enabled])
    plan = plans.plan_for(plans.ANONYMOUS)     # DEFAULT_PLAN 오타면 여기서 바로 죽게
    log.info("요금제: 모든 사용자 %s (하루 %s건) — DEFAULT_PLAN", plan.name,
             plan.daily_limit if plan.daily_limit is not None else "무제한")
    # uvicorn 은 "http://0.0.0.0:8000" 을 찍는데, 0.0.0.0 은 바인드 주소라 브라우저로 열 수 없다 (ERR_ADDRESS_INVALID)
    log.info("준비 완료 — 채팅 테스트: http://localhost:8000/chat  (API 문서: /docs)")
    yield


app = FastAPI(title="철학 RAG API", version="0.1.0", lifespan=lifespan)

# 개발 단계에서는 에뮬레이터·실기기에서 바로 붙을 수 있게 열어둔다.
# 배포 전에 반드시 좁힐 것. (CLAUDE.md 8절)
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class AskRequest(BaseModel):
    persona: str = Field(..., examples=["nietzsche"])
    question: str = Field(..., min_length=1, max_length=2000,
                          examples=["삶이 고통스러운데 계속 살아야 할 이유가 있습니까?"])
    top_k: int | None = Field(None, ge=1, le=20)


class Source(BaseModel):
    chunk_id: str              # 인덱스 청크 키 (예: "jesus#12")
    work: str                  # 작품명 영어 (코퍼스 표기)
    work_ko: str               # 작품명 한글 ("마태복음"). 앱의 근거 목록에 이걸 보여준다 (works.py)
    ref: str
    title: str | None = None
    score: float


class GlossaryItem(BaseModel):
    term: str
    meaning: str


class UsageInfo(BaseModel):
    plan: str                  # "personal" | "pro"
    plan_name: str             # 화면 표시용 ("Personal")
    used_today: int            # 오늘 쓴 질문 수 (이번 질문 포함)
    daily_limit: int | None    # None 이면 무제한


class AskResponse(BaseModel):
    persona: str
    persona_name: str
    question: str
    answer: str
    grounded: bool
    safety: bool = False       # 자해·자살 암시가 감지돼 안전 안내가 앞에 붙었는지
    retries: int = 0           # 규칙 위반으로 다시 생성한 횟수 (CLAUDE.md 4.7)
    glossary: list[GlossaryItem] = []   # 답변 속 용어·호칭의 뜻. 각주용 (glossary.py)
    sources: list[Source]
    usage: UsageInfo | None = None      # 요금제와 오늘 사용량 (plans.py)


class ReportRequest(BaseModel):
    """대화 신고 (reports.py). 앱이 철학자의 답 하나와 그 질문을 사유와 함께 보낸다."""
    persona: str = Field(..., examples=["jesus"])
    reason: str = Field(..., min_length=1, max_length=100, examples=["예수의 사상과 맞지 않음"])
    detail: str | None = Field(None, max_length=1000)       # "기타" 직접 입력
    question: str = Field(..., max_length=4000)
    answer: str = Field(..., min_length=1, max_length=10000)
    extra: dict | None = None      # 근거 구절 위치·근거 여부 등 (앱이 붙인다)


class MeInfo(BaseModel):
    user_id: str
    admin: bool                # 신고 내역을 볼 수 있는 개발자인지 (ADMIN_USERS)


STATIC = Path(__file__).resolve().parent / "static"


@app.get("/chat", include_in_schema=False)
def chat_page():
    """개발용 채팅 테스트 화면 (static/chat.html). /ask 를 그대로 부르므로 질문마다 LLM 비용이 든다.
    배포 전에 지울 것 (CLAUDE.md 8절)."""
    return FileResponse(STATIC / "chat.html", media_type="text/html; charset=utf-8")


@app.get("/health")
def health():
    s = get_settings()
    return {"status": "ok", "llm_provider": s.llm_provider, "llm_model": s.llm_model}


@app.get("/personas")
def list_personas():
    return [{"key": p.key, "name": p.name, "blurb": p.blurb, "enabled": p.enabled}
            for p in personas.listed()]


@app.get("/usage", response_model=UsageInfo)
def usage(authorization: str | None = Header(None, description="Bearer <Firebase ID 토큰>"),
          x_user_id: str | None = Header(None, description="기기 ID. 로그인 토큰이 없을 때만 쓴다")):
    """요금제와 오늘 쓴 질문 수. 세지 않고 읽기만 한다 — 앱 설정 화면의 "남은 사용량" 용 (2026-10-12)."""
    try:
        user_id = auth.resolve_user(authorization, x_user_id)
    except plans.InvalidUserId as e:
        raise HTTPException(400, str(e))
    except auth.AuthError as e:
        raise HTTPException(401, str(e))
    return plans.status(user_id).as_dict()


def _identity(authorization: str | None, x_user_id: str | None) -> tuple[str, str | None]:
    try:
        return auth.resolve(authorization, x_user_id)
    except plans.InvalidUserId as e:
        raise HTTPException(400, str(e))
    except auth.AuthError as e:
        raise HTTPException(401, str(e))


@app.get("/me", response_model=MeInfo)
def me(authorization: str | None = Header(None, description="Bearer <Firebase ID 토큰>"),
       x_user_id: str | None = Header(None, description="기기 ID. 로그인 토큰이 없을 때만 쓴다")):
    """요청한 사용자와 개발자 여부. 앱 설정 화면이 신고 내역 메뉴를 보일지 정한다 (2026-10-12)."""
    user_id, email = _identity(authorization, x_user_id)
    return {"user_id": user_id, "admin": auth.is_admin(user_id, email)}


@app.post("/reports")
def create_report(req: ReportRequest,
                  authorization: str | None = Header(None, description="Bearer <Firebase ID 토큰>"),
                  x_user_id: str | None = Header(None, description="기기 ID. 로그인 토큰이 없을 때만 쓴다")):
    """대화 신고 접수. 질문·답이 함께 저장된다 (사용자 결정 — 대화 내용 첨부)."""
    user_id, _ = _identity(authorization, x_user_id)
    try:
        personas.get(req.persona)
    except KeyError:
        raise HTTPException(404, f"페르소나 '{req.persona}' 를 찾을 수 없습니다.")
    rid = reports.add(user_id=user_id, persona=req.persona, reason=req.reason.strip(),
                      detail=(req.detail or "").strip() or None, question=req.question,
                      answer=req.answer, extra=req.extra)
    log.info("대화 신고 #%d (%s, %s)", rid, req.persona, req.reason)
    return {"id": rid}


@app.get("/reports")
def list_reports(authorization: str | None = Header(None, description="Bearer <Firebase ID 토큰>"),
                 x_user_id: str | None = Header(None, description="기기 ID. 로그인 토큰이 없을 때만 쓴다")):
    """신고 내역 (최근 200건). 개발자(ADMIN_USERS)만."""
    user_id, email = _identity(authorization, x_user_id)
    if not auth.is_admin(user_id, email):
        raise HTTPException(403, "신고 내역은 개발자만 볼 수 있습니다.")
    return reports.recent()


@app.post("/ask", response_model=AskResponse)
def ask(req: AskRequest,
        authorization: str | None = Header(None, description="Bearer <Firebase ID 토큰>. 로그인한 앱이 보낸다"),
        x_user_id: str | None = Header(None, description="기기 ID. 로그인 토큰이 없을 때만 쓴다 (AUTH_REQUIRED=false)")):
    try:
        user_id = auth.resolve_user(authorization, x_user_id)
    except plans.InvalidUserId as e:
        raise HTTPException(400, str(e))
    except auth.AuthError as e:
        raise HTTPException(401, str(e))

    # 하루 한도 (plans.py). LLM 을 부르기 전에 1건을 미리 세고, 답을 못 주면 돌려준다
    try:
        usage = plans.reserve(user_id)
    except plans.QuotaExceeded as e:
        # 한도에 걸려도 위기 신호가 명백하면 상담전화 안내는 준다 (LLM 호출 없음, 사용량에 안 셈)
        try:
            safe = rag.safety_only(req.persona, req.question)
        except KeyError:            # 없는·준비 중인 페르소나
            safe = None
        if safe is not None:
            log.info("한도 초과지만 안전 안내 반환 (user=%s)", user_id)
            return {**safe, "usage": e.usage.as_dict()}
        raise HTTPException(429, str(e))

    try:
        result = _answer(req)
    except HTTPException:
        plans.refund(user_id, usage.day)
        raise
    return {**result, "usage": usage.as_dict()}


def _answer(req: AskRequest) -> dict:
    """rag.answer 를 부르고 오류를 앱이 읽을 수 있는 HTTP 오류로 바꾼다."""
    try:
        return rag.answer(req.persona, req.question, req.top_k)
    except KeyError:
        raise HTTPException(404, f"페르소나 '{req.persona}' 를 찾을 수 없거나 아직 준비 중입니다.")
    except FileNotFoundError as e:
        raise HTTPException(503, str(e))
    except RuntimeError as e:
        raise HTTPException(500, str(e))
    except Exception as e:
        # LLM 프로바이더 오류(모델명 폐기, 할당량 초과, 503 등)를 앱이 읽을 수 있는 메시지로 돌려준다
        log.exception("LLM 호출 실패")
        raise HTTPException(502, f"LLM 호출 실패: {e}")
