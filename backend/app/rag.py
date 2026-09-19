"""안전 판단 -> 검색 -> 프롬프트 조립 -> LLM 호출 -> 규칙 검사."""
import logging
import re

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage

from . import glossary, guard, personas, retriever
from .config import get_settings

log = logging.getLogger(__name__)
_HANGUL = re.compile(r"[가-힣]")

PASSAGE_TEMPLATE = """[구절 {n}] {work} {ref} ({title})
{text}"""

# 2026-09-19 전면 축소 (CLAUDE.md 6.19). 규칙은 시스템 프롬프트(personas.py)에 있다. 여기는 재료만 준다.
USER_TEMPLATE = """구절:
{passages}

질문: {question}"""

# 근거 구절이 하나도 없을 때. "가장 가까운 것을 꺼내라"고 시키면 학습 기억에서 지어낸다 (6.9). 멈추게 한다.
NO_CONTEXT = """질문: {question}

이 질문에 맞는 구절이 없다. 이 주제는 다룬 적이 없다고 한두 문장으로 말하고 멈춰라. 조언하지 마라."""

# ── 안전 분기 (CLAUDE.md 6.19) ──
# 1차: 정규식 — 명백한 표현은 호출 없이 잡는다 (빠르고 공짜).
# 2차: LLM 판단 — "삶이 고통스러운데 계속 살아야 할 이유가 있습니까?" 처럼 정규식이 못 잡는
#      위기 신호를 모델이 가린다. 위기면 검색을 건너뛰고 고정 안내 뒤에 짧은 말만 붙인다.
SAFETY_PATTERNS = re.compile(
    r"자살|자해|죽고\s*싶|죽어\s*버리|사라지고\s*싶|없어지고\s*싶|살기\s*싫|살아갈\s*자신|"
    r"살\s*이유가?\s*없|끝내고\s*싶|목숨을?\s*끊|뛰어내리|손목을?\s*긋")

CRISIS_PROMPT = """다음 메시지를 쓴 사람이 자해·자살을 생각하거나 삶을 포기하려는 위기 상태로 보이는가?
철학적·일반적 질문이면 "아니오". 본인의 위기가 비치면 "예". 확실하지 않으면 "예".
"예" 또는 "아니오" 한 단어로만 답하라.

메시지: {question}"""

SAFETY_NOTICE = """지금 많이 힘드신 것 같습니다. 이 이야기는 혼자 안고 있지 마시고, 믿을 수 있는 사람이나 전문가에게 꼭 말해 주세요.
자살예방 상담전화 109 (24시간, 무료) 로 전화하시면 지금 바로 이야기를 들어 줄 사람이 있습니다.
아래는 그 다음에 드리는 말입니다."""

SAFETY_TEMPLATE = """상대가 이렇게 말했다: "{question}"

도움을 청하라는 안내는 이미 전달됐다. 그 뒤에 이어질 두세 문장만 네 말투로 쓰라.
상대가 여기 있다는 것, 이 대화가 끝이 아니라는 것만 전하라. 상담전화·전문가 이야기는 반복하지 마라."""


def _is_crisis(question: str) -> tuple[bool, str]:
    """위기 여부와 판단 근거("regex" | "llm"). 정규식이 잡으면 호출 없이 끝낸다."""
    if SAFETY_PATTERNS.search(question):
        return True, "regex"
    from .llm import get_llm
    resp = get_llm().invoke([HumanMessage(content=CRISIS_PROMPT.format(question=question))])
    verdict = resp.text.strip()
    return verdict.startswith("예"), "llm"


