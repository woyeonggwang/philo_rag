/// 로그인한 사용자의 홈 (2026-10-10). 계정마다 대화 상태·저장 폴더를 따로 만든다.
/// 첫 화면은 철학자 2열 바둑판(persona_grid_screen.dart), 누르면 대화창(chat_screen.dart).
library;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../state/auth.dart';
import '../state/chat.dart';
import '../state/chat_storage.dart';
import '../state/settings.dart';
import 'persona_grid_screen.dart';

class HomeShell extends StatefulWidget {
  final SettingsStore settings;
  final AuthController auth;
  final AppUser user;

  const HomeShell({super.key, required this.settings, required this.auth, required this.user});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final ChatController _chat;

  PhiloRagClient _client() => PhiloRagClient(
        widget.settings.baseUrl,
        userId: widget.settings.userId,
        idToken: widget.auth.idToken, // 로그인했으면 계정 기준으로 한도를 센다
      );

  void _onSettings() => _chat.client = _client(); // 서버 주소가 바뀌면 새 주소로

  @override
  void initState() {
    super.initState();
    // 대화는 계정별 폴더에 저장된다 (페르소나당 최근 200개)
    _chat = ChatController(_client(), storage: ChatStorage(userKey: widget.user.uid));
    _chat.load().catchError((Object e) => debugPrint('저장된 대화를 불러오지 못함: $e'));
    widget.settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PersonaGridScreen(
        settings: widget.settings,
        chat: _chat,
        auth: widget.auth,
        client: _client,
      );
}
