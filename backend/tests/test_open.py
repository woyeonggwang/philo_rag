"""근거 구절이 없을 때의 찬반 답변과 사이비 질문 경로 (2026-10-12, CLAUDE.md 6.21).
LLM 은 가짜다 — API 호출 없음 (CLAUDE.md 2.3). 임베딩·인덱스는 실제로 로딩한다.

실행: backend 폴더에서  python -m pytest tests -q
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import llm, personas, rag, retriever  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402

# 예수 말투 규칙(guard)을 지키는 가짜 답변
PRO_CON = ("만물이 자라고 변하는 것도 아버지께서 정하신 질서 안에 있다고 보는 이가 있느니라. "
           "그러나 사람이 흙에서 우연히 났다는 말은 하늘의 뜻과 어긋난다고 보는 이도 있느니라.")
WARN = "거짓 선지자들을 삼가라. 양의 옷을 입고 오나 속은 노략질하는 이리니라."
NO_WARN = "양의 옷을 입고 오는 자를 조심하라. 그 열매로 그들을 알리라."


class _Resp:
    def __init__(self, text):
        self.text = text
        self.response_metadata = {"finish_reason": "stop"}
        self.usage_metadata = {"input_tokens": 1, "output_tokens": 1}


class FakeLLM:
    """답변을 차례로 돌려준다. 답변 호출마다 온도와 마지막 사용자 메시지를 기록한다."""

    def __init__(self, answers, label="가르침"):
        self.answers = list(answers)
        self.label = label          # 분류 호출(위기/미혹/일반)에 돌려줄 답
        self.classified = 0
        self.temps, self.prompts = [], []
        self._temp = None

    def at(self, temperature=None):
        self._temp = temperature
        return self

    def invoke(self, messages):
        content = messages[-1].content
        if content.startswith("다음은 ") and "여섯 가지" in content:    # 질문 분류 (위기·미혹·행적·가르침·토론·잡담)
            self.classified += 1
            return _Resp(self.label)
        self.temps.append(self._temp)
        self.prompts.append(messages[1].content)
        return _Resp(self.answers.pop(0))


@pytest.fixture
def fake(monkeypatch):
    def make(*answers, label="가르침"):
        f = FakeLLM(answers, label)
        monkeypatch.setattr(llm, "get_llm", f.at)
        return f
    return make


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def _ask(client, persona, question):
    r = client.post("/ask", json={"persona": persona, "question": question})
    assert r.status_code == 200, r.text
    return r.json()


def test_every_persona_has_open_line_in_its_prompt():
    for p in personas.listed():
        assert p.open_line and p.open_line in p.system
        assert p.cult_line
        # 첫 문장에는 "찬반"이 없다 — 찬반이 필요 없는 질문도 있다 (포켓몬, 2026-10-12)
        assert "찬반" not in p.open_line
        # 자기 삶·행적을 묻는 질문에는 "가르친 바가 아니니라"를 쓰지 않는다 (십자가의 무게, 2026-10-12)
        assert "네 삶과 행적을 물으면 네가 겪은 일로 답한다" in p.system
        # 첫 문장을 붙일지는 코드가 정한다 — 모델은 먼저 쓰지 않는다 (B안, 2026-10-14)
        assert "네가 먼저 하지 않는다" in p.system


def test_debate_opens_with_fixed_line_then_world_vs_me(client, fake, monkeypatch):
    """분류가 "토론"이면 코드가 첫 문장을 붙이고 "세상은 … 그러나 나는" 으로 (B안)."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [])      # 맞는 구절 없음
    f = fake(PRO_CON, label="토론")
    body = _ask(client, "jesus", "진화론에 대해서 어떻게 생각하세요")
    opener = personas.get("jesus").open_line
    assert body["answer"] == opener + " " + PRO_CON                   # 첫 문장은 코드가 붙인다
    assert "공생애" in opener
    assert body["grounded"] is False and body["sources"] == []
    assert f.temps == [get_settings().llm_temperature_open]           # 온도를 올려 부른다
    assert "그러나 나는" in f.prompts[0] and "가까운 구절" not in f.prompts[0]   # 세상의 생각 → 나의 가르침


