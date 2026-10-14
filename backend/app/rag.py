"""질문 분류(위기·미혹·행적·가르침·토론·잡담) -> 검색 -> 프롬프트 조립 -> LLM 호출 -> 규칙 검사."""
import logging
import re

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage

from . import concepts, glossary, guard, personas, retriever, works
from .config import get_settings

log = logging.getLogger(__name__)
_HANGUL = re.compile(r"[가-힣]")

PASSAGE_TEMPLATE = """[구절 {n}] {work} {ref} ({title})
{text}"""

# 2026-09-19 전면 축소 (CLAUDE.md 6.19). 규칙은 시스템 프롬프트(personas.py)에 있다. 여기는 재료만 준다.
USER_TEMPLATE = """구절:
{passages}

질문: {question}"""

# 근거 구절이 하나도 없을 때 (2026-10-12 사용자 결정으로 바꿈, CLAUDE.md 6.21).
# 예전엔 "다룬 적 없다"로 멈췄다(6.9) — 비용은 드는데 답을 못 들었다. 이제는 "직접 다룬 문제가 아니다"라는
# 첫 문장(personas.open_line)을 코드가 그대로 붙여 지어낸 말이 아님을 먼저 밝힌다. 온도는 settings.llm_temperature_open.
# 처음엔 "찬성 하나·반대 하나"를 시켰더니 예수가 "이 세상의 영생"을 선하다 하는, 교리와 정면으로 어긋나는 쪽까지 편들었다.
# 그래서 (사용자 결정 2026-10-12)
#  ① 반대편은 "세상 사람들의 생각"으로 소개하고 "그러나 나는"으로 자기 가르침을 말하게 한다
#    (마 5:21 "너희가 들었으나 나는 너희에게 이르노니" 꼴. 니까야의 "어떤 사문·바라문들은 … 그러나 나는" 도 같은 꼴)
#  ② 첫 문장을 붙일지는 처음엔 모델이 판단했다(A안) — 30문항 평가에서 예수가 「바람직한 삶」「십자가를 지고 가실 때」에도
#    "가르친 바가 아니니라"로 시작했다. 그래서 **분류 호출이 질문 종류를 정하고 코드가 결정한다** (B안, 사용자 결정 2026-10-14, CLAUDE.md 6.23).
#    토론·잡담에만 코드가 첫 문장을 붙이고 온도를 올린다. 행적·가르침에서는 모델이 그 말을 쓰면 다시 쓰게 한다.
DEBATE_TEMPLATE = """{near}질문: {question}

이 질문은 네가 직접 다룬 문제가 아니다. "직접 다룬 문제가 아니다"라는 첫 문장은 이미 앞에 붙는다. 다시 쓰지 말고 바로 이어서,
세상 사람들의 생각을 먼저 말하고, "그러나 나는"으로 네 가르침에 비춘 생각을 말하라. "그러나 나는"은 한 번만 쓴다.
네 가르침과 어긋나는 생각을 네 것으로 말하지 마라. {near_rule}있지도 않은 네 말을 인용하지 마라. 구체적인 투자·의료·법률 지시는 하지 마라."""

# 토론에는 0.40 이상 구절 최대 3개를 "가까운 구절"로 준다 — 피터 틸 영생 질문에 막 8:35~36 이 답의 중심이 됐다 (6.21).
# 근거로 보이지는 않는다 (sources 에 안 넣음 — 앱이 "직접 다루지 않은 질문"과 출처를 같이 띄우게 되므로)
NEAR_BLOCK = """가까운 구절:
{passages}

"""
NEAR_RULE = "가까운 구절 가운데 질문과 맞는 것이 있으면 그 뜻에 기대라. 맞지 않는 구절은 쓰지 마라. "

CHAT_TEMPLATE = """질문: {question}

이 질문은 취향이나 잡담이다. "직접 다룬 문제가 아니다"라는 첫 문장은 이미 앞에 붙는다. 다시 쓰지 말고 바로 이어서,
찬반 없이 한두 문장으로 짧게, 네 생각이 드러나게 답하라."""

# 행적 — 자기 삶을 남의 기록처럼 말했다 ("성경은 그 무게를 밝히지 아니하였느니라", "성경에 기록되어 있지 아니하니라")
HISTORY_NOTE = """

이 질문은 네가 살면서 겪은 일을 묻는다. 네가 겪은 일로 1인칭으로 답하라.
구절에 없는 세부는 지어내지 말고 아는 만큼만 말하라. 기록·책·성경에 무엇이 적혔는지를 말하지 마라."""

