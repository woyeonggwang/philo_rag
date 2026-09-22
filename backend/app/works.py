"""작품명 한글 표기. 앱의 근거 구절 목록에 "마태복음 3:1~3:15" 처럼 보이게 한다 (2026-09-22, 사용자 요청).

코퍼스 .txt 머리말의 영어 제목(대문자) -> 통용 한국어 제목. 고정 표이며 LLM 을 쓰지 않는다.
표에 없는 작품은 영어 그대로 내보낸다 (앱이 깨지지 않게).
"""

WORK_KO = {
    # 니체 (4절)
    "THUS SPAKE ZARATHUSTRA": "차라투스트라는 이렇게 말했다",
    "BEYOND GOOD AND EVIL": "선악의 저편",
    "THE GENEALOGY OF MORALS": "도덕의 계보",
    "THE TWILIGHT OF THE IDOLS": "우상의 황혼",
    "THE ANTICHRIST": "안티크리스트",
    "ECCE HOMO": "이 사람을 보라",
    # 예수 (4절, 공관복음)
    "THE GOSPEL ACCORDING TO MATTHEW": "마태복음",
    "THE GOSPEL ACCORDING TO MARK": "마가복음",
    "THE GOSPEL ACCORDING TO LUKE": "누가복음",
    # 부처 (4절, 빠알리 경장 8종)
    "THE DHAMMAPADA": "법구경",
    "THE SUTTA NIPATA": "숫타니파타",
    "THE UDANA": "우다나",
    "THE ITIVUTTAKA": "여시어경",
    "THE DHAMMACAKKAPPAVATTANA SUTTA": "초전법륜경",
    "THE SATIPATTHANA SUTTA": "염처경",
    "THE KALAMA SUTTA": "깔라마경",
    "THE MAHAPARINIBBANA SUTTA": "대반열반경",
}


def work_ko(work: str) -> str:
    return WORK_KO.get(work.strip().upper(), work)
