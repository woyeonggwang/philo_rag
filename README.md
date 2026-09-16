# 철학 RAG 프로그램

철학자(예수 · 니체 · 부처)의 페르소나로 사용자의 질문에 답하는 RAG 챗봇과 Android 앱.

원전(퍼블릭 도메인 영역본)을 검색해 근거 구절을 찾고, 그 구절을 바탕으로 해당 철학자의
목소리로 한국어 답변을 생성한다. 인용 ID를 함께 반환해 어느 구절에 근거했는지 확인할 수 있다.

## 구성

| 폴더 | 내용 |
|---|---|
| `backend/` | FastAPI 서버. 코퍼스 검색(FAISS) + LLM 호출 + API 키 보관 |
| `scripts/` | 코퍼스 빌드 · 인덱스 빌드 스크립트 |
| `mobile/` | Flutter 앱 (Android 우선) |

API 키와 벡터 검색은 전부 서버에 둔다. 앱은 `{persona, question}` 만 보낸다.
자세한 설계 근거는 [CLAUDE.md](./CLAUDE.md) 참조.

## 개발 환경

- Python 3.11
- Flutter 3.47.4 stable (SDK는 저장소 바깥, 예: `C:\dev\flutter`)
- Android SDK 36.0.0 / **cmdline-tools 22.0 고정** (23.x 는 Flutter와 호환 문제 — CLAUDE.md 6.1절)

## 시작하기

### 백엔드

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
copy .env.example .env         # 키를 채워 넣는다
uvicorn app.main:app --reload
```

`http://localhost:8000/docs` 에서 API를 직접 호출해 볼 수 있다.

### 앱

```bash
cd mobile
flutter pub get
flutter run
```

Android 에뮬레이터에서 PC의 로컬 서버 주소는 `127.0.0.1` 이 아니라 **`10.0.2.2`** 다.

## 코퍼스 출처

전부 Project Gutenberg 퍼블릭 도메인 텍스트. 수록 기준과 제외 기준은 CLAUDE.md 2절·5절에 기록되어 있다.