# ── 사이비·이단 (2026-10-12 사용자 결정) ──
# 이런 질문은 찬반을 나누지 않고 무조건 경계하게 한다. 근거 구절은 검색이 아니라 문구로 고른다
# (한국어 질문으로는 마 7:15 가 상위에 안 올라온다. retriever.find).
# 1차: 이름 목록(정규식, 공짜). 2차: "OO가 재림 예수입니까", "OO의 설교를 들어 보니 선지자입니까" 처럼
#      이름 없이 묻는 것은 분류 호출(CLASSIFY_PROMPT 의 "미혹")이 잡는다. 위기 판단과 한 번에 묻기 때문에 호출이 늘지 않는다.
CULT_PATTERNS = re.compile(
    r"이만희|신천지|정명석|JMS|기독교복음선교회|안상홍|장길자|하나님의교회\s*세계복음선교협회|"
    r"문선명|한학자|통일교|통일\s*가정연합|유병언|구원파|이재록|만민중앙|신옥주|은혜로\s*교회", re.I)

CULT_NEEDLES = {
    # 마 7:15 / 24:23 "보라 그리스도가 여기 있다 하여도 믿지 말라" / 24:24 / 막 13:21~22
    "jesus": ["Beware of false prophets", "Lo, here is Christ", "false Christs"],
    "nietzsche": ["lose me and find yourselves", 'pronounced "holy."'],  # 차라투스트라 「베푸는 덕」, 이 사람을 보라 「나는 왜 운명인가」 1
    "buddha": ["don't go by oral transmission"],                       # 깔라마경
}

CULT_NOTE = """

이 질문은 어떤 사람이나 단체를 재림주·선지자·구원자로 믿고 따르는 일에 관한 것이다. 찬반을 나누지 마라.
위 구절로 {cult_line}"""

# ── 안전 분기 (CLAUDE.md 6.19) ──
# 1차: 정규식 — 명백한 표현은 호출 없이 잡는다 (빠르고 공짜).
# 2차: LLM 판단 — "삶이 고통스러운데 계속 살아야 할 이유가 있습니까?" 처럼 정규식이 못 잡는
#      위기 신호를 모델이 가린다. 위기면 검색을 건너뛰고 고정 안내 뒤에 짧은 말만 붙인다.
# 2026-10-12: 같은 호출에서 "미혹"(재림주·선지자 판별 질문)도 함께 가린다 (CLAUDE.md 6.21). 위기가 언제나 먼저다.
# 2026-10-14: 질문 종류(행적·가르침·토론·잡담)도 같은 호출에서 정한다 (B안). 위기는 **본인 생명에 관한 말**로 좁혔다 —
#   「돈 걱정으로 잠이 안 옵니다」에 109 안내가 나갔다 (사용자 결정: 죽음·살기 싫다처럼 생명을 직접 말할 때만, 단순 걱정은 제외)
SAFETY_PATTERNS = re.compile(
    r"자살|자해|죽고\s*싶|죽어\s*버리|사라지고\s*싶|없어지고\s*싶|살기\s*싫|살아갈\s*자신|"
    r"살\s*이유가?\s*없|끝내고\s*싶|목숨을?\s*끊|뛰어내리|손목을?\s*긋")

CLASSIFY_PROMPT = """다음은 {name}에게 한 질문이다. 아래 여섯 가지 중 하나로 분류하라. 한 단어로만 답하라.
위기: 쓴 사람 본인이 죽고 싶다·살기 싫다·자해처럼 자기 생명에 관한 말을 한다. 걱정·불면·스트레스·슬픔만으로는 위기가 아니다. 자기 생명에 관한 말인데 확실하지 않으면 위기.
미혹: 어떤 사람이나 단체가 재림 예수·재림주·메시아·보혜사·선지자·구원자인지 묻거나, 그렇다고 하는 사람·단체를 믿고 따라도 되는지 묻는다. 성경 속 인물이 선지자인지, 예수의 재림 자체는 미혹이 아니다.
행적: {name} 본인이 살면서 겪은 일·한 일·느낀 것을 묻는다.
가르침: 삶·고통·사랑·용서·돈·죽음·믿음·마음처럼 {name}가 가르치거나 다룬 주제나 개념을 묻는다. 개인의 고민도 여기다.
토론: {name}가 다룰 수 없었던 현대·전문 주제로 의견이 갈리는 문제다 (과학 이론, 기술, 정치 등).
잡담: 취향·추천·일상 잡담·실용 정보를 묻는다.

질문: {question}"""

