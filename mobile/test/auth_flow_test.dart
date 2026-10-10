// 첫 실행 → 소개 → 로그인 → 홈, 그리고 "로그인돼 있으면 바로 홈" (ui/auth_gate.dart, state/auth.dart).
// Firebase 없이 가짜 로그인으로 확인한다.  실행: mobile 폴더에서  flutter test
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/state/auth.dart';
import 'package:philo_rag/state/settings.dart';
import 'package:philo_rag/ui/auth_gate.dart';
import 'package:philo_rag/ui/login_screen.dart';
import 'package:philo_rag/ui/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth implements AuthBackend {
  FakeAuth({this.available = true});

  @override
  final bool available;
  final _users = StreamController<AppUser?>.broadcast();
  final calls = <String>[];
  AuthFailure? failWith;

  void emit(AppUser? u) => _users.add(u);

  @override
  Stream<AppUser?> userChanges() => _users.stream;

  Future<void> _do(String name, [AppUser? success]) async {
    calls.add(name);
    if (failWith != null) throw failWith!;
    if (success != null) emit(success);
  }

  @override
  Future<void> signInWithGoogle() =>
      _do('google', const AppUser(uid: 'g1', email: 'a@gmail.com', provider: 'google.com'));
  @override
  Future<void> signInWithApple() => _do('apple', const AppUser(uid: 'a1', provider: 'apple.com'));
  @override
  Future<void> signInWithEmail(String email, String password) =>
      _do('email:$email', AppUser(uid: 'e1', email: email, provider: 'password'));
  @override
  Future<void> signUpWithEmail(String email, String password) =>
      _do('signup:$email', AppUser(uid: 'e2', email: email, provider: 'password'));
  @override
  Future<void> sendPasswordReset(String email) => _do('reset:$email');
  @override
  Future<void> signOut() async {
    calls.add('signout');
    emit(null);
  }

  @override
  Future<String?> idToken() async => 'token-of-current-user';
}

/// 앱을 켠다. [passTitle] 이면 첫 화면을 눌러 넘긴 상태로 돌려준다.
Future<(SettingsStore, AuthController, FakeAuth)> _app(WidgetTester t,
    {bool passTitle = false, bool available = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore();
  await settings.load();
  final backend = FakeAuth(available: available);
  final auth = AuthController(backend);
  await t.pumpWidget(MaterialApp(
    home: AuthGate(
      settings: settings,
      auth: auth,
      home: (_, user) => Scaffold(body: Text('HOME ${user.label}')),
    ),
  ));
  if (passTitle) {
    await t.tapAt(const Offset(200, 120)); // 첫 화면 아무 데나
    await t.pump();
  }
  return (settings, auth, backend);
}

void main() {
  testWidgets('켤 때마다 첫 화면 → 화면을 누르면 → 로그인 화면', (t) async {
    final (settings, auth, backend) = await _app(t);
    expect(find.byType(WelcomeScreen), findsOneWidget); // 로그인 확인 중에도 첫 화면이 먼저
    expect(find.byType(FilledButton), findsNothing); // 버튼 없음 (사용자 결정)
    backend.emit(null);
    await t.pump();
    expect(find.byType(WelcomeScreen), findsOneWidget); // 누르기 전에는 넘어가지 않는다
    await t.tapAt(const Offset(200, 120)); // 화면 아무 데나
    await t.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    // 다시 켜면 첫 화면이 또 나온다 — 한 번만이 아니다 (앱을 내렸다 다시 올린 것처럼 화면을 비웠다가 새로 그린다)
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(
        home: AuthGate(settings: settings, auth: auth, home: (_, u) => Text('HOME ${u.label}'))));
    await t.pump();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('이미 로그인돼 있으면 첫 화면 → 누르면 로그인 화면 없이 바로 홈', (t) async {
    final (_, _, backend) = await _app(t);
    backend.emit(const AppUser(uid: 'g1', email: 'a@gmail.com', provider: 'google.com'));
    await t.pump();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await t.tapAt(const Offset(200, 120));
    await t.pump();
    expect(find.text('HOME a@gmail.com'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('첫 화면을 일찍 눌러 로그인 확인이 덜 끝났으면 잠깐 로딩', (t) async {
    final (_, _, backend) = await _app(t, passTitle: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    backend.emit(null);
    await t.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('구글 · 애플 · 이메일 로그인 → 홈, 로그아웃 → 로그인 화면', (t) async {
    final (_, auth, backend) = await _app(t, passTitle: true);
    backend.emit(null);
    await t.pump();

    await t.tap(find.byKey(const Key('google')));
    await t.pump();
    expect(backend.calls, ['google']);
    expect(find.text('HOME a@gmail.com'), findsOneWidget);
    expect(await auth.idToken(), 'token-of-current-user'); // 서버 요청에 붙는다

    await auth.signOut();
    await t.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    await t.tap(find.byKey(const Key('apple')));
    await t.pump();
    expect(backend.calls.last, 'apple');
    await auth.signOut();
    await t.pump();

    await t.enterText(find.byKey(const Key('email')), 'me@example.com');
    await t.enterText(find.byKey(const Key('password')), 'secret123');
    await t.tap(find.byKey(const Key('email-submit')));
    await t.pump();
    expect(backend.calls.last, 'email:me@example.com');
    expect(find.text('HOME me@example.com'), findsOneWidget);
  });

  testWidgets('가입하기로 바꾸면 가입을 부른다 · 짧은 비밀번호는 보내기 전에 막는다', (t) async {
    final (_, _, backend) = await _app(t, passTitle: true);
    backend.emit(null);
    await t.pump();
    await t.tap(find.text('처음이신가요? 가입하기'));
    await t.pump();
    await t.enterText(find.byKey(const Key('email')), 'new@example.com');
    await t.enterText(find.byKey(const Key('password')), '123');
    await t.tap(find.byKey(const Key('email-submit')));
    await t.pump();
    expect(find.text('비밀번호는 6자 이상이어야 합니다.'), findsOneWidget);
    expect(backend.calls, isEmpty);

    await t.enterText(find.byKey(const Key('password')), '123456');
    await t.tap(find.byKey(const Key('email-submit')));
    await t.pump();
    expect(backend.calls, ['signup:new@example.com']);
  });

  testWidgets('실패 문장을 화면에 보여준다', (t) async {
    final (_, _, backend) = await _app(t, passTitle: true);
    backend.emit(null);
    await t.pump();
    backend.failWith = const AuthFailure('이 로그인 방식이 아직 Firebase 콘솔에서 켜져 있지 않습니다.');
    await t.tap(find.byKey(const Key('apple')));
    await t.pump();
    expect(find.text('이 로그인 방식이 아직 Firebase 콘솔에서 켜져 있지 않습니다.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('Firebase 설정 전: 경고를 보여 주고, 개발용 우회로 들어갈 수 있다 (토큰 없음)', (t) async {
    final (_, auth, _) = await _app(t, passTitle: true, available: false);
    await t.pump();
    expect(find.textContaining('Firebase 설정 전'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('dev-skip')), 200,
        scrollable: find.byType(Scrollable).first); // 화면 맨 아래에 있다 (입력칸도 Scrollable 이라 목록을 지정)
    await t.tap(find.byKey(const Key('dev-skip')));
    await t.pump();
    expect(find.text('HOME 개발용 (로그인 안 함)'), findsOneWidget);
    expect(await auth.idToken(), isNull); // 서버는 기기 ID 로 센다
    await auth.signOut();
    await t.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
