"""FastAPI 서버.

앱은 {persona, question} 만 보낸다. 검색·프롬프트 조립·LLM 호출·API 키 보관은 전부 여기서 한다.
(CLAUDE.md 2.1 — 앱에 키를 넣지 않는 이유)

실행:
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
문서:
    http://localhost:8000/docs
"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import personas, rag, retriever
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
    # uvicorn 은 "http://0.0.0.0:8000" 을 찍는데, 0.0.0.0 은 바인드 주소라 브라우저로 열 수 없다 (ERR_ADDRESS_INVALID)
    log.info("준비 완료 — 문서: http://localhost:8000/docs")
    yield


app = FastAPI(title="철학 RAG API", version="0.1.0", lifespan=lifespan)

# 개발 단계에서는 에뮬레이터·실기기에서 바로 붙을 수 있게 열어둔다.
# 배포 전에 반드시 좁힐 것. (CLAUDE.md 10절 — 인증·사용량 제한 미설계)
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


class AskResponse(BaseModel):
    persona: str
    persona_name: str
    question: str
    answer: str
    grounded: bool
    safety: bool = False       # 자해·자살 암시가 감지돼 안전 안내가 앞에 붙었는지
    retries: int = 0           # 규칙 위반으로 다시 생성한 횟수 (CLAUDE.md 6.13)
    glossary: list[GlossaryItem] = []   # 답변 속 용어·호칭의 뜻. 각주용 (glossary.py)
    sources: list[Source]


@app.get("/health")
def health():
    s = get_settings()
    return {"status": "ok", "llm_provider": s.llm_provider, "llm_model": s.llm_model}


@app.get("/personas")
def list_personas():
    return [{"key": p.key, "name": p.name, "blurb": p.blurb, "enabled": p.enabled}
            for p in personas.listed()]


@app.post("/ask", response_model=AskResponse)
def ask(req: AskRequest):
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
