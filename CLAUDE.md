# CLAUDE.md — 철학 RAG 프로그램

철학자 페르소나(예수 / 니체 / 부처)로 답하는 RAG 챗봇 + Android 앱.
이 문서는 **확인된 사실만** 기록한다. 미확인 항목은 `[확인필요]`로 표시한다.

최종 갱신: 2026-09-16

---

## 0. 저장소 구조

모노레포. 저장소 루트 = `D:\ai_project\philo_rag`

```
philo_rag/
├─ CLAUDE.md
├─ README.md
├─ .gitignore
├─ backend/              FastAPI 서버 (RAG 검색 + LLM 호출)
│  ├─ .env.example       키 없이 형식만. 실제 .env 는 커밋 금지
│  ├─ requirements.txt
│  ├─ app/               FastAPI 애플리케이션 코드
│  └─ data/
│     ├─ corpus/         .txt / _units.jsonl (커밋함)
│     └─ index/          FAISS 인덱스 (커밋 안 함 — 재생성 가능)
├─ scripts/              코퍼스 빌드 / 인덱스 빌드 스크립트
└─ mobile/               Flutter 앱 (flutter create 로 생성 예정)
```

## 1. 개발 환경 (확정, 2026-09-16 실측)

| 항목 | 값 | 비고 |
|---|---|---|
| OS | Windows 11 25H2 (10.0.26200.9445), locale ko-KR | |
| Flutter | 3.47.4 stable / Dart 3.13.3 | SDK 위치 `C:\dev\flutter` |
| Android Studio | Quail 2026.1.2 | |
| Android SDK | 36.0.0 | `C:\Users\USER\AppData\Local\Android\Sdk` |
| **cmdline-tools** | **22.0 고정** | 23.x 금지 — 6절 참조 |
| Python | 3.11.16 | **conda 환경 `philo-rag`**. venv 아님 — 아래 참조 |
| PyTorch | 2.11.0+cu128 | `arch list` 에 `sm_120` 포함 확인 완료 |
| NVIDIA 드라이버 | 595.97 (CUDA 13.2) | cu128 빌드와 호환 |
| GPU | RTX 5070 (Blackwell, sm_120) | BGE-M3 임베딩 로컬 실행용, VRAM 12GB |

- Flutter SDK는 저장소 **바깥**(`C:\dev\flutter`)에 둔다. 저장소 안에 넣으면 SDK 자체가 git 저장소라 중첩 문제가 생긴다.
- `flutter doctor` 의 **Visual Studio 항목이 `[!]` 인 것은 정상**이다. Windows 데스크톱 앱을 빌드하지 않으므로 무시한다.
- Windows 개발자 모드 ON. 플러터 플러그인이 심볼릭 링크를 쓰기 때문에 필요하다.
- **파이썬 환경은 conda 를 쓴다.** 이 PC 의 PATH 에 잡히는 `python` 은 Microsoft Store 스텁
  (`AppData\Local\Microsoft\WindowsApps\python.exe`)이라 개발용으로 쓰지 않는다. `py` 런처도 설치돼 있지 않다.
  실제 파이썬은 `C:\Users\USER\anaconda3` 이고, 기존 환경으로 `mlagents`, `unique3d-py311` 이 있다.
  `philo-rag` 는 그것들과 완전히 분리된 별도 환경이므로 충돌하지 않는다.
- **torch 는 `requirements.txt` 에 넣지 않는다.** 일반 pip 로 받으면 CPU 빌드가 깔려 임베딩이 GPU 를 못 쓴다.
  `pip install torch --index-url https://download.pytorch.org/whl/cu128` 로 따로 설치하고,
  `torch.cuda.get_arch_list()` 에 `sm_120` 이 있는지 반드시 확인한다.

## 2. 확정된 설계 결정

### 2.1 앱 / 배포 구조 (2026-09-16 확정)

| 항목 | 결정 | 이유 |
|---|---|---|
| 앱 프레임워크 | **Flutter** | 한 코드베이스로 Android/iOS. Dart가 C#과 유사해 Unity 경험이 전이됨 |
| 우선 타깃 | **Android 전용** | macOS 장비가 없어 iOS 빌드·심사 제출이 불가. 코드는 크로스플랫폼으로 유지 |
| 백엔드 | **FastAPI 서버를 둔다** | 아래 두 가지 이유 |
| 저장소 | 모노레포 1개 | 1인 개발, 규칙을 CLAUDE.md 하나로 공유 |

