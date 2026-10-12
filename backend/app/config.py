"""환경 설정. 전부 backend/.env 에서 읽는다. 코드에 키를 넣지 않는다."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND / ".env", env_file_encoding="utf-8", extra="ignore")

    # LLM
    llm_provider: str = "google"          # google | groq | openai | openrouter | anthropic | ollama
    llm_model: str = "gemini-3.6-flash"   # .env 가 항상 덮어쓴다. 3.8 은 하루 20요청이라 쓰지 않는다 (6.10)
    llm_temperature: float = 0.0          # 6.16: 0 이 길이·규칙 준수에 유리. 창작은 온도로 안 줄어든다
    # 근거 구절이 없을 때 "직접 다룬 문제가 아니다" + 찬반 양쪽을 말하는 답변의 온도 (2026-10-12 사용자 결정, CLAUDE.md 6.21)
    llm_temperature_open: float = 0.7
    llm_max_tokens: int = 4096           # Gemini 는 사고 토큰도 이 한도에 포함된다. 2048 은 잘렸다 (9.2)
    # Gemini 사고(thinking) 제어. 둘 다 비어 있으면 모델 기본값을 쓴다.
    #   3.x 계열: llm_thinking_level = low | medium | high  (3.8-flash 는 minimal 거부)
    #   2.5 계열: llm_thinking_budget = 0(끔) | -1(자동) | 토큰 수
    llm_thinking_level: str = ""
    llm_thinking_budget: int | None = None

    # 로컬 LLM (Ollama). 테스트 전용 — 배포 모델이 아니다 (CLAUDE.md 6.11)
    ollama_base_url: str = "http://localhost:11434"
    ollama_num_ctx: int = 8192            # 기본 4096 은 구절 5개(≈3,500토큰) + 답변에 빠듯하다
    ollama_keep_alive: str = "30m"        # 요청 사이에 모델을 VRAM 에서 내리지 않게
    # qwen3.5 같은 사고(thinking) 모델은 기본값이면 num_predict 를 사고에 다 쓰고 본문이 잘린다.
    # 페르소나 답변에 사고 과정은 필요 없다. None 이면 모델 기본 동작 (CLAUDE.md 6.14)
    ollama_reasoning: bool | None = False

    google_api_key: str = ""
    groq_api_key: str = ""

    # OpenAI gpt-5.6 계열은 추론 모델이다. 기본값 medium 이면 사고 토큰이 출력 요금으로 청구된다.
    # "none" 이면 추론이 꺼지고, 동시에 temperature 를 쓸 수 있게 된다
    # (추론이 켜져 있으면 gpt-5 계열은 temperature=1 로 고정된다). CLAUDE.md 6.18
    # gpt-5 계열에만 보낸다. 빈 값이면 파라미터 자체를 보내지 않는다 (gpt-4o 계열은 이 파라미터를 모른다)
    openai_reasoning_effort: str = "none"   # none | low | medium | high | xhigh | max | (빈 값)
    openai_api_key: str = ""
    openrouter_api_key: str = ""
    anthropic_api_key: str = ""

    # 임베딩
    embedding_model: str = "BAAI/bge-m3"
    embedding_device: str = "cuda"
    # fp16 으로 올리면 VRAM 이 2.4GB -> 1.2GB 로 줄어 그만큼 LLM 에 쓸 수 있다 (CLAUDE.md 6.14).
    # 검색 점수 차이는 소수점 셋째 자리 수준이라 인덱스를 다시 만들 필요가 없다.
    embedding_dtype: str = "float16"      # float16 | float32

    # 경로
    index_dir: Path = BACKEND / "data" / "index"

    # 규칙 위반 시 재생성 횟수 (CLAUDE.md 6.13). 0 이면 검사만 하고 재생성하지 않는다
    max_retries: int = 3

    # 검색
    top_k: int = 5
    min_score: float = 0.45               # 이보다 낮으면 근거 없음으로 본다 (2026-09-16 실측: 관련 0.49+, 무관 0.40-)

    # 요금제 (plans.py). 로그인이 없어 모든 사용자가 이 요금제를 받는다.
    # 테스트 단계라 pro(무제한). personal 로 바꾸면 하루 5건 제한이 걸린다
    default_plan: str = "pro"             # personal | pro
    usage_db: Path = BACKEND / "data" / "usage.db"   # 사용자·날짜별 질문 수 (gitignore)

    # 로그인 (auth.py). Firebase 프로젝트 ID 로 앱이 보낸 로그인 토큰을 검증한다
    firebase_project_id: str = ""
    # true 면 로그인 토큰 없는 /ask 를 401 로 막는다. Firebase 설정 전·개발 중에는 false (기기 ID 로 센다)
    auth_required: bool = False

    # 서버
    host: str = "0.0.0.0"
    port: int = 8000


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    if not s.index_dir.is_absolute():
        s.index_dir = BACKEND / s.index_dir
    if not s.usage_db.is_absolute():
        s.usage_db = BACKEND / s.usage_db
    return s