def _invoke(persona_key, messages, s) -> str:
    """LLM 을 한 번 호출하고 본문만 돌려준다. 잘렸거나 한국어가 아니면 예외."""
    from .llm import get_llm
    resp = get_llm().invoke(messages)

    # langchain-core 1.x 는 content 가 블록 리스트로 올 수 있다. text 가 text 블록만 합쳐 준다 (사고 블록 제외)
    text = resp.text.strip()
    meta = resp.response_metadata or {}
    finish = meta.get("finish_reason") or meta.get("done_reason")
    usage = resp.usage_metadata or {}
    log.info("[%s] finish=%s in=%s out=%s%s", persona_key, finish,
             usage.get("input_tokens"), usage.get("output_tokens"),
             f" reasoning={usage['output_token_details'].get('reasoning')}"
             if usage.get("output_token_details") else "")

    # 사고 토큰이 한도를 다 먹어 본문이 잘리면(Gemini 3.x, CLAUDE.md 9.2 A1·E1) 잘린 조각이나
    # 사고 과정의 끝자락이 그대로 나간다. 그런 응답은 사용자에게 보내지 않는다.
    if str(finish).upper() in ("MAX_TOKENS", "LENGTH"):
        raise RuntimeError(
            f"답변이 토큰 한도({s.llm_max_tokens})에서 잘렸습니다. LLM_MAX_TOKENS 를 늘리거나 "
            f"LLM_THINKING_LEVEL 을 낮추세요. (finish_reason={finish})")
    if not text or not _HANGUL.search(text[:80]):
        # 한국어 답변이어야 하는데 첫 80자에 한글이 없다 = 사고 누출·영어 응답·빈 응답
        raise RuntimeError(f"답변 형식 이상 (한국어 아님): {text[:120]!r}")
    return text


def answer(persona_key: str, question: str, top_k: int | None = None) -> dict:
    s = get_settings()
    persona = personas.get(persona_key)

    # 안전 판단이 먼저다. 위기면 검색·근거 구절을 쓰지 않는다 (구절에서 죽음의 수사를 끌어올 수 있다)
    safety, how = _is_crisis(question)
    if safety:
        log.info("[%s] 안전 경로 (%s)", persona_key, how)
        kept = []
        user = SAFETY_TEMPLATE.format(question=question)
    else:
        hits = retriever.search(persona_key, question, top_k)
        kept = [h for h in hits if h["score"] >= s.min_score]
        log.info("[%s] 검색 %d개 중 %d개 채택 (최고 %.3f)",
                 persona_key, len(hits), len(kept),
                 hits[0]["score"] if hits else 0.0)
        if kept:
            passages = "\n\n".join(
                PASSAGE_TEMPLATE.format(
                    n=i,
                    work=h["work"],
                    ref=h["ref_start"] if h["ref_end"] == h["ref_start"]
                        else f"{h['ref_start']}~{h['ref_end']}",
                    title=h["division_title"] or f"{h['division']}장",
                    text=h["text"])
                for i, h in enumerate(kept, 1))
            user = USER_TEMPLATE.format(passages=passages, question=question)
        else:
            user = NO_CONTEXT.format(question=question)

    # 규칙 위반이면 무엇을 어겼는지 알려 주고 다시 쓰게 한다 (CLAUDE.md 6.13).
    messages = [SystemMessage(content=persona.system), HumanMessage(content=user)]
    retries = 0
    for attempt in range(s.max_retries + 1):
        answer_text = _invoke(persona_key, messages, s)
        violations = guard.check(persona_key, answer_text,
                                 grounded=bool(kept), safety=safety)
        if not violations:
            break
        if attempt == s.max_retries:
            log.warning("[%s] 재생성 후에도 위반: %s", persona_key, " / ".join(violations))
            break
        log.info("[%s] 규칙 위반 %d회차: %s", persona_key, attempt + 1, " / ".join(violations))
        retries += 1
        messages += [AIMessage(content=answer_text),
                     HumanMessage(content=guard.retry_message(violations))]

    if safety:
        answer_text = SAFETY_NOTICE + "\n\n" + answer_text

    return {
        "persona": persona_key,
        "persona_name": persona.name,
        "question": question,
        "answer": answer_text,
        "safety": safety,
        "grounded": bool(kept),
        "retries": retries,
        # 답변에 나온 경전 용어·호칭의 뜻. 앱이 각주로 보여준다 (glossary.py)
        "glossary": glossary.extract(persona_key, answer_text),
        "sources": [{
            "work": h["work"],
            "ref": h["ref_start"] if h["ref_end"] == h["ref_start"]
                   else f"{h['ref_start']}~{h['ref_end']}",
            "title": h["division_title"] or None,
            "score": h["score"],
        } for h in kept],
    }
