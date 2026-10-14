/// 앱 진입. 상태 객체를 만들고 화면에 넘기는 일만 한다 (CLAUDE.md 5.1).
///   api/    서버 호출                   — Claude
///   state/  설정·로그인·대화 상태        — Claude
///   ui/     화면                        — Codex. 지금 있는 화면들은 기능 확인용이며 교체 대상이다.
///
/// 흐름: 로그인 상태 확인 → (로그인돼 있으면) 바로 홈 / (아니면) 첫 실행 소개 → 로그인 (ui/auth_gate.dart)
library;

import 'package:flutter/material.dart';

import 'state/auth.dart';
import 'state/firebase_auth_backend.dart';
import 'state/settings.dart';
import 'ui/auth_gate.dart';
import 'ui/app_theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();

  // google-services.json 이 없으면 로그인 없는 모드로 켜진다 (앱은 죽지 않는다)
  final auth = AuthController(await FirebaseAuthBackend.create());

  runApp(PhiloRagApp(settings: settings, auth: auth));
}

class PhiloRagApp extends StatelessWidget {
  final SettingsStore settings;
  final AuthController auth;

  const PhiloRagApp({super.key, required this.settings, required this.auth});

  @override
  Widget build(BuildContext context) {
    // 테마(라이트/다크)와 글씨 크기는 설정 탭에서 바꾼다 (SettingsStore, 2026-10-12)
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: '쉼표,',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.themeMode,
        builder: (context, child) {
          final system =
              MediaQuery.textScalerOf(context).scale(14) /
              14; // 기기 글씨 크기 설정도 살린다
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(system * settings.textSize.scale),
            ),
            child: child!,
          );
        },
        home: AuthGate(
          settings: settings,
          auth: auth,
          home: (context, user) =>
              HomeShell(settings: settings, auth: auth, user: user),
        ),
      ),
    );
  }
}
