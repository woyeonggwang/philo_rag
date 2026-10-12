// 아래 탭(대화·소개·설정), 소개 슬라이드 → 사상·서적 페이지, 설정(테마·글씨·계정·사용량·결제), 대화 중 탭 숨김.
// 서버는 MockClient, 로그인은 가짜.  실행: mobile 폴더에서  flutter test
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/state/auth.dart';
import 'package:philo_rag/state/chat.dart';
import 'package:philo_rag/state/settings.dart';
import 'package:philo_rag/ui/chat_screen.dart';
import 'package:philo_rag/ui/main_tabs.dart';
import 'package:philo_rag/ui/persona_detail_screen.dart';
import 'package:philo_rag/ui/persona_grid_screen.dart' show PersonaVisual;
import 'package:shared_preferences/shared_preferences.dart';

class _Auth implements AuthBackend {
  final _users = StreamController<AppUser?>.broadcast();
  int signOuts = 0;
  @override
  bool get available => true;
  @override
  Stream<AppUser?> userChanges() => _users.stream;
  void emit(AppUser? u) => _users.add(u);
  @override
  Future<void> signOut() async {
    signOuts++;
    emit(null);
  }

  @override
  Future<String?> idToken() async => 'tok';
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signInWithApple() async {}
  @override
  Future<void> signInWithEmail(String e, String p) async {}
  @override
  Future<void> signUpWithEmail(String e, String p) async {}
  @override
  Future<void> sendPasswordReset(String e) async {}
}

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});

/// [admin] 이면 /me 가 개발자라고 답하고 /reports 가 신고를 돌려준다
PhiloRagClient _server({bool admin = false}) => PhiloRagClient('http://x', httpClient: MockClient((req) async {
      switch (req.url.path) {
        case '/me':
          return _json({'user_id': 'u1', 'admin': admin});
        case '/reports':
          return admin
              ? _json([
                  {
                    'id': 3, 'created_at': '2026-10-12T15:00:00+09:00', 'user_id': 'someone',
                    'persona': 'jesus', 'reason': '예수의 사상과 맞지 않음', 'detail': null,
                    'question': '바람직한 삶이란?', 'answer': '보라, 먼저 하나님의 나라를 구하라.', 'extra': null,
                  }
                ])
              : http.Response('{"detail":"no"}', 403);
        case '/personas':
          return _json([
            {'key': 'nietzsche', 'name': '니체', 'blurb': '', 'enabled': true},
            {'key': 'jesus', 'name': '예수', 'blurb': '', 'enabled': true},
            {'key': 'buddha', 'name': '부처', 'blurb': '', 'enabled': true},
          ]);
        case '/usage':
          return _json({'plan': 'personal', 'plan_name': 'Personal', 'used_today': 2, 'daily_limit': 5});
      }
      return http.Response('not found', 404);
    }));

Future<(SettingsStore, _Auth)> _pump(WidgetTester t, {bool admin = false}) async {
  t.view.physicalSize = const Size(400, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore();
  await settings.load();
  final backend = _Auth();
  final auth = AuthController(backend);
  backend.emit(const AppUser(uid: 'u1', email: 'me@example.com', provider: 'google.com'));
  final client = _server(admin: admin);
  await t.pumpWidget(MaterialApp(
    home: MainTabs(settings: settings, auth: auth, chat: ChatController(client), client: () => client),
  ));
  await t.pumpAndSettle();
  return (settings, backend);
}

void main() {
  testWidgets('아래 탭 세 개: 대화 · 소개 · 설정. 처음엔 대화(철학자 바둑판)', (t) async {
    await _pump(t);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['대화', '소개', '설정']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('persona-jesus')), findsOneWidget);
  });

  testWidgets('대화창이 열리면 탭이 보이지 않고, 뒤로 가면 다시 보인다', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const ValueKey('persona-jesus')));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('소개 탭: 한 화면에 한 명, 밀면 다음 철학자, 누르면 사상·서적 페이지', (t) async {
    await _pump(t);
    await t.tap(find.text('소개'));
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('니체'), findsOneWidget);
    expect(find.textContaining('망치를 든 철학자'), findsOneWidget);

    await t.drag(find.byType(PageView), const Offset(-300, 0)); // 다음 철학자로
    await t.pumpAndSettle();
    expect(find.textContaining('공관복음의 목소리'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('intro-jesus')));
    await t.pumpAndSettle();
    expect(find.byType(PersonaDetailScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('사상'), findsOneWidget);
    expect(find.textContaining('예수 그리스도'), findsOneWidget);
    expect(find.textContaining('유대 베들레헴'), findsOneWidget);
    expect(find.textContaining('나사렛 예수'), findsNothing);

    final visual = find.descendant(of: find.byType(PersonaDetailScreen), matching: find.byType(PersonaVisual));
    final top = t.getTopLeft(visual).dy;
    await t.scrollUntilVisible(find.text('요한복음'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('마태복음'), findsOneWidget);
    expect(find.text('요한복음'), findsOneWidget);
    expect(t.getTopLeft(visual).dy, top); // 글을 넘겨도 일러스트는 제자리
  });

  testWidgets('설정 탭: 테마·글씨 크기를 바꾸면 저장되고, 계정·남은 사용량이 보이고, 결제는 비활성', (t) async {
    final (settings, backend) = await _pump(t);
    await t.tap(find.text('설정'));
    await t.pumpAndSettle();

    expect(settings.themeMode, ThemeMode.dark); // 기본 다크
    await t.tap(find.text('라이트'));
    await t.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.light);

    await t.tap(find.text('크게'));
    await t.pumpAndSettle();
    expect(settings.textSize, TextSize.large);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
    expect(prefs.getString('text_size'), 'large');

    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.textContaining('Google 계정'), findsOneWidget);
    expect(find.text('Personal 요금제'), findsOneWidget);
    expect(find.textContaining('오늘 2 / 5건 사용 · 3건 남음'), findsOneWidget);

    await t.scrollUntilVisible(find.byKey(const Key('pay')), 200, scrollable: find.byType(Scrollable).last);
    expect(t.widget<FilledButton>(find.byKey(const Key('pay'))).onPressed, isNull); // 비활성

    await t.scrollUntilVisible(find.byKey(const Key('signout')), -200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('signout')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '로그아웃'));
    await t.pumpAndSettle();
    expect(backend.signOuts, 1);
  });

  testWidgets('설정 값은 다시 켜도 남는다', (t) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light', 'text_size': 'xlarge'});
    final s = SettingsStore();
    await s.load();
    expect(s.themeMode, ThemeMode.light);
    expect(s.textSize, TextSize.xlarge);
    expect(s.textSize.scale, 1.3);
  });

  testWidgets('일반 사용자에게는 신고 내역이 보이지 않는다', (t) async {
    await _pump(t);
    await t.tap(find.text('설정'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('reports')), findsNothing);
  });

  testWidgets('개발자에게는 신고 내역이 보이고, 누르면 질문·답과 함께 목록이 열린다', (t) async {
    await _pump(t, admin: true);
    await t.tap(find.text('설정'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('reports')), 200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('reports')));
    await t.pumpAndSettle();
    expect(find.text('예수 · 예수의 사상과 맞지 않음'), findsOneWidget);
    await t.tap(find.text('예수 · 예수의 사상과 맞지 않음'));
    await t.pumpAndSettle();
    expect(find.text('바람직한 삶이란?'), findsOneWidget);
    expect(find.text('보라, 먼저 하나님의 나라를 구하라.'), findsOneWidget);
  });
}
