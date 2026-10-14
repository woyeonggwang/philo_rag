# CLAUDE.md — 쉼표, (철학자 RAG 챗봇)

철학자 페르소나(니체 · 예수 · 부처)로 답하는 RAG 챗봇. FastAPI 백엔드 + Flutter Android 앱. 모노레포 `D:\ai_project\philo_rag`.
이 문서는 **확인된 사실만** 기록한다. 미확인 항목은 `[확인필요]`로 표시한다.
**지금 상태만 적는다.** 바뀐 결정의 경위, 모델별 비교, 옛 측정치 같은 지난 기록은 커밋 `70bdc08` 의 CLAUDE.md(약 1,600줄)에 있다 —
`git show 70bdc08:CLAUDE.md`.

최종 갱신: 2026-10-14

---

## 0. 작업 규칙 (먼저 읽을 것)

1. **API(LLM) 호출은 사용자가 지시할 때만 한다.** 측정·검증 목적이라도 스스로 토큰을 쓰지 않는다.
   비교·분석은 웹 조사와 로컬 계산(`tiktoken`, 로컬 검색)으로 한다
2. **실패나 이상한 답을 찾으면 고치기 전에 사용자에게 먼저 묻는다.** 새로 발견한 이상한 답은 바로 고치지 않고
   평가 세트(`scripts/eval_questions.json`)에 넣는다
3. 요청 범위 밖의 기능을 덧붙이지 않는다 (근거 구절 본문 번역을 만들었다가 걷어낸 일이 있다)
4. 프롬프트는 짧게 쓴다. 규칙을 쌓을수록 답이 길어지고 어색해졌다
5. 키는 `backend/.env` 에만 둔다. `.env.example` 은 커밋되므로 키를 넣지 않는다. `.env` 내용을 출력하지 않는다.
   `mobile/android/app/google-services.json` 도 커밋하지 않는다 (gitignore)
6. 역할: UI 디자인은 Codex, 백엔드와 앱 기능(API·상태·저장)은 Claude. **Codex 는 커밋하지 않는다 — Codex 수정분도 Claude 가 커밋·푸시한다**
7. 앱의 새 화면은 Flutter 의 `Text` 대신 `keep_words.dart` 의 `Text` 를 쓴다 (5.6)
8. 코퍼스에서 제외한 글(역자 서문·유고 등)을 다시 넣거나 보관하자는 제안은 하지 않는다 (3.2)
9. 포트폴리오 자료는 `output/Portfolio/` 에 둔다

**완성선 (2026-10-14 사용자 결정)**: 포트폴리오 + 지인 대상 비공개 베타. 사용자는 **백엔드 직군**으로 지원한다.
유료 출시·결제·Windows 버전·iOS·대화 기억·스트리밍은 범위 밖이다.

## 1. 저장소 구조

```
philo_rag/
├─ README.md             포트폴리오 첫 화면
├─ CLAUDE.md             이 문서
├─ backend/              FastAPI 서버 (분류 · 검색 · 프롬프트 · LLM 호출 · 규칙 검사)
│  ├─ app/               4절
│  ├─ tests/             pytest — 가짜 LLM, API 호출 없음
│  ├─ .env.example       키 없이 형식만
│  └─ data/
│     ├─ corpus/         .txt + _units.jsonl (커밋)
│     ├─ index/          페르소나별 FAISS (gitignore — 재생성 가능)
│     └─ usage.db · reports.db   (gitignore)
├─ scripts/              코퍼스·인덱스 빌드, 평가, 서버 기동
├─ mobile/               Flutter 앱
├─ docs/                 Codex 에게 넘긴 디자인 요청서
└─ output/
   ├─ Portfolio/         화면 캡처 · 답변 평가 보고서
   ├─ design-2026-10-14/ 디자인 미리보기 (테스트 렌더링)
   └─ illustration-samples/  일러스트 생성 기록 (그림 출처)
```

## 2. 개발 환경

PC 가 두 대다. **PC 별 차이는 저장소 밖에만 둔다** — ① `backend/.env` ② 사용자 환경변수·`flutter config` ③ conda 환경의 내용물(torch 빌드).
커밋되는 파일은 두 PC 에서 같다. 새 경로·장치 설정이 필요하면 코드가 아니라 `.env` 항목으로 만든다 (`.env.example` 에는 집 PC 기준 기본값).

| | 집 PC | 두 번째 PC |
|---|---|---|
| OS | Windows 11 25H2, ko-KR | 같음 |
| GPU | RTX 5070 (Blackwell sm_120, 12GB) | 없음 (i5-10210U, RAM 20GB) |
| Flutter | 3.47.4 / Dart 3.13.3, `C:\dev\flutter` | 3.47.5 / Dart 3.13.4, `D:\DevProgram\flutter` |
| Android SDK | `C:\Users\USER\AppData\Local\Android\Sdk` | `D:\DevProgram\Android\Sdk` (`ANDROID_HOME`, `flutter config --android-sdk`) |
| cmdline-tools | **22.0 고정** | **22.0 고정** |
| Android Studio | Quail 2026.1.2 | `D:\DevProgram\AndroidStudio` (설정 `D:\DevProgram\AndroidStudio-data`, `STUDIO_PROPERTIES`) |
| 에뮬레이터 | `Pixel_9` (API 36, google_apis x86_64) | `Pixel_9_API_36` (`ANDROID_AVD_HOME=D:\DevProgram\Android\avd`) |
| Python | conda `philo-rag` 3.11.16 | 같은 환경 이름. 실제 위치 `D:\DevProgram\conda-envs\philo-rag` 를 `C:\Users\USER\anaconda3\envs\philo-rag` 에 정션 |
| torch | 2.11.0+cu128 | 2.14.0+cpu |
| `.env` 임베딩 | `EMBEDDING_DEVICE=cuda` / `EMBEDDING_DTYPE=float16` | `cpu` / `float32` |
| 그 밖 | VS C++ 워크로드 없음 (Windows 빌드 불가) | JDK `D:\DevProgram\AndroidStudio\jbr`, `GRADLE_USER_HOME=D:\DevProgram\gradle`, `HF_HOME=D:\DevProgram\huggingface`, VS 2026 C++ 워크로드 있음 |

- **파이썬은 conda 를 쓴다.** PATH 의 `python` 은 Microsoft Store 스텁이다. 인터프리터는 두 PC 모두 `C:\Users\USER\anaconda3\envs\philo-rag\python.exe`
- **torch 는 `requirements.txt` 에 넣지 않는다.** 집 PC 는 `pip install torch --index-url https://download.pytorch.org/whl/cu128` 뒤
  `torch.cuda.get_arch_list()` 에 `sm_120` 이 있는지 확인한다. 두 번째 PC 는 `.../whl/cpu`
- 인덱스는 집 PC 에서 만들어 복사한다 (gitignore). GPU fp16 으로 만든 인덱스를 CPU fp32 로 질의해도 점수가 소수 셋째 자리까지 같다.
  두 번째 PC 에서 인덱스를 새로 빌드하지 않는다 (시간 단위)