def test_debate_retries_when_model_repeats_the_opener(client, fake, monkeypatch):
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [])
    opener = personas.get("jesus").open_line
    fake(opener + " " + PRO_CON, PRO_CON, label="토론")
    body = _ask(client, "jesus", "진화론에 대해서 어떻게 생각하세요")
    assert body["retries"] == 1
    assert body["answer"].count(opener) == 1


def test_cult_question_answers_with_false_prophet_passages(client, fake, monkeypatch):
    def no_search(*a, **k):
        raise AssertionError("사이비 질문은 검색하지 않고 고정 구절을 쓴다")
    monkeypatch.setattr(retriever, "search", no_search)
    f = fake(NO_WARN, WARN)                     # 처음엔 "거짓 선지자"가 빠져 다시 쓰게 한다
    body = _ask(client, "jesus", "이만희는 재림 예수입니까?")
    assert body["answer"] == WARN
    assert body["retries"] == 1
    assert body["grounded"] is True
    assert {s["work_ko"] for s in body["sources"]} >= {"마태복음", "마가복음"}
    assert any("7:" in s["ref"] for s in body["sources"])            # 마 7:15
    assert any(s["ref"].startswith("24:") for s in body["sources"])  # 마 24:23~24
    assert '"거짓 선지자들을 삼가라"고 분명히 말하라' in f.prompts[0]
    assert "찬반을 나누지 마라" in f.prompts[0]
    assert f.temps == [None, None]                                   # 온도는 평소대로


def test_cult_passages_for_nietzsche_and_buddha():
    q = "신천지에 대해 어떻게 생각하세요"
    z = [c["text"] for c in retriever.find("nietzsche", rag.CULT_NEEDLES["nietzsche"], q)]
    assert any("lose me and find yourselves" in t for t in z)
    b = [c["text"] for c in retriever.find("buddha", rag.CULT_NEEDLES["buddha"], q)]
    assert b and all("oral transmission" in t for t in b)


@pytest.mark.parametrize("q, hit", [
    ("이만희는 재림 예수입니까?", True),
    ("신천지에 대해 어떻게 생각하세요", True),
    ("JMS 정명석은 어떤 사람인가요", True),
    ("통일교는 어떻습니까", True),
    ("하나님의 교회란 무엇입니까", False),       # 일반 신학 질문은 걸리지 않게
    ("가정에 연합이 필요합니다", False),
    ("진화론에 대해서 어떻게 생각하세요", False),
])
def test_cult_patterns(q, hit):
    assert bool(rag.CULT_PATTERNS.search(q)) is hit


