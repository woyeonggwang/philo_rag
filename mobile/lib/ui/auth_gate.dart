/// 앱을 켰을 때 어느 화면을 보여줄지 정한다 (2026-10-10).
///
///   켤 때마다 첫 화면(소개) → 화면을 누르면
///     → 로그인돼 있음   : 바로 홈 (로그인 화면을 건너뛴다)
///     → 로그인 안 됨    : 로그인 화면
///     → 아직 확인 중    : 잠깐 로딩
///
/// 첫 화면은 "설치 후 한 번만"이 아니라 **켤 때마다** 나온다 (사용자 결정 2026-10-10. 처음엔 한 번만 보이게 했었다).
/// 첫 화면이 떠 있는 동안 저장된 로그인 상태를 확인하므로, 누른 뒤 로딩을 거의 보지 않는다.
library;

import 'package:flutter/material.dart';

import '../state/auth.dart';
import '../state/settings.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatefulWidget {
  final SettingsStore settings;
  final AuthController auth;

  /// 로그인 뒤 보여줄 화면. 계정이 바뀌면 새로 만들어지도록 사용자별 key 를 붙인다.
  final Widget Function(BuildContext context, AppUser user) home;

  const AuthGate({super.key, required this.settings, required this.auth, required this.home});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// 이번 실행에서 첫 화면을 눌러 넘겼는지. 저장하지 않는다 — 다시 켜면 첫 화면부터.
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return WelcomeScreen(onStart: () => setState(() => _started = true));
    }
    final auth = widget.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final user = auth.user;
        if (auth.status == AuthStatus.unknown) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (auth.status == AuthStatus.signedIn && user != null) {
          return KeyedSubtree(key: ValueKey('home-${user.uid}'), child: widget.home(context, user));
        }
        return LoginScreen(auth: auth);
      },
    );
  }
}
