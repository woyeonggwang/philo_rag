"""LLM 프로바이더 팩토리.

.env 의 LLM_PROVIDER 하나로 교체할 수 있게 한다 (CLAUDE.md 2.2).
필요한 프로바이더의 패키지만 설치돼 있으면 된다.
"""
from functools import lru_cache

from .config import get_settings


@lru_cache(maxsize=1)
def get_llm():
    s = get_settings()
    p = s.llm_provider.lower()
    common = dict(temperature=s.llm_temperature)

    if p == "google":
        from langchain_google_genai import ChatGoogleGenerativeAI
        if not s.google_api_key:
            raise RuntimeError("GOOGLE_API_KEY 가 .env 에 없습니다.")
        # Gemini 는 사고(thinking) 토큰이 max_output_tokens 를 잠식한다. 기본 사고 수준이면
        # 1024 토큰이 사고에 다 쓰여 답변이 중간에 잘렸다 (2026-09-16 실측). 세대별로 파라미터가 다르다.
        thinking = {}
        if s.llm_thinking_level:
            thinking["thinking_level"] = s.llm_thinking_level.upper()
        if s.llm_thinking_budget is not None:
            thinking["thinking_budget"] = s.llm_thinking_budget
        return ChatGoogleGenerativeAI(
            model=s.llm_model, google_api_key=s.google_api_key,
            max_output_tokens=s.llm_max_tokens,
            thinking_config=thinking or None,
            **common)

    if p == "openai":
        # gpt-5.6 계열(sol/terra/luna)은 추론 모델이라 기본값 medium 이면 보이지 않는 사고 토큰이
        # 출력 요금으로 청구된다. reasoning_effort="none" 으로 끈다 (CLAUDE.md 6.18).
        # max_tokens 는 langchain-openai 가 max_completion_tokens 로 자동 변환한다.
        from langchain_openai import ChatOpenAI
        if not s.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY 가 .env 에 없습니다.")
        return ChatOpenAI(model=s.llm_model, api_key=s.openai_api_key,
                          max_tokens=s.llm_max_tokens,
                          reasoning_effort=s.openai_reasoning_effort, **common)

    if p == "groq":
        # Groq 도 OpenAI 호환이다. 무료 티어에 카드가 필요 없고 추론이 매우 빠르다 (CLAUDE.md 6.15).
        # 한도는 요청 수가 아니라 토큰 수가 먼저 걸린다 — 하루 20만 토큰 / 우리 호출 평균 3,093 토큰.
        from langchain_openai import ChatOpenAI
        if not s.groq_api_key:
            raise RuntimeError("GROQ_API_KEY 가 .env 에 없습니다.")
        return ChatOpenAI(model=s.llm_model, api_key=s.groq_api_key,
                          base_url="https://api.groq.com/openai/v1",
                          max_tokens=s.llm_max_tokens, **common)

    if p == "openrouter":
        # OpenRouter 는 OpenAI 호환 API 다. base_url 만 바꾸면 된다.
        from langchain_openai import ChatOpenAI
        if not s.openrouter_api_key:
            raise RuntimeError("OPENROUTER_API_KEY 가 .env 에 없습니다.")
        return ChatOpenAI(model=s.llm_model, api_key=s.openrouter_api_key,
                          base_url="https://openrouter.ai/api/v1",
                          max_tokens=s.llm_max_tokens, **common)

    if p == "anthropic":
        from langchain_anthropic import ChatAnthropic
        if not s.anthropic_api_key:
            raise RuntimeError("ANTHROPIC_API_KEY 가 .env 에 없습니다.")
        return ChatAnthropic(model=s.llm_model, api_key=s.anthropic_api_key,
                             max_tokens=s.llm_max_tokens, **common)

    if p == "ollama":
        # 로컬 GPU 추론. API 키·할당량이 없어 회귀 테스트를 무제한으로 돌릴 수 있다.
        # 한국어 문체는 클라우드 모델보다 떨어지므로 페르소나 최종 판정에는 쓰지 않는다.
        from langchain_ollama import ChatOllama
        return ChatOllama(model=s.llm_model, base_url=s.ollama_base_url,
                          num_ctx=s.ollama_num_ctx, num_predict=s.llm_max_tokens,
                          keep_alive=s.ollama_keep_alive,
                          reasoning=s.ollama_reasoning, **common)

    raise RuntimeError(f"모르는 LLM_PROVIDER: {s.llm_provider}")