def test_claim_without_a_name_is_caught_by_the_classifier(client, fake, monkeypatch):
    """이름 없이 "이분이 선지자입니까" 하고 묻는 것은 분류 호출의 "미혹"이 잡는다 (사용자 지적 2026-10-12)."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: pytest.fail("검색하면 안 된다"))
    f = fake(WARN, label="미혹")
    body = _ask(client, "jesus", "우리 교회 목사님 설교를 들어 보니 이분이 선지자 같은데 맞습니까?")
    assert body["answer"] == WARN and body["grounded"] is True
    assert "찬반을 나누지 마라" in f.prompts[0]
    assert f.classified == 1                                         # 위기 판단과 같은 한 번의 호출


def test_crisis_wins_over_cult(client, fake):
    """위기 신호가 있으면 사이비 이름이 있어도 안전 경로가 먼저다."""
    f = fake("너는 혼자가 아니니라. 이 밤이 끝이 아니니라.", label="위기")
    body = _ask(client, "jesus", "신천지에서 나왔는데 이제 아무것도 남지 않았습니다")
    assert body["safety"] is True and body["sources"] == []
    assert body["answer"].startswith(rag.SAFETY_NOTICE)
    assert f.classified == 1


def test_ordinary_prophet_question_stays_normal(client, fake, monkeypatch):
    """분류가 미혹이 아니면(세례 요한 같은 성경 속 인물) 보통 검색 경로다."""
    called = {}
    def search(*a, **k):
        called["search"] = True
        return []
    monkeypatch.setattr(retriever, "search", search)
    fake(PRO_CON)
    _ask(client, "jesus", "세례 요한은 선지자입니까?")
    assert called.get("search")


def _hit(ref, score, text):
    a, b = ref.split("~") if "~" in ref else (ref, ref)
    return {"chunk_id": f"jesus#{ref}", "work": "THE GOSPEL ACCORDING TO MARK", "ref_start": a, "ref_end": b,
            "division": 8, "division_title": "", "text": text, "score": score}


def test_low_but_relevant_passages_go_to_the_normal_path(client, fake, monkeypatch):
    """0.40 이상이면 보통 경로로 구절을 준다. 「바람직한 삶」(0.448)이 기준선 0.45 에 걸려 근거 없음으로 빠졌던 것 (2026-10-12)."""
    hits = [_hit("6:17~6:31", 0.448, "lay up for yourselves treasures in heaven"),
            _hit("6:32~6:44", 0.429, "seek ye first the kingdom of God"),
            _hit("5:1~5:20", 0.380, "unclean spirit")]
    monkeypatch.setattr(retriever, "search", lambda *a, **k: hits)
    f = fake(PRO_CON)
    body = _ask(client, "jesus", "바람직한 삶이란 무엇이라고 생각하십니까?")
    p = f.prompts[0]
    assert p.startswith("구절:") and "treasures in heaven" in p and "kingdom of God" in p
    assert "unclean spirit" not in p                     # 0.40 미만은 버린다
    assert "이 질문에 맞는 구절이 없다" not in p
    assert body["grounded"] is True and len(body["sources"]) == 2
    assert f.temps == [None]                             # 보통 경로의 온도


def test_chat_question_gets_opener_and_short_answer(client, fake, monkeypatch):
    """분류가 "잡담"이면 구절 없이, 코드가 첫 문장을 붙이고 찬반 없이 짧게 (B안)."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [_hit("22:1~22:14", 0.442, "a marriage for his son")])
    opener = personas.get("jesus").open_line
    f = fake("나는 사람이 만든 것보다 하늘의 뜻을 귀히 여기라 하리라.", label="잡담")
    body = _ask(client, "jesus", "좋아하는 포켓몬이 뭔가요")
    assert body["answer"].startswith(opener)
    assert body["grounded"] is False and body["sources"] == []
    assert "찬반 없이 한두 문장으로" in f.prompts[0] and "marriage" not in f.prompts[0]
    assert f.temps == [get_settings().llm_temperature_open]


def test_teaching_question_never_opens_with_not_taught(client, fake, monkeypatch):
    """분류가 "가르침"인데 모델이 "가르친 바가 아니니라"로 시작하면 다시 쓰게 한다 — 「바람직한 삶」 (30문항 평가 J04)."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [_hit("6:17~6:31", 0.448, "treasures in heaven")])
    opener = personas.get("jesus").open_line
    good = "먼저 하나님의 나라와 그의 의를 구하라. 하늘에 보물을 쌓으라."
    fake(opener + " " + good, good, label="가르침")
    body = _ask(client, "jesus", "바람직한 삶이란 무엇이라고 생각하십니까?")
    assert body["answer"] == good and body["retries"] == 1
    assert body["grounded"] is True and body["sources"]


def test_teaching_question_uses_nearest_passages_even_below_threshold(client, fake, monkeypatch):
    """그 사람의 주제라고 분류됐으면 0.40 미만이라도 가장 가까운 구절 3개로 답한다."""
    hits = [_hit(f"{i}:1~{i}:9", 0.39 - i / 100, f"passage {i}") for i in range(1, 6)]
    monkeypatch.setattr(retriever, "search", lambda *a, **k: hits)
    f = fake(PRO_CON, label="가르침")
    body = _ask(client, "jesus", "인생의 의미는 무엇입니까?")
    p = f.prompts[0]
    assert p.startswith("구절:") and "passage 1" in p and "passage 3" in p and "passage 4" not in p
    assert body["grounded"] is True and len(body["sources"]) == 3
    assert f.temps == [None]


def test_history_question_answers_as_lived_experience(client, fake, monkeypatch):
    """분류가 "행적"이면 겪은 일로 답하라는 말을 붙인다 — 「십자가를 지고 가실 때」 (30문항 평가 J06)."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [_hit("27:27~27:44", 0.52, "Simon by name: him they compelled to bear his cross")])
    f = fake("구레네 사람 시몬이 내 십자가를 지고 따랐느니라.", label="행적")
    body = _ask(client, "jesus", "십자가를 지고 가실 때 어떠셨습니까?")
    assert "네가 겪은 일로 1인칭으로 답하라" in f.prompts[0]
    assert "기록·책·성경에 무엇이 적혔는지를 말하지 마라" in f.prompts[0]
    assert body["grounded"] is True and not body["answer"].startswith(personas.get("jesus").open_line)


