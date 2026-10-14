"""핵심 개념어 사전 — 검색할 때만 질문 뒤에 원어를 덧붙인다 (2026-10-12, 사용자 결정, CLAUDE.md 6.22).

한글 음차("아모르파티", "위버멘쉬")와 불교 한자어("열반", "사성제")로 물으면 BGE-M3 가 영어 코퍼스의 원어와 잘 잇지 못한다.
「아모르파티란 무엇인가요」는 amor fati 구절(이 사람을 보라 2:10)이 20위로 밀려 니체가 "책에서 다룬 문제가 아니다"라고 답했다.
질문 뒤에 "(amor fati)"를 붙이면 1위가 된다. 모델이 보는 질문은 그대로다 — 이것은 검색어에만 쓴다.

문장 전체를 영어로 번역하는 것과는 다르다 (그건 측정상 더 나빴다, CLAUDE.md 2.2). 개념어 몇 개만 덧붙인다.
원어는 코퍼스 번역본에 실제로 있는 표기다 (차라투스트라의 Superman, 도덕의 계보의 resentment, Sujato 역의 extinguishment).
각 항목은 「OO란 무엇입니까?」로 순위가 오르는 것을 확인한 것만 넣었다. 낱말 경계로 찾으므로 "무상"이 "무상으로"(공짜로)에는 걸리지 않는다.
"""
from .glossary import _word_boundary

CONCEPTS: dict[str, dict[str, str]] = {
    "nietzsche": {
        "아모르파티": "amor fati", "아모르 파티": "amor fati", "운명애": "amor fati",
        "위버멘쉬": "Superman", "위버멘슈": "Superman", "초인": "Superman",
        "영원회귀": "eternal recurrence", "영겁회귀": "eternal recurrence",
        "권력에의 의지": "will to power", "힘에의 의지": "will to power",
        "르상티망": "resentment",
        "니힐리즘": "nihilism", "허무주의": "nihilism",
        "주인 도덕": "master-morality", "노예 도덕": "slave-morality",
        "금욕주의적 이상": "ascetic ideal", "금욕적 이상": "ascetic ideal",
        "마지막 인간": "last man", "최후의 인간": "last man",
        "가치의 전도": "transvaluation", "가치 전환": "transvaluation",
        "신의 죽음": "God is dead",
        "거리의 파토스": "pathos of distance",
    },
    "buddha": {
        "열반": "extinguishment", "니르바나": "extinguishment", "닙바나": "extinguishment",
        "사성제": "four noble truths", "팔정도": "noble eightfold path", "팔성도": "noble eightfold path",
        "제행무상": "impermanent", "무상": "impermanence",
        "갈애": "craving",
        "연기법": "dependent origination", "십이연기": "dependent origination",
        "중도": "middle way",
        "업보": "deeds",
        "사념처": "mindfulness meditation", "염처": "mindfulness meditation",
        "탐진치": "greed, hate, and delusion",
        "해탈": "freedom",
        "아라한": "perfected one",
        "자비": "compassion", "자애": "love",
        "보시": "giving",
    },
    "jesus": {
        "팔복": "Blessed are the poor in spirit", "산상수훈": "Blessed are the poor in spirit",
        "선한 사마리아인": "Samaritan",
        "오병이어": "five loaves",
        "최후의 만찬": "this is my body",
        "달란트": "talent",
        "재림": "coming of the Son of man",
        "성령": "Holy Ghost",
        "황금률": "do ye even so to them",
        # 공관복음에선 구레네 사람 시몬이 십자가를 대신 진다 (마 27:32, 막 15:21, 눅 23:26). 그 대목(막 15:20~38)이
        # 「십자가를 지고 가실 때」 10위·「십자가의 무게」 21위라 모델이 요한복음 기억으로 "내가 지고 골고다로" 라고 했다 → 둘 다 1위.
        # 대가: 「자기 십자가를 지라는 말은」의 마 16:24 청크가 2위 → 3위 (2026-10-14, 사용자 지시)
        "십자가": "cross, Golgotha",
    },
}


def expand(persona_key: str, question: str) -> str:
    """질문에 개념어가 있으면 검색어 뒤에 원어를 괄호로 덧붙인다. 없으면 질문 그대로."""
    table = CONCEPTS.get(persona_key) or {}
    terms: list[str] = []
    for ko in sorted(table, key=len, reverse=True):
        en = table[ko]
        if ko in question and _word_boundary(question, ko) and en not in terms:
            terms.append(en)
    return f"{question} ({', '.join(terms)})" if terms else question
