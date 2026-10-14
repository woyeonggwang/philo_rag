# 쉼표, 디자인 수정 결과 — 2026-10-14

요청하신 다섯 가지를 기존 흑백 먹 일러스트 톤으로 반영했습니다.

- 설정·메뉴·확인 창·신고 창·신고 내역·시크릿 화면은 `AppTheme`의 표면색, 글꼴, 테두리, 모서리와 간격을 사용합니다.
- 내 질문은 무채색 표면과 오른쪽 정렬로 구분합니다. 질문 말풍선의 글자 대비는 다크 **11.58:1**, 라이트 **12.98:1**입니다. 답 말풍선도 4.5:1 이상인지 실제 렌더링 색상으로 검사했습니다.
- `Source.label`을 그대로 쓰는 출처 칩을 답 아래에 모두 표시합니다. 칩에는 본문·번역·탭 동작이 없습니다. 근거 없는 답에는 “원전에서 직접 다루지 않은 질문”을 표시하며, 안전 안내 답에는 이 표시를 붙이지 않습니다.
- 철학자 카드에 이름과 `Persona.blurb`을 넣었습니다. 첫 줄은 두 칸, 마지막 홀수 카드는 두 칸 너비입니다.
- 기존 그림의 얼굴 부분을 답 말풍선과 빈 화면·기다림 표시에 사용합니다. 기다림은 “니체가 생각하는 중…”처럼 이름을 포함하며 스피너가 없습니다. 여러 초상은 디코딩된 이미지 메모리를 공유합니다.

## 캡처

Flutter의 실제 화면 위젯을 테스트 환경에서 PNG로 렌더링했습니다. 대화·출처·신고·사용량은 **가짜 서버의 디자인 검증용 샘플**입니다. 실제 API 요청, 신고 전송, 사용자 대화 저장은 수행하지 않았습니다. 에뮬레이터 화면 캡처는 아닙니다.

기본 캡처는 390 × 844 논리 픽셀, PNG는 2배 해상도입니다. 각 변경 화면에 라이트·다크, 보통·1.3배 글씨, 320px 너비의 1.3배 글씨 변형을 포함했습니다. 첫 화면 참고 캡처 두 장을 포함하여 PNG **104개**입니다.

| 화면 | 다크 | 라이트 |
|---|---|---|
| 첫 화면 참고 | [보기](welcome-dark.png) | [보기](welcome-light.png) |
| 철학자 바둑판 | [보기](persona-grid-dark.png) | [보기](persona-grid-light.png) |
| 빈 대화 | [보기](chat-empty-dark.png) | [보기](chat-empty-light.png) |
| 답 기다림 | [보기](chat-waiting-dark.png) | [보기](chat-waiting-light.png) |
| 답과 답의 근거 (펼친 상태) | [보기](chat-sources-dark.png) | [보기](chat-sources-light.png) |
| 말풍선 메뉴 | [보기](chat-menu-dark.png) | [보기](chat-menu-light.png) |
| 질문·답 삭제 확인 | [보기](confirm-delete-dark.png) | [보기](confirm-delete-light.png) |
| 전체 삭제 확인 | [보기](confirm-clear-dark.png) | [보기](confirm-clear-light.png) |
| 신고 사유 선택 | [보기](report-dialog-dark.png) | [보기](report-dialog-light.png) |
| 신고 동의 영역 | [보기](report-consent-dark.png) | [보기](report-consent-light.png) |
| 근거 없는 답 | [보기](chat-ungrounded-dark.png) | [보기](chat-ungrounded-light.png) |
| 시크릿 빈 대화 | [보기](secret-empty-dark.png) | [보기](secret-empty-light.png) |
| 시크릿 대화 | [보기](secret-chat-dark.png) | [보기](secret-chat-light.png) |
| 시크릿 끄기 확인 | [보기](confirm-secret-off-dark.png) | [보기](confirm-secret-off-light.png) |
| 설정 | [보기](settings-dark.png) | [보기](settings-light.png) |
| 설정 계정·사용량·개발자 | [보기](settings-account-usage-dark.png) | [보기](settings-account-usage-light.png) |
| 신고 목록 | [보기](reports-dark.png) | [보기](reports-light.png) |
| 신고 상세 | [보기](reports-detail-dark.png) | [보기](reports-detail-light.png) |

