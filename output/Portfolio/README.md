# 쉼표, — 포트폴리오 자료

철학자(니체·예수·부처)에게 고민을 묻는 RAG 챗봇 앱. 답은 각 철학자의 원전(영어 공개 번역본)에서 찾은 구절을 근거로 한국어로 만든다.
자세한 설계 결정과 측정 기록은 저장소 루트의 [CLAUDE.md](../../CLAUDE.md).

## 화면 (화면 흐름 순서, 2026-10-14, Android 에뮬레이터 Pixel 9 · 배포 빌드 · 다크 테마)

대화 화면의 질문과 답은 아래 평가 30문항을 실제 서버에 보낸 결과를 그대로 넣은 것이다 (에뮬레이터에서는 한글을 자동 입력할 수 없어서).

| | 화면 | 파일 |
|---|---|---|
| 1 | 첫 화면 — 화면을 누르면 시작. 철학자 초상이 먹처럼 번지며 니체 → 예수 → 부처로 바뀐다 | [니체](screenshots/01-title-nietzsche.png) · [예수](screenshots/01-title-jesus.png) · [부처](screenshots/01-title-buddha.png) |
| 2 | 대화 탭 — 철학자 고르기 | [02-philosophers.png](screenshots/02-philosophers.png) |
| 3 | 니체와의 대화 — 「아모르파티란 무엇인가요」, 원전 출처 칩 | [03-chat-nietzsche.png](screenshots/03-chat-nietzsche.png) |
| 4 | 예수와의 대화 — 「원수를 어떻게 대해야 합니까?」 | [04-chat-jesus.png](screenshots/04-chat-jesus.png) |
| 5 | 부처와의 대화 — 「화가 날 때 어떻게 해야 합니까?」, 경전 용어 풀이 | [05-chat-buddha.png](screenshots/05-chat-buddha.png) |
| 6 | 말풍선을 길게 누르면 — 삭제 · 복사 · 대화내용 신고 | [06-message-menu.png](screenshots/06-message-menu.png) |
| 7 | 시크릿 모드 — 폰에 저장하지 않는 대화 | [07-secret-mode.png](screenshots/07-secret-mode.png) |
| 8 | 소개 탭 — 철학자를 한 명씩 넘겨 보기 | [08-intro.png](screenshots/08-intro.png) |
| 9 | 소개 상세 — 사상과 책 | [09-intro-detail.png](screenshots/09-intro-detail.png) |
| 10 | 설정 — 테마 · 글씨 크기 · 사용량 | [10-settings.png](screenshots/10-settings.png) |

라이트 테마·큰 글씨·좁은 화면 변형은 [../design-2026-10-14/](../design-2026-10-14/README.md) (테스트 환경 렌더링, 가짜 샘플).

## 답변 평가

[eval/report-2026-10-14.md](eval/report-2026-10-14.md) — 30문항, 사람 판정 통과 23 · 주의 4 · 실패 3.