LABELS = ("위기", "미혹", "행적", "가르침", "토론", "잡담")

SAFETY_NOTICE = """지금 많이 힘드신 것 같습니다. 이 이야기는 혼자 안고 있지 마시고, 믿을 수 있는 사람이나 전문가에게 꼭 말해 주세요.
자살예방 상담전화 109 (24시간, 무료) 로 전화하시면 지금 바로 이야기를 들어 줄 사람이 있습니다.
아래는 그 다음에 드리는 말입니다."""

SAFETY_TEMPLATE = """상대가 이렇게 말했다: "{question}"

도움을 청하라는 안내는 이미 전달됐다. 그 뒤에 이어질 두세 문장만 네 말투로 쓰라.
상대가 여기 있다는 것, 이 대화가 끝이 아니라는 것만 전하라. 상담전화·전문가 이야기는 반복하지 마라."""


def _classify(question: str, name: str) -> tuple[str, str]:
    """(LABELS 중 하나, 판단 근거 "regex" | "llm"). 위기 정규식이 잡으면 호출 없이 끝낸다.
    사이비 이름 정규식이 잡혀도 분류는 부른다 — 위기 판단을 건너뛰지 않기 위해서다.
    모르는 답이 오면 "가르침" — 답할 수 있는 질문을 "다루지 않았다"로 놓치는 쪽이 더 나쁘다."""
    if SAFETY_PATTERNS.search(question):
        return "위기", "regex"
    from .llm import get_llm
    resp = get_llm().invoke([HumanMessage(content=CLASSIFY_PROMPT.format(question=question, name=name))])
    verdict = resp.text.strip()[:10]
    label = next((l for l in LABELS if l in verdict), "가르침")
    if label != "위기" and CULT_PATTERNS.search(question):
        return "미혹", "regex"
    return label, "llm"


def _declined(persona, text: str) -> bool:
    """모델이 "직접 다룬 문제가 아니다"(open_line 의 첫 문장)로 답을 시작했는가."""
    first = persona.open_line.split(".")[0]
    return text.lstrip().startswith(first)


def _passages(hits) -> str:
    return "\n\n".join(
        PASSAGE_TEMPLATE.format(
            n=i,
            work=h["work"],
            ref=retriever.ref_label(h),
            title=h["division_title"] or f"{h['division']}장",
            text=h["text"])
        for i, h in enumerate(hits, 1))


def _invoke(persona_key, messages, s, temperature=None) -> str:
    """LLM 을 한 번 호출하고 본문만 돌려준다. 잘렸거나 한국어가 아니면 예외."""
    from .llm import get_llm
    resp = (get_llm() if temperature is None else get_llm(temperature)).invoke(messages)

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


def safety_only(persona_key: str, question: str) -> dict | None:
    """하루 한도에 걸린 요청이라도 위기 신호가 명백하면(정규식) 상담전화 안내는 준다.
    LLM 을 부르지 않는 고정 문구뿐이라 비용이 없고, 사용량에도 세지 않는다 (plans.py, main.py).
    정규식에 안 걸리면 None — 한도 초과로 처리된다 (LLM 위기 판단은 호출 비용이 들어 하지 않는다)."""
    if not SAFETY_PATTERNS.search(question):
        return None
    persona = personas.get(persona_key)
    return {
        "persona": persona_key,
        "persona_name": persona.name,
        "question": question,
        "answer": SAFETY_NOTICE,
        "safety": True,
        "grounded": False,
        "retries": 0,
        "glossary": [],
        "sources": [],
    }


