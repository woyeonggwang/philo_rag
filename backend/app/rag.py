"""검색 -> 프롬프트 조립 -> LLM 호출."""
import logging
import re

from langchain_core.messages import HumanMessage, SystemMessage

from . import personas, retriever
from .config import get_settings

log = logging.getLogger(__name__)
_HANGUL = re.compile(r"[가-힣]")

PASSAGE_TEMPLATE = """[구절 {n}] {work} {ref} ({title})
{text}"""

USER_TEMPLATE = """아래는 네가 쓴 글에서 이 질문과 관련이 있어 보이는 구절들이다.

{passages}

---

질문: {question}

위 구절에 담긴 생각을 바탕으로, 네 목소리로 한국어로 답하라.
구절을 그대로 번역해 옮기지 말고, 그 생각을 지금 이 사람에게 하는 말로 바꿔라.
구절 속의 구체적인 이미지와 장면을 가져다 써라.

다시 말한다: 너는 {name} 본인이다. "{name}는", "{name}라면" 같은 3인칭 해설 없이, 1인칭 "나"로,
{name}의 말투로 답하라."""

# 자해·자살 암시. 모델에 맡기지 않고 코드가 잡는다 (CLAUDE.md 6.12).
# 로컬 8B 는 "자살을 말하면 109 를 안내하라"는 조건 규칙을 못 지켰다 — 주식 질문에도 109 를 붙이고,
# 정작 위기 문장에는 비유 뒤에 슬쩍 붙였다. 첫 문단은 사람이 쓴 고정 문구로 보장한다.
SAFETY_PATTERNS = re.compile(
    r"자살|자해|죽고\s*싶|죽어\s*버리|사라지고\s*싶|없어지고\s*싶|살기\s*싫|살아갈\s*자신|"
    r"살\s*이유가?\s*없|끝내고\s*싶|목숨을?\s*끊|뛰어내리|손목을?\s*긋")

SAFETY_NOTICE = """지금 많이 힘드신 것 같습니다. 이 이야기는 혼자 안고 있지 마시고, 믿을 수 있는 사람이나 전문가에게 꼭 말해 주세요.
자살예방 상담전화 109 (24시간, 무료) 로 전화하시면 지금 바로 이야기를 들어 줄 사람이 있습니다.
아래는 그 다음에 드리는 말입니다."""

SAFETY_TEMPLATE = """상대가 이렇게 말했다: "{question}"

상대가 지금 매우 힘든 상태다. 사람에게 도움을 청하라는 안내는 **이미 별도로 전달되었다.**
너는 그 안내 뒤에 이어질 짧은 말만 쓴다.

반드시 지킬 것:
- 상담전화, 전문가, 병원 이야기를 반복하지 마라. 이미 전달됐다.
- 두세 문장. 네 말투로. 상대가 지금 여기 있다는 것, 이 대화가 끝이 아니라는 것만 전하라.
- 죽음·고통을 미화하거나 "고통이 너를 강하게 만든다"는 식으로 말하지 마라. 되묻지도 마라.
- 한국어로. 1인칭 "나"로."""

# 근거 구절이 하나도 없을 때. "가장 가까운 것을 꺼내라"고 시키면 모델이 학습 기억에서
# 코퍼스에 없는 내용(『즐거운 학문』 등)을 끌어와 지어낸다 (CLAUDE.md 6.9). 그래서 멈추게 한다.
NO_CONTEXT = """아래 질문에 대해 네 글에서 마땅한 구절을 찾지 못했다.

질문: {question}

딱 두 문장으로 답하라. 이 주제는 내가 다룬 적이 없다고 말하고, 그것은 내 영역이 아니니 다른 곳에 물으라고 말하면 된다.
"첫 문장", "둘째 문장" 같은 표시를 붙이지 말고 그냥 문장만 써라.

절대 하지 말 것:
- 질문의 주제에 대해 어떤 조언·방법·비유·격려도 하지 마라. "먼저 ~하라", "~이 중요하다" 같은 문장이 하나라도 있으면 실패다.
- 네 저작을 인용하거나 "나는 ~라고 말했다"는 주장을 하지 마라. 지금 네게 주어진 근거가 없다.
- 상담전화나 전문가 이야기를 꺼내지 마라. 이 질문은 그런 상황이 아니다.

다시 말한다: 너는 {name} 본인이다. 1인칭 "나"로, {name}의 말투로, 두 문장만."""


def answer(persona_key: str, question: str, top_k: int | None = None) -> dict:
    s = get_settings()
    persona = personas.get(persona_key)

    hits = retriever.search(persona_key, question, top_k)
    kept = [h for h in hits if h["score"] >= s.min_score]
    log.info("[%s] 검색 %d개 중 %d개 채택 (최고 %.3f)",
             persona_key, len(hits), len(kept),
             hits[0]["score"] if hits else 0.0)

    safety = bool(SAFETY_PATTERNS.search(question))
    if safety:
        # 위기 문장은 검색 결과와 무관하게 안전 경로로. 근거 구절을 주면 모델이 거기서 죽음의 수사를 끌어온다
        user = SAFETY_TEMPLATE.format(question=question)
        kept = []
    elif kept:
        passages = "\n\n".join(
            PASSAGE_TEMPLATE.format(
                n=i,
                work=h["work"],
                ref=h["ref_start"] if h["ref_end"] == h["ref_start"]
                    else f"{h['ref_start']}~{h['ref_end']}",
                title=h["division_title"] or f"{h['division']}장",
                text=h["text"])
            for i, h in enumerate(kept, 1))
        user = USER_TEMPLATE.format(passages=passages, question=question, name=persona.name)
    else:
        user = NO_CONTEXT.format(question=question, name=persona.name)

    from .llm import get_llm
    resp = get_llm().invoke([
        SystemMessage(content=persona.system),
        HumanMessage(content=user),
    ])

    # langchain-core 1.x 는 content 가 블록 리스트로 올 수 있다. text 가 text 블록만 합쳐 준다 (사고 블록 제외)
    answer_text = resp.text.strip()
    finish = (resp.response_metadata or {}).get("finish_reason") \
        or (resp.response_metadata or {}).get("done_reason")
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
    if not answer_text or not _HANGUL.search(answer_text[:80]):
        # 한국어 답변이어야 하는데 첫 80자에 한글이 없다 = 사고 누출·영어 응답·빈 응답
        raise RuntimeError(f"답변 형식 이상 (한국어 아님): {answer_text[:120]!r}")

    if safety:
        answer_text = SAFETY_NOTICE + "\n\n" + answer_text
        log.info("[%s] 안전 경로", persona_key)

    return {
        "persona": persona_key,
        "persona_name": persona.name,
        "question": question,
        "answer": answer_text,
        "safety": safety,
        "grounded": bool(kept),
        "sources": [{
            "work": h["work"],
            "ref": h["ref_start"] if h["ref_end"] == h["ref_start"]
                   else f"{h['ref_start']}~{h['ref_end']}",
            "title": h["division_title"] or None,
            "score": h["score"],
        } for h in kept],
    }
