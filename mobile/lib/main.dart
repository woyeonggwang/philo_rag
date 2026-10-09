/// 앱 진입. 상태 객체를 만들고 화면에 넘기는 일만 한다 (CLAUDE.md 13절).
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
    return MaterialApp(
      title: '철학 RAG',
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      home: AuthGate(
        settings: settings,
        auth: auth,
        home: (context, user) => HomeShell(settings: settings, auth: auth, user: user),
      ),
    );
  }
}
