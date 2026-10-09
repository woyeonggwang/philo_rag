/// 앱을 켰을 때 어느 화면을 보여줄지 정한다 (2026-10-10). 기능 확인용 — 디자인은 Codex 몫.
///
///   로그인 상태 확인 중              → 로딩 (잠깐)
///   로그인돼 있음                    → 바로 홈 (로그인 화면을 건너뛴다)
///   로그인 안 됨 + 처음 실행          → 소개 화면 → "시작하기" → 로그인 화면
///   로그인 안 됨 + 소개를 이미 봄      → 로그인 화면
library;

import 'package:flutter/material.dart';

import '../state/auth.dart';
import '../state/settings.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatelessWidget {
  final SettingsStore settings;
  final AuthController auth;

  /// 로그인 뒤 보여줄 화면. 계정이 바뀌면 새로 만들어지도록 사용자별 key 를 붙인다.
  final Widget Function(BuildContext context, AppUser user) home;

  const AuthGate({super.key, required this.settings, required this.auth, required this.home});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([auth, settings]),
      builder: (context, _) {
        final user = auth.user;
        if (auth.status == AuthStatus.unknown) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (auth.status == AuthStatus.signedIn && user != null) {
          return KeyedSubtree(key: ValueKey('home-${user.uid}'), child: home(context, user));
        }
        if (!settings.welcomeSeen) {
          return WelcomeScreen(onStart: settings.markWelcomeSeen);
        }
        return LoginScreen(auth: auth);
      },
    );
  }
}
