"""환경 설정. 전부 backend/.env 에서 읽는다. 코드에 키를 넣지 않는다."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND / ".env", env_file_encoding="utf-8", extra="ignore")

    # LLM
    llm_provider: str = "google"          # google | openai | openrouter | anthropic | ollama
    llm_model: str = "gemini-3.8-flash"
    llm_temperature: float = 0.8          # 페르소나 답변이라 결정적일 필요가 없다
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

    google_api_key: str = ""
    openai_api_key: str = ""
    openrouter_api_key: str = ""
    anthropic_api_key: str = ""

    # 임베딩
    embedding_model: str = "BAAI/bge-m3"
    embedding_device: str = "cuda"

    # 경로
    index_dir: Path = BACKEND / "data" / "index"

    # 검색
    top_k: int = 5
    min_score: float = 0.45               # 이보다 낮으면 근거 없음으로 본다 (2026-09-16 실측: 관련 0.49+, 무관 0.40-)

    # 서버
    host: str = "0.0.0.0"
    port: int = 8000


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    if not s.index_dir.is_absolute():
        s.index_dir = BACKEND / s.index_dir
    return s