**백엔드를 두는 이유 (앱에서 LLM API 직접 호출을 배제한 근거):**

1. APK는 압축을 풀어 문자열을 추출할 수 있다. 앱에 넣은 API 키는 공개된 것과 같다.
2. BGE-M3는 파라미터 5억대 모델이고, FAISS는 공식 Flutter/모바일 바인딩이 없다. 검색 단계를 앱 안에서 실행할 수 없다.

→ 앱은 `{persona, question}` 만 보내고, 검색·프롬프트 조립·LLM 호출·키 보관은 전부 서버가 한다.

### 2.2 코퍼스 / RAG

| 항목 | 결정 | 이유 |
|---|---|---|
| 코퍼스 언어 | **영어** | ① 기존 `mathe.txt`가 KJV 영어 ② 영어 토큰 소모가 적음 ③ 한국어 번역본은 저작권 보호 대상 |
| 한국어 답변 | LLM 생성 단계에서 처리 | 코퍼스는 영어, 출력은 한국어 |
| 페르소나 분리 | 철학자별 탭(인덱스) 분리 | 검색 결과 쏠림 방지 |
| **수록 기준** | **니체가 직접 쓰고 스스로 출간한 텍스트만** | 아래 "제외 기준" 참조 |
| 해설의 1인칭 변환 | **하지 않음** | 니체가 쓰지 않은 문장을 니체 발언으로 만드는 것 = 근거 조작 |
| 임베딩 | BGE-M3, 로컬 GPU 실행 | 임베딩 비용 제거. 생성 호출만 외부 API |
| LLM | 개발: Gemini Flash 무료 티어 → 비교: OpenRouter → 배포: 승자 | 프로바이더는 환경변수로 교체 가능한 LangChain 패턴 유지 |

### 제외 기준 (2026-09-16 확정)

1. **타인의 글** — 역자 서문·해설·각주, 편집자(Oscar Levy) 노트, 엘리자베트 푀르스터-니체 서문
2. **유고(Nachlass) 편집물** — 니체 본인 글이지만 출간하지 않은 노트. 잠정적 입장이 섞여 있어
   페르소나가 니체가 철회한 주장을 말할 위험. 『권력에의 의지』 제외와 같은 기준
3. **중복** — 이미 코퍼스에 있는 텍스트의 축자 재인용
4. **서지 부속물** — 목차, 판권지, 식자공 노트, PG 보일러플레이트

**제외분은 보관하지 않는다 (2026-09-16 확정).** 엘리자베트 서문, Ludovici 주해 등 제외된 글은
코퍼스에 다시 넣지 않으며, 별도 폴더에 보관하지도 않고, 재수집하지도 않는다.
검색에 쓰이지 않는 텍스트를 저장소에 두는 것은 의미가 없다는 판단이다.
무엇을 제외했는지는 각 `.txt` 머리말과 `scripts/build_*.py` 의 제외 로직에 남아 있어 근거로 충분하다.

향후 이 결정을 되돌리자는 제안은 하지 않는다.

## 3. 코퍼스 포맷

기존 `mathe.txt`(KJV 마태복음) 형식 계열.

```
Chapter 1
1:1 The book of the generation of Jesus Christ...
```

**차라투스트라** — 담화 형식이라 단위 = 문단

```
Chapter 0. Zarathustra's Prologue
[SS 1]
0:1 When Zarathustra was thirty years old, ...
```

**나머지 5권** — 번호 붙은 아포리즘 형식이라 단위 = 니체가 매긴 절(節)

```
Division 1. Prejudices of Philosophers
1:1 The Will to Truth, which is to tempt us to many a hazardous enterprise, ...
```

- 인용 ID: `<구분>:<절>`. 절 번호는 **니체 본인의 번호**를 그대로 쓴다
- Division 0 = 서문. 번호 없는 구절은 순번 부여
- `237A` 처럼 원문에 알파벳 접미가 붙은 절은 접미를 유지
- 운문 블록은 한 단위로 묶고 줄바꿈·들여쓰기 보존
- 곡선 따옴표는 ASCII 정규화, `_이탤릭_` 마크업 제거, 엠대시는 보존
- 각 `.txt`마다 **`<작품명>_units.jsonl`** 동봉. `scripts/build_jsonl.py` 가 `.txt` 를 역파싱해 생성한다
- JSONL 필드: `uid / seq / ref / persona / work / author / year / translator / pg_id / part /
  division / division_title / section / section_suffix / author_section / numbered / anomaly / text`
