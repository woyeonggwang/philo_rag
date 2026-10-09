/// 앱 진입. 상태 객체를 만들고 화면에 넘기는 일만 한다 (CLAUDE.md 13절).
///   api/    서버 호출            — Claude
///   state/  설정·대화 상태       — Claude
///   ui/     화면                 — Codex. 지금 들어 있는 PlaceholderHome 은 기능 확인용이며 교체 대상이다.
library;

import 'package:flutter/material.dart';

import 'api/client.dart';
import 'state/chat.dart';
import 'state/chat_storage.dart';
import 'state/settings.dart';
import 'ui/placeholder_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();

  PhiloRagClient makeClient() =>
      PhiloRagClient(settings.baseUrl, userId: settings.userId);
  // 대화는 폰에 저장된다 (페르소나당 최근 200개). 켤 때 불러온다
  final chat = ChatController(makeClient(), storage: ChatStorage());
  await chat.load();
  // 설정에서 서버 주소를 바꾸면 대화 컨트롤러도 새 주소를 쓴다
  settings.addListener(() => chat.client = makeClient());

  runApp(PhiloRagApp(settings: settings, chat: chat));
}

class PhiloRagApp extends StatelessWidget {
  final SettingsStore settings;
  final ChatController chat;

  const PhiloRagApp({super.key, required this.settings, required this.chat});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '철학 RAG',
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      home: PlaceholderHome(settings: settings, chat: chat),
    );
  }
}