def answer(persona_key: str, question: str, top_k: int | None = None) -> dict:
    s = get_settings()
    persona = personas.get(persona_key)

    # 안전 판단이 먼저다. 위기면 검색·근거 구절을 쓰지 않는다 (구절에서 죽음의 수사를 끌어올 수 있다)
    label, how = _classify(question, persona.name)
    log.info("[%s] 분류: %s (%s)", persona_key, label, how)
    safety, cult = label == "위기", label == "미혹"
    open_ = False           # 토론·잡담 — 코드가 "직접 다룬 문제가 아니다"를 붙인다
    must = None             # 답변에 반드시 들어가야 할 말 (guard 가 확인)
    if safety:
        log.info("[%s] 안전 경로 (%s)", persona_key, how)
        kept = []
        user = SAFETY_TEMPLATE.format(question=question)
    else:
        if cult:
            hits = []
            kept = retriever.find(persona_key, CULT_NEEDLES[persona_key], question)
            log.info("[%s] 사이비 경로 (%s) — 고정 구절 %d개", persona_key, how, len(kept))
            if persona_key == "jesus":
                must = "거짓 선지자"
        else:
            # 한글 개념어("아모르파티", "열반")는 원어를 덧붙여 찾는다 (concepts.py). 모델에게는 원래 질문을 준다
            query = concepts.expand(persona_key, question)
            if query != question:
                log.info("[%s] 검색어 보강: %s", persona_key, query[len(question):].strip())
            hits = retriever.search(persona_key, query, top_k)
            kept = [h for h in hits if h["score"] >= s.min_score]
            log.info("[%s] 검색 %d개 중 %d개 채택 (최고 %.3f)",
                     persona_key, len(hits), len(kept),
                     hits[0]["score"] if hits else 0.0)
            if label in ("행적", "가르침") and not kept:
                kept = hits[:3]     # 그 사람의 주제라고 분류됐다 — 기준선 아래라도 가장 가까운 구절로 답하게 한다
            if label in ("토론", "잡담") or not kept:
                open_ = True
        if open_ and label == "잡담":
            user = CHAT_TEMPLATE.format(question=question)
        elif open_:
            near = kept[:3]
            user = DEBATE_TEMPLATE.format(
                near=NEAR_BLOCK.format(passages=_passages(near)) if near else "",
                near_rule=NEAR_RULE if near else "",
                question=question)
        elif not safety:
            user = USER_TEMPLATE.format(passages=_passages(kept), question=question)
            if cult:
                user += CULT_NOTE.format(cult_line=persona.cult_line)
            elif label == "행적":
                user += HISTORY_NOTE
        if open_:
            kept = []               # 토론·잡담은 근거로 보이지 않는다

    answer_text, retries = _generate(
        persona_key, persona, user, safety, s,
        temperature=s.llm_temperature_open if open_ else None,
        must_include=must,
        # 토론·잡담은 코드가 첫 문장을 붙이므로 또 쓰면 두 번 나온다. 행적·가르침에서는 아예 쓰면 안 된다 (B안)
        must_not_include=None if safety else persona.open_line.split(".")[0])

    if safety:
        answer_text = SAFETY_NOTICE + "\n\n" + answer_text
    elif open_:
        answer_text = persona.open_line + " " + answer_text
    elif kept and not cult and _declined(persona, answer_text):
        # 다시 쓰게 해도 모델이 끝내 "다루지 않았다"로 시작했다 — 앱에는 근거 구절 없음으로 보인다
        log.info("[%s] 재생성 뒤에도 '다루지 않았다'로 시작 — 근거 없음으로 표시", persona_key)
        kept = []

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
        # 앱은 work_ko + ref 로 "마태복음 3:1~3:15" 처럼 보여준다 (works.py). 본문은 보내지 않는다
        "sources": [{
            "chunk_id": h["chunk_id"],
            "work": h["work"],
            "work_ko": works.work_ko(h["work"]),
            "ref": retriever.ref_label(h),
            "title": h["division_title"] or None,
            "score": h["score"],
        } for h in kept],
    }


def _generate(persona_key, persona, user, safety, s, *, temperature=None,
              must_include=None, must_not_include=None) -> tuple[str, int]:
    """LLM 호출 + 규칙 검사 + 재생성. (답변 본문, 재생성 횟수)."""
    # 규칙 위반이면 무엇을 어겼는지 알려 주고 다시 쓰게 한다 (CLAUDE.md 6.13).
    messages = [SystemMessage(content=persona.system), HumanMessage(content=user)]
    retries = 0
    for attempt in range(s.max_retries + 1):
        answer_text = _invoke(persona_key, messages, s, temperature)
        violations = guard.check(persona_key, answer_text, safety=safety,
                                 must_include=must_include,
                                 must_not_include=must_not_include)
        if not violations:
            break
        if attempt == s.max_retries:
            log.warning("[%s] 재생성 후에도 위반: %s", persona_key, " / ".join(violations))
            break
        log.info("[%s] 규칙 위반 %d회차: %s", persona_key, attempt + 1, " / ".join(violations))
        retries += 1
        messages += [AIMessage(content=answer_text),
                     HumanMessage(content=guard.retry_message(violations))]
    return answer_text, retries