- Flutter SDK 는 저장소 밖에 둔다 (SDK 자체가 git 저장소다). Windows 개발자 모드 ON (플러그인이 심볼릭 링크를 쓴다)
- **cmdline-tools 23.x 금지.** 23.0 부터 `sdkmanager` 가 폐기돼 `flutter doctor --android-licenses` 가 프롬프트 없이 끝난다
  ([flutter#191558](https://github.com/flutter/flutter/issues/191558)). SDK Manager → SDK Tools → Show Package Details 에서 22.0 을 고른다

### 2.1 서버 띄우기

- **VS Code F5** (`.vscode/launch.json`) — 인터프리터·`PYTHONUTF8=1`·작업 폴더가 들어 있고, 서버가 뜨면 `http://localhost:8000/chat` 이 열린다
- **`scripts/start_backend.bat`** — 8000 포트가 비어 있을 때만 최소화 창으로 띄운다 (여러 번 불러도 안전). `HF_HOME` 이 없으면
  레지스트리(`HKCU\Environment`)에서 읽고, 모델이 캐시에 있으면 `HF_HUB_OFFLINE=1` 을 건다. 기동(BGE-M3 로딩)은 20초 안팎
- Android Studio 에서는 External Tool "Start backend"(명령 `D:\ai_project\philo_rag\scripts\start_backend.bat`)를 Flutter 실행 구성
  **`main.dart + backend`** 의 Before launch 에 걸어 두었다 (두 PC 모두). 이 설정은 저장소 밖(`External Tools.xml`)과 gitignore 된
  `mobile/.idea/runConfigurations/` 에 있어 PC 마다 따로 만든다. 집 PC 의 파일은 `%APPDATA%\Google\AndroidStudio2026.1.2\tools\External Tools.xml`,
  Android Studio 가 꺼져 있을 때 써야 한다
- **Android Studio 에서는 저장소 루트가 아니라 `mobile\` 을 연다.** 실행 전에 에뮬레이터를 먼저 켠다 — 꺼져 있으면 기기가 "Windows (desktop)" 로
  골라져 `Unable to find suitable Visual Studio toolchain` 이 난다
- 집 PC Android Studio 에 Flutter·Dart 플러그인이 없던 적이 있다. Android Studio 를 닫고
  `"C:\Program Files\Android\Android Studio\bin\studio64.exe" installPlugins io.flutter Dart`

### 2.2 Windows 셸 함정

- cmd 의 `set PYTHONUTF8=1 && uvicorn ...` 은 값이 `"1 "` 이 되어 파이썬이 죽는다. 붙여 쓰거나 F5 를 쓴다. uvicorn 로그 한글이 깨지면 `PYTHONUTF8=1`
- Git Bash 의 `curl -d '{"question":"한글"}'` 은 본문을 cp949 로 보내 FastAPI 가 파싱에 실패한다. 한글 요청은 `/chat`·`/docs`·Python `urllib` 으로
- 포트 점유 확인은 `netstat -ano | findstr :8000`, 종료는 PowerShell `Stop-Process` (Git Bash 에서는 `taskkill /F` 의 `/F` 가 경로로 바뀐다).
  `Errno 10048 ... bind on address 8000` 은 이미 떠 있다는 뜻이다
- 브라우저로 `http://0.0.0.0:8000` 은 열리지 않는다 (바인드 주소). `http://localhost:8000` 을 연다. `--host 0.0.0.0` 은 실기기 접속에 필요해 유지
- Anaconda Prompt(cmd)에서 드라이브를 바꾸려면 `cd /d D:\...`
- **IDE 를 켜 둔 채 새로 만든 사용자 환경변수는 그 IDE 와 자식 프로세스에 보이지 않는다** (`HF_HOME` 을 못 받아 BGE-M3 2.2GB 를 C 에 다시 받은 일이 있다)
- 집 PC LAN IP `192.168.0.10`. 실기기에서 붙으려면 방화벽 인바운드 8000 허용 (관리자 PowerShell):
  `New-NetFirewallRule -DisplayName "philo-rag backend 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow`
- 원격 컨테이너 셸에서는 gutenberg.org·archive.org·wikisource 가 정책상 403 이다 (재시도·우회하지 않는다). github·raw.githubusercontent·pypi 는 열린다.
  Gutenberg 원본이 필요하면 사용자가 파일로 첨부한다

## 3. 코퍼스

### 3.1 원칙

| 항목 | 결정 | 이유 |
|---|---|---|
| 언어 | 영어 공개 번역본 | 한국어 번역본은 저작권 보호 대상, 영어가 토큰이 적다 |
| 답변 언어 | 한국어 (LLM 생성 단계) | |
| 수록 기준 | 니체는 **본인이 직접 쓰고 스스로 출간한 글만**. 예수는 공관복음, 부처는 가장 이른 층의 경장 | 페르소나가 남의 말이나 철회한 주장을 자기 말로 하지 않게 |
| 해설의 1인칭 변환 | 하지 않는다 | 쓰지 않은 문장을 본인 발언으로 만드는 것은 근거 조작이다 |
| 인덱스 | 페르소나별 분리 `data/index/<persona>/` | 니체 질문에 마태복음이 섞이는 것을 구조로 막는다 |

### 3.2 제외 기준

1. **타인의 글** — 역자 서문·해설·각주, 편집자(Oscar Levy) 노트, 엘리자베트 푀르스터-니체 서문
2. **유고(Nachlass) 편집물** — 출간하지 않은 노트. 잠정적 입장이 섞여 있다. 『권력에의 의지』 제외와 같은 기준
3. **중복** — 이미 코퍼스에 있는 텍스트의 축자 재인용
4. **서지 부속물** — 목차, 판권지, 식자공 노트, PG 보일러플레이트

**제외분은 보관하지 않고 재수집하지 않는다.** 무엇을 뺐는지는 각 `.txt` 머리말과 `scripts/build_*.py` 의 제외 로직에 남아 있다.
빌드 스크립트도 제외분을 파일로 쓰지 않는다 — `build_zarathustra.py`(엘리자베트 서문·Ludovici 해설)와 `build_books.py`(역자 서문·유고 등 8가지)가
`commentary_*.txt`·`excluded/` 로 저장하게 되어 있던 것을 2026-10-14 걷어냈다 (옛 원격 환경 경로라 실제로 저장된 적은 없다. 저장소·git 기록에 없음을 확인).
`build_books.py` 의 `drop_excluded()` 는 무엇을 왜 잘랐는지 출력만 한다

| 작품 | 제외한 것 |
|---|---|
| Zarathustra | 엘리자베트 서문(1905), Ludovici 부록 해설(1909), 목차, 각 부 제사(본문 축자 중복) |
| Beyond Good and Evil | 식자공 노트, 목차, `[FOOTNOTE: ...]` 역주 |
| Genealogy of Morals | Levy 편집자 노트, 목차, Samuel 역주, 「Peoples and Countries」 유고 단편 27개 |
| Twilight of the Idols | 역자 서문, 역주, 「The Hammer Speaketh」(차라투스트라 III.29 축자 인용) |
| The Antichrist | 역자 서문, 역주, 「The Eternal Recurrence」 + 차라투스트라 주해(유고) |
| Ecce Homo | 역자 서문, 역주, Levy 노트, 시가 부록(편집자가 고른 유고. 「Hymn to Life」 가사는 루 살로메의 것) |

### 3.3 수록 현황

**니체** — Project Gutenberg, Levy 전집 영역본. 단위 = 차라투스트라는 문단, 나머지는 니체가 매긴 절

| 작품 | PG ID | 역자 | 단위 | 단어 |
|---|---|---|---|---|
| Thus Spake Zarathustra | 1998 | Thomas Common | 3,489 | 89,315 |
| Beyond Good and Evil | 4363 | Helen Zimmern | 315 | 62,032 |
| The Genealogy of Morals | 52319 | Horace B. Samuel | 79 | 51,700 |
| The Twilight of the Idols | 52263 | Anthony M. Ludovici | 152 | 29,340 |
| The Antichrist | 52263 | Anthony M. Ludovici | 62 | 27,645 |
| Ecce Homo | 52190 | Ludovici / Paul V. Cohn | 73 | 35,828 |
| **합계** | | | **4,170** | **295,860** |

**예수** — KJV 공관복음 (Project Gutenberg 낱권). 마태 28장 1,071절 · 마가(8041) 16장 678절 · 누가(8042) 24장 1,151절 = **2,900절 / 64,789단어**.
요한복음은 문체·화법이 달라 페르소나가 흔들려서 넣지 않았다

**부처** — SuttaCentral `bilara-data` 의 Bhikkhu Sujato 영역 (CC0 1.0). `scripts/build_suttas.py` 가 GitHub raw 에서 직접 받는다

| 작품 | 원전 | 단위 | 단어 |
|---|---|---|---|
| Dhammapada (법구경) | Dhp 1~423, 게송 | 423 | 9,979 |
| Sutta Nipata (숫타니파타) | Snp 1.1~5.19, 게송 | 1,265 | 37,235 |
| Udana (우다나) | Ud 1.1~8.10, 문단 | 641 | 26,035 |
| Itivuttaka (여시어경) | Iti 1~112, 문단 | 695 | 20,302 |
| 초전법륜경 · 염처경 · 깔라마경 | SN 56.11 · MN 10 · AN 3.65 | 14 · 39 · 49 | 5,564 |
| Mahaparinibbana (대반열반경) | DN 16, 문단 | 212 | 20,771 |
| **합계** | | **3,338** | **119,886** |

논장·율장·주석서·본생담·대승경전·Carus 『The Gospel of Buddha』 같은 편집물은 넣지 않는다.

**인덱스** (BGE-M3 토크나이저): nietzsche **1,124 청크**, jesus **213**, buddha **541** — 합계 1,878.
최대 청크는 640 / 512 / 645 (부처의 645 는 대반열반경의 긴 문단 하나가 문장 경계 분할로 상한을 조금 넘은 것)

### 3.4 포맷

```
Chapter 0. Zarathustra's Prologue        (차라투스트라 — 단위 = 문단)
[SS 1]
0:1 When Zarathustra was thirty years old, ...

Division 1. Prejudices of Philosophers   (나머지 5권 — 단위 = 니체가 매긴 절)
1:1 The Will to Truth, which is to tempt us to many a hazardous enterprise, ...

Chapter 1                                 (복음서 — 단위 = 절)
1:1 The book of the generation of Jesus Christ...
```

- 인용 ID `<구분>:<절>`. 절 번호는 **니체 본인의 번호** 그대로. Division 0 = 서문. `237A` 같은 알파벳 접미는 유지
- 부처는 `<경 일련번호>:<게송/문단>`(모음집) 또는 `<장>:<문단>`(단일 경). 경의 원전 번호("1.8")는 Division 제목 앞에 붙는다
- 운문 블록은 한 단위로 묶고 줄바꿈·들여쓰기를 보존한다. 곡선 따옴표는 ASCII 로, `_이탤릭_` 마크업은 제거, 엠대시는 보존
- `.txt` 마다 `<작품>_units.jsonl` 이 있다. `scripts/build_jsonl.py` 가 `.txt` 를 역파싱해 만든다 (원본 PG 파일 불필요.
  차라투스트라 원본 jsonl 과 3,489/3,489 일치로 검증). 운문 첫 줄 들여쓰기는 이어지는 줄의 공통 들여쓰기로 되돌린다
- 필드: `uid / seq / ref / persona / work / author / year / translator / pg_id / part / division / division_title / section /
  section_suffix / author_section / numbered / anomaly / text`. **고유 키는 `uid`** (`<파일명>#<순번>`) — `ref` 는 드물게 중복된다

### 3.5 알려진 결함 (고치지 않는다)

- `ref` 중복 6건 — 원본 처리 중 번호가 어긋났다. 본문 유실은 없다. JSONL `anomaly` 로 표시하고 고유 키는 `uid`
  - `epigraph_or_subtitle`: 부제·제사가 1번 절 번호를 받음 (GM `3:1`, EH `7:1`·`10:1`·`12:1`)
  - `fragment_of_previous_section`: 앞 절의 뒷부분이 다음 번호를 받음 (EH `2:3`·`2:10`). `duplicate_ref_in_source` 쪽이 진짜 본문
- AC 61 번호 없음(본문은 60 에 붙어 있음), EH 「Why I Am So Wise」 1–7·「The Birth of Tragedy」 1·3 — 원본에서 번호만 빠졌다
- **`mathe.txt` 가 25:46 에서 잘려 있던 적이 있다** (2026-09-19 jsonl 로 복원, 원인 미상). **`build_jsonl.py` 를 다시 돌리기 전에
  `.txt` 단위 수가 위 표와 맞는지 볼 것** — 안 맞으면 jsonl 이 덮어써지며 유실된다

### 3.6 청킹

**목표 512 / 최대 640 / 오버랩 96 토큰.** 단위의 91%가 128토큰 미만인데 2,000토큰이 넘는 절도 있어서 한쪽은 묶고 한쪽은 쪼갠다.

1. 목표 이하의 단위는 **같은 구분 안에서 연속으로 묶는다** (차라투스트라·복음서는 단위가 30토큰 안팎이라 그대로면 문맥 없는 조각이 잡힌다)
2. 최대를 넘는 단위만 **문장 경계에서** 나누고, 오버랩은 이때만 쓴다
3. 고정 길이 분할 금지. 서로 다른 구분·작품·페르소나를 한 청크에 섞지 않는다

검색 A/B (`scripts/eval_retrieval.py`, 질문 7개, MRR): 512 한국어 **0.619** / 256 한국어 0.512 / 256 영어 0.462 / 512 영어 0.262.
→ 512 유지, **한국어 질의를 영어로 번역하지 않는다** (번역이 오히려 나빴다. 개념어 몇 개만 덧붙이는 사전은 예외 — 4.4).
질문이 7개뿐이라 강한 근거는 아니다.

### 3.7 빌드 스크립트

| 스크립트 | 역할 |
|---|---|
| `build_zarathustra.py` / `build_books.py` | PG 원본 → 니체 `.txt` (원본 PG 파일 필요. 평소엔 쓸 일 없음) |
| `build_gospels.py <PG원본디렉터리>` | KJV 마가·누가 → `.txt`. 장 결번·절 불연속·중복 ref 를 자동 검증 |
| `build_suttas.py` | SuttaCentral → 부처 8파일 `.txt`. GitHub 무인증 API 한도(시간당 60회) 때문에 트리 조회 4회로 경로를 받아 `scripts/.cache/` 에 둔다 |
| `build_jsonl.py` | `.txt` → `_units.jsonl` 역파싱. JSONL 스키마의 단일 출처 |
| `build_index.py` | JSONL → 청킹 → BGE-M3 임베딩 → 페르소나별 FAISS |
| `search_test.py` / `eval_retrieval.py` | 검색 육안 점검 / 검색 A/B |
| `eval_answers.py` | 답변 평가 (6절). **실제 LLM 호출** |

순서: `build_jsonl.py` → `build_index.py` → `search_test.py`. BGE-M3 는 질의 접두사("Represent this sentence…")를 붙이지 않는다.

**Gutenberg 파싱 함정**: ① 목차가 모든 제목을 반복한다 — 제목은 0열에서 시작하므로 좌측 공백을 보존한 채 매칭 (Ecce Homo 는 목차도 0열이라
본문 기준으로 먼저 자른다) ② `[Footnote: ...]`·`[FOOTNOTE: ...]` 가 문장 중간에 있다 — 줄 단위로 건너뛰면 아포리즘 17개가 사라진다.
전체 텍스트에서 `\[Footnote.*?\]` 를 `re.S | re.I` 로 지운다 ③ 절 번호 표기가 섞인다(`1.` 단독 줄 / `1. 본문` / `278.--본문`, `237A.`)
④ 구형 파일은 `*** END ***` 앞에 `End of Project Gutenberg's ...` 줄이 또 있다 ⑤ CRLF·곡선 따옴표는 매칭보다 먼저 정규화한다.
SuttaCentral 은 염처경의 범위 키(`mn10:18-23.1` → 시작 번호), 모음집마다 다른 제목 줄 위치(마지막 비어 있지 않은 `0.x` 가 제목)에 주의.

## 4. 백엔드

### 4.1 모듈

```
backend/app/
├─ config.py      .env 를 읽는 설정 하나 (pydantic-settings). 코드에 키를 넣지 않는다
├─ main.py        FastAPI 엔드포인트 (4.2)
├─ rag.py         분류 → 검색 → 프롬프트 조립 → LLM 호출 → 규칙 검사 → (위반 시) 재생성 (4.3)
├─ personas.py    페르소나 정의와 시스템 프롬프트 (4.6). 답변 품질은 대부분 여기서 정해진다
├─ retriever.py   FAISS 검색. 임베딩 모델은 프로세스당 1회, 서버 기동 때 미리 로딩
├─ concepts.py    개념어 사전 — 검색어에만 원어를 덧붙인다 (4.4)
├─ guard.py       답변 규칙 검사. 검사만 하고 고치지는 않는다 (4.7)
├─ llm.py         프로바이더 팩토리. .env 의 LLM_PROVIDER 하나로 교체
├─ glossary.py    답변 속 경전 용어·호칭의 뜻 (각주용 고정 표, LLM 안 씀)
├─ works.py       작품명 한글 표기 고정 표 ("THE GOSPEL ACCORDING TO MATTHEW" → "마태복음")
├─ plans.py       요금제와 사용자별 하루 사용량 (SQLite)
├─ auth.py        Firebase ID 토큰 검증, 개발자 확인(ADMIN_USERS)
├─ reports.py     대화 신고 저장 (SQLite)
└─ static/chat.html  개발용 채팅 테스트 화면 (GET /chat) — 배포 전 삭제
```

### 4.2 API

**앱은 `{persona, question}` 만 보내고 검색·프롬프트·LLM 호출·키 보관은 전부 서버가 한다.** APK 는 압축을 풀어 문자열을 뽑을 수 있어
앱에 넣은 키는 공개된 것과 같고, BGE-M3(5억대 파라미터)와 FAISS 는 공식 모바일 바인딩이 없어 폰에서 검색할 수 없다.

| 엔드포인트 | 내용 |
|---|---|
| `POST /ask` | `{persona, question}` → `{answer, grounded, safety, retries, sources[], glossary[], usage}`. 앱이 보내는 것은 이 둘뿐 |
| `GET /health` · `GET /personas` | 상태 · 페르소나 목록 |
| `GET /usage` | 오늘 사용량 (횟수를 올리지 않는다) |
| `GET /me` | `{user_id, admin}` |
| `POST /reports` · `GET /reports` | 대화 신고 저장 · 목록 (목록은 개발자만, 아니면 403) |
| `GET /chat` | 개발용 브라우저 채팅 화면. 인증 없이 LLM 을 부르므로 **배포 전 삭제** |

- `sources[]` 는 `chunk_id, work, work_ko, ref, title, score` — **구절 본문은 보내지도 번역하지도 않는다** (사용자 결정 2026-09-22).
  앱은 "마태복음 3:1~3:15" 처럼 한글 작품명 + 위치만 보여준다. 작품을 더하면 `works.py` 표도 늘린다 (`tests/test_sources.py` 가 검사)
- LLM 프로바이더 오류(404·429·503 등)는 **502 + 원문 메시지**. 인덱스를 만든 임베딩 설정과 다르면 서버가 기동 때 에러를 낸다
- CORS 가 `allow_origins=["*"]` 다 — 배포 전에 좁힌다

### 4.3 질문 처리 흐름 (`rag.answer`)

1. **분류** (`_classify`) — 위기 정규식 `SAFETY_PATTERNS` 에 걸리면 호출 없이 위기. 아니면 LLM 한 번(`CLASSIFY_PROMPT`, 철학자 이름 포함)으로
   여섯 갈래. 모르는 답이 오면 "가르침"(답할 질문을 놓치는 쪽이 더 나쁘다). 위기가 아닌데 사이비 이름 정규식 `CULT_PATTERNS` 에 걸리면 미혹
2. **분류별 처리**

| 분류 | 기준 (요지) | 처리 |
|---|---|---|
| 위기 | 쓴 사람 **본인이** 죽고 싶다·살기 싫다·자해처럼 자기 생명에 관한 말을 한다. 걱정·불면·스트레스·슬픔만으로는 아니다. 생명에 관한 말인데 확실하지 않으면 위기 | 검색하지 않는다. 사람이 쓴 고정 안내 `SAFETY_NOTICE`(자살예방 상담전화 109) + 모델의 두세 문장 |
| 미혹 | 어떤 사람·단체가 재림 예수·메시아·선지자·구원자인지, 따라도 되는지 묻는다 (성경 속 인물, 재림 자체는 아님) | 검색 대신 문구로 고른 고정 구절(`retriever.find`) + `cult_line`. 예수는 답에 "거짓 선지자"가 없으면 재생성 |
| 행적 | 자기 삶·겪은 일 | 구절 + `HISTORY_NOTE` (겪은 일로 1인칭, 기록·성경에 무엇이 적혔는지 말하지 않음) |
| 가르침 | 그 사람이 가르친 주제 | `MIN_SCORE` 이상 구절로 답한다. 하나도 없으면 가장 가까운 3개로 |
| 토론 | 의견이 갈리는 현대 문제 (진화론 등) | 코드가 첫 문장(`open_line`)을 붙이고 `DEBATE_TEMPLATE` — "세상은 … 그러나 나는". 0.40 이상 "가까운 구절" 최대 3개는 모델에게만 (sources 엔 없음). 온도 0.7 |
| 잡담 | 취향·일상 (점심 메뉴, 포켓몬) | 코드가 첫 문장을 붙이고 `CHAT_TEMPLATE` — 찬반 없이 한두 문장. 구절 없음. 온도 0.7 |

3. **생성 + 검사** — guard 가 위반을 찾으면 무엇을 어겼는지 알려 주고 다시 쓰게 한다 (`MAX_RETRIES` 3).
   대화 형식으로 이어 붙인다: `[System, Human(요청), AI(실패한 답), Human(지적)]`
4. **마무리** — 위기면 고정 안내를 앞에, 토론·잡담이면 `open_line` 을 앞에 붙인다. 행적·가르침인데 모델이 끝내 `open_line` 첫 문장으로
   시작하면 근거 없음으로 표시한다 (`_declined`, `grounded=false`, `sources=[]`)

**`open_line`** (사람이 쓴 고정 문장, `personas.py`): 예수 "이는 내가 공생애 동안 가르친 바가 아니니라." / 니체 "이것은 내가 책에서 다룬 문제가 아니다." /
부처 "그대여, 이것은 내가 설한 법이 아니다." — 지어낸 근거가 아니라 그 사람의 관점에서 추론한 답임을 듣는 사람이 알게 한다.
반대 의견은 "세상 사람들의 생각"으로 소개하고 "그러나 나는" 으로 자기 가르침을 말한다 — 교리와 어긋나는 생각을 자기 것으로 편들지 않게 (마 5:21 의 꼴).

**사이비 고정 구절** (한국어 질문으로는 마 7:15 가 상위 5위에 안 잡혀 본문 문구로 찾는다):

| 페르소나 | 구절 | `cult_line` |
|---|---|---|
| 예수 | 마 7:15, 24:23~24, 막 13:21~22 | "거짓 선지자들을 삼가라"고 분명히 말하라 |
| 니체 | 차라투스트라 「베푸는 덕」 22:49, 이 사람을 보라 「나는 왜 운명인가」 14:1 | 그런 자를 따르지 말고 그대 자신을 찾으라 |
| 부처 | 깔라마경 | 스승을 자처하는 자의 말이라도 해로운지 스스로 살피라 |

`CULT_PATTERNS`: 이만희·신천지(사용자가 든 예) + 정명석·JMS·기독교복음선교회, 안상홍·장길자·하나님의교회세계복음선교협회, 문선명·한학자·통일교·
통일가정연합, 유병언·구원파, 이재록·만민중앙, 신옥주·은혜로교회. "하나님의 교회"·"가정연합" 처럼 일반 낱말과 겹치는 형태는 넣지 않았다.
목록에 없는 이름은 분류 호출이 잡는다. **목록은 사용자 검토 전** `[확인필요]`.

### 4.4 검색

- BGE-M3 + FAISS `IndexFlatIP` (벡터 정규화 → 내적 = 코사인). 청크가 2천 개 미만이라 근사 인덱스가 필요 없다. `faiss-cpu`
- `top_k` 5, **`MIN_SCORE` 0.40**. 점수만으로는 답할 질문과 못 할 질문을 가를 수 없다 (예수: 「바람직한 삶」 0.448 vs 「점심 메뉴」 0.442) —
  기준선은 낮게 두고, 답할 질문인지는 분류가 정한다
- 집 PC 는 임베딩을 fp16 으로 올린다 (VRAM 2.2 → 1.1GB). fp32 인덱스와 순위가 같고 점수 차는 최대 0.0002
- **개념어 사전** `concepts.py` — 질문에 개념어가 있으면 **검색어에만** 원어를 괄호로 덧붙인다. 모델이 보는 질문은 그대로다.
  한글 음차·한자어("아모르파티", "열반")는 BGE-M3 가 영어 원어와 잘 잇지 못한다. 니체 23 · 부처 21 · 예수 10 항목 (합계 54).
  원어는 코퍼스 번역본의 표기다 (차라투스트라의 Superman, 도덕의 계보의 resentment, Sujato 역의 extinguishment). 낱말 경계는 `glossary._word_boundary`
  ("무상으로"·"사업"에는 안 걸린다). 서버 로그에 `검색어 보강: (...)` 이 찍힌다
  - **항목은 「OO란 무엇입니까?」로 순위가 오르는 것을 재고 넣는다.** 아모르파티 26 → 1, 운명애 30위 밖 → 1, 열반 7 → 1, 사성제 30위 밖 → 3,
    팔정도 25 → 1, 팔복 30위 밖 → 1, 오병이어 14 → 1. 뺀 것: 무아(붙여도 30위 밖), 탕자(비유가 두 청크로 갈려 있다)
  - **"십자가" → "cross, Golgotha" 만 대가가 있다**: 구레네 시몬이 십자가를 대신 지는 막 15:20~38 이 「십자가를 지고 가실 때」 10 → 1,
    「십자가의 무게」 21 → 1 이 되는 대신 「자기 십자가를 지라는 말은」의 마 16:24 청크가 2 → 3 (근거 5개 안). 시험한 7가지 표기 모두 그랬다

### 4.5 LLM

- **OpenAI `gpt-5.6-luna`**. 입력 $0.20 / 출력 $1.20 per 1M. 답 1개 약 $0.0009, 분류 호출을 더해 질문당 약 $0.001
- **`OPENAI_REASONING_EFFORT=none` 필수.** 추론 모델이라 기본(medium)이면 화면에 안 보이는 추론 토큰이 출력 요금으로 청구된다.
  none 이면 추론 토큰 0 이 실측됐고, temperature 도 쓸 수 있게 된다 (추론이 켜져 있으면 gpt-5 계열은 1 고정)
- 온도 **0** (`LLM_TEMPERATURE`), 토론·잡담 **0.7** (`LLM_TEMPERATURE_OPEN`). `LLM_MAX_TOKENS` 4096
- 접근 권한은 3단계다 — ① 프로젝트에서 모델 허용 ② Tier 1(누적 $5 결제) ③ 조직 신원 인증(보호 모델). 모델 목록 조회는 되는데 추론만 403 이면 ③ 대기 중
- 토크나이저 `o200k_base` — `tiktoken` 로컬 계산과 실제 입력의 차이가 0.5% 다. **호출 없이 비용을 미리 계산해도 된다**
- 다른 프로바이더는 `.env` 의 `LLM_PROVIDER`·`LLM_MODEL` 만 바꾸면 된다 (google · groq · openrouter · anthropic · ollama, 서버 재시작).
  로컬 Ollama `qwen3.5:9b`(`OLLAMA_REASONING=false` 필수)는 개발용이다 — 말투 위반이 20% 남아 배포 품질이 아니다. 두 번째 PC 에서는 쓰지 않는다.
  `gpt-4o-mini` 는 같은 구절을 받고도 구절 내용을 하나도 안 쓰고 일반론으로 채워 쓸 수 없다
- langchain-core 1.x 는 `resp.content` 가 블록 리스트일 수 있다 — **`resp.text`** 를 쓴다. `max_tokens` → `max_completion_tokens` 변환은 langchain 이 한다
- `[확인필요]` gpt-5.6 출력 토큰 과다 청구 버그 제보 (community.openai.com) — effort none 이면 추론 토큰이 없어 영향이 없을 것으로 본다. 대시보드로 확인

### 4.6 프롬프트 (`personas.py`)

- 구성 순서는 **정체성 → 말투 → 공통 규칙**. 시스템 프롬프트는 페르소나당 300~400 토큰. 사용자 메시지는 `구절: … 질문: …` 재료만
- 말투: 니체 `~다/~라/~는가`(사극체 금지) · 예수 개역 성경 어투(`~하라/~하리라/~느니라`, 상대는 "너") ·
  부처 초기불전연구원 니까야 역본 어투, 호칭은 "그대여"로 통일 (경전 호칭 "장자여"는 부유한 재가 신도 전용이라 임의로 쓰면 어색하다)
- 공통 규칙: 1인칭 · 구절 안에서 · **논지 방향을 뒤집지 않는다** · 인용 맥락·발화자·경험을 구분한다(차라투스트라의 말은 니체 본인의 체험이 아니다,
  예수는 겪지 않은 일을 겪었다고 하지 않는다) · 3~5문장 · 상담 안내는 먼저 꺼내지 않는다 · `open_line` 은 먼저 쓰지 않는다
- **답변 예시를 넣지 않는다** — 예시 내용이 무관한 답에 그대로 복사된다. 말투 규칙의 예문도 복사된다
- 부처는 갈애·무상·열반 같은 용어를 풀어 쓰지 않는다 — 앱이 `glossary` 로 각주를 단다 (부처 45개, 니체·예수 표는 비어 있음.
  불교 용어에 밝은 사람의 검토 전)

### 4.7 guard (`guard.py`)

| 검사 | 내용 |
|---|---|
| 영어 | `[A-Za-z]{2,}` |
| 한자·가나 | 있으면 위반 |
| 3인칭 자칭 | `니체는/니체라면`, `예수님/예수께서`, `부처님/세존께서` 등. 이름 자체("나는 니체다")와 경전의 자칭 `여래는` 은 허용 |
| 금지 어미 (문장 끝만) | 니체: 존댓말·요체·구어체·사극체 / 예수: `~습니다/~십시오`·요체 (`~리요` 는 성경체라 허용 — `(?<!리)(요\|죠)`) / 부처: 존댓말·요체·구어체 |
| 겸양어 | `저는/제가` — 상대를 윗사람으로 대하는 꼴 |
| "구절" | 시스템이 준 재료를 드러내는 말 ("그대가 제시한 구절들에 따르면") |
| 출처 표기 | `(마태복음 25:35)`, `N장 N절` |
| 길이 | 500자·3문단 이하 (안전 경로는 제외) |
| `must_include` / `must_not_include` | 사이비 질문의 "거짓 선지자" / 코드가 붙이는 첫 문장 |

**검사만 하고 고치지는 않는다** — 후처리로 문장을 바꾸면 근거와 어긋날 수 있다. 재생성 횟수는 응답의 `retries` 로 보인다.
내용 오류(구절을 거꾸로 말하기, 인용 맥락)는 검사로 못 잡는다 — 사람이 코퍼스와 대조한다 (6절).

### 4.8 요금제 · 로그인 · 신고

- **요금제** (`plans.py`): `personal` 하루 5건 / `pro` 무제한. 가격·결제 방식은 미정이라 코드에 없다. `DEFAULT_PLAN` 하나를 모두가 받고 **기본값 `pro`**
  - 사용자 구분: 로그인 토큰(`Authorization: Bearer <Firebase ID 토큰>` → `fb_<uid>`) → 없으면 앱이 만든 기기 UUID(`X-User-Id`) → 둘 다 없으면 `anonymous`
  - `usage.db` 에 (사용자, 날짜)별 건수. 하루 경계는 한국 시간 자정(+9 고정). LLM 호출 **전에** 1건을 올리고(`BEGIN IMMEDIATE` — 동시 요청에도 한도를
    못 넘는다) 답을 못 주면 돌려준다. 한도 초과는 429 + 안내 문장
  - **한도에 걸려도 위기 정규식에 걸리면 상담전화 고정 안내는 나간다** (LLM 안 부름, 사용량 안 셈)
- **로그인** (`auth.py`): Firebase ID 토큰을 Google 공개키로 검증한다 — 서비스 계정 키 없이 `FIREBASE_PROJECT_ID`(`philo-rag-ef4be`)만.
  **`AUTH_REQUIRED=false` — 출시 전까지 false** (사용자 결정). true 면 토큰 없는 요청은 401
- **신고** (`reports.py`): `POST /reports` 로 사유·질문·답이 `reports.db` 에 쌓인다. `GET /reports` 는 개발자만.
  개발자는 `.env` 의 `ADMIN_USERS`(쉼표로 여럿) — 이메일은 토큰이 `email_verified` 일 때만 인정(이메일 가입은 인증 메일이 없어 남의 주소로도 가입된다),
  또는 사용자 ID. `anonymous` 는 개발자가 될 수 없다. 집 PC `.env` 에는 설정했고 **두 번째 PC `.env` 는 아직**

### 4.9 테스트

`backend/tests/` — 가짜 LLM, API 호출 없음. `python -m pytest tests -q` (임베딩 로딩 포함 약 15초~1분). **72개.**
`test_open.py`(분류 여섯 갈래·사이비·위기 우선·토론/잡담/행적/가르침 경로·"~리요") · `test_concepts.py`(사전·경계·"구절" 재생성) ·
`test_sources.py`(작품명 한글 표·본문 미전송) · `test_plans.py`(한도·환불·위기 예외·/chat) · `test_auth.py`(토큰 검증) · `test_reports.py`.
`conftest.py` 가 사용량·신고 DB 를 임시 파일로 돌린다.

## 5. 앱 (Flutter, `mobile/`)

`flutter create mobile --platforms=android,windows --org com.philorag --project-name philo_rag`. 패키지명 `com.philorag.philo_rag`.
앱 이름 **"쉼표,"**. 패키지: `http`, `shared_preferences`, `path_provider`, `firebase_core`, `firebase_auth`, `google_sign_in`.
상태 관리는 `ChangeNotifier` + `AnimatedBuilder`/`ListenableBuilder` (패키지 없음).

### 5.1 구조

```
mobile/lib/
├─ main.dart        앱 진입. 테마·글씨 크기 반영
├─ api/             client.dart (PhiloRagClient — /ask·/personas·/usage·/me·/reports, ApiException), models.dart (서버 응답 모델과 1:1)
├─ state/           settings.dart (서버 주소·기기 ID·테마·글씨 크기), chat.dart (ChatController), chat_storage.dart, auth.dart, firebase_auth_backend.dart
├─ data/            persona_profiles.dart (소개 탭의 고정 글)
└─ ui/              화면·위젯. api/ 의 함수만 부르고 http 를 직접 쓰지 않는다
```

**서버 주소**: 에뮬레이터 `http://10.0.2.2:8000` (기본값) / 실기기 `http://192.168.0.10:8000` / Windows `http://localhost:8000`.
디버그 빌드에만 설정 탭 "개발용 · 서버 주소"가 있다. **릴리스 빌드는 주소를 바꿀 수 없어 에뮬레이터에서만 서버에 붙는다.**
`ask` 타임아웃 90초, 응답은 `utf8.decode(bodyBytes)` (한글).

### 5.2 화면

첫 화면(켤 때마다. 아무 데나 누르면 넘어감) → **아래 탭 세 칸** `ui/main_tabs.dart`:
- **대화** — 철학자 2열 바둑판(`persona_grid_screen.dart`). 서버가 켜지는 중이면 3초 간격 10번 재시도 후 "다시 시도". 누르면 대화창(`chat_screen.dart`)이 탭을 덮는 전체 화면으로 열린다
- **소개** — 한 명씩 넘기는 슬라이드(`persona_intro_screen.dart`) → 상세(`persona_detail_screen.dart`: 사상·책). 일러스트는 위에 고정되고 글만 그 아래로 스크롤된다
- **설정** — 테마(라이트/다크, 기본 다크) · 글씨 크기(작게 0.9 / 보통 1.0 / 크게 1.15 / 아주 크게 1.3, 기기 글꼴 크기 × 배율) · 계정 ·
  오늘 사용량(`GET /usage`) · **결제 버튼은 비활성 "결제 (준비 중)"** · 개발자에게만 "신고 내역"

**소개 글** (`persona_profiles.dart`, 서버·LLM 안 씀): 예수 인용은 코퍼스(KJV)와 대조한 것만 장절을 붙였다. 책 목록 ● 는 앱이 근거로 찾는 책, ○ 는 안 넣은 책.
**예수 표기는 "예수 그리스도 · 기원전 4년경–기원후 30년경 · 유대 베들레헴"** (사용자 지적 2026-10-12. "나사렛 예수 · 갈릴리"는 나사렛을 성씨처럼 붙인 것이라 틀렸다.
출생지는 마 2:1 "Bethlehem of Judaea"). 불교·신학 쪽 사람의 검토는 아직.

### 5.3 대화창

- **답 말풍선**: 본문 · 용어 풀이(부처) · **"답의 근거 N곳"** 한 줄 — 기본은 접혀 있고 누르면 "마태복음 3:1~3:15" 칩이 펼쳐진다 (`source_tile.dart`.
  칩은 누를 수 없고 본문도 안 보여준다). 근거 없는 답은 따로 표시. 모델이 문장 끝에 넣는 마크다운 줄바꿈(공백 두 칸 + 줄바꿈)은
  화면과 복사에서 정리한다 (`bubbleText`)
- **열면 맨 아래** — `_jumpToEnd` 가 목록 끝이 더 늘지 않을 때까지 다시 내려간다 (긴 답이 뒤에 있으면 목록이 길이를 짧게 어림해 중간에서 열렸다.
  `test/chat_scroll_test.dart` 가 고치기 전 코드에서 실패하는 것을 확인)
- **저장** (`chat_storage.dart`): 페르소나마다 JSON 하나를 앱 전용 폴더(`getApplicationSupportDirectory()/chats/<계정>/<persona>.json`)에.
  질문·답을 각각 1개로 세어 **200개**, 넘으면 오래된 것부터 지운다. 질문을 붙인 직후와 답을 받은 뒤 저장, 임시 파일에 쓰고 바꿔치기한다.
  **저장은 기억이 아니다** — 서버는 매 질문을 따로 받는다. `[확인필요]` Android 자동 백업(`allowBackup`)에 이 폴더가 들어가는지
- **말풍선 길게 누르기** (PC 는 오른쪽 클릭) — 누른 자리에 메뉴: **삭제 · 복사 · 대화내용 신고**. 복사·신고는 답에만, 복사는 답 본문만.
  삭제는 확인 창 뒤 **그 질문과 답을 함께** 지운다 (`deleteExchange`). 전체 지우기는 위쪽 휴지통
- **시크릿 모드** — 위쪽 모자·안경 아이콘(`incognito_icon.dart`). 켜면 어두운 화면에 빈 대화, 여기 대화는 **폰에 저장하지 않고** 끄거나 나가면 사라진다.
  질문이 서버와 LLM 으로 가는 것은 같다 (서버는 질문을 저장·로그하지 않고 횟수만 센다)
- **신고 창** (`report_dialog.dart`) — 사유 하나 고르기: "{이름}의 사상과 맞지 않음", 폭력적인 발화, 혐오·차별 표현, 선정적인 내용, 사실과 다른 내용,
  위험하거나 부적절한 조언, 기타(직접 입력 필수). **질문과 답이 개발자에게 제공되는 것에 동의하는 체크박스**를 체크해야 보낼 수 있다

### 5.4 로그인 (Firebase Authentication)

- 구글 · 애플 · 이메일. `state/auth.dart`(`AuthController`), `firebase_auth_backend.dart`, `ui/login_screen.dart`, `ui/auth_gate.dart`.
  계정마다 대화를 따로 저장한다 (`home_shell.dart`)
- **로그인 화면은 가려 두었다** (2026-10-14 사용자 결정, 포트폴리오 시연용): `state/auth.dart` 의 `const loginScreenEnabled = false`.
  첫 화면을 누르면 **"로그인 없이 사용 중"**(기기 ID)으로 바로 홈에 간다. 이때 설정의 로그아웃은 숨긴다. `true` 로 바꾸면 로그인 흐름이 돌아온다
- `google-services.json` 이 없어도 앱이 켜진다 (Gradle 플러그인 조건부 적용, 초기화 실패를 잡는다). 집 PC 에만 있다
- Firebase 설정 순서: ① 프로젝트 `philo-rag-ef4be` ② Android 앱 등록 시 **SHA-1 을 먼저 등록하고** json 을 받는다(PC 마다 디버그 키가 다르다 —
  두 번째 PC 는 `"D:\DevProgram\AndroidStudio\jbr\bin\keytool.exe" -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android`)
  ③ Authentication(콘솔 왼쪽 "보안" 아래)에서 이메일·Google 을 켠 **뒤에** json 을 받는다 — 켜기 전에 받으면 `oauth_client` 가 비어 있다
  ④ `.env` 의 `FIREBASE_PROJECT_ID`. 애플은 Apple Developer Program(연 $99)이 있어야 켤 수 있다
- 실제 기기 로그인은 아직 안 해 봤다 `[확인필요]`. 이메일 가입은 인증 메일을 보내지 않는다

### 5.5 빌드 · 에뮬레이터

- **`android/gradle.properties` 에 `kotlin.incremental=false`** — Kotlin 증분 캐시 오류(`Could not close incremental caches`)로 빌드가 실패해서. 원인 미상
- 개발 서버가 http 라 `AndroidManifest.xml` 에 `usesCleartextTraffic="true"` + `INTERNET`. **배포 시 https 로 바꾸고 지운다**
- 에뮬레이터에서 PC 키보드로는 한글이 안 들어간다 — 에뮬레이터 Gboard 에 한국어 자판을 추가하거나 붙여넣기. adb `input text` 도 한글이 안 된다
- 첫 빌드 2분 47초, 이후 30초 안팎. **release APK 59.3MB** (`--split-per-abi`·글꼴 서브셋 미적용). 글꼴은 고운바탕 2종(OFL)만
- 에뮬레이터 캡처: `adb exec-out screencap -p > x.png`. 화면 가장자리에 초록 테두리가 찍힐 때가 있다 (앱과 무관, 다시 찍으면 된다).
  Git Bash 에서 기기 쪽 경로를 쓰면 `MSYS_NO_PATHCONV=1`. `run-as` 는 디버그 빌드에서만 된다

### 5.6 한글 낱말 줄바꿈 (`keep_words.dart`)

Flutter 는 한글을 글자 단위로 줄바꿈하고 CSS `word-break: keep-all` 같은 설정이 없다. `keep_words.dart` 가 낱말 글자 사이에
보이지 않는 단어 잇기 문자(U+2060)를 넣어 띄어쓰기에서만 줄이 바뀌게 한다.
**화면 파일은 `import 'package:flutter/material.dart' hide Text;` + `import 'keep_words.dart';`** 로 쓴다 (새 화면도, Codex 도).
한 낱말짜리와 25자 넘는 덩어리는 그대로, 화면 낭독기와 복사에는 원래 글. 입력칸은 건드리지 않는다.
테스트는 `find.text` 대신 `test/text_finders.dart` 의 `findText`/`findTextContaining`.

### 5.7 테스트

`mobile/test/` — **53개** (`flutter test`). 가짜 서버·가짜 로그인. `design_preview_test.dart` 는 `output/design-2026-10-14/` 의 미리보기 PNG 를 다시 만든다.

## 6. 답변 평가

- **세트**: `scripts/eval_questions.json` 31문항 — 철학자마다 일반 · 개념어 · 행적 · 토론 · 잡담 · 미혹 · 위기 (니체는 위기 2문항)
- **실행**: `python scripts/eval_answers.py [문항 ID …]` — 서버 `/ask` 에 보내고 경로(근거 있음 / 직접 다루지 않음 / 경계 / 안전 안내)를 자동 검사해
  `output/Portfolio/eval/answers-*.json` 에 저장한다. **실제 LLM 호출이라 사용자 지시 때만**
- **판정**: 사람이 모든 답을 읽고 근거 구절·코퍼스와 대조한다. 기준은 셋 — **논지 일치**(구절의 방향을 뒤집지 않았는가) / **인용 적합성**(이 질문에 맞는 구절인가) /
  **발화자 정합**(본인의 말·겪은 일로 말하는가). 신학·불교의 맥락 판단은 해당 전통을 아는 사람이 해야 한다 (사용자가 예수 답 하나를 내 판정과 다르게 봤고 사용자가 옳았다)
- **결과**: [`output/Portfolio/eval/report-2026-10-14.md`](output/Portfolio/eval/report-2026-10-14.md)

| | 통과 | 주의 | 실패 | 응답 평균 (최대) | 재생성 |
|---|---|---|---|---|---|
| 첫 측정 (30문항) | 23 | 4 | 3 (전부 예수) | 6.0초 (19.7초) | 7회 |
| **수정 후 (31문항, 2026-10-14)** | **29** | **2** | **0** | **5.7초 (11.6초)** | **2회** |

- 첫 측정 실패의 원인과 수정 (모두 사용자 결정): J02 돈 걱정이 위기로 분류됨 → 위기 기준을 "자기 생명에 관한 말"로 좁힘 /
  J04·J06 근거가 있는데 "가르친 바가 아니니라"로 시작 → 분류 호출이 질문 종류까지 정하게 함(4.3) / J01 "있으리요" 오탐 → `~리요` 허용 /
  J06 구레네 시몬 구절 미검색 → 개념어 사전 "십자가"
- 남은 주의 2건: B04 열반 답이 여시어경 72 의 세 가지 벗어남을 모두 열반으로 묶음(불교 쪽 확인 필요), B08 잡담 경로에서 부처가 "아이폰을 택한다"
- N08 점심 메뉴를 지어내는 것은 사소한 잡담이라 그대로 둔다 (사용자 결정)

## 7. 지금도 유효한 교훈

1. **근거가 없을 때 "네가 한 말 중 가장 가까운 것을 말하라"고 시키면 학습 기억으로 지어낸다.** RAG 의 근거 보장은 검색된 구절에만 미친다.
   그래서 근거 없는 답은 첫 문장으로 "직접 다룬 문제가 아니다"를 밝힌다
2. **온도를 낮춰도 창작은 줄지 않는다.** 온도 0 은 가장 그럴듯한 연상을 더 확실하게 고른다. 온도 0 이어도 같은 질문의 답은 매번 다르다.
   창작을 줄이는 것은 구절 밖 금지 프롬프트·코퍼스 대조·모델뿐이다
3. **프롬프트 수정의 효과는 여러 번 돌려 봐야 안다.** 한 번 돌려 "고쳐졌다"고 판단했다가 다시 돌리니 위반이 되살아났다. 말투는 프롬프트로 보장되지 않아 코드로 검사한다
4. **프롬프트는 짧을수록 낫다.** 875토큰 → 250토큰대로 줄이자 답이 짧아지고 자연스러워졌다. 예시는 복사된다
5. **어휘 적중 지표는 논지 역전을 못 잡는다.** "근거 이미지 적중률" 만점 답 두 개가 대조해 보니 둘 다 구절의 논지를 뒤집고 있었다 → 사람 판정 3기준으로 바꿨다
6. **추론 모델은 끄지 않으면 보이지 않는 토큰이 비용의 대부분이다** (Gemini 사고 토큰은 출력의 84~95%). gpt-5.6-luna 는 effort none 으로 질문당 약 $0.001
7. **점수 기준선으로는 답할 질문을 가를 수 없다.** 0.45 일 때 「바람직한 삶」(0.448)이 근거 없음으로 떨어졌다 → 기준선은 낮추고 분류 호출이 질문 종류를 정한다
8. **음차·한자어 개념어는 다국어 임베딩에도 약하다** → 검색어에만 원어를 덧붙이는 사전. 문장 번역은 오히려 나빴다
9. **모델을 바꾸면 없던 결함이 생긴다** (qwen 계열의 겸양어 "저는/제가"). 교체 때는 전체 문항을 다시 돌린다
10. **안전은 모델에 맡기지 않는다.** 위기 안내 문구는 사람이 쓴 고정 문장을 코드가 붙인다. 소형 모델은 "자살을 말하면 109 를 안내하라" 같은 조건 규칙을 못 지켰다

## 8. 남은 일

**베타(지인 대상)에 필요한 것**
- 서버를 밖에서 접속할 수 있게 올리기 (GPU 없는 환경의 임베딩 처리 결정 포함), 릴리스 빌드의 서버 주소
- https 전환과 `usesCleartextTraffic` 제거, CORS 좁히기, `/chat` 삭제
- `AUTH_REQUIRED=true` 와 로그인 화면 되살리기 (`loginScreenEnabled`), 실제 기기 로그인 확인
- 신고(`reports.db`)는 사용자의 질문·답을 담는다 — 보관 기간·개인정보 처리방침. 신고 처리(완료·삭제) 기능 없음
- 두 번째 PC: `google-services.json`, `.env`(`FIREBASE_PROJECT_ID`·`ADMIN_USERS`), SHA-1 등록 후 json 다시 받기

**품질**
- 복음서 청크가 비유 경계와 무관하다 — 탕자(눅 15:11~32)가 `15:1~15:16` / `15:17~15:32` 로 갈려 「탕자는 왜 돌아왔습니까?」에 상위 3위 안에 안 든다. 비유 단위 분할 필요
- 불교 쪽 사람의 교차 검증, `glossary.py` 용어 표 검토. `CULT_PATTERNS` 목록 사용자 검토
- `sources` 에 같은 `ref` 가 두 번 나올 수 있다 (640 토큰을 넘어 쪼개진 절). 부처 최대 청크 645 > 640
- 페르소나별 분량 불균형 (니체 29.6만 / 부처 12.0만 / 예수 6.5만 단어) — 인덱스가 분리돼 있어 검색이 섞이지는 않는다
