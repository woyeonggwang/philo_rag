# 쉼표, — Flutter 앱 (Android)

철학자에게 묻는 RAG 챗봇의 앱입니다. 프로젝트 소개는 [저장소 README](../README.md), 화면은 [output/Portfolio](../output/Portfolio/README.md)에 있습니다.

- 앱은 서버에 `{persona, question}` 만 보냅니다. 검색·LLM 호출·키는 전부 백엔드에 있습니다
- `lib/api/` 서버 호출과 응답 모델 · `lib/state/` 설정·대화 상태·기기 저장·로그인 · `lib/ui/` 화면 · `lib/data/` 소개 글
- 대화는 페르소나마다 기기의 앱 전용 폴더에 저장되고(최대 200개), 시크릿 모드 대화는 저장하지 않습니다

```bash
flutter pub get
flutter run          # Android 에뮬레이터에서 PC 의 서버는 http://10.0.2.2:8000
flutter test         # 53개, 가짜 서버
```

설계와 작업 규칙은 [CLAUDE.md](../CLAUDE.md) 5절.
