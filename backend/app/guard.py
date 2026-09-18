"""생성된 답변이 페르소나 규칙을 지켰는지 검사한다.

왜 코드로 검사하는가 (CLAUDE.md 6.13):
로컬 8B 모델은 같은 프롬프트로도 실행마다 결과가 달라진다. 말투·1인칭·한국어 규칙을
지킬 때도 있고 안 지킬 때도 있다. 프롬프트를 더 손봐도 편차 자체는 없어지지 않는다.
그래서 지키는지를 **매번 확인**하고, 어겼으면 무엇을 어겼는지 알려 주고 다시 쓰게 한다.
안전 경로를 코드로 옮긴 것과 같은 접근이다.

검사만 하고 고치지는 않는다. 후처리로 문장을 바꾸면 근거와 어긋날 수 있다.
"""
import re

# 영어 단어. 규칙 2 — 답변 전체를 한국어로 쓴다.
# 원전 제목·인물명이 영어로 튀어나오는 것("Zarathustra의 웃음")을 잡는다.
_ENGLISH = re.compile(r"[A-Za-z]{2,}")

# 자기 자신을 3인칭으로 부르는 것. 규칙 1.
# 이름 자체는 허용한다("나는 니체다"). 뒤에 3인칭 조사·서술이 붙는 경우만 잡는다.
_THIRD_PERSON = {
    "nietzsche": re.compile(r"니체(라면|는\s|가\s|의\s|께서|도\s|에게|와\s같)"),
    "jesus": re.compile(r"예수(님|께서|는\s|가\s|의\s|와\s같)|그리스도(께서|는\s)"),
}

# 페르소나별 금지 어미. 문장 끝에서만 본다.
# (정규식, 무엇이 잘못인지, 어떻게 고칠지). 고치는 법을 같이 주지 않으면 8B 는 재생성해도 같은 실수를 반복한다.
_BANNED_ENDINGS = {
    # 니체: ~다/~라/~는가/~인가. 존댓말·구어체·옛문체 금지
    "nietzsche": [
        (re.compile(r"(습니다|읍니다|입니다|합니다|십니다)[.!?…\"']"), "존댓말",
         '"~습니다/~입니다"를 "~다"로 바꿔라'),
        (re.compile(r"(세요|해요|어요|아요|네요|군요|지요|죠)[.!?…\"']"), "~요체",
         '"~요"로 끝나는 문장을 "~다"로 바꿔라'),
        (re.compile(r"(거든|잖아|야|어\?|지\?)[.!?…\"']"), "구어체",
         '"~거든/~잖아/~야"를 "~다"로 바꿔라'),
        (re.compile(r"(느니라|나이다|하옵|더이다|노라)"), "옛 문체",
         '"~느니라/~하옵/~노라" 같은 옛 문체를 전부 "~다" 또는 "~하라"로 바꿔라. '
         '예: "약해지느니라" -> "약해진다", "명심하라니라" -> "명심하라"'),
    ],
    # 예수: 하십시오체만. ~요체·반말·옛문체 금지
    "jesus": [
        (re.compile(r"(요|죠)[.!?…\"']"), "~요체",
         '"~요/~죠"로 끝나는 문장을 "~십시오" 또는 "~입니다"로 바꿔라. '
         '예: "보세요" -> "보십시오", "힘들겠군요" -> "힘드실 것입니다"'),
        (re.compile(r"(구나|단다|거야|해라|이야)[.!?…\"']"), "반말",
         '반말을 "~십시오/~입니다"로 바꿔라. 예: "무겁구나" -> "무거우실 것입니다"'),
        (re.compile(r"(느니라|나이다|하옵|더이다|노라)"), "옛 문체",
         '"~느니라/~나이다" 같은 옛 문체를 "~입니다"로 바꿔라'),
        (re.compile(r"(보라|하라|기억하라|생각하라)[.!?…\"']"), "반말 명령형",
         '"~하라"를 "~하십시오"로 바꿔라. 예: "기억하라" -> "기억하십시오"'),
    ],
}

# 성경 장절·작품 인용 표기. 규칙 4 — 출처는 시스템이 따로 보여준다.
_CITATION = re.compile(r"\(\s*(마태복음|마태|마|차라투스트라)[^)]*\d+[:：]\d+[^)]*\)|\d+장\s*\d+절")

# 길이. 규칙 4 는 600자 이내지만 실측상 8B 는 거의 지키지 못한다.
# 너무 빡빡하면 재생성만 반복하므로 "명백히 길다" 선에서 자른다.
_MAX_CHARS = 1000
_MAX_PARAGRAPHS = 5

# 근거 없음(NO_CONTEXT) 경로는 두 문장이 목표다.
_NO_CONTEXT_MAX_CHARS = 260


def check(persona_key: str, text: str, *, grounded: bool, safety: bool) -> list[str]:
    """어긴 규칙을 한국어 설명으로 돌려준다. 빈 리스트면 통과."""
    bad: list[str] = []

    m = _ENGLISH.search(text)
    if m:
        bad.append(f'영어 단어를 썼다("{m.group(0)}"). 한국어 표기로 바꿔라')

    tp = _THIRD_PERSON.get(persona_key)
    if tp:
        m = tp.search(text)
        if m:
            bad.append(f'자기를 3인칭으로 불렀다("{m.group(0).strip()}"). 너가 본인이므로 "나"로 말하라')

    for pattern, label, howto in _BANNED_ENDINGS.get(persona_key, []):
        m = pattern.search(text)
        if m:
            bad.append(f'{label}를 썼다("{m.group(0)}"). {howto}')
            break           # 말투 지적은 하나면 충분하다

    m = _CITATION.search(text)
    if m:
        bad.append(f'출처 표기를 적었다("{m.group(0)}"). 장절 번호를 쓰지 마라')

    if safety:
        return bad          # 안전 경로는 길이를 따지지 않는다 (앞에 고정 문구가 붙는다)

    if not grounded:
        if len(text) > _NO_CONTEXT_MAX_CHARS:
            bad.append(f"너무 길다({len(text)}자). 두 문장으로만 답하라")
    else:
        if len(text) > _MAX_CHARS:
            bad.append(f"너무 길다({len(text)}자). 4문단 이내, 600자 정도로 줄여라")
        elif text.count("\n\n") + 1 > _MAX_PARAGRAPHS:
            bad.append("문단이 너무 많다. 4문단 이내로 줄여라")

    return bad


def retry_message(violations: list[str]) -> str:
    """재생성 지시. 무엇을 어겼는지 그대로 알려준다."""
    items = "\n".join(f"- {v}" for v in violations)
    return (f"방금 답변이 규칙을 어겼다:\n{items}\n\n"
            f"**내용과 구성은 그대로 두고 지적된 부분만 고쳐서** 답변 전체를 다시 써라.\n"
            f"특히 모든 문장의 끝을 하나하나 확인하라. 한 문장이라도 남아 있으면 실패다.\n"
            f"고쳤다는 설명이나 사과는 쓰지 말고 답변 본문만 써라.")