- **고유 키는 `ref` 가 아니라 `uid`** (`<파일명>#<순번>`). `ref` 는 `.txt` 에 적힌 그대로 두며 드물게 중복된다 (9절 참조)

## 4. 수집 완료 현황 (6작품, 2026-09-16)

전부 Project Gutenberg 퍼블릭 도메인. Levy 전집 영역본 기준.

| 작품 | PG ID | 역자 | 연도 | 단위 | 단어 |
|---|---|---|---|---|---|
| Thus Spake Zarathustra | 1998 | Thomas Common | 1883–85 | 3,489 | 89,315 |
| Beyond Good and Evil | 4363 | Helen Zimmern | 1886 | 315 | 62,032 |
| The Genealogy of Morals | 52319 | Horace B. Samuel | 1887 | 79 | 51,700 |
| The Twilight of the Idols | 52263 | Anthony M. Ludovici | 1889 | 152 | 29,340 |
| The Antichrist | 52263 | Anthony M. Ludovici | 1895 | 62 | 27,645 |
| Ecce Homo | 52190 | Ludovici / Paul V. Cohn | 1908 | 73 | 35,828 |
| **합계** | | | | **4,170** | **295,860** (~393,000 토큰) |

빌드 스크립트: `scripts/build_zarathustra.py`(1998 전용), `scripts/build_books.py`(나머지 4파일)

### 절 번호 커버리지 검증 결과

- BGE: 1–296 전부 존재 (65A, 73A, 237A 포함). 결번 없음
- GM: 서문 1–8 / 1논문 1–17 / 2논문 1–25 / 3논문 1–28. 결번 없음
- TI: 10개 장, 각 장 1–N 연속. 결번 없음
- AC: 1–62 중 **61 번호 없음** — 원본 결함. 본문(르네상스·루터 대목)은 60에 붙어 있고 유실 없음
- EH: 「Why I Am So Wise」가 1–7 (표준판은 8절), 「The Birth of Tragedy」가 1·3 — **원본에서 번호만 누락**.
  본문은 앞 절에 합쳐진 상태로 존재하며 유실 없음

## 5. 작품별 제외 내역

| 작품 | 제외한 것 |
|---|---|
| Zarathustra | 엘리자베트 서문(1905), Ludovici 부록 해설(1909), 목차, 각 부 제사(본문 축자 중복) |
| Beyond Good and Evil | 식자공 노트, 목차, `[FOOTNOTE: ...]` 역주 |
| Genealogy of Morals | Levy 편집자 노트, 목차, Samuel 역주(`[N] ... —H. B. S.`), **「Peoples and Countries」 27개 유고 단편**(Kennedy 역) |
| Twilight of the Idols | Ludovici 역자 서문, 역주, **「The Hammer Speaketh」**(차라투스트라 III.29 축자 인용 = 중복) |
| The Antichrist | Ludovici 역자 서문, 역주, **「The Eternal Recurrence」 + 차라투스트라 주해**(유고) |
| Ecce Homo | Ludovici 역자 서문, 역주, Levy 편집자 노트, **시가 부록**(편집자가 노트에서 선별한 유고) |

**시가 부록 제외 근거**: 원문에 `HYMN TO LIFE. WORDS BY LOU SALOMÉ. MUSIC BY FRIEDRICH NIETZSCHE.`
라고 명기돼 있다. 가사는 루 살로메의 것이다. 「Speeches, Parables, and Similes」도 번호가
3, 11, 13, 14… 로 건너뛰어 편집자 선별임이 드러난다.

## 6. 시행착오 기록

### 6.1 Android cmdline-tools 는 22.0 에 고정한다 (2026-09-16)

**증상**: `flutter doctor --android-licenses` 실행 시 약관 프롬프트가 뜨지 않고 즉시 종료.

```
WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated. Android CLI will be used instead.
Warning: The --licenses option is no longer needed.
```

