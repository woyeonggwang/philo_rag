"""검색 -> 프롬프트 조립 -> LLM 호출."""
import logging

from langchain_core.messages import HumanMessage, SystemMessage

from . import personas, retriever
from .config import get_settings

log = logging.getLogger(__name__)

PASSAGE_TEMPLATE = """[구절 {n}] {work} {ref} ({title})
{text}"""

USER_TEMPLATE = """아래는 네가 쓴 글에서 이 질문과 관련이 있어 보이는 구절들이다.

{passages}

---

질문: {question}

위 구절에 담긴 생각을 바탕으로, 네 목소리로 한국어로 답하라.
구절을 그대로 번역해 옮기지 말고, 그 생각을 지금 이 사람에게 하는 말로 바꿔라."""

# 근거 구절이 하나도 없을 때. "가장 가까운 것을 꺼내라"고 시키면 모델이 학습 기억에서
# 코퍼스에 없는 내용(『즐거운 학문』 등)을 끌어와 지어낸다 (CLAUDE.md 6.9). 그래서 멈추게 한다.
NO_CONTEXT = """아래 질문에 대해 네 글에서 마땅한 구절을 찾지 못했다.

질문: {question}

한국어로 두세 문장 안에 짧게 답하라.

반드시 지킬 것:
- **네 저작을 인용하거나 "나는 ~라고 말했다"는 식의 구체적 주장을 하지 마라.**
  지금 네게 주어진 근거가 없다. 기억에 의존해 말하면 틀린 말을 하게 된다.
- 이 주제는 네가 다루지 않았다고 밝히고, 거기서 멈춰라.
- 투자·의료·법률처럼 실제 판단이 걸린 문제라면, 그것은 네가 답할 영역이 아니라고 분명히 말하라.
- 말투는 네 것을 유지하되, 길게 말하지 마라."""


def answer(persona_key: str, question: str, top_k: int | None = None) -> dict:
    s = get_settings()
    persona = personas.get(persona_key)

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

    from .llm import get_llm
    resp = get_llm().invoke([
        SystemMessage(content=persona.system),
        HumanMessage(content=user),
    ])

    return {
        "persona": persona_key,
        "persona_name": persona.name,
        "question": question,
        # langchain-core 1.x 는 content 가 블록 리스트로 올 수 있다. text 가 문자열만 합쳐 준다
        "answer": resp.text,
        "grounded": bool(kept),
        "sources": [{
            "work": h["work"],
            "ref": h["ref_start"] if h["ref_end"] == h["ref_start"]
                   else f"{h['ref_start']}~{h['ref_end']}",
            "title": h["division_title"] or None,
            "score": h["score"],
        } for h in kept],
    }