같은 파일명에서 `.png` 앞에 `-xlarge`를 넣으면 1.3배 글씨, `-xlarge-narrow`를 넣으면 320px 너비 캡처입니다. 예: [라이트 대화 1.3배](chat-sources-light-xlarge.png), [좁은 화면의 시크릿 안내](secret-empty-dark-xlarge-narrow.png).

## 바꾼 파일

화면 파일은 모두 `mobile/lib/ui/` 아래입니다.

| 파일 | 변경 |
|---|---|
| `app_theme.dart` | 기능 화면 공통 테마·간격·컨트롤·출처 칩 스타일 |
| `brand_widgets.dart` (추가) | 기존 일러스트의 작은 초상, 설정 그룹 표면 |
| `chat_screen.dart` | 무채색 말풍선·초상·기다림·근거 없음 표시·시크릿 안내·메뉴 |
| `source_tile.dart` | 접힘을 없애고 비활성 출처 칩 표시 |
| `persona_grid_screen.dart` | 이름·소개·2열과 홀수 카드 전체 너비·얼굴 크롭·이미지 공유 |
| `settings_screen.dart` | 그룹 카드·테마 선택·큰 글씨 대응 |
| `report_dialog.dart` | 사유·동의 영역의 간격과 브랜드 스타일 |
| `reports_screen.dart` | 신고 목록 카드·빈 화면 스타일 |
| `main_tabs.dart` | 설정과 하단 탭이 공통 브랜드 글꼴을 사용하도록 적용 |

테스트 파일은 `mobile/test/` 아래입니다.

- `source_tile_test.dart`: 출처를 펼치는 기대값을 처음부터 표시되고 탭해도 변화가 없는 기대값으로 바꾸었습니다. 출처 key와 한글 label을 검사합니다.
- `persona_grid_test.dart`: `GridView` 열 수 대신 첫 두 카드의 실제 위치·동일 너비와 마지막 카드의 두 칸 너비를 검사합니다. 이름·소개가 보이는 기대값과 새 캡처 경로를 반영했습니다.
- `main_tabs_test.dart`: 신고 내역으로 스크롤한 뒤 화면 갱신을 기다리고 탭하도록 한 줄 추가했습니다.
- `welcome_visual_test.dart`: 참고 캡처 저장 위치를 이번 결과 폴더로 변경했습니다.
- `design_preview_test.dart` (추가): 두 테마, 1.0·1.3배 글씨, 390·320px 화면에서 실제 위젯 렌더링·넘침·출처·대비·대기·메뉴·신고 동의·시크릿 종료를 검사하고 캡처합니다.

첫 전체 테스트 실행 시 기존 `output/illustration-samples/welcome-dark-preview.png`와 `welcome-light-preview.png`도 기존 테스트의 저장 동작으로 재생성되었습니다. 이후 캡처는 이번 결과 폴더에 저장하도록 변경했습니다.

## 검증

`mobile`에서 실행한 `flutter analyze`: **No issues found**. `flutter test`: **52개 통과**. `git diff --check`: 통과.

기존 키, 메뉴 항목, 삭제 확인, 복사 본문, 신고 동의·기타 입력, 시크릿 저장·종료 규칙을 유지했습니다. `lib/api/`, `lib/state/`, `backend/` 수정은 없습니다. 새 패키지·글꼴·그림 추가와 커밋·푸시는 없습니다.

재생성 명령:

```powershell
cd mobile
flutter test test/design_preview_test.dart test/welcome_visual_test.dart
```