def test_debate_gets_near_passages_hidden_from_sources(client, fake, monkeypatch):
    """토론에는 0.40 이상 구절을 "가까운 구절"로 주되 근거로 보이지 않는다 — 피터 틸 질문 (6.21)."""
    monkeypatch.setattr(retriever, "search", lambda *a, **k: [_hit("8:35~8:38", 0.45, "whosoever will save his life shall lose it")])
    f = fake(PRO_CON, label="토론")
    body = _ask(client, "jesus", "피터 틸이 이 세상에서의 영생을 이루려고 한다는데 어떻게 보십니까?")
    assert "가까운 구절:" in f.prompts[0] and "save his life" in f.prompts[0]
    assert body["grounded"] is False and body["sources"] == []


@pytest.mark.parametrize("verdict, want", [
    ("행적", "행적"), ("가르침입니다", "가르침"), ("토론", "토론"), ("잡담", "잡담"), ("위기", "위기"), ("미혹", "미혹"),
    ("일반", "가르침"), ("모르겠다", "가르침"),     # 모르는 답은 가르침 — 답할 수 있는 질문을 놓치지 않게
])
def test_classify_labels(monkeypatch, verdict, want):
    seen = {}

    class _One:
        def invoke(self, messages):
            seen["prompt"] = messages[-1].content
            return _Resp(verdict)
    monkeypatch.setattr(llm, "get_llm", lambda *a, **k: _One())
    assert rag._classify("요즘 마음이 무겁습니다", "예수")[0] == want
    assert "예수에게 한 질문" in seen["prompt"]


def test_classify_cult_name_and_crisis_priority(monkeypatch):
    class _One:
        def __init__(self, v):
            self.v = v

        def invoke(self, messages):
            return _Resp(self.v)
    monkeypatch.setattr(llm, "get_llm", lambda *a, **k: _One("가르침"))
    assert rag._classify("신천지에 대해 어떻게 생각하세요", "니체") == ("미혹", "regex")
    monkeypatch.setattr(llm, "get_llm", lambda *a, **k: _One("위기"))
    assert rag._classify("신천지에서 나왔는데 이제 아무것도 남지 않았습니다", "예수")[0] == "위기"


def test_crisis_is_only_about_ones_own_life():
    """위기는 본인 생명에 관한 말일 때만 — 「돈 걱정으로 잠이 안 옵니다」에 109 안내가 나갔다 (사용자 결정 2026-10-14)."""
    assert "걱정·불면·스트레스·슬픔만으로는 위기가 아니다" in rag.CLASSIFY_PROMPT
    assert "자기 생명에 관한 말" in rag.CLASSIFY_PROMPT
    # 명백한 표현은 여전히 정규식이 호출 없이 잡는다
    for q in ["죽고 싶어요", "살기 싫습니다", "더 이상 살아갈 자신이 없습니다", "사라지고 싶어요"]:
        assert rag.SAFETY_PATTERNS.search(q)
    assert not rag.SAFETY_PATTERNS.search("돈 걱정으로 잠이 안 옵니다")