이후 `flutter doctor` 는 `Android license status unknown` 또는 `Some Android licenses not accepted` 를 계속 표시.

**원인**: Google이 cmdline-tools **23.0**부터 `sdkmanager` 를 폐기하고 `android` CLI로 대체했는데,
Flutter가 아직 대응하지 않았다. Flutter 측 미해결 이슈다.
([flutter#191558](https://github.com/flutter/flutter/issues/191558), [flutter#191963](https://github.com/flutter/flutter/issues/191963))

**해결**: SDK Manager → SDK Tools 탭 → `Show Package Details` 체크 →
`Android SDK Command-line Tools` 에서 23.x 해제하고 **22.0** 체크 → Apply.
그 뒤 `flutter doctor --android-licenses` 가 정상 동작한다.

**주의**: Flutter가 대응하기 전까지 cmdline-tools 를 최신으로 올리지 말 것.

### 6.2 Flutter SDK zip 압축 해제 시 폴더가 한 겹 더 생긴다 (2026-09-16)

탐색기 우클릭 "압축 풀기"로 풀면 `C:\dev\flutter_windows_3.47.4-stable\flutter\bin` 이 되어
PATH에 등록한 `C:\dev\flutter\bin` 과 맞지 않는다. 최종 경로가 `C:\dev\flutter\bin\flutter.bat` 이 되도록 정리해야 한다.

### 6.3 JSONL 은 원본 PG 파일 없이 .txt 역파싱으로 재생성한다 (2026-09-16)

**상황**: 니체 6작품 중 차라투스트라를 뺀 5작품의 `.jsonl` 과 원본 Gutenberg 파일이 남아 있지 않았다.

**해결**: `scripts/build_jsonl.py` 로 완성된 `.txt` 를 역파싱해 생성한다. `.txt` 머리말에 서지 정보가,
`Division N. 제목` 줄에 구분이, `<구분>:<절> 본문` 줄에 인용 ID가 들어 있어 원본 없이도 복원된다.

**검증**: 차라투스트라는 원본 `.jsonl` 이 남아 있어 대조가 가능했다.
역파싱 결과가 **3,489 / 3,489 레코드 모두 ref·text 완전 일치**했다. 역파서가 옳다는 근거다.

**주의**: `.txt` 에서 첫 줄 들여쓰기는 `"<ref> "` 접두사에 먹혀 사라진다. 운문 블록은
이어지는 줄들의 공통 들여쓰기를 첫 줄에 되돌려야 원본과 일치한다. 이 처리를 빼면 24개 운문 단위가 어긋난다.

### 6.4 Anaconda Prompt 는 cmd 라서 `cd` 로 드라이브가 안 바뀐다 (2026-09-16)

`cd D:\ai_project\philo_rag\backend` 를 쳐도 현재 위치가 C: 그대로다. cmd 의 동작이다.
`cd /d D:\...` 를 쓰거나, `D:` 를 먼저 입력한 뒤 `cd \ai_project\...` 로 이동한다.
PowerShell 에서는 `cd` 만으로 드라이브가 바뀐다.

### 6.5 Gutenberg 도메인은 컨테이너 셸에서 차단됨 (2026-09-01)

**증상**: `curl https://www.gutenberg.org/...` → `curl: (56) CONNECT tunnel failed, response 403`

**원인**: 조직 egress 정책. 프록시 안내 문서(`/root/.ccr/README.md`)에 "403/407 정책 거부는 재시도·우회하지 말고 보고하라"고 명시됨.

**차단 확인**: `www.gutenberg.org`, `gutenberg.org`, `gutenberg.pglaf.org`, `aleph.gutenberg.org`,
`gutendex.com`, `archive.org`, `en.wikisource.org`, `example.com`
**셸 접근 가능**: `github.com`, `raw.githubusercontent.com`, `api.github.com`(저장소 스코프), `pypi.org`

**해결**: 사용자가 브라우저에서 받아 **채팅에 파일로 첨부** → 업로드 디렉터리에서 처리.
본문을 텍스트로 붙여넣으면 파일로 저장되지 않으므로 반드시 파일 첨부여야 한다.

## 7. 파싱 함정 — 반드시 기억할 것

Gutenberg 텍스트를 파싱할 때 실제로 발목을 잡은 것들.

1. **목차가 모든 제목을 반복한다** — 대개 들여쓰기되어 있으므로 `.strip()` 후 매칭하면 목차에 걸린다.
   제목은 항상 0열에서 시작하므로 **좌측 공백을 보존한 채 매칭**해야 한다.
   단 Ecce Homo는 목차도 0열이라 이 규칙이 안 통한다 → 슬라이스 시작점을 본문 기준으로 먼저 잡을 것
2. **역주가 본문 한가운데 있다** — `[Footnote: ...]` / `[FOOTNOTE: ...]`(대문자!) 가 문장 중간에 끼어 있다.
   "각주 시작 → 다음 제목까지 건너뛰기" 방식은 **아포리즘 17개를 통째로 삼킨다.**
   → 줄 단위 skip이 아니라 전체 텍스트에서 `\[Footnote.*?\]`를 `re.S | re.I`로 제거할 것
3. **절 번호 표기가 한 파일 안에서도 섞인다** — `1.` 단독 줄 / `1. 본문` / `278.--본문`(공백 없이 대시).
   세 가지를 모두 받아야 한다. `237A.` 처럼 알파벳 접미도 있다
4. **구형 PG 파일은 `*** END ***` 마커 앞에 `End of Project Gutenberg's ...` 줄을 또 넣는다**
5. 줄바꿈은 CRLF. 곡선 따옴표 때문에 제목 정규식이 빗나간다 → 정규화를 매칭보다 먼저

## 8. 원본 .txt 의 알려진 결함 (2026-09-16, JSONL 생성 중 발견)

인용 ID(`ref`)가 중복되는 단위가 6건 있다. `build_books.py` 가 원본 Gutenberg 텍스트를 처리할 때 생긴 것으로,
**본문 유실은 없고 번호만 어긋난다.** 4,170 단위 중 6건(0.14%)이다.

고치지 않는다. `.txt` 와 `.jsonl` 의 1:1 대응을 깨뜨리지 않기 위해서다.
대신 JSONL 의 `anomaly` 필드로 표시하고, 고유 키로는 `uid` 를 쓴다.

| 유형 | 내용 | 해당 건 |
|---|---|---|
| `epigraph_or_subtitle` | 작품 부제·제사가 1번 절 번호를 받았다. 바로 뒤에 진짜 1절이 온다 | GM `3:1`, EH `7:1`, `10:1`, `12:1` |
| `fragment_of_previous_section` | 앞 절의 뒷부분이 다음 절 번호를 받았다. 소문자로 시작한다 | EH `2:3`, `2:10` |

`anomaly` 가 `duplicate_ref_in_source` 인 레코드가 진짜 본문이다.

## 9. 남은 전처리 계획

1. 청킹 — **아포리즘 경계를 자르지 않는다.** 짧은 것은 묶고 긴 것만 분할. 고정 길이 분할 금지
2. 메타데이터 — JSONL에 이미 들어 있음. `persona` 필드만 추가하면 됨
3. 검증 — 대표 질문 5개로 검색 결과 육안 점검

## 10. 미해결 과제

### RAG
- 벡터 스토어 미정 — FAISS 유력하나 확정 아님
- 청크 크기·오버랩 수치 미확정 (계획 단계 추정: 600토큰 / 100–150토큰 오버랩)
- 부처 페르소나 코퍼스 미선정
- 예수 페르소나 코퍼스가 마태복음 1권뿐 — 추가 예정
- `mathe.txt`를 다른 작품들과 같은 JSONL 메타데이터 형식으로 변환할지 미정
- 페르소나별 분량 불균형 (니체 29.6만 단어 vs 예수 2.3만 단어) — 인덱스 분리로 대응 예정
- 니체 코퍼스는 6작품으로 **수집 완료**

### 백엔드 / 앱
- `[확인필요]` RTX 5070(Blackwell)용 PyTorch 휠 — CUDA 빌드 버전 확인 후 `requirements.txt` 반영
- API 스펙(엔드포인트·요청/응답 스키마) 미확정
- 대화 이력 유지 방식 미정 (매 요청 stateless vs 세션)
- 배포처 미정 — 개발 중엔 로컬, 배포 시 클라우드 이전 예정. 이전 시 GPU 없는 환경의 임베딩 처리 방법 재결정 필요
- 앱 인증·사용량 제한 미설계
